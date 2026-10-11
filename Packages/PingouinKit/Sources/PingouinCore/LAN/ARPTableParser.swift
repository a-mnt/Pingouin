import Foundation

/// Entrée de la table ARP du système.
public struct ARPEntry: Hashable, Sendable {
    public let address: IPAddressV4
    /// Absente quand la résolution n'a pas abouti (« incomplete »).
    public let macAddress: MACAddress?
    public let interfaceName: String?
    public let isPermanent: Bool

    public init(address: IPAddressV4, macAddress: MACAddress?, interfaceName: String?, isPermanent: Bool) {
        self.address = address
        self.macAddress = macAddress
        self.interfaceName = interfaceName
        self.isPermanent = isPermanent
    }
}

/// Lecture de la sortie de `arp -an`, dont les lignes ont la forme :
/// `? (192.168.1.1) at 0:11:22:33:44:55 on en0 ifscope [ethernet]`
public enum ARPTableParser {
    public static func parse(_ output: String) -> [ARPEntry] {
        var entries: [ARPEntry] = []
        for line in output.split(whereSeparator: \.isNewline) {
            guard let open = line.firstIndex(of: "("),
                  let close = line[open...].firstIndex(of: ")") else { continue }
            let addressText = String(line[line.index(after: open)..<close])
            guard let address = IPAddressV4(addressText) else { continue }

            let words = line[line.index(after: close)...].split(separator: " ").map(String.init)
            var macAddress: MACAddress?
            var interfaceName: String?
            if let index = words.firstIndex(of: "at"), index + 1 < words.count {
                macAddress = MACAddress(words[index + 1])
            }
            if let index = words.firstIndex(of: "on"), index + 1 < words.count {
                interfaceName = words[index + 1]
            }
            entries.append(
                ARPEntry(
                    address: address,
                    macAddress: macAddress,
                    interfaceName: interfaceName,
                    isPermanent: words.contains("permanent")
                )
            )
        }
        return entries
    }
}
