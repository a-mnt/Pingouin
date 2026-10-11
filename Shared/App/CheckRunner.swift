import Foundation
import PingouinCore
import PingouinNetwork

/// Résultat d'un contrôle ponctuel, tel que le consomment la supervision et l'automatisation.
struct CheckResult: Sendable, Equatable {
    enum Level: String, Sendable, Codable {
        case ok
        case warning
        case failure
    }

    let level: Level
    let milliseconds: Double?
    let detail: String

    var succeeded: Bool { level != .failure }
}

/// Contrôles ponctuels bâtis sur les services réseau de l'application : un ping, une connexion TCP,
/// une requête HTTP, une question DNS, une inspection TLS. Chaque appel fait un seul essai.
struct CheckRunner: Sendable {
    private static let timeoutMilliseconds = 2_000

    func ping(host: String) async -> CheckResult {
        let options = PingOptions(count: 1, intervalSeconds: 1, timeoutMilliseconds: Self.timeoutMilliseconds)
        do {
            for try await event in ICMPPinger().ping(host: host, options: options) {
                switch event {
                case .reply(_, let milliseconds, _):
                    return CheckResult(level: .ok, milliseconds: milliseconds, detail: L("Réponse en ") + NumberInput.milliseconds(milliseconds))
                case .timeout:
                    return CheckResult(level: .failure, milliseconds: nil, detail: L("Aucune réponse au ping"))
                case .sendFailure(_, let code):
                    return CheckResult(level: .failure, milliseconds: nil, detail: L("Envoi impossible (code \(code))"))
                case .resolved, .finished:
                    continue
                }
            }
            return CheckResult(level: .failure, milliseconds: nil, detail: L("Aucune réponse au ping"))
        } catch PingError.hostNotFound {
            return CheckResult(level: .failure, milliseconds: nil, detail: L("Nom d'hôte introuvable"))
        } catch {
            return CheckResult(level: .failure, milliseconds: nil, detail: L("Ping impossible"))
        }
    }

    func tcp(host: String, port: UInt16) async -> CheckResult {
        let options = PortScanOptions(timeoutMilliseconds: Self.timeoutMilliseconds, concurrency: 1)
        do {
            for try await event in TCPPortScanner().scan(host: host, ports: [port], options: options) {
                guard case .result(let result) = event else { continue }
                switch result.detail {
                case .accepted(let milliseconds):
                    return CheckResult(level: .ok, milliseconds: milliseconds, detail: L("Port \(port) ouvert"))
                case .refused:
                    return CheckResult(level: .failure, milliseconds: nil, detail: L("Port \(port) fermé"))
                case .timedOut:
                    return CheckResult(level: .failure, milliseconds: nil, detail: L("Port \(port) sans réponse"))
                case .networkError:
                    return CheckResult(level: .failure, milliseconds: nil, detail: L("Port \(port) injoignable"))
                }
            }
            return CheckResult(level: .failure, milliseconds: nil, detail: L("Port \(port) sans réponse"))
        } catch PortScanError.hostNotFound {
            return CheckResult(level: .failure, milliseconds: nil, detail: L("Nom d'hôte introuvable"))
        } catch {
            return CheckResult(level: .failure, milliseconds: nil, detail: L("Connexion impossible"))
        }
    }

    /// `expectedStatus` : code attendu ; sans lui, tout code inférieur à 400 est un succès.
    func http(urlText: String, expectedStatus: Int? = nil) async -> CheckResult {
        guard let url = HTTPTarget.url(from: urlText) else {
            return CheckResult(level: .failure, milliseconds: nil, detail: L("URL non valide"))
        }
        do {
            let result = try await URLSessionHTTPProbe().send(url: url, options: HTTPProbeOptions(method: "GET", timeoutSeconds: 10))
            let isExpected = expectedStatus.map { $0 == result.statusCode } ?? (result.statusCode < 400)
            return CheckResult(
                level: isExpected ? .ok : .failure,
                milliseconds: result.totalMilliseconds,
                detail: isExpected ? L("Code \(result.statusCode)") : L("Code \(result.statusCode) inattendu")
            )
        } catch HTTPProbeError.timedOut {
            return CheckResult(level: .failure, milliseconds: nil, detail: L("Délai dépassé"))
        } catch HTTPProbeError.hostNotFound {
            return CheckResult(level: .failure, milliseconds: nil, detail: L("Nom d'hôte introuvable"))
        } catch HTTPProbeError.secureConnectionFailed {
            return CheckResult(level: .failure, milliseconds: nil, detail: L("Connexion sécurisée refusée"))
        } catch {
            return CheckResult(level: .failure, milliseconds: nil, detail: L("Requête impossible"))
        }
    }

    func dns(name: String) async -> CheckResult {
        do {
            let result = try await UDPDNSClient().query(name: name, type: .a, server: nil, timeoutMilliseconds: Self.timeoutMilliseconds)
            switch result.outcome {
            case .answers(let records):
                return CheckResult(level: .ok, milliseconds: result.milliseconds, detail: L("\(records.count) enregistrements"))
            case .truncated:
                return CheckResult(level: .ok, milliseconds: result.milliseconds, detail: L("Réponse tronquée"))
            case .noRecords:
                return CheckResult(level: .failure, milliseconds: result.milliseconds, detail: L("Aucun enregistrement A"))
            case .nonexistentDomain:
                return CheckResult(level: .failure, milliseconds: result.milliseconds, detail: L("Domaine inexistant"))
            case .serverFailure(let code):
                return CheckResult(level: .failure, milliseconds: result.milliseconds, detail: L("Erreur du serveur DNS (code \(code))"))
            case .timedOut:
                return CheckResult(level: .failure, milliseconds: nil, detail: L("Serveur DNS sans réponse"))
            case .networkError, .malformedResponse:
                return CheckResult(level: .failure, milliseconds: nil, detail: L("Serveur DNS injoignable"))
            }
        } catch {
            return CheckResult(level: .failure, milliseconds: nil, detail: L("Requête DNS impossible"))
        }
    }

    /// Avertit quand le certificat expire dans moins de `warningDays` jours.
    func tls(target: String, warningDays: Int = CertificateExpiry.warningDays) async -> CheckResult {
        guard let parts = HostPort.split(target, defaultPort: 443) else {
            return CheckResult(level: .failure, milliseconds: nil, detail: L("Hôte non valide"))
        }
        do {
            let started = Date()
            let result = try await NetworkTLSInspector().inspect(host: parts.host, port: parts.port, serverName: nil, timeoutSeconds: 10)
            let elapsed = Date().timeIntervalSince(started) * 1_000
            guard result.isTrusted else {
                return CheckResult(level: .failure, milliseconds: elapsed, detail: L("Certificat refusé par \(Platform.systemName)"))
            }
            let leaf = result.chain.first
            switch CertificateExpiry.evaluate(notBefore: leaf?.notBefore, notAfter: leaf?.notAfter, now: Date()) {
            case .valid(let days), .expiringSoon(let days):
                let level: CheckResult.Level = days < warningDays ? .warning : .ok
                return CheckResult(level: level, milliseconds: elapsed, detail: L("Certificat valide encore \(days) jours"))
            case .expired:
                return CheckResult(level: .failure, milliseconds: elapsed, detail: L("Certificat expiré"))
            case .notYetValid:
                return CheckResult(level: .failure, milliseconds: elapsed, detail: L("Certificat pas encore valide"))
            case .unknown:
                return CheckResult(level: .warning, milliseconds: elapsed, detail: L("Certificat approuvé, date d'expiration illisible"))
            }
        } catch TLSInspectionError.timedOut {
            return CheckResult(level: .failure, milliseconds: nil, detail: L("Délai dépassé"))
        } catch {
            return CheckResult(level: .failure, milliseconds: nil, detail: L("Négociation TLS impossible"))
        }
    }
}
