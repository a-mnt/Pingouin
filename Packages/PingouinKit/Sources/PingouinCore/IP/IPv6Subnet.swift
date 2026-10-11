import Foundation

/// Nature d'une plage IPv6, déterminée à partir de l'adresse réseau.
public enum IPv6RangeKind: Hashable, Sendable {
    case unspecified     // ::/128
    case loopback        // ::1/128
    case ipv4Mapped      // ::ffff:0:0/96
    case linkLocal       // fe80::/10
    case uniqueLocal     // fc00::/7
    case multicast       // ff00::/8
    case documentation   // 2001:db8::/32
    case globalUnicast   // 2000::/3
    case reserved
}

/// Réseau IPv6 en notation CIDR. L'adresse réseau est toujours normalisée.
/// Il n'existe pas d'adresse de broadcast en IPv6 : toute la plage est adressable.
public struct IPv6Subnet: Hashable, Sendable, CustomStringConvertible {
    public let network: IPAddressV6
    public let prefixLength: Int

    public init?(address: IPAddressV6, prefixLength: Int) {
        guard (0...128).contains(prefixLength) else { return nil }
        self.prefixLength = prefixLength
        self.network = IPAddressV6(rawValue: address.rawValue & Self.maskValue(prefixLength))
    }

    static func maskValue(_ prefixLength: Int) -> UInt128 {
        prefixLength <= 0 ? 0 : UInt128.max << UInt128(128 - prefixLength)
    }

    private var maskValue: UInt128 { Self.maskValue(prefixLength) }

    public var lastAddress: IPAddressV6 { IPAddressV6(rawValue: network.rawValue | ~maskValue) }

    /// Nombre d'adresses, ou `nil` pour un /0 dont le total (2^128) dépasse la capacité d'un entier de 128 bits.
    public var addressCount: UInt128? {
        prefixLength == 0 ? nil : UInt128(1) << UInt128(128 - prefixLength)
    }

    /// Nombre d'adresses sous forme lisible, y compris pour un /0.
    public var addressCountDescription: String {
        guard let count = addressCount else { return "2^128" }
        return String(count)
    }

    public func contains(_ address: IPAddressV6) -> Bool {
        address.rawValue & maskValue == network.rawValue
    }

    /// Nombre de sous-réseaux obtenus avec un préfixe plus long. `nil` si le préfixe ne convient pas
    /// ou si le total dépasse la capacité d'un entier de 128 bits (découpage d'un /0 en /128).
    public func subnetCount(prefixLength newPrefix: Int) -> UInt128? {
        guard newPrefix > prefixLength, newPrefix <= 128 else { return nil }
        let bits = newPrefix - prefixLength
        return bits >= 128 ? nil : UInt128(1) << UInt128(bits)
    }

    /// Indique si le préfixe demandé est valide pour un découpage, indépendamment du nombre obtenu.
    public func canSplit(prefixLength newPrefix: Int) -> Bool {
        newPrefix > prefixLength && newPrefix <= 128
    }

    /// Les `limit` premiers sous-réseaux du découpage.
    public func subnets(prefixLength newPrefix: Int, limit: Int) -> [IPv6Subnet] {
        guard canSplit(prefixLength: newPrefix), limit > 0 else { return [] }
        let shown: Int
        if let count = subnetCount(prefixLength: newPrefix), count < UInt128(limit) {
            shown = Int(count)
        } else {
            shown = limit
        }
        // Pas entre deux sous-réseaux consécutifs. Pour un /128 le pas vaut 1.
        let step: UInt128 = UInt128(1) << UInt128(128 - newPrefix)
        var result: [IPv6Subnet] = []
        result.reserveCapacity(shown)
        for index in 0..<shown {
            let raw = network.rawValue + UInt128(index) * step
            if let subnet = IPv6Subnet(address: IPAddressV6(rawValue: raw), prefixLength: newPrefix) {
                result.append(subnet)
            }
        }
        return result
    }

    public var kind: IPv6RangeKind {
        func within(_ base: String, _ prefix: Int) -> Bool {
            guard let address = IPAddressV6(base),
                  let range = IPv6Subnet(address: address, prefixLength: prefix) else { return false }
            return range.contains(network)
        }
        if prefixLength == 128, network.rawValue == 0 { return .unspecified }
        if prefixLength == 128, network.rawValue == 1 { return .loopback }
        if within("::ffff:0:0", 96) { return .ipv4Mapped }
        if within("fe80::", 10) { return .linkLocal }
        if within("fc00::", 7) { return .uniqueLocal }
        if within("ff00::", 8) { return .multicast }
        if within("2001:db8::", 32) { return .documentation }
        if within("2000::", 3) { return .globalUnicast }
        return .reserved
    }

    public var description: String { "\(network)/\(prefixLength)" }
}
