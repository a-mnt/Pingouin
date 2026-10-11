import Testing
@testable import PingouinCore

@Suite("IPv4")
struct IPv4Tests {

    private func subnet(_ cidr: String) throws -> IPv4Subnet {
        guard case .success(.v4(let subnet)) = IPSubnet.parse(cidr) else {
            throw TestFailure.notIPv4(cidr)
        }
        return subnet
    }

    enum TestFailure: Error { case notIPv4(String) }

    // MARK: Analyse des adresses

    @Test func analyseUneAdresseValide() {
        #expect(IPAddressV4("192.168.10.57")?.rawValue == 0xC0A8_0A39)
        #expect(IPAddressV4("0.0.0.0")?.rawValue == 0)
        #expect(IPAddressV4("255.255.255.255")?.rawValue == UInt32.max)
    }

    @Test(arguments: [
        "", "1.2.3", "1.2.3.4.5", "256.1.1.1", "1.2.3.-4", "1..2.3", "a.b.c.d",
        "1.2.3.4 ", " 1.2.3.4", "01.2.3.4", "1.2.3.0004", "1.2.3.4/24", "+1.2.3.4", "１.2.3.4"
    ])
    func refuseUneAdresseInvalide(text: String) {
        #expect(IPAddressV4(text) == nil)
    }

    @Test func formateUneAdresse() {
        #expect(IPAddressV4(rawValue: 0xC0A8_0A39).description == "192.168.10.57")
        #expect(IPAddressV4("255.255.252.0")?.binaryDescription == "11111111.11111111.11111100.00000000")
    }

    // MARK: Calculs de réseau

    @Test func calculeUnSlash24() throws {
        let net = try subnet("192.168.10.57/24")
        #expect(net.description == "192.168.10.0/24")
        #expect(net.mask.description == "255.255.255.0")
        #expect(net.wildcardMask.description == "0.0.0.255")
        #expect(net.broadcast?.description == "192.168.10.255")
        #expect(net.firstUsable.description == "192.168.10.1")
        #expect(net.lastUsable.description == "192.168.10.254")
        #expect(net.addressCount == 256)
        #expect(net.usableHostCount == 254)
    }

    @Test func calculeUnSlash22() throws {
        let net = try subnet("10.20.37.200/22")
        #expect(net.description == "10.20.36.0/22")
        #expect(net.mask.description == "255.255.252.0")
        #expect(net.wildcardMask.description == "0.0.3.255")
        #expect(net.broadcast?.description == "10.20.39.255")
        #expect(net.firstUsable.description == "10.20.36.1")
        #expect(net.lastUsable.description == "10.20.39.254")
        #expect(net.addressCount == 1024)
        #expect(net.usableHostCount == 1022)
    }

    @Test func traiteLeSlash31CommeUnLienPointAPoint() throws {
        let net = try subnet("192.0.2.11/31")
        #expect(net.description == "192.0.2.10/31")
        #expect(net.broadcast == nil)
        #expect(net.firstUsable.description == "192.0.2.10")
        #expect(net.lastUsable.description == "192.0.2.11")
        #expect(net.addressCount == 2)
        #expect(net.usableHostCount == 2)
    }

    @Test func traiteLeSlash32CommeUnHoteUnique() throws {
        let net = try subnet("192.0.2.10/32")
        #expect(net.description == "192.0.2.10/32")
        #expect(net.broadcast == nil)
        #expect(net.firstUsable == net.lastUsable)
        #expect(net.addressCount == 1)
        #expect(net.usableHostCount == 1)
        #expect(net.mask.description == "255.255.255.255")
    }

    @Test func traiteLeSlash0() throws {
        let net = try subnet("203.0.113.9/0")
        #expect(net.description == "0.0.0.0/0")
        #expect(net.mask.description == "0.0.0.0")
        #expect(net.broadcast?.description == "255.255.255.255")
        #expect(net.addressCount == 4_294_967_296)
        #expect(net.usableHostCount == 4_294_967_294)
    }

    @Test func accepteUnMasquePointe() throws {
        let net = try subnet("172.16.5.4/255.255.240.0")
        #expect(net.description == "172.16.0.0/20")
    }

    @Test func refuseUnMasqueNonContigu() {
        #expect(IPSubnet.parse("10.0.0.0/255.0.255.0") == .failure(.invalidMask))
        #expect(IPv4Subnet.prefixLength(forMask: IPAddressV4(rawValue: 0xFF00_FF00)) == nil)
        #expect(IPv4Subnet.prefixLength(forMask: IPAddressV4(rawValue: 0)) == 0)
        #expect(IPv4Subnet.prefixLength(forMask: IPAddressV4(rawValue: UInt32.max)) == 32)
    }

    // MARK: Appartenance

    @Test func verifieLAppartenance() throws {
        let net = try subnet("10.20.36.0/22")
        let last = try #require(IPAddressV4("10.20.39.255"))
        let after = try #require(IPAddressV4("10.20.40.0"))
        let before = try #require(IPAddressV4("10.20.35.255"))
        #expect(net.contains(net.network))
        #expect(net.contains(last))
        #expect(!net.contains(after))
        #expect(!net.contains(before))
    }

    // MARK: Découpage

    @Test func decoupeUnSlash24EnSlash26() throws {
        let net = try subnet("192.168.10.0/24")
        #expect(net.subnetCount(prefixLength: 26) == 4)
        let parts = net.subnets(prefixLength: 26, limit: 16).map(\.description)
        #expect(parts == ["192.168.10.0/26", "192.168.10.64/26", "192.168.10.128/26", "192.168.10.192/26"])
    }

    @Test func limiteLeNombreDeSousReseauxRenvoyes() throws {
        let net = try subnet("10.0.0.0/8")
        #expect(net.subnetCount(prefixLength: 24) == 65_536)
        let parts = net.subnets(prefixLength: 24, limit: 3).map(\.description)
        #expect(parts == ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"])
    }

    @Test func decoupeJusquAuDernierSousReseau() throws {
        let net = try subnet("255.255.255.252/30")
        let parts = net.subnets(prefixLength: 32, limit: 8).map(\.description)
        #expect(parts == ["255.255.255.252/32", "255.255.255.253/32", "255.255.255.254/32", "255.255.255.255/32"])
    }

    @Test func refuseUnPrefixeDeDecoupageInadapte() throws {
        let net = try subnet("192.168.10.0/24")
        #expect(net.subnetCount(prefixLength: 24) == nil)
        #expect(net.subnetCount(prefixLength: 16) == nil)
        #expect(net.subnetCount(prefixLength: 33) == nil)
        #expect(net.subnets(prefixLength: 24, limit: 8).isEmpty)
        #expect(net.subnets(prefixLength: 26, limit: 0).isEmpty)
    }

    // MARK: Nature de la plage

    @Test(arguments: [
        ("10.1.2.0/24", IPv4RangeKind.privateUse),
        ("172.31.0.0/16", IPv4RangeKind.privateUse),
        ("172.32.0.0/16", IPv4RangeKind.publicRange),
        ("192.168.1.0/24", IPv4RangeKind.privateUse),
        ("127.0.0.1/32", IPv4RangeKind.loopback),
        ("169.254.10.0/24", IPv4RangeKind.linkLocal),
        ("100.64.0.0/10", IPv4RangeKind.sharedAddressSpace),
        ("198.51.100.0/24", IPv4RangeKind.documentation),
        ("224.0.0.0/24", IPv4RangeKind.multicast),
        ("240.0.0.0/8", IPv4RangeKind.reserved),
        ("8.8.8.0/24", IPv4RangeKind.publicRange)
    ])
    func identifieLaNatureDeLaPlage(cidr: String, expected: IPv4RangeKind) throws {
        let net = try subnet(cidr)
        #expect(net.kind == expected)
    }

    // MARK: Erreurs de saisie

    @Test func distingueLesErreursDeSaisie() {
        #expect(IPSubnet.parse("") == .failure(.empty))
        #expect(IPSubnet.parse("   ") == .failure(.empty))
        #expect(IPSubnet.parse("192.168.1.0") == .failure(.missingPrefix))
        #expect(IPSubnet.parse("192.168.1/24") == .failure(.invalidAddress))
        #expect(IPSubnet.parse("192.168.1.0/24/3") == .failure(.invalidAddress))
        #expect(IPSubnet.parse("192.168.1.0/33") == .failure(.invalidPrefix(maximum: 32)))
        #expect(IPSubnet.parse("192.168.1.0/") == .failure(.invalidPrefix(maximum: 32)))
        #expect(IPSubnet.parse("192.168.1.0/+24") == .failure(.invalidPrefix(maximum: 32)))
        #expect(IPSubnet.parse("192.168.1.0/-1") == .failure(.invalidPrefix(maximum: 32)))
    }

    @Test func tolereLesEspacesAutourDeLaSaisie() throws {
        let net = try subnet("  192.168.10.0 / 24 ")
        #expect(net.description == "192.168.10.0/24")
    }
}
