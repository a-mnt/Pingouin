import Foundation

/// Nature d'une plage IPv4, déterminée à partir de l'adresse réseau.
public enum IPv4RangeKind: Hashable, Sendable {
    case privateUse          // RFC 1918
    case loopback            // 127.0.0.0/8
    case linkLocal           // 169.254.0.0/16
    case sharedAddressSpace  // 100.64.0.0/10, RFC 6598
    case documentation       // RFC 5737
    case multicast           // 224.0.0.0/4
    case reserved            // 0.0.0.0/8 et 240.0.0.0/4
    case publicRange
}

/// Réseau IPv4 en notation CIDR. L'adresse réseau est toujours normalisée
/// (les bits d'hôte sont remis à zéro à la construction).
public struct IPv4Subnet: Hashable, Sendable, CustomStringConvertible {
    public let network: IPAddressV4
    public let prefixLength: Int

    public init?(address: IPAddressV4, prefixLength: Int) {
        guard (0...32).contains(prefixLength) else { return nil }
        self.prefixLength = prefixLength
        self.network = IPAddressV4(rawValue: address.rawValue & Self.maskValue(prefixLength))
    }

    /// Longueur de préfixe correspondant à un masque pointé, ou `nil` si le masque n'est pas contigu.
    public static func prefixLength(forMask mask: IPAddressV4) -> Int? {
        let ones = mask.rawValue.nonzeroBitCount
        return mask.rawValue == maskValue(ones) ? ones : nil
    }

    static func maskValue(_ prefixLength: Int) -> UInt32 {
        prefixLength <= 0 ? 0 : UInt32.max << UInt32(32 - prefixLength)
    }

    private var maskValue: UInt32 { Self.maskValue(prefixLength) }

    public var mask: IPAddressV4 { IPAddressV4(rawValue: maskValue) }

    public var wildcardMask: IPAddressV4 { IPAddressV4(rawValue: ~maskValue) }

    /// Dernière adresse de la plage, qu'elle soit utilisable ou non.
    public var lastAddress: IPAddressV4 { IPAddressV4(rawValue: network.rawValue | ~maskValue) }

    /// Adresse de broadcast. Absente pour un /31 (RFC 3021) et un /32.
    public var broadcast: IPAddressV4? { prefixLength >= 31 ? nil : lastAddress }

    public var addressCount: UInt64 { UInt64(1) << UInt64(32 - prefixLength) }

    /// Nombre d'adresses attribuables à des hôtes : 1 pour un /32, 2 pour un /31, sinon total moins deux.
    public var usableHostCount: UInt64 {
        if prefixLength == 32 { return 1 }
        if prefixLength == 31 { return 2 }
        return addressCount - 2
    }

    public var firstUsable: IPAddressV4 {
        prefixLength >= 31 ? network : IPAddressV4(rawValue: network.rawValue + 1)
    }

    public var lastUsable: IPAddressV4 {
        prefixLength >= 31 ? lastAddress : IPAddressV4(rawValue: lastAddress.rawValue - 1)
    }

    public func contains(_ address: IPAddressV4) -> Bool {
        address.rawValue & maskValue == network.rawValue
    }

    /// Nombre de sous-réseaux obtenus avec un préfixe plus long, ou `nil` si le préfixe demandé ne convient pas.
    public func subnetCount(prefixLength newPrefix: Int) -> UInt64? {
        guard newPrefix > prefixLength, newPrefix <= 32 else { return nil }
        return UInt64(1) << UInt64(newPrefix - prefixLength)
    }

    /// Les `limit` premiers sous-réseaux du découpage. La limite évite de matérialiser des millions d'entrées.
    public func subnets(prefixLength newPrefix: Int, limit: Int) -> [IPv4Subnet] {
        guard let count = subnetCount(prefixLength: newPrefix), limit > 0 else { return [] }
        let step = UInt64(1) << UInt64(32 - newPrefix)
        let shown = min(count, UInt64(limit))
        var result: [IPv4Subnet] = []
        result.reserveCapacity(Int(shown))
        var index: UInt64 = 0
        while index < shown {
            let raw = UInt32(UInt64(network.rawValue) + index * step)
            if let subnet = IPv4Subnet(address: IPAddressV4(rawValue: raw), prefixLength: newPrefix) {
                result.append(subnet)
            }
            index += 1
        }
        return result
    }

    public var kind: IPv4RangeKind {
        func within(_ base: String, _ prefix: Int) -> Bool {
            guard let address = IPAddressV4(base),
                  let range = IPv4Subnet(address: address, prefixLength: prefix) else { return false }
            return range.contains(network)
        }
        if within("10.0.0.0", 8) || within("172.16.0.0", 12) || within("192.168.0.0", 16) { return .privateUse }
        if within("127.0.0.0", 8) { return .loopback }
        if within("169.254.0.0", 16) { return .linkLocal }
        if within("100.64.0.0", 10) { return .sharedAddressSpace }
        if within("192.0.2.0", 24) || within("198.51.100.0", 24) || within("203.0.113.0", 24) { return .documentation }
        if within("224.0.0.0", 4) { return .multicast }
        if within("0.0.0.0", 8) || within("240.0.0.0", 4) { return .reserved }
        return .publicRange
    }

    public var description: String { "\(network)/\(prefixLength)" }
}
