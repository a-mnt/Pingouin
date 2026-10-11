import Testing
@testable import PingouinCore

@Suite("Scan de ports : logique pure")
struct PortListTests {

    @Test func litUneListeEtDesPlages() {
        #expect(PortList.parse("22, 80, 443") == .success([22, 80, 443]))
        #expect(PortList.parse("8000-8003") == .success([8000, 8001, 8002, 8003]))
        #expect(PortList.parse("443; 22\n80") == .success([22, 80, 443]))
        #expect(PortList.parse(" 8000 - 8002 , 22 ") == .success([22, 8000, 8001, 8002]))
    }

    @Test func trieEtDedoublonne() {
        #expect(PortList.parse("443, 22, 443, 20-23") == .success([20, 21, 22, 23, 443]))
    }

    @Test func accepteLesBornes() {
        #expect(PortList.parse("1") == .success([1]))
        #expect(PortList.parse("65535") == .success([65535]))
        #expect(PortList.parse("80-80") == .success([80]))
    }

    @Test func compteLesPortsDeLExempleDeLaMaquette() throws {
        let ports = try PortList.parse("22, 80, 443, 445, 8000-8100").get()
        #expect(ports.count == 105)
    }

    @Test func refuseUneSaisieVide() {
        #expect(PortList.parse("") == .failure(.empty))
        #expect(PortList.parse("  ,  ; ") == .failure(.empty))
    }

    @Test(arguments: ["abc", "22 80", "80-", "-80", "1-2-3", "80.5", "+80", "８０", "1234567"])
    func refuseUnElementMalForme(token: String) {
        #expect(PortList.parse("22, \(token)") == .failure(.invalidToken(token)))
    }

    @Test func refuseUnPortHorsIntervalle() {
        #expect(PortList.parse("0") == .failure(.outOfRange("0")))
        #expect(PortList.parse("65536") == .failure(.outOfRange("65536")))
        #expect(PortList.parse("65000-70000") == .failure(.outOfRange("65000-70000")))
    }

    @Test func refuseUnePlageInversee() {
        #expect(PortList.parse("8100-8000") == .failure(.reversedRange("8100-8000")))
    }

    @Test func accepteTousLesPorts() throws {
        let everything = try PortList.parse("1-65535").get()
        #expect(everything.count == 65_535)
        #expect(everything == PortList.all)
        #expect(PortList.all.first == 1)
        #expect(PortList.all.last == 65_535)
        // Des plages qui se recouvrent ne comptent chaque port qu'une fois.
        let overlapping = try PortList.parse("1-6000, 5000-12000").get()
        #expect(overlapping.count == 12_000)
    }

    @Test func connaitLesServicesHabituels() {
        #expect(PortList.usualService(for: 22) == "SSH")
        #expect(PortList.usualService(for: 443) == "HTTPS")
        #expect(PortList.usualService(for: 8011) == nil)
    }

    @Test func deduitLEtatDuDetail() {
        #expect(PortScanResult(port: 22, detail: .accepted(milliseconds: 2.1)).state == .open)
        #expect(PortScanResult(port: 23, detail: .refused).state == .closed)
        #expect(PortScanResult(port: 24, detail: .timedOut).state == .undetermined)
        #expect(PortScanResult(port: 25, detail: .networkError(code: 65)).state == .undetermined)
    }

    @Test(arguments: ["192.168.1.20", "example.com", "nas-bureau.home", "2001:db8::1", "fe80::1%en0"])
    func accepteUnHotePlausible(host: String) {
        #expect(HostInput.isPlausible(host))
    }

    @Test(arguments: ["", "exemple .com", "http://example.com", "example.com/chemin", "utilisateur@example.com", "a\tb"])
    func refuseUnHoteInvraisemblable(host: String) {
        #expect(!HostInput.isPlausible(host))
    }

    @Test func refuseUnHoteTropLong() {
        #expect(!HostInput.isPlausible(String(repeating: "a", count: 254)))
        #expect(HostInput.isPlausible(String(repeating: "a", count: 253)))
    }
}
