import Foundation

/// Situation d'un certificat par rapport à sa période de validité.
public enum CertificateExpiry: Equatable, Sendable {
    /// La date de début de validité n'est pas encore atteinte.
    case notYetValid
    case expired(daysAgo: Int)
    /// Valide, mais la fin approche (moins de `warningDays` jours).
    case expiringSoon(daysLeft: Int)
    case valid(daysLeft: Int)
    /// Les dates n'ont pas pu être lues.
    case unknown

    /// Seuil en dessous duquel une expiration est signalée.
    public static let warningDays = 30

    public static func evaluate(notBefore: Date?, notAfter: Date?, now: Date) -> CertificateExpiry {
        guard let notAfter else { return .unknown }
        if let notBefore, now < notBefore { return .notYetValid }
        let secondsPerDay = 86_400.0
        if now > notAfter {
            return .expired(daysAgo: Int(now.timeIntervalSince(notAfter) / secondsPerDay))
        }
        // Jours entiers restants : 21,9 jours s'affichent « 21 jours ».
        let daysLeft = Int(notAfter.timeIntervalSince(now) / secondsPerDay)
        return daysLeft < warningDays ? .expiringSoon(daysLeft: daysLeft) : .valid(daysLeft: daysLeft)
    }
}

/// Séparation « hôte:port » d'une saisie.
public enum HostPort {
    /// Sépare l'hôte du port. Sans port, `defaultPort` est utilisé. Une adresse IPv6 doit être
    /// entre crochets pour porter un port : « [2001:db8::1]:443 ».
    public static func split(_ input: String, defaultPort: UInt16) -> (host: String, port: UInt16)? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("[") {
            guard let close = trimmed.firstIndex(of: "]") else { return nil }
            let host = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
            let rest = trimmed[trimmed.index(after: close)...]
            guard HostInput.isPlausible(host) else { return nil }
            if rest.isEmpty { return (host, defaultPort) }
            guard rest.hasPrefix(":"), let port = parsePort(rest.dropFirst()) else { return nil }
            return (host, port)
        }

        let colons = trimmed.filter { $0 == ":" }.count
        if colons == 1, let separator = trimmed.firstIndex(of: ":") {
            let host = String(trimmed[..<separator])
            guard HostInput.isPlausible(host),
                  let port = parsePort(trimmed[trimmed.index(after: separator)...]) else { return nil }
            return (host, port)
        }
        // Aucun deux-points (nom ou IPv4) ou plusieurs (IPv6 nue) : pas de port dans la saisie.
        guard HostInput.isPlausible(trimmed) else { return nil }
        return (trimmed, defaultPort)
    }

    private static func parsePort(_ text: Substring) -> UInt16? {
        guard !text.isEmpty, text.count <= 5, text.allSatisfy({ $0.isASCII && $0.isWholeNumber }),
              let value = UInt16(text), value > 0 else { return nil }
        return value
    }
}
