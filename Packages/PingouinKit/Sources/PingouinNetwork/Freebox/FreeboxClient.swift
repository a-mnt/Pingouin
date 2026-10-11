import Foundation
import os
import PingouinCore

public enum FreeboxError: Error, Sendable, Equatable {
    /// Aucune réponse à l'adresse de la box.
    case unreachable
    /// Une réponse est arrivée, mais ce n'est pas celle d'une Freebox.
    case notAFreebox
    /// La session a expiré ou n'a jamais été ouverte : il faut en rouvrir une.
    case authenticationRequired
    /// Le jeton enregistré n'est plus accepté par la box (accès révoqué).
    case invalidToken
    /// Erreur signalée par la box, avec son code et son message.
    case api(code: String, message: String)
    case badResponse
    /// En HTTPS, le certificat présenté n'a pas pu être rattaché à une autorité acceptée
    /// (celles de Free ou celles de macOS), ou ne correspond pas au nom de la box.
    case untrustedCertificate
}

/// Où joindre l'API d'une Freebox, après découverte.
public struct FreeboxEndpoint: Sendable, Equatable {
    public let host: String
    public let basePath: String
    public let deviceName: String

    public init(host: String, basePath: String, deviceName: String) {
        self.host = host
        self.basePath = basePath
        self.deviceName = deviceName
    }
}

/// Partie d'un relevé que la box n'a pas pu fournir.
public struct FreeboxPartialFailure: Sendable, Equatable {
    public enum Part: Sendable, Equatable {
        case wifi
        case ethernet
    }

    public let part: Part
    public let error: FreeboxError
}

/// Relevé complet ou partiel : ce qui a pu être lu, et ce qui a échoué.
public struct FreeboxReadings: Sendable {
    public let readings: [UsageReading]
    public let failures: [FreeboxPartialFailure]
}

public enum FreeboxAuthorizationState: Sendable, Equatable {
    /// L'utilisateur n'a pas encore répondu sur l'écran de la box.
    case pending
    case granted
    case denied
    /// Personne n'a répondu à temps sur la box.
    case timedOut
    case unknown
}

/// Client de l'API locale de Freebox OS, limité à ce dont la mesure de consommation a besoin.
///
/// Les échanges se font en HTTPS par défaut, à l'adresse `mafreebox.freebox.fr`. Le certificat de la
/// box est signé par une autorité de Free que macOS ne connaît pas : elle est ajoutée aux autorités
/// acceptées pour ces seuls échanges (`FreeboxAuthorities`), et la validation TLS reste entière.
/// Le HTTP simple reste possible, sur demande, pour une box dont le certificat ne passerait pas.
public struct FreeboxClient: Sendable {
    public static let defaultHost = "mafreebox.freebox.fr"
    public static let appID = "fr.a-mnt.pingouin"

    private let host: String
    private let session: URLSession
    private let trust: TrustDelegate
    /// Vrai : HTTPS avec validation du certificat. Faux : HTTP simple, non chiffré.
    public let usesHTTPS: Bool

    private var scheme: String { usesHTTPS ? "https" : "http" }

    public init(host: String = FreeboxClient.defaultHost, usesHTTPS: Bool = true) {
        self.host = host
        self.usesHTTPS = usesHTTPS
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        trust = TrustDelegate()
        session = URLSession(configuration: configuration, delegate: trust, delegateQueue: nil)
    }

    /// Validation du certificat de la box : l'évaluation normale de macOS (chaîne, dates, nom du
    /// serveur), avec les autorités de Free ajoutées à celles du système. Un certificat qui ne
    /// passe pas fait échouer la connexion ; rien n'est accepté d'office.
    private final class TrustDelegate: NSObject, URLSessionDelegate, Sendable {
        private let refused = OSAllocatedUnfairLock(initialState: false)

        /// Vrai si une connexion vient d'être refusée pour son certificat ; remis à faux à la lecture.
        func takeRefusal() -> Bool {
            refused.withLock { value in
                let was = value
                value = false
                return was
            }
        }

        func urlSession(
            _ session: URLSession,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  let serverTrust = challenge.protectionSpace.serverTrust else {
                completionHandler(.performDefaultHandling, nil)
                return
            }
            SecTrustSetAnchorCertificates(serverTrust, FreeboxAuthorities.certificates() as CFArray)
            // Les autorités de macOS restent acceptées : la box peut présenter un certificat public.
            SecTrustSetAnchorCertificatesOnly(serverTrust, false)
            if SecTrustEvaluateWithError(serverTrust, nil) {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                refused.withLock { $0 = true }
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }

    // MARK: Découverte et accès

    public func discover() async throws -> FreeboxEndpoint {
        guard let url = URL(string: "\(scheme)://\(host)/api_version") else { throw FreeboxError.unreachable }
        let data = try await fetch(URLRequest(url: url))
        guard let version = try? JSONDecoder().decode(FreeboxAPIVersion.self, from: data),
              let basePath = version.basePath else {
            throw FreeboxError.notAFreebox
        }
        return FreeboxEndpoint(host: host, basePath: basePath, deviceName: version.deviceName ?? "Freebox")
    }

    /// Demande l'accès : la box affiche alors la demande sur son écran, et attend une réponse sur place.
    public func requestAuthorization(endpoint: FreeboxEndpoint, appVersion: String, deviceName: String) async throws -> FreeboxAuthorization {
        let body = [
            "app_id": Self.appID,
            "app_name": "Pingouin",
            "app_version": appVersion,
            "device_name": deviceName
        ]
        return try await call(endpoint, "login/authorize/", method: "POST", body: body)
    }

    public func authorizationState(endpoint: FreeboxEndpoint, trackID: Int) async throws -> FreeboxAuthorizationState {
        let status: FreeboxAuthorizationStatus = try await call(endpoint, "login/authorize/\(trackID)")
        switch status.status {
        case "pending": return .pending
        case "granted": return .granted
        case "denied": return .denied
        case "timeout": return .timedOut
        default: return .unknown
        }
    }

    /// Ouvre une session avec le jeton de l'application et renvoie le jeton de session.
    public func openSession(endpoint: FreeboxEndpoint, appToken: String) async throws -> String {
        let login: FreeboxLogin = try await call(endpoint, "login/")
        guard let challenge = login.challenge else { throw FreeboxError.badResponse }
        let body = [
            "app_id": Self.appID,
            "password": FreeboxLogic.sessionPassword(appToken: appToken, challenge: challenge)
        ]
        let opened: FreeboxSession = try await call(endpoint, "login/session/", method: "POST", body: body)
        guard let token = opened.sessionToken, !token.isEmpty else { throw FreeboxError.badResponse }
        return token
    }

    // MARK: Relevés

    /// Compteurs de tous les appareils Wi-Fi et de tous les ports Ethernet occupés.
    ///
    /// Le Wi-Fi et l'Ethernet sont lus séparément : l'échec de l'un n'empêche pas l'autre, et il est
    /// rapporté dans `failures`. Seule une session refusée interrompt tout, pour qu'elle soit rouverte.
    public func readings(endpoint: FreeboxEndpoint, sessionToken: String) async throws -> FreeboxReadings {
        var readings: [UsageReading] = []
        var failures: [FreeboxPartialFailure] = []

        do {
            let accessPoints: [FreeboxLossy<FreeboxAccessPoint>] = try await call(endpoint, "wifi/ap/", sessionToken: sessionToken)
            // Une liste non vide dont aucun élément n'a pu être lu est un échec, pas une absence d'appareil.
            if !accessPoints.isEmpty, accessPoints.allSatisfy({ $0.value == nil }) {
                throw FreeboxError.badResponse
            }
            for accessPoint in accessPoints.compactMap(\.value) {
                let stations: [FreeboxLossy<FreeboxStation>] = try await call(
                    endpoint, "wifi/ap/\(accessPoint.id)/stations/", sessionToken: sessionToken
                )
                if !stations.isEmpty, stations.allSatisfy({ $0.value == nil }) {
                    throw FreeboxError.badResponse
                }
                readings += stations.compactMap(\.value).compactMap {
                    FreeboxLogic.reading(station: $0, band: accessPoint.config?.band)
                }
            }
        } catch let error as FreeboxError {
            if error == .authenticationRequired || error == .invalidToken { throw error }
            failures.append(FreeboxPartialFailure(part: .wifi, error: error))
        }

        // Appareils connus de la box, pour nommer ceux d'un port et donner leur adresse IP.
        // Si cette liste manque, les ports restent relevés, avec les seuls noms vus par le port.
        var hosts: [String: FreeboxLanHost] = [:]
        if let known: [FreeboxLossy<FreeboxLanHost>] = try? await call(endpoint, "lan/browser/pub/", sessionToken: sessionToken) {
            for host in known.compactMap(\.value) {
                for mac in host.macAddresses {
                    hosts[mac] = host
                }
            }
        }

        do {
            let ports: [FreeboxLossy<FreeboxSwitchPort>] = try await call(endpoint, "switch/status/", sessionToken: sessionToken)
            if !ports.isEmpty, ports.allSatisfy({ $0.value == nil }) {
                throw FreeboxError.badResponse
            }
            var portFailure: FreeboxError?
            for port in ports.compactMap(\.value) where port.link?.lowercased() == "up" {
                do {
                    let stats: FreeboxPortStats = try await call(endpoint, "switch/port/\(port.id)/stats", sessionToken: sessionToken)
                    if let reading = FreeboxLogic.reading(port: port, stats: stats, hosts: hosts) {
                        readings.append(reading)
                    }
                } catch let error as FreeboxError {
                    if error == .authenticationRequired || error == .invalidToken { throw error }
                    portFailure = error
                }
            }
            if let portFailure {
                failures.append(FreeboxPartialFailure(part: .ethernet, error: portFailure))
            }
        } catch let error as FreeboxError {
            if error == .authenticationRequired || error == .invalidToken { throw error }
            failures.append(FreeboxPartialFailure(part: .ethernet, error: error))
        }

        return FreeboxReadings(readings: readings, failures: failures)
    }

    // MARK: Diagnostic

    /// Réponses brutes de la box aux appels utilisés pour les relevés, tronquées, pour comprendre
    /// un relevé vide ou en erreur. Le texte contient des noms d'appareils et des adresses MAC.
    public func diagnostic(endpoint: FreeboxEndpoint, sessionToken: String) async -> String {
        var lines = ["Freebox : \(endpoint.deviceName) · API \(endpoint.basePath) · \(usesHTTPS ? "HTTPS" : "HTTP non chiffré")"]
        var paths = ["wifi/ap/", "switch/status/"]
        var index = 0
        while index < paths.count {
            let path = paths[index]
            index += 1
            guard let url = URL(string: "\(scheme)://\(endpoint.host)\(endpoint.basePath)\(path)") else { continue }
            var request = URLRequest(url: url)
            request.setValue(sessionToken, forHTTPHeaderField: "X-Fbx-App-Auth")
            do {
                let (data, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let text = String(decoding: data.prefix(1_500), as: UTF8.self)
                lines.append("GET \(path) → HTTP \(status), \(data.count) octets\n\(text)")
                // Le premier point d'accès et le premier port servent d'exemples pour les appels de détail.
                if let firstID = Self.firstIdentifier(in: data) {
                    if path == "wifi/ap/" { paths.append("wifi/ap/\(firstID)/stations/") }
                    if path == "switch/status/" { paths.append("switch/port/\(firstID)/stats") }
                }
            } catch {
                lines.append("GET \(path) → aucune réponse (\(error.localizedDescription))")
            }
        }
        lines.append(await hostsDiagnostic(endpoint: endpoint, sessionToken: sessionToken))
        return lines.joined(separator: "\n\n")
    }

    /// Ce que la box sait de chaque appareil du réseau : sert à voir si elle tient un compteur par
    /// appareil, y compris pour ceux qui passent par un autre point d'accès.
    private func hostsDiagnostic(endpoint: FreeboxEndpoint, sessionToken: String) async -> String {
        let path = "lan/browser/pub/"
        guard let url = URL(string: "\(scheme)://\(endpoint.host)\(endpoint.basePath)\(path)") else { return "" }
        var request = URLRequest(url: url)
        request.setValue(sessionToken, forHTTPHeaderField: "X-Fbx-App-Auth")
        guard let (data, response) = try? await session.data(for: request) else {
            return "GET \(path) → aucune réponse"
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hosts = object["result"] as? [[String: Any]] else {
            return "GET \(path) → HTTP \(status), \(data.count) octets\n" + String(decoding: data.prefix(1_000), as: UTF8.self)
        }
        var lines = ["GET \(path) → HTTP \(status), \(hosts.count) appareils connus"]
        let keys = Set(hosts.flatMap { $0.keys }).sorted()
        lines.append("Champs présents : " + keys.joined(separator: ", "))
        let withAccessPoint = hosts.filter { $0["access_point"] != nil }
        lines.append("Appareils avec un champ access_point : \(withAccessPoint.count)")
        // Deux exemples complets : un appareil rattaché à un point d'accès, et un autre appareil actif.
        let examples = [
            withAccessPoint.first { ($0["active"] as? Bool) == true } ?? withAccessPoint.first,
            hosts.first { $0["access_point"] == nil && ($0["active"] as? Bool) == true }
        ]
        for example in examples {
            guard let example,
                  let pretty = try? JSONSerialization.data(withJSONObject: example, options: [.prettyPrinted, .sortedKeys]) else {
                continue
            }
            lines.append(String(decoding: pretty.prefix(3_000), as: UTF8.self))
        }
        return lines.joined(separator: "\n")
    }

    private static func firstIdentifier(in data: Data) -> Int? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = object["result"] as? [[String: Any]] else {
            return nil
        }
        return list.compactMap { $0["id"] as? Int }.first
    }

    // MARK: Appels

    private func call<Payload: Decodable & Sendable>(
        _ endpoint: FreeboxEndpoint,
        _ path: String,
        method: String = "GET",
        body: [String: String]? = nil,
        sessionToken: String? = nil
    ) async throws -> Payload {
        guard let url = URL(string: "\(scheme)://\(endpoint.host)\(endpoint.basePath)\(path)") else {
            throw FreeboxError.badResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let sessionToken {
            request.setValue(sessionToken, forHTTPHeaderField: "X-Fbx-App-Auth")
        }
        let data = try await fetch(request)
        // L'état est lu d'abord, sans le contenu : une erreur porte parfois un `result` d'une autre forme.
        guard let status = try? JSONDecoder().decode(FreeboxStatus.self, from: data) else {
            throw FreeboxError.badResponse
        }
        guard status.success else {
            switch status.errorCode {
            case "auth_required": throw FreeboxError.authenticationRequired
            case "invalid_token": throw FreeboxError.invalidToken
            default: throw FreeboxError.api(code: status.errorCode ?? "", message: status.message ?? "")
            }
        }
        guard let envelope = try? JSONDecoder().decode(FreeboxEnvelope<Payload>.self, from: data) else {
            throw FreeboxError.badResponse
        }
        // Une liste vide peut être omise par la box : `result` est alors absent.
        if let result = envelope.result { return result }
        if let empty = try? JSONDecoder().decode(Payload.self, from: Data("[]".utf8)) { return empty }
        throw FreeboxError.badResponse
    }

    /// Corps de la réponse, quel que soit le code HTTP : la box décrit ses erreurs dans le corps.
    private func fetch(_ request: URLRequest) async throws -> Data {
        do {
            let (data, _) = try await session.data(for: request)
            return data
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            // Un certificat refusé interrompt la connexion de la même façon qu'une annulation.
            if trust.takeRefusal() { throw FreeboxError.untrustedCertificate }
            throw CancellationError()
        } catch let error as URLError where error.code == .serverCertificateUntrusted
            || error.code == .serverCertificateHasBadDate
            || error.code == .serverCertificateHasUnknownRoot
            || error.code == .serverCertificateNotYetValid
            || error.code == .secureConnectionFailed {
            throw FreeboxError.untrustedCertificate
        } catch {
            throw FreeboxError.unreachable
        }
    }
}
