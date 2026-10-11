import Foundation
import PingouinCore

public struct HTTPProbeOptions: Sendable {
    /// Méthode HTTP : GET, HEAD ou OPTIONS.
    public var method: String
    public var followRedirects: Bool
    /// Nombre maximal de redirections suivies, de 0 à 20.
    public var maximumRedirects: Int
    public var timeoutSeconds: Double

    public init(method: String = "GET", followRedirects: Bool = true, maximumRedirects: Int = 5, timeoutSeconds: Double = 15) {
        self.method = method
        self.followRedirects = followRedirects
        self.maximumRedirects = maximumRedirects
        self.timeoutSeconds = timeoutSeconds
    }

    public static let allowedMethods = ["GET", "HEAD", "OPTIONS"]
}

public struct HTTPRedirect: Hashable, Sendable {
    public let statusCode: Int
    /// URL qui a répondu par une redirection.
    public let url: String
    /// Destination annoncée.
    public let location: String
    /// Faux si la redirection a été constatée mais pas suivie (option désactivée ou limite atteinte).
    public let followed: Bool

    public init(statusCode: Int, url: String, location: String, followed: Bool) {
        self.statusCode = statusCode
        self.url = url
        self.location = location
        self.followed = followed
    }
}

public struct HTTPHeader: Hashable, Sendable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct HTTPProbeResult: Sendable {
    public let finalURL: String
    public let statusCode: Int
    public let headers: [HTTPHeader]
    public let bodyByteCount: Int
    public let redirects: [HTTPRedirect]
    /// Durée totale, redirections comprises, en millisecondes.
    public let totalMilliseconds: Double
    /// Décomposition de la dernière requête (celle qui a produit la réponse finale).
    public let timing: HTTPTimingBreakdown?
    /// Protocole négocié, par exemple « h2 » ou « http/1.1 ».
    public let protocolName: String?

    public init(
        finalURL: String,
        statusCode: Int,
        headers: [HTTPHeader],
        bodyByteCount: Int,
        redirects: [HTTPRedirect],
        totalMilliseconds: Double,
        timing: HTTPTimingBreakdown?,
        protocolName: String?
    ) {
        self.finalURL = finalURL
        self.statusCode = statusCode
        self.headers = headers
        self.bodyByteCount = bodyByteCount
        self.redirects = redirects
        self.totalMilliseconds = totalMilliseconds
        self.timing = timing
        self.protocolName = protocolName
    }
}

public enum HTTPProbeError: Error, Equatable, Sendable {
    case unsupportedMethod
    case timedOut
    case hostNotFound
    case cannotConnect
    /// La connexion sécurisée a échoué : certificat refusé ou négociation impossible.
    case secureConnectionFailed(String)
    case notHTTPResponse
    case other(String)
}

/// Contrat de la sonde HTTP, pour pouvoir l'injecter et la remplacer dans les tests.
public protocol HTTPProbing: Sendable {
    func send(url: URL, options: HTTPProbeOptions) async throws -> HTTPProbeResult
}

/// Sonde HTTP bâtie sur URLSession, avec la validation TLS normale du système.
/// Chaque requête utilise une session éphémère : ni cache, ni cookies, ni identifiants conservés.
public struct URLSessionHTTPProbe: HTTPProbing {
    public init() {}

    public func send(url: URL, options: HTTPProbeOptions) async throws -> HTTPProbeResult {
        let method = options.method.uppercased()
        guard HTTPProbeOptions.allowedMethods.contains(method) else { throw HTTPProbeError.unsupportedMethod }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = min(max(options.timeoutSeconds, 1), 120)
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: url)
        request.httpMethod = method

        let collector = Collector(
            followRedirects: options.followRedirects,
            maximumRedirects: min(max(options.maximumRedirects, 0), 20)
        )
        let started = Date()

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: collector)
        } catch let error as URLError {
            throw Self.translate(error)
        } catch {
            throw HTTPProbeError.other(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw HTTPProbeError.notHTTPResponse }

        let snapshot = collector.snapshot()
        let headers = http.allHeaderFields
            .map { HTTPHeader(name: String(describing: $0.key), value: String(describing: $0.value)) }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }

        return HTTPProbeResult(
            finalURL: http.url?.absoluteString ?? url.absoluteString,
            statusCode: http.statusCode,
            headers: headers,
            bodyByteCount: data.count,
            redirects: snapshot.redirects,
            totalMilliseconds: (snapshot.totalSeconds ?? Date().timeIntervalSince(started)) * 1_000,
            timing: snapshot.marks.map { HTTPTimingBreakdown(marks: $0) },
            protocolName: snapshot.protocolName
        )
    }

    private static func translate(_ error: URLError) -> HTTPProbeError {
        switch error.code {
        case .timedOut:
            return .timedOut
        case .cannotFindHost, .dnsLookupFailed:
            return .hostNotFound
        case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
            return .cannotConnect
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected,
             .clientCertificateRequired:
            return .secureConnectionFailed(error.localizedDescription)
        default:
            return .other(error.localizedDescription)
        }
    }

    /// Recueille les redirections et les mesures de temps pendant la requête.
    /// Les méthodes du délégué sont appelées sur la file de la session : l'état est protégé par un verrou.
    private final class Collector: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        struct Snapshot {
            var redirects: [HTTPRedirect] = []
            var marks: HTTPTimingMarks?
            var protocolName: String?
            var totalSeconds: Double?
        }

        private let followRedirects: Bool
        private let maximumRedirects: Int
        private let lock = NSLock()
        private var state = Snapshot()

        init(followRedirects: Bool, maximumRedirects: Int) {
            self.followRedirects = followRedirects
            self.maximumRedirects = maximumRedirects
        }

        func snapshot() -> Snapshot {
            lock.withLock { state }
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest
        ) async -> URLRequest? {
            let follow = lock.withLock { () -> Bool in
                let follow = followRedirects && state.redirects.count < maximumRedirects
                state.redirects.append(HTTPRedirect(
                    statusCode: response.statusCode,
                    url: response.url?.absoluteString ?? "",
                    location: request.url?.absoluteString ?? "",
                    followed: follow
                ))
                return follow
            }
            // Rendre `nil` arrête la chaîne : la réponse de redirection devient la réponse finale.
            return follow ? request : nil
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
            guard let last = metrics.transactionMetrics.last else { return }
            var marks = HTTPTimingMarks()
            marks.fetchStart = last.fetchStartDate
            marks.domainLookupStart = last.domainLookupStartDate
            marks.domainLookupEnd = last.domainLookupEndDate
            marks.connectStart = last.connectStartDate
            marks.connectEnd = last.connectEndDate
            marks.secureConnectionStart = last.secureConnectionStartDate
            marks.secureConnectionEnd = last.secureConnectionEndDate
            marks.requestStart = last.requestStartDate
            marks.responseStart = last.responseStartDate
            marks.responseEnd = last.responseEndDate

            let protocolName = last.networkProtocolName
            let totalSeconds = metrics.taskInterval.duration
            lock.withLock {
                state.marks = marks
                state.protocolName = protocolName
                state.totalSeconds = totalSeconds
            }
        }
    }
}
