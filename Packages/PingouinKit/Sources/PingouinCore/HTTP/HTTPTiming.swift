import Foundation

/// Instants relevés pendant une requête HTTP. Tous sont optionnels : une connexion réutilisée,
/// par exemple, n'a ni résolution DNS ni négociation TLS.
public struct HTTPTimingMarks: Equatable, Sendable {
    public var fetchStart: Date?
    public var domainLookupStart: Date?
    public var domainLookupEnd: Date?
    public var connectStart: Date?
    public var connectEnd: Date?
    public var secureConnectionStart: Date?
    public var secureConnectionEnd: Date?
    public var requestStart: Date?
    public var responseStart: Date?
    public var responseEnd: Date?

    public init() {}
}

/// Décomposition du temps d'une requête, en millisecondes. Une phase absente vaut `nil`.
public struct HTTPTimingBreakdown: Equatable, Sendable {
    public let dnsLookup: Double?
    /// Établissement de la connexion TCP, hors négociation TLS.
    public let tcpConnect: Double?
    public let tlsHandshake: Double?
    /// Attente entre l'envoi de la requête et le premier octet de la réponse.
    public let firstByte: Double?
    public let transfer: Double?

    public init(marks: HTTPTimingMarks) {
        func span(_ start: Date?, _ end: Date?) -> Double? {
            guard let start, let end, end >= start else { return nil }
            return end.timeIntervalSince(start) * 1_000
        }
        dnsLookup = span(marks.domainLookupStart, marks.domainLookupEnd)
        // Quand il y a du TLS, la connexion TCP se termine là où la négociation commence.
        tcpConnect = span(marks.connectStart, marks.secureConnectionStart ?? marks.connectEnd)
        tlsHandshake = span(marks.secureConnectionStart, marks.secureConnectionEnd)
        firstByte = span(marks.requestStart, marks.responseStart)
        transfer = span(marks.responseStart, marks.responseEnd)
    }

    /// Somme des phases mesurées.
    public var measuredTotal: Double {
        [dnsLookup, tcpConnect, tlsHandshake, firstByte, transfer].compactMap { $0 }.reduce(0, +)
    }
}

public enum HTTPTarget {
    /// Transforme une saisie en URL HTTP ou HTTPS. Sans schéma, « https:// » est ajouté.
    /// Renvoie `nil` pour un autre schéma, une URL sans hôte ou une saisie contenant des espaces.
    public static func url(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isWhitespace }) else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              components.host?.isEmpty == false,
              let url = components.url else { return nil }
        return url
    }
}
