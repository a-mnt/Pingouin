import Foundation

/// Adresse d'un hôte, IPv4 ou IPv6.
///
/// Nommée `HostAddress` pour ne pas entrer en conflit avec `IPAddress` du framework Network.
public enum HostAddress: Hashable, Sendable, CustomStringConvertible {
    case v4(IPAddressV4)
    case v6(IPAddressV6)

    /// Adresse littérale. Une zone (« %en0 ») n'est pas acceptée ici.
    public init?(_ text: String) {
        if let address = IPAddressV4(text) {
            self = .v4(address)
        } else if let address = IPAddressV6(text) {
            self = .v6(address)
        } else {
            return nil
        }
    }

    public var isIPv6: Bool {
        if case .v6 = self { return true }
        return false
    }

    public var description: String {
        switch self {
        case .v4(let address): address.description
        case .v6(let address): address.description
        }
    }
}

/// Protocole à utiliser pour joindre un hôte.
public enum IPFamilyChoice: String, Sendable, CaseIterable, Identifiable {
    /// L'adresse saisie décide ; pour un nom, l'IPv4 d'abord, l'IPv6 à défaut.
    case automatic
    case ipv4
    case ipv6

    public var id: String { rawValue }
}
