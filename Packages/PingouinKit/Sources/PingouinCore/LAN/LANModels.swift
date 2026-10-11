import Foundation

/// Interface réseau locale disposant d'une adresse IPv4.
public struct LocalInterface: Hashable, Sendable, Identifiable {
    public let name: String
    public let address: IPAddressV4
    public let subnet: IPv4Subnet

    public init(name: String, address: IPAddressV4, subnet: IPv4Subnet) {
        self.name = name
        self.address = address
        self.subnet = subnet
    }

    public var id: String { "\(name)/\(address)" }
}

/// Hôte repéré sur le réseau local. Chaque champ optionnel n'est renseigné que s'il a réellement été observé.
public struct DiscoveredHost: Hashable, Sendable, Identifiable {
    public let address: IPAddressV4
    public var macAddress: MACAddress?
    public var hostname: String?
    /// Temps de réponse au ping, en millisecondes. `nil` si l'hôte n'a pas répondu au ping.
    public var responseMilliseconds: Double?
    /// Vrai pour l'adresse de ce Mac sur l'interface utilisée.
    public var isLocalDevice: Bool
    /// Adresses IPv6 du même appareil, reconnues par son adresse MAC dans la table des voisins.
    public var ipv6Addresses: [IPAddressV6]

    public init(
        address: IPAddressV4,
        macAddress: MACAddress? = nil,
        hostname: String? = nil,
        responseMilliseconds: Double? = nil,
        isLocalDevice: Bool = false,
        ipv6Addresses: [IPAddressV6] = []
    ) {
        self.address = address
        self.macAddress = macAddress
        self.hostname = hostname
        self.responseMilliseconds = responseMilliseconds
        self.isLocalDevice = isLocalDevice
        self.ipv6Addresses = ipv6Addresses
    }

    public var id: UInt32 { address.rawValue }

    public var respondedToPing: Bool { responseMilliseconds != nil }
}

/// Appareil vu dans la table des voisins IPv6 sans adresse IPv4 connue sur la plage.
public struct IPv6OnlyNeighbor: Hashable, Sendable, Identifiable {
    public let macAddress: MACAddress
    public let addresses: [IPAddressV6]

    public init(macAddress: MACAddress, addresses: [IPAddressV6]) {
        self.macAddress = macAddress
        self.addresses = addresses
    }

    public var id: String { macAddress.description }
}

/// Décision prise avant de lancer une découverte, selon la taille de la plage.
public enum LANScanDecision: Equatable, Sendable {
    case allowed(hostCount: Int)
    case needsConfirmation(hostCount: Int)
    case refused(hostCount: UInt64, maximum: Int)
}

/// Règles de taille : une découverte ne part jamais seule sur une grande plage.
public enum LANScanPlan {
    /// Au-delà de ce nombre d'adresses (un /24), une confirmation explicite est demandée.
    public static let confirmationThreshold = 254
    /// Au-delà de ce nombre d'adresses (un /20), la découverte est refusée.
    public static let maximumHosts = 4094

    public static func decision(for subnet: IPv4Subnet) -> LANScanDecision {
        let count = subnet.usableHostCount
        if count > UInt64(maximumHosts) {
            return .refused(hostCount: count, maximum: maximumHosts)
        }
        if count > UInt64(confirmationThreshold) {
            return .needsConfirmation(hostCount: Int(count))
        }
        return .allowed(hostCount: Int(count))
    }

    /// Adresses à interroger, dans l'ordre. Vide si la plage dépasse la limite.
    public static func targets(in subnet: IPv4Subnet) -> [IPAddressV4] {
        let count = subnet.usableHostCount
        guard count <= UInt64(maximumHosts) else { return [] }
        let first = subnet.firstUsable.rawValue
        return (0..<UInt32(count)).map { IPAddressV4(rawValue: first + $0) }
    }
}
