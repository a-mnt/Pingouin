import Foundation

/// Adresse MAC sur 48 bits.
public struct MACAddress: Hashable, Sendable, CustomStringConvertible {
    public let bytes: [UInt8]

    public init?(bytes: [UInt8]) {
        guard bytes.count == 6 else { return nil }
        self.bytes = bytes
    }

    /// Analyse une adresse à six groupes hexadécimaux séparés par « : » ou « - ».
    /// Les groupes d'un seul chiffre sont acceptés, car `arp` n'écrit pas les zéros de tête (« 0:1c:42:0:0:8 »).
    public init?(_ string: String) {
        let separator: Character = string.contains("-") ? "-" : ":"
        let parts = string.split(separator: separator, omittingEmptySubsequences: false)
        guard parts.count == 6 else { return nil }
        var result: [UInt8] = []
        result.reserveCapacity(6)
        for part in parts {
            guard (1...2).contains(part.count),
                  part.allSatisfy({ $0.isASCII && $0.isHexDigit }),
                  let value = UInt8(part, radix: 16) else { return nil }
            result.append(value)
        }
        self.bytes = result
    }

    public var isBroadcast: Bool { bytes.allSatisfy { $0 == 0xFF } }

    /// Bit de groupe : l'adresse désigne plusieurs stations (multidiffusion ou broadcast).
    public var isMulticast: Bool { bytes[0] & 0x01 != 0 }

    /// Bit « administrée localement » : typique des adresses privées aléatoires des téléphones et ordinateurs récents.
    public var isLocallyAdministered: Bool { bytes[0] & 0x02 != 0 }

    /// Forme normalisée : minuscules, deux chiffres par octet.
    public var description: String {
        bytes
            .map { byte in
                let digits = String(byte, radix: 16)
                return digits.count == 1 ? "0" + digits : digits
            }
            .joined(separator: ":")
    }
}
