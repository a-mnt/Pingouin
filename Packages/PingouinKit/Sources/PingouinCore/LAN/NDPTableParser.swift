import Foundation

/// Entrée de la table des voisins IPv6 du système (l'équivalent IPv6 de la table ARP).
public struct NDPEntry: Hashable, Sendable {
    public let address: IPAddressV6
    /// Absente quand la résolution n'a pas abouti (« incomplete »).
    public let macAddress: MACAddress?
    public let interfaceName: String
    /// Vrai pour les adresses de ce Mac lui-même.
    public let isPermanent: Bool

    public init(address: IPAddressV6, macAddress: MACAddress?, interfaceName: String, isPermanent: Bool) {
        self.address = address
        self.macAddress = macAddress
        self.interfaceName = interfaceName
        self.isPermanent = isPermanent
    }

    /// Adresse de liaison locale (fe80::/10) : elle n'a de sens que sur son interface.
    public var isLinkLocal: Bool {
        address.rawValue >> 118 == 0x3FA
    }
}

/// Lecture de la sortie de `ndp -an`, dont les lignes ont la forme :
/// `fe80::1%en0   0:11:22:33:44:55   en0 23h59m58s S  R`
public enum NDPTableParser {
    public static func parse(_ output: String) -> [NDPEntry] {
        var entries: [NDPEntry] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let words = line.split(separator: " ").map(String.init)
            guard words.count >= 4 else { continue }
            // La zone (« %en0 ») suit l'adresse de liaison locale ; l'interface a aussi sa colonne.
            let addressText = words[0].split(separator: "%", maxSplits: 1).first.map(String.init) ?? words[0]
            guard let address = IPAddressV6(addressText) else { continue }
            entries.append(NDPEntry(
                address: address,
                macAddress: MACAddress(words[1]),
                interfaceName: words[2],
                isPermanent: words[3] == "permanent"
            ))
        }
        return entries
    }

    /// Regroupe les adresses IPv6 de l'interface par adresse MAC, les adresses de ce Mac à part.
    /// Les adresses de diffusion groupée et les entrées sans adresse MAC sont écartées.
    public static func addressesByDevice(
        _ entries: [NDPEntry],
        interfaceName: String
    ) -> (neighbors: [MACAddress: [IPAddressV6]], local: [IPAddressV6]) {
        var neighbors: [MACAddress: [IPAddressV6]] = [:]
        var local: [IPAddressV6] = []
        for entry in entries where entry.interfaceName == interfaceName {
            // ff00::/8 : diffusion groupée.
            guard entry.address.rawValue >> 120 != 0xFF else { continue }
            if entry.isPermanent {
                local.append(entry.address)
            } else if let mac = entry.macAddress, !mac.isMulticast {
                neighbors[mac, default: []].append(entry.address)
            }
        }
        return (neighbors.mapValues { Array(Set($0)).sorted() }, Array(Set(local)).sorted())
    }
}
