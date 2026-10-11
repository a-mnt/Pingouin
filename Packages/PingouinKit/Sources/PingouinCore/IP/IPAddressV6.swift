import Foundation

/// Adresse IPv6, stockée sous forme d'entier non signé de 128 bits (ordre réseau).
///
/// Nommée `IPAddressV6` pour ne pas entrer en conflit avec `IPv6Address` du framework Network.
public struct IPAddressV6: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let rawValue: UInt128

    public init(rawValue: UInt128) {
        self.rawValue = rawValue
    }

    /// Analyse d'une adresse IPv6 textuelle. La lecture est confiée à `inet_pton`, qui gère
    /// la compression « :: » et les formes à IPv4 embarquée. Les identifiants de zone (« %en0 »)
    /// sont refusés : ils n'ont pas de sens dans un calcul de sous-réseau.
    public init?(_ string: String) {
        guard !string.isEmpty, !string.contains("%"), !string.contains("/") else { return nil }
        var address = in6_addr()
        guard inet_pton(AF_INET6, string, &address) == 1 else { return nil }
        let bytes = withUnsafeBytes(of: address) { Array($0) }
        guard bytes.count == 16 else { return nil }
        var value: UInt128 = 0
        for byte in bytes {
            value = (value << 8) | UInt128(byte)
        }
        self.rawValue = value
    }

    /// Les huit groupes de 16 bits, du plus significatif au moins significatif.
    public var groups: [UInt16] {
        (0..<8).map { index in
            UInt16(truncatingIfNeeded: rawValue >> UInt128((7 - index) * 16))
        }
    }

    /// Forme canonique selon la RFC 5952 : minuscules, zéros de tête supprimés,
    /// plus longue suite de groupes nuls (au moins deux) remplacée par « :: », la première en cas d'égalité.
    public var description: String {
        let groups = self.groups
        var bestStart = -1
        var bestLength = 0
        var currentStart = -1
        var currentLength = 0
        for (index, group) in groups.enumerated() {
            if group == 0 {
                if currentStart < 0 {
                    currentStart = index
                    currentLength = 0
                }
                currentLength += 1
                if currentLength > bestLength {
                    bestStart = currentStart
                    bestLength = currentLength
                }
            } else {
                currentStart = -1
            }
        }
        func hex(_ slice: ArraySlice<UInt16>) -> String {
            slice.map { String($0, radix: 16) }.joined(separator: ":")
        }
        guard bestLength >= 2 else { return hex(groups[...]) }
        return hex(groups[..<bestStart]) + "::" + hex(groups[(bestStart + bestLength)...])
    }

    /// Forme développée : huit groupes de quatre chiffres hexadécimaux.
    public var expandedDescription: String {
        groups
            .map { group in
                let digits = String(group, radix: 16)
                return String(repeating: "0", count: 4 - digits.count) + digits
            }
            .joined(separator: ":")
    }

    public static func < (lhs: IPAddressV6, rhs: IPAddressV6) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
