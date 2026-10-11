import Foundation
import Testing
@testable import PingouinCore

@Suite("Certificat X.509 : lecture des champs")
struct X509ReaderTests {
    /// Certificat d'essai auto-signé, fabriqué pour ces tests : nom « nas.example.test »,
    /// organisation « Pingouin Essais », valide du 11 octobre 2026 au 11 octobre 2027.
    private static let sample = """
        MIICBzCCAaygAwIBAgIUCvmhQ2yLImlDeh3DzbY17XCPydQwCgYIKoZIzj0EAwIwNTEZMBcGA1UE
        AwwQbmFzLmV4YW1wbGUudGVzdDEYMBYGA1UECgwPUGluZ291aW4gRXNzYWlzMB4XDTI2MTAxMTEy
        MzkxN1oXDTI3MTAxMTEyMzkxN1owNTEZMBcGA1UEAwwQbmFzLmV4YW1wbGUudGVzdDEYMBYGA1UE
        CgwPUGluZ291aW4gRXNzYWlzMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEi4Ybg2Uo/stxkStz
        dHJ6ISjdKyuXL/qMUXSi4gu6uEcljp0H0VU3x2wc1lzJOBowZsVJQ1LMAafAgDnblER3wqOBmTCB
        ljAdBgNVHQ4EFgQUOUJgtJR3xDbVaVsiwse/vfUcr3cwHwYDVR0jBBgwFoAUOUJgtJR3xDbVaVsi
        wse/vfUcr3cwDwYDVR0TAQH/BAUwAwEB/zBDBgNVHREEPDA6ghBuYXMuZXhhbXBsZS50ZXN0gg4q
        LmV4YW1wbGUudGVzdIcEwKgBFIcQIAENuAAAAAAAAAAAAAAAIDAKBggqhkjOPQQDAgNJADBGAiEA
        lgTUf3mE0Jx7bkvpALqs5ZzdXPyGomCm16uKOfblQMwCIQC5ZYv7DKQz2v1EohQkFBbAPXKZiQWG
        I5ZtGay3qpNekg==
        """

    private var der: [UInt8] {
        let compact = Self.sample.filter { !$0.isWhitespace }
        return [UInt8](Data(base64Encoded: compact) ?? Data())
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    @Test("Les dates de validité sont lues en temps universel")
    func validity() throws {
        let fields = try #require(X509Reader.parse(der: der))
        let start = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: try #require(fields.notBefore))
        #expect(start.year == 2026)
        #expect(start.month == 10)
        #expect(start.day == 11)
        #expect(start.hour == 12)
        #expect(start.minute == 39)
        #expect(start.second == 17)
        let end = calendar.dateComponents([.year, .month, .day], from: try #require(fields.notAfter))
        #expect(end.year == 2027)
        #expect(end.month == 10)
        #expect(end.day == 11)
    }

    @Test("L'émetteur donne son nom commun et son organisation")
    func issuer() throws {
        let fields = try #require(X509Reader.parse(der: der))
        #expect(fields.issuerCommonName == "nas.example.test")
        #expect(fields.issuerOrganization == "Pingouin Essais")
    }

    @Test("Les noms couverts comprennent les noms DNS et les adresses IPv4 et IPv6")
    func alternativeNames() throws {
        let fields = try #require(X509Reader.parse(der: der))
        #expect(fields.subjectAlternativeNames == ["nas.example.test", "*.example.test", "192.168.1.20", "2001:db8::20"])
    }

    @Test("Un contenu tronqué ou étranger n'est pas un certificat")
    func malformed() {
        #expect(X509Reader.parse(der: []) == nil)
        #expect(X509Reader.parse(der: [0x30, 0x03, 0x02, 0x01]) == nil)
        #expect(X509Reader.parse(der: Array(der.prefix(120))) == nil)
        #expect(X509Reader.parse(der: Array("ceci n'est pas un certificat".utf8)) == nil)
    }
}
