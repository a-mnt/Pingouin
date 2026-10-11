import Foundation
import Testing
@testable import PingouinCore

@Suite("Ping et traceroute : logique pure")
struct PingLogicTests {

    @Test func calculeLesStatistiquesDeLaMaquette() throws {
        let times = [1.4, 1.2, 1.6, 1.3, 2.1, 1.5, 1.1, 1.8, 2.4, 1.7, 1.3, 4.6, 1.9, 1.5, 1.6, 2.2, 1.4, 1.8, 1.6]
        let stats = PingStatistics(sent: 20, roundTrips: times)
        #expect(stats.sent == 20)
        #expect(stats.received == 19)
        #expect(stats.lost == 1)
        #expect(stats.lossPercent == 5)
        #expect(stats.minimum == 1.1)
        #expect(stats.maximum == 4.6)
        let average = try #require(stats.average)
        #expect(abs(average - 34.0 / 19.0) < 1e-9)
    }

    @Test func traiteUneSerieSansReponse() {
        let stats = PingStatistics(sent: 5, roundTrips: [])
        #expect(stats.received == 0)
        #expect(stats.lossPercent == 100)
        #expect(stats.minimum == nil)
        #expect(stats.average == nil)
        #expect(stats.maximum == nil)
        #expect(stats.standardDeviation == nil)
    }

    @Test func traiteUneSerieVideOuIncoherente() {
        #expect(PingStatistics(sent: 0, roundTrips: []).lossPercent == 0)
        // Plus de réponses que d'envois annoncés : le nombre d'envois est corrigé.
        let stats = PingStatistics(sent: 1, roundTrips: [2, 4])
        #expect(stats.sent == 2)
        #expect(stats.lossPercent == 0)
        #expect(stats.average == 3)
        #expect(stats.standardDeviation == 1)
    }

    // MARK: Messages ICMP

    private func ipHeader(ttl: UInt8 = 57) -> [UInt8] {
        var header = [UInt8](repeating: 0, count: 20)
        header[0] = 0x45
        header[8] = ttl
        header[9] = 1
        return header
    }

    @Test func classeUneReponseEcho() {
        let datagram = ipHeader(ttl: 64) + [0, 0, 0, 0, 0x12, 0x34, 0, 7] + ICMPEcho.defaultPayload
        #expect(ICMPEcho.classify(datagram: datagram)
            == .echoReply(identifier: 0x1234, sequence: 7, payload: ICMPEcho.defaultPayload, ttl: 64))
    }

    @Test func classeUneReponseEchoSansEnTeteIP() {
        let datagram: [UInt8] = [0, 0, 0, 0, 0x12, 0x34, 0, 7]
        #expect(ICMPEcho.classify(datagram: datagram)
            == .echoReply(identifier: 0x1234, sequence: 7, payload: [], ttl: nil))
    }

    @Test func retrouveLaRequeteDansUnMessageDureeDeVieEpuisee() {
        let original = ICMPEcho.request(identifier: 0x1234, sequence: 42)
        let datagram = ipHeader() + [11, 0, 0, 0, 0, 0, 0, 0] + ipHeader(ttl: 1) + Array(original.prefix(8))
        #expect(ICMPEcho.classify(datagram: datagram)
            == .timeExceeded(originalIdentifier: 0x1234, originalSequence: 42))
    }

    @Test func retrouveLaRequeteDansUnMessageDestinationInjoignable() {
        let original = ICMPEcho.request(identifier: 9, sequence: 3)
        let datagram = ipHeader() + [3, 1, 0, 0, 0, 0, 0, 0] + ipHeader() + Array(original.prefix(8))
        #expect(ICMPEcho.classify(datagram: datagram)
            == .destinationUnreachable(code: 1, originalIdentifier: 9, originalSequence: 3))
    }

    @Test func refuseUnMessageDErreurTronqueOuEtranger() {
        // Message d'erreur sans la requête d'origine.
        #expect(ICMPEcho.classify(datagram: ipHeader() + [11, 0, 0, 0, 0, 0, 0, 0]) == nil)
        // Requête d'origine coupée avant ses 8 octets.
        #expect(ICMPEcho.classify(datagram: ipHeader() + [11, 0, 0, 0, 0, 0, 0, 0] + ipHeader() + [8, 0, 0]) == nil)
        // L'erreur concerne un paquet qui n'est pas une requête Echo (ici de l'UDP recopié).
        #expect(ICMPEcho.classify(datagram: ipHeader() + [11, 0, 0, 0, 0, 0, 0, 0] + ipHeader() + [0x30, 0x39, 0, 53, 0, 8, 0, 0]) == nil)
        #expect(ICMPEcho.classify(datagram: []) == nil)
    }

    @Test func signaleLesAutresTypes() {
        #expect(ICMPEcho.classify(datagram: ipHeader() + [8, 0, 0, 0, 0, 1, 0, 1]) == .other(type: 8))
    }
}

@Suite("DNS : logique pure")
struct DNSMessageTests {

    private let response: [UInt8] = [
        18, 52, 129, 128, 0, 1, 0, 5, 0, 0, 0, 0, 7, 101, 120, 97, 109, 112, 108, 101, 3, 99, 111, 109, 0, 0, 1, 0, 1,
        192, 12, 0, 1, 0, 1, 0, 0, 14, 16, 0, 4, 198, 51, 100, 34,
        192, 12, 0, 15, 0, 1, 0, 0, 1, 44, 0, 9, 0, 10, 4, 109, 97, 105, 108, 192, 12,
        192, 12, 0, 16, 0, 1, 0, 0, 0, 60, 0, 12, 11, 118, 61, 115, 112, 102, 49, 32, 45, 97, 108, 108,
        192, 12, 0, 28, 0, 1, 0, 0, 14, 16, 0, 16, 32, 1, 13, 184, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 52,
        192, 12, 0, 6, 0, 1, 0, 0, 3, 132, 0, 33, 2, 110, 115, 192, 12, 5, 97, 100, 109, 105, 110, 192, 12,
        120, 195, 217, 9, 0, 0, 28, 32, 0, 0, 14, 16, 0, 18, 117, 0, 0, 0, 1, 44
    ]

    @Test func construitUneQuestion() {
        let expected: [UInt8] = [18, 52, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 7, 101, 120, 97, 109, 112, 108, 101, 3, 99, 111, 109, 0, 0, 1, 0, 1]
        #expect(DNSMessage.query(id: 0x1234, name: "example.com", type: .a) == expected)
        #expect(DNSMessage.query(id: 0x1234, name: "example.com.", type: .a) == expected)
    }

    @Test(arguments: ["", ".", "exemple..com", "été.example", "a b.example", String(repeating: "a", count: 64) + ".com"])
    func refuseUnNomNonEncodable(name: String) {
        #expect(DNSMessage.query(id: 1, name: name, type: .a) == nil)
    }

    @Test func litUneReponseAvecCompression() throws {
        let parsed = try #require(DNSMessage.parse(response))
        #expect(parsed.id == 0x1234)
        #expect(parsed.responseCode == 0)
        #expect(!parsed.isTruncated)
        #expect(parsed.answers.count == 5)
        #expect(parsed.answers.map(\.name) == Array(repeating: "example.com", count: 5))
        #expect(parsed.answers.map(\.typeName) == ["A", "MX", "TXT", "AAAA", "SOA"])
        #expect(parsed.answers.map(\.ttl) == [3600, 300, 60, 3600, 900])
        #expect(parsed.answers[0].value == "198.51.100.34")
        #expect(parsed.answers[1].value == "10 mail.example.com")
        #expect(parsed.answers[2].value == "\"v=spf1 -all\"")
        #expect(parsed.answers[3].value == "2001:db8::34")
        #expect(parsed.answers[4].value == "ns.example.com admin.example.com série 2026101001 rafraîchissement 7200 s nouvel essai 3600 s expiration 1209600 s minimum 300 s")
    }

    @Test func litUnDomaineInexistant() throws {
        let bytes: [UInt8] = [190, 239, 129, 131, 0, 1, 0, 0, 0, 0, 0, 0, 7, 101, 120, 97, 109, 112, 108, 101, 3, 99, 111, 109, 0, 0, 1, 0, 1]
        let parsed = try #require(DNSMessage.parse(bytes))
        #expect(parsed.id == 0xBEEF)
        #expect(parsed.responseCode == 3)
        #expect(parsed.answers.isEmpty)
    }

    @Test func detecteUneReponseTronquee() throws {
        var bytes: [UInt8] = [190, 239, 129, 131, 0, 1, 0, 0, 0, 0, 0, 0, 7, 101, 120, 97, 109, 112, 108, 101, 3, 99, 111, 109, 0, 0, 1, 0, 1]
        bytes[2] = 0x83   // drapeau TC
        bytes[3] = 0x80
        let parsed = try #require(DNSMessage.parse(bytes))
        #expect(parsed.isTruncated)
        #expect(parsed.responseCode == 0)
    }

    @Test func refuseUnMessageInexploitable() {
        #expect(DNSMessage.parse([]) == nil)
        #expect(DNSMessage.parse(Array(response.prefix(11))) == nil)
        // Une question n'est pas une réponse.
        #expect(DNSMessage.parse(DNSMessage.query(id: 1, name: "example.com", type: .a) ?? []) == nil)
        // Données coupées au milieu d'un enregistrement.
        #expect(DNSMessage.parse(Array(response.prefix(40))) == nil)
        // Pointeur de compression qui se vise lui-même.
        let loop: [UInt8] = [0, 1, 129, 128, 0, 1, 0, 1, 0, 0, 0, 0, 7, 101, 120, 97, 109, 112, 108, 101, 3, 99, 111, 109, 0, 0, 1, 0, 1, 192, 29, 0, 1, 0, 1, 0, 0, 0, 1, 0, 4, 0, 0, 0, 0]
        #expect(DNSMessage.parse(loop) == nil)
    }

    @Test func construitLeNomDUneRechercheInverse() {
        #expect(DNSMessage.questionName(for: "192.168.1.20", type: .ptr) == "20.1.168.192.in-addr.arpa.")
        #expect(DNSMessage.questionName(for: "2001:db8::1", type: .ptr)
            == "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.b.d.0.1.0.0.2.ip6.arpa.")
        #expect(DNSMessage.questionName(for: " example.com ", type: .ptr) == "example.com")
        // Hors recherche PTR, une adresse est interrogée telle quelle.
        #expect(DNSMessage.questionName(for: "192.168.1.20", type: .a) == "192.168.1.20")
    }

    @Test func nommeLesTypes() {
        #expect(DNSRecordType.name(forCode: 1) == "A")
        #expect(DNSRecordType.name(forCode: 28) == "AAAA")
        #expect(DNSRecordType.name(forCode: 65) == "TYPE65")
        #expect(Set(DNSRecordType.displayOrder) == Set(DNSRecordType.allCases))
    }
}

@Suite("HTTP et TLS : logique pure")
struct HTTPAndTLSLogicTests {

    private let origin = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func at(_ milliseconds: Double) -> Date {
        origin.addingTimeInterval(milliseconds / 1_000)
    }

    private func close(_ value: Double?, _ expected: Double) -> Bool {
        guard let value else { return false }
        return abs(value - expected) < 0.001
    }

    @Test func decomposeLeTempsDeLaMaquette() {
        var marks = HTTPTimingMarks()
        marks.fetchStart = at(0)
        marks.domainLookupStart = at(0)
        marks.domainLookupEnd = at(18)
        marks.connectStart = at(18)
        marks.secureConnectionStart = at(42)
        marks.secureConnectionEnd = at(103)
        marks.connectEnd = at(103)
        marks.requestStart = at(103)
        marks.responseStart = at(200)
        marks.responseEnd = at(212)
        let breakdown = HTTPTimingBreakdown(marks: marks)
        #expect(close(breakdown.dnsLookup, 18))
        #expect(close(breakdown.tcpConnect, 24))
        #expect(close(breakdown.tlsHandshake, 61))
        #expect(close(breakdown.firstByte, 97))
        #expect(close(breakdown.transfer, 12))
        #expect(abs(breakdown.measuredTotal - 212) < 0.001)
    }

    @Test func traiteUneConnexionSansTLSNiDNS() {
        var marks = HTTPTimingMarks()
        marks.connectStart = at(0)
        marks.connectEnd = at(5)
        marks.requestStart = at(5)
        marks.responseStart = at(9)
        marks.responseEnd = at(10)
        let breakdown = HTTPTimingBreakdown(marks: marks)
        #expect(breakdown.dnsLookup == nil)
        #expect(breakdown.tlsHandshake == nil)
        #expect(close(breakdown.tcpConnect, 5))
        #expect(close(breakdown.firstByte, 4))
        #expect(close(breakdown.transfer, 1))
    }

    @Test func ignoreDesInstantsIncoherents() {
        var marks = HTTPTimingMarks()
        marks.requestStart = at(10)
        marks.responseStart = at(5)
        #expect(HTTPTimingBreakdown(marks: marks).firstByte == nil)
        #expect(HTTPTimingBreakdown(marks: HTTPTimingMarks()).measuredTotal == 0)
    }

    @Test func normaliseUneURL() {
        #expect(HTTPTarget.url(from: "example.com")?.absoluteString == "https://example.com")
        #expect(HTTPTarget.url(from: " http://example.com/chemin?x=1 ")?.absoluteString == "http://example.com/chemin?x=1")
        #expect(HTTPTarget.url(from: "192.168.1.20:8080")?.absoluteString == "https://192.168.1.20:8080")
        #expect(HTTPTarget.url(from: "HTTPS://Example.com") != nil)
    }

    @Test(arguments: ["", "   ", "ftp://example.com", "file:///etc/hosts", "https://", "exemple .com", "http:///chemin"])
    func refuseUneURLInvalide(input: String) {
        #expect(HTTPTarget.url(from: input) == nil)
    }

    // MARK: Expiration des certificats

    private func days(_ count: Double) -> Date {
        origin.addingTimeInterval(count * 86_400)
    }

    @Test func evalueLExpiration() {
        #expect(CertificateExpiry.evaluate(notBefore: days(-60), notAfter: days(21.9), now: origin) == .expiringSoon(daysLeft: 21))
        #expect(CertificateExpiry.evaluate(notBefore: days(-60), notAfter: days(30), now: origin) == .valid(daysLeft: 30))
        #expect(CertificateExpiry.evaluate(notBefore: days(-60), notAfter: days(29.99), now: origin) == .expiringSoon(daysLeft: 29))
        #expect(CertificateExpiry.evaluate(notBefore: days(-60), notAfter: days(0.5), now: origin) == .expiringSoon(daysLeft: 0))
        #expect(CertificateExpiry.evaluate(notBefore: days(-60), notAfter: days(-3.2), now: origin) == .expired(daysAgo: 3))
        #expect(CertificateExpiry.evaluate(notBefore: days(2), notAfter: days(90), now: origin) == .notYetValid)
        #expect(CertificateExpiry.evaluate(notBefore: nil, notAfter: nil, now: origin) == .unknown)
        #expect(CertificateExpiry.evaluate(notBefore: nil, notAfter: days(400), now: origin) == .valid(daysLeft: 400))
    }

    // MARK: Hôte et port

    @Test func separeLHoteDuPort() throws {
        let plain = try #require(HostPort.split("example.com", defaultPort: 443))
        #expect(plain.host == "example.com")
        #expect(plain.port == 443)

        let withPort = try #require(HostPort.split(" example.com:8443 ", defaultPort: 443))
        #expect(withPort.host == "example.com")
        #expect(withPort.port == 8443)

        let bareIPv6 = try #require(HostPort.split("2001:db8::1", defaultPort: 443))
        #expect(bareIPv6.host == "2001:db8::1")
        #expect(bareIPv6.port == 443)

        let bracketed = try #require(HostPort.split("[2001:db8::1]:8443", defaultPort: 443))
        #expect(bracketed.host == "2001:db8::1")
        #expect(bracketed.port == 8443)

        let bracketedNoPort = try #require(HostPort.split("[2001:db8::1]", defaultPort: 443))
        #expect(bracketedNoPort.port == 443)
    }

    @Test(arguments: ["", "example.com:", "example.com:0", "example.com:70000", "example.com:https", ":443", "[2001:db8::1", "[2001:db8::1]443", "exemple .com:443"])
    func refuseUneSaisieHotePortInvalide(input: String) {
        #expect(HostPort.split(input, defaultPort: 443) == nil)
    }
}
