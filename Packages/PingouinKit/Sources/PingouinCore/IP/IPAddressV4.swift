import Foundation

/// Adresse IPv4, stockée sous forme d'entier non signé de 32 bits (ordre réseau).
///
/// Nommée `IPAddressV4` pour ne pas entrer en conflit avec `IPv4Address` du framework Network.
public struct IPAddressV4: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Analyse stricte d'une notation décimale pointée : exactement quatre octets de 0 à 255.
    ///
    /// Les zéros non significatifs (« 010 ») sont refusés, car certains outils les lisent en octal
    /// et d'autres en décimal : mieux vaut signaler l'ambiguïté que choisir à la place de l'utilisateur.
    public init?(_ string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard !part.isEmpty, part.count <= 3 else { return nil }
            guard part.allSatisfy({ $0.isASCII && $0.isWholeNumber }) else { return nil }
            if part.count > 1, part.first == "0" { return nil }
            guard let octet = UInt32(part), octet <= 255 else { return nil }
            value = (value << 8) | octet
        }
        self.rawValue = value
    }

    public var octets: [UInt8] {
        [
            UInt8(truncatingIfNeeded: rawValue >> 24),
            UInt8(truncatingIfNeeded: rawValue >> 16),
            UInt8(truncatingIfNeeded: rawValue >> 8),
            UInt8(truncatingIfNeeded: rawValue)
        ]
    }

    public var description: String {
        octets.map { String($0) }.joined(separator: ".")
    }

    /// Notation binaire pointée, par exemple `11111111.11111111.11111111.00000000`.
    public var binaryDescription: String {
        octets
            .map { octet in
                let bits = String(octet, radix: 2)
                return String(repeating: "0", count: 8 - bits.count) + bits
            }
            .joined(separator: ".")
    }

    public static func < (lhs: IPAddressV4, rhs: IPAddressV4) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
