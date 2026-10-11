import Foundation
import Testing
@testable import PingouinCore

@Suite("IPv6 : ping, traceroute et voisins")
struct IPv6DiagnosticsTests {

    @Test("Une adresse d'hôte se lit en IPv4 comme en IPv6")
    func hostAddress() throws {
        let v4 = try #require(HostAddress("192.168.1.1"))
        let v6 = try #require(HostAddress("2001:db8::1"))
        #expect(!v4.isIPv6)
        #expect(v6.isIPv6)
        #expect(v4.description == "192.168.1.1")
        #expect(v6.description == "2001:db8::1")
        #expect(HostAddress("example.com") == nil)
        #expect(HostAddress("fe80::1%en0") == nil)
    }

    @Test("La requête Echo ICMPv6 est de type 128, somme de contrôle laissée au système")
    func requestV6() {
        let packet = ICMPEcho.requestV6(identifier: 0x1234, sequence: 7)
        #expect(Array(packet.prefix(8)) == [128, 0, 0, 0, 0x12, 0x34, 0, 7])
        #expect(Array(packet.dropFirst(8)) == ICMPEcho.defaultPayload)
    }

    @Test("Une réponse Echo ICMPv6 est reconnue, sans durée de vie")
    func echoReplyV6() {
        let datagram: [UInt8] = [129, 0, 0xAB, 0xCD, 0x12, 0x34, 0, 7] + ICMPEcho.defaultPayload
        #expect(ICMPEcho.classifyV6(datagram: datagram)
            == .echoReply(identifier: 0x1234, sequence: 7, payload: ICMPEcho.defaultPayload, ttl: nil))
    }

    /// Message d'erreur ICMPv6 : 8 octets, puis l'en-tête IPv6 de la requête (40 octets), puis la requête.
    private func errorMessage(type: UInt8, code: UInt8, nextHeader: UInt8 = 58, sequence: UInt16) -> [UInt8] {
        var ipHeader = [UInt8](repeating: 0, count: 40)
        ipHeader[0] = 0x60
        ipHeader[6] = nextHeader
        return [type, code, 0, 0, 0, 0, 0, 0] + ipHeader + ICMPEcho.requestV6(identifier: 0x1234, sequence: sequence)
    }

    @Test("« Sauts épuisés » et « injoignable » retrouvent le numéro de notre requête")
    func errorsV6() {
        #expect(ICMPEcho.classifyV6(datagram: errorMessage(type: 3, code: 0, sequence: 42))
            == .timeExceeded(originalIdentifier: 0x1234, originalSequence: 42))
        #expect(ICMPEcho.classifyV6(datagram: errorMessage(type: 1, code: 4, sequence: 9))
            == .destinationUnreachable(code: 4, originalIdentifier: 0x1234, originalSequence: 9))
    }

    @Test("Un message d'erreur tronqué ou portant un autre protocole n'est pas reconnu")
    func malformedV6() {
        #expect(ICMPEcho.classifyV6(datagram: [3, 0, 0, 0]) == nil)
        #expect(ICMPEcho.classifyV6(datagram: Array(errorMessage(type: 3, code: 0, sequence: 1).prefix(50))) == nil)
        #expect(ICMPEcho.classifyV6(datagram: errorMessage(type: 3, code: 0, nextHeader: 17, sequence: 1)) == nil)
        #expect(ICMPEcho.classifyV6(datagram: [135, 0, 0, 0, 0, 0, 0, 0]) == .other(type: 135))
    }

    private let table = """
    Neighbor                                Linklayer Address  Netif Expire    St Flgs Prbs
    2a01:e0a:1:2::10                        a4:83:e7:1:2:3       en0 permanent R
    fe80::a683:e7ff:fe01:203%en0            a4:83:e7:1:2:3       en0 permanent R
    fe80::1%en0                             0:24:d4:aa:bb:cc     en0 23h59m58s S  R
    2a01:e0a:1:2::1                         0:24:d4:aa:bb:cc     en0 23h58m1s  S  R
    fe80::1c2b:3aff:fe4d:5e6f%en0           (incomplete)         en0 expired   N
    fe80::aede:48ff:fe00:1122%en5           ac:de:48:0:11:22     en5 23h59m59s S
    ff02::fb%en0                            33:33:0:0:0:fb       en0 permanent R
    """

    @Test("La table des voisins est lue ligne par ligne, zone et entrées incomplètes comprises")
    func ndpTable() throws {
        let entries = NDPTableParser.parse(table)
        #expect(entries.count == 7)
        let router = try #require(entries.first { $0.address == IPAddressV6("fe80::1") })
        #expect(router.macAddress == MACAddress("00:24:d4:aa:bb:cc"))
        #expect(router.interfaceName == "en0")
        #expect(router.isLinkLocal)
        #expect(!router.isPermanent)
        let incomplete = try #require(entries.first { $0.address == IPAddressV6("fe80::1c2b:3aff:fe4d:5e6f") })
        #expect(incomplete.macAddress == nil)
        let own = try #require(entries.first { $0.address == IPAddressV6("2a01:e0a:1:2::10") })
        #expect(own.isPermanent)
        #expect(!own.isLinkLocal)
    }

    @Test("Les adresses sont regroupées par appareil, celles de ce Mac à part")
    func ndpDevices() throws {
        let devices = NDPTableParser.addressesByDevice(NDPTableParser.parse(table), interfaceName: "en0")
        let routerMAC = try #require(MACAddress("00:24:d4:aa:bb:cc"))
        #expect(devices.neighbors.count == 1)
        #expect(devices.neighbors[routerMAC]?.map(\.description) == ["2a01:e0a:1:2::1", "fe80::1"])
        #expect(devices.local.map(\.description) == ["2a01:e0a:1:2::10", "fe80::a683:e7ff:fe01:203"])
    }
}
