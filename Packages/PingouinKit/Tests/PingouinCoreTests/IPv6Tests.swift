import Testing
@testable import PingouinCore

@Suite("IPv6")
struct IPv6Tests {

    private func subnet(_ cidr: String) throws -> IPv6Subnet {
        guard case .success(.v6(let subnet)) = IPSubnet.parse(cidr) else {
            throw TestFailure.notIPv6(cidr)
        }
        return subnet
    }

    enum TestFailure: Error { case notIPv6(String) }

    // MARK: Analyse et format

    @Test(arguments: [
        ("2001:0db8:0000:0000:0000:0000:0000:0001", "2001:db8::1"),
        ("2001:DB8::1", "2001:db8::1"),
        ("::", "::"),
        ("::1", "::1"),
        ("fe80::", "fe80::"),
        ("2001:db8:0:1:1:1:1:1", "2001:db8:0:1:1:1:1:1"),
        ("2001:0:0:1:0:0:0:1", "2001:0:0:1::1"),
        ("2001:db8:0:0:1:0:0:1", "2001:db8::1:0:0:1"),
        ("1:2:3:4:5:6:7:8", "1:2:3:4:5:6:7:8")
    ])
    func produitLaFormeCanonique(input: String, expected: String) throws {
        let address = try #require(IPAddressV6(input))
        #expect(address.description == expected)
    }

    @Test func produitLaFormeDeveloppee() throws {
        let address = try #require(IPAddressV6("2001:db8::1"))
        #expect(address.expandedDescription == "2001:0db8:0000:0000:0000:0000:0000:0001")
    }

    @Test func litLaValeurNumerique() throws {
        let loopback = try #require(IPAddressV6("::1"))
        let unspecified = try #require(IPAddressV6("::"))
        let highest = try #require(IPAddressV6("ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"))
        let mapped = try #require(IPAddressV6("::ffff:192.0.2.1"))
        #expect(loopback.rawValue == 1)
        #expect(unspecified.rawValue == 0)
        #expect(highest.rawValue == UInt128.max)
        #expect(mapped.rawValue == 0xFFFF_C000_0201)
    }

    @Test(arguments: [
        "", ":", ":::", "2001:db8", "2001:db8::1::2", "2001:db8::g", "1:2:3:4:5:6:7:8:9",
        "fe80::1%en0", "2001:db8::/32", "192.168.1.1", "12345::1"
    ])
    func refuseUneAdresseInvalide(text: String) {
        #expect(IPAddressV6(text) == nil)
    }

    // MARK: Calculs de réseau

    @Test func calculeUnSlash64() throws {
        let net = try subnet("2001:db8:abcd:12::1/64")
        #expect(net.description == "2001:db8:abcd:12::/64")
        #expect(net.lastAddress.description == "2001:db8:abcd:12:ffff:ffff:ffff:ffff")
        #expect(net.addressCountDescription == "18446744073709551616")
    }

    @Test func calculeUnPrefixeNonAligneSurUnGroupe() throws {
        let net = try subnet("2001:db8:ffff::/37")
        #expect(net.description == "2001:db8:f800::/37")
        #expect(net.lastAddress.description == "2001:db8:ffff:ffff:ffff:ffff:ffff:ffff")
    }

    @Test func traiteLesPrefixesExtremes() throws {
        let host = try subnet("2001:db8::7/128")
        #expect(host.description == "2001:db8::7/128")
        #expect(host.lastAddress == host.network)
        #expect(host.addressCount == 1)

        let link = try subnet("2001:db8::7/127")
        #expect(link.description == "2001:db8::6/127")
        #expect(link.addressCount == 2)

        let everything = try subnet("2001:db8::7/0")
        #expect(everything.description == "::/0")
        #expect(everything.addressCount == nil)
        #expect(everything.addressCountDescription == "2^128")
        #expect(everything.lastAddress.rawValue == UInt128.max)
    }

    // MARK: Appartenance

    @Test func verifieLAppartenance() throws {
        let net = try subnet("2001:db8:abcd:12::/64")
        let inside = try #require(IPAddressV6("2001:db8:abcd:12::42"))
        let last = try #require(IPAddressV6("2001:db8:abcd:12:ffff:ffff:ffff:ffff"))
        let outside = try #require(IPAddressV6("2001:db8:abcd:13::1"))
        #expect(net.contains(inside))
        #expect(net.contains(last))
        #expect(!net.contains(outside))
    }

    // MARK: Découpage

    @Test func decoupeUnSlash48EnSlash50() throws {
        let net = try subnet("2001:db8:1::/48")
        #expect(net.subnetCount(prefixLength: 50) == 4)
        let parts = net.subnets(prefixLength: 50, limit: 16).map(\.description)
        #expect(parts == [
            "2001:db8:1::/50", "2001:db8:1:4000::/50", "2001:db8:1:8000::/50", "2001:db8:1:c000::/50"
        ])
    }

    @Test func limiteLeNombreDeSousReseauxRenvoyes() throws {
        let net = try subnet("2001:db8::/32")
        #expect(net.subnetCount(prefixLength: 64) == 4_294_967_296)
        let parts = net.subnets(prefixLength: 64, limit: 2).map(\.description)
        #expect(parts == ["2001:db8::/64", "2001:db8:0:1::/64"])
    }

    @Test func decoupeLeSlash0SansDebordement() throws {
        let net = try subnet("::/0")
        #expect(net.canSplit(prefixLength: 128))
        #expect(net.subnetCount(prefixLength: 128) == nil)
        let parts = net.subnets(prefixLength: 128, limit: 2).map(\.description)
        #expect(parts == ["::/128", "::1/128"])
    }

    @Test func refuseUnPrefixeDeDecoupageInadapte() throws {
        let net = try subnet("2001:db8::/64")
        #expect(!net.canSplit(prefixLength: 64))
        #expect(!net.canSplit(prefixLength: 129))
        #expect(net.subnets(prefixLength: 48, limit: 4).isEmpty)
    }

    // MARK: Nature de la plage

    @Test(arguments: [
        ("::/128", IPv6RangeKind.unspecified),
        ("::1/128", IPv6RangeKind.loopback),
        ("::ffff:192.0.2.0/120", IPv6RangeKind.ipv4Mapped),
        ("fe80::/64", IPv6RangeKind.linkLocal),
        ("fd12:3456:789a::/48", IPv6RangeKind.uniqueLocal),
        ("ff02::/16", IPv6RangeKind.multicast),
        ("2001:db8:1::/48", IPv6RangeKind.documentation),
        ("2a01:e0a::/32", IPv6RangeKind.globalUnicast),
        ("4000::/8", IPv6RangeKind.reserved)
    ])
    func identifieLaNatureDeLaPlage(cidr: String, expected: IPv6RangeKind) throws {
        let net = try subnet(cidr)
        #expect(net.kind == expected)
    }

    // MARK: Erreurs de saisie

    @Test func distingueLesErreursDeSaisie() {
        #expect(IPSubnet.parse("2001:db8::1") == .failure(.missingPrefix))
        #expect(IPSubnet.parse("2001:db8::zz/64") == .failure(.invalidAddress))
        #expect(IPSubnet.parse("2001:db8::/129") == .failure(.invalidPrefix(maximum: 128)))
        #expect(IPSubnet.parse("2001:db8::/") == .failure(.invalidPrefix(maximum: 128)))
        #expect(IPSubnet.parse("2001:db8::/ffff::") == .failure(.invalidPrefix(maximum: 128)))
    }
}
