import Testing
@testable import PingouinCore

@Suite("Noms DNS au format des messages")
struct DNSWireNameTests {

    private func wire(_ labels: [String], terminated: Bool = true) -> [UInt8] {
        var bytes: [UInt8] = []
        for label in labels {
            let content = Array(label.utf8)
            bytes.append(UInt8(content.count))
            bytes.append(contentsOf: content)
        }
        if terminated { bytes.append(0) }
        return bytes
    }

    @Test func decodeUnNom() {
        #expect(DNSWireName.decode(wire(["MacBook-Pro", "local"])) == "MacBook-Pro.local")
        #expect(DNSWireName.decode(wire(["nas"])) == "nas")
        #expect(DNSWireName.decode(wire(["imprimante-accueil", "home", "arpa"])) == "imprimante-accueil.home.arpa")
    }

    @Test func decodeUnNomAccentue() {
        #expect(DNSWireName.decode(wire(["Mac-de-Zoé", "local"])) == "Mac-de-Zoé.local")
    }

    @Test func refuseDesDonneesInexploitables() {
        #expect(DNSWireName.decode([]) == nil)
        // Nom vide (racine seule).
        #expect(DNSWireName.decode([0]) == nil)
        // Pas d'octet de terminaison.
        #expect(DNSWireName.decode(wire(["nas", "local"], terminated: false)) == nil)
        // Longueur annoncée supérieure aux données restantes.
        #expect(DNSWireName.decode([5, 0x6E, 0x61, 0x73]) == nil)
        // Pointeur de compression.
        #expect(DNSWireName.decode([0xC0, 0x0C]) == nil)
    }

    @Test func construitLeNomDeRechercheInverse() throws {
        let address = try #require(IPAddressV4("192.168.1.20"))
        #expect(DNSWireName.reverseLookupName(for: address) == "20.1.168.192.in-addr.arpa.")
    }
}
