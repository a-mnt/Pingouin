import Testing
@testable import PingouinCore

@Suite("Découverte LAN : logique pure")
struct LANTests {

    // MARK: Adresses MAC

    @Test(arguments: [
        ("0:1c:42:0:0:8", "00:1c:42:00:00:08"),
        ("AA:BB:CC:DD:EE:FF", "aa:bb:cc:dd:ee:ff"),
        ("aa-bb-cc-dd-ee-ff", "aa:bb:cc:dd:ee:ff"),
        ("ff:ff:ff:ff:ff:ff", "ff:ff:ff:ff:ff:ff")
    ])
    func normaliseUneAdresseMAC(input: String, expected: String) throws {
        let mac = try #require(MACAddress(input))
        #expect(mac.description == expected)
    }

    @Test(arguments: ["", "(incomplete)", "aa:bb:cc:dd:ee", "aa:bb:cc:dd:ee:ff:00", "aa:bb:cc:dd:ee:gg", "aaa:bb:cc:dd:ee:ff", "aa::cc:dd:ee:ff"])
    func refuseUneAdresseMACInvalide(text: String) {
        #expect(MACAddress(text) == nil)
    }

    @Test func litLesBitsDUneAdresseMAC() throws {
        let broadcast = try #require(MACAddress("ff:ff:ff:ff:ff:ff"))
        let multicast = try #require(MACAddress("1:0:5e:0:0:fb"))
        let randomized = try #require(MACAddress("da:a1:19:12:34:56"))
        let vendor = try #require(MACAddress("00:1c:42:00:00:08"))
        #expect(broadcast.isBroadcast)
        #expect(broadcast.isMulticast)
        #expect(multicast.isMulticast)
        #expect(!multicast.isBroadcast)
        #expect(randomized.isLocallyAdministered)
        #expect(!randomized.isMulticast)
        #expect(!vendor.isLocallyAdministered)
        #expect(!vendor.isMulticast)
    }

    // MARK: Table ARP

    @Test func litLaSortieDeArp() throws {
        let output = """
        ? (192.168.1.1) at 0:11:22:33:44:55 on en0 ifscope [ethernet]
        ? (192.168.1.50) at (incomplete) on en0 ifscope [ethernet]
        ? (192.168.1.255) at ff:ff:ff:ff:ff:ff on en0 ifscope [ethernet]
        ? (224.0.0.251) at 1:0:5e:0:0:fb on en0 ifscope permanent [ethernet]
        ligne sans rapport
        ? (999.1.1.1) at 0:11:22:33:44:55 on en0 ifscope [ethernet]

        """
        let entries = ARPTableParser.parse(output)
        #expect(entries.count == 4)

        let gateway = try #require(entries.first)
        #expect(gateway.address.description == "192.168.1.1")
        #expect(gateway.macAddress?.description == "00:11:22:33:44:55")
        #expect(gateway.interfaceName == "en0")
        #expect(!gateway.isPermanent)

        #expect(entries[1].address.description == "192.168.1.50")
        #expect(entries[1].macAddress == nil)
        #expect(entries[1].interfaceName == "en0")

        #expect(entries[2].macAddress?.isBroadcast == true)
        #expect(entries[3].isPermanent)
        #expect(entries[3].macAddress?.isMulticast == true)
    }

    @Test func renvoieUneListeVidePourUneSortieVide() {
        #expect(ARPTableParser.parse("").isEmpty)
    }

    // MARK: ICMP Echo

    @Test func construitUneRequeteEcho() {
        let packet = ICMPEcho.request(identifier: 0x1234, sequence: 1)
        #expect(packet == [8, 0, 174, 150, 18, 52, 0, 1, 80, 73, 78, 71, 79, 85, 73, 78])
        // La somme de contrôle d'un message complet et valide vaut zéro.
        #expect(ICMPEcho.checksum(packet) == 0)
    }

    @Test func calculeLaSommeDeControleSurUneLongueurImpaire() {
        #expect(ICMPEcho.checksum([8, 0, 0, 0, 0, 1, 0, 2, 0x41]) == 0xB6FC)
    }

    @Test func litUneReponseSansEnTeteIP() throws {
        let datagram: [UInt8] = [0, 0, 0xAA, 0xBB, 0x12, 0x34, 0, 7, 80, 73]
        let message = try #require(ICMPEcho.parse(datagram: datagram))
        #expect(message.isEchoReply)
        #expect(message.identifier == 0x1234)
        #expect(message.sequence == 7)
        #expect(message.payload == [80, 73])
    }

    @Test func litUneReponsePrecedeeDUnEnTeteIP() throws {
        var datagram = [UInt8](repeating: 0, count: 20)
        datagram[0] = 0x45
        datagram[9] = 1
        datagram.append(contentsOf: [0, 0, 0xAA, 0xBB, 0x12, 0x34, 0, 2, 80, 73, 78, 71])
        let message = try #require(ICMPEcho.parse(datagram: datagram))
        #expect(message.isEchoReply)
        #expect(message.sequence == 2)
        #expect(message.payload == [80, 73, 78, 71])
    }

    @Test func refuseUnDatagrammeInexploitable() {
        #expect(ICMPEcho.parse(datagram: []) == nil)
        #expect(ICMPEcho.parse(datagram: [0, 0, 0]) == nil)
        // En-tête IP annonçant de l'UDP (17) et non de l'ICMP (1).
        var udp = [UInt8](repeating: 0, count: 28)
        udp[0] = 0x45
        udp[9] = 17
        #expect(ICMPEcho.parse(datagram: udp) == nil)
        // En-tête IP tronqué.
        #expect(ICMPEcho.parse(datagram: [0x45, 0, 0, 0]) == nil)
    }

    @Test func distingueUneRequeteDUneReponse() throws {
        let request = try #require(ICMPEcho.parse(datagram: ICMPEcho.request(identifier: 1, sequence: 1)))
        #expect(!request.isEchoReply)
        #expect(request.payload == ICMPEcho.defaultPayload)
    }

    // MARK: Plan de découverte

    private func subnet(_ cidr: String) throws -> IPv4Subnet {
        guard case .success(.v4(let subnet)) = IPSubnet.parse(cidr) else {
            throw TestFailure.notIPv4(cidr)
        }
        return subnet
    }

    enum TestFailure: Error { case notIPv4(String) }

    @Test func autoriseUnSlash24SansConfirmation() throws {
        let net = try subnet("192.168.1.0/24")
        #expect(LANScanPlan.decision(for: net) == .allowed(hostCount: 254))
        let targets = LANScanPlan.targets(in: net)
        #expect(targets.count == 254)
        #expect(targets.first?.description == "192.168.1.1")
        #expect(targets.last?.description == "192.168.1.254")
    }

    @Test func demandeConfirmationAuDelaDUnSlash24() throws {
        let slash23 = try subnet("10.0.0.0/23")
        let slash20 = try subnet("10.0.0.0/20")
        #expect(LANScanPlan.decision(for: slash23) == .needsConfirmation(hostCount: 510))
        #expect(LANScanPlan.decision(for: slash20) == .needsConfirmation(hostCount: 4094))
        #expect(LANScanPlan.targets(in: slash20).count == 4094)
    }

    @Test func refuseUnePlageTropGrande() throws {
        let net = try subnet("10.0.0.0/19")
        #expect(LANScanPlan.decision(for: net) == .refused(hostCount: 8190, maximum: 4094))
        #expect(LANScanPlan.targets(in: net).isEmpty)
    }

    @Test func traiteLesPetitsReseaux() throws {
        let link = try subnet("192.0.2.10/31")
        let host = try subnet("192.0.2.10/32")
        let slash30 = try subnet("192.0.2.8/30")
        #expect(LANScanPlan.targets(in: link).map(\.description) == ["192.0.2.10", "192.0.2.11"])
        #expect(LANScanPlan.targets(in: host).map(\.description) == ["192.0.2.10"])
        #expect(LANScanPlan.targets(in: slash30).map(\.description) == ["192.0.2.9", "192.0.2.10"])
    }

    @Test("La route par défaut donne la passerelle et l'interface")
    func defaultRoute() {
        let output = """
           route to: default
        destination: default
               mask: default
            gateway: 192.168.1.254
          interface: en0
              flags: <UP,GATEWAY,DONE,STATIC,PRCLONING,GLOBAL>
        """
        #expect(DefaultRouteParser.parse(output) == DefaultRoute(gateway: "192.168.1.254", interfaceName: "en0"))
        #expect(DefaultRouteParser.parse("route: writing to routing socket: not in table") == nil)
        #expect(DefaultRouteParser.parse("  interface: en0") == nil)
    }
}
