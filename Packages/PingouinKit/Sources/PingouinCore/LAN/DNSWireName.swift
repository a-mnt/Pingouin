import Foundation

/// Noms de domaine au format des messages DNS (RFC 1035) : suite de labels précédés de leur longueur,
/// terminée par un octet nul.
public enum DNSWireName {

    /// Décode un nom non compressé. Renvoie `nil` si les données sont tronquées, sans terminaison,
    /// vides, ou si elles utilisent la compression (que l'API système ne renvoie pas).
    public static func decode(_ bytes: [UInt8]) -> String? {
        var labels: [String] = []
        var index = 0
        while index < bytes.count {
            let length = Int(bytes[index])
            if length == 0 {
                return labels.isEmpty ? nil : labels.joined(separator: ".")
            }
            guard length & 0xC0 == 0, index + 1 + length <= bytes.count else { return nil }
            labels.append(String(decoding: bytes[(index + 1)..<(index + 1 + length)], as: UTF8.self))
            index += 1 + length
        }
        return nil
    }

    /// Nom à interroger pour la recherche inverse d'une adresse IPv4, par exemple
    /// `20.1.168.192.in-addr.arpa.` pour 192.168.1.20.
    public static func reverseLookupName(for address: IPAddressV4) -> String {
        let octets = address.octets
        return "\(octets[3]).\(octets[2]).\(octets[1]).\(octets[0]).in-addr.arpa."
    }
}
