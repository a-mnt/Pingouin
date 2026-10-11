import Foundation
import PingouinCore
import PingouinNetwork
import Testing
@testable import Pingouin

@MainActor
@Suite("Traceroute : modèle de présentation")
struct TracerouteViewModelTests {

    @Test("Les sondes forment les sauts, et un saut muet est compté à part")
    func hops() async throws {
        let first = try #require(IPAddressV4("192.168.1.1"))
        let last = try #require(IPAddressV4("203.0.113.9"))
        let events: [TracerouteEvent] = [
            .probe(hop: 1, index: 0, address: .v4(first), milliseconds: 1.2),
            .probe(hop: 2, index: 0, address: nil, milliseconds: nil),
            .probe(hop: 3, index: 0, address: .v4(last), milliseconds: 12),
            .hopName(hop: 1, name: "passerelle"),
            .finished(.destinationReached(hops: 3))
        ]
        let model = TracerouteViewModel(tracer: FakeTracer(events: events))
        model.host = "203.0.113.9"
        model.probesText = "1"
        model.start()
        await waitUntil { !model.isRunning }

        #expect(model.hopCount == 3)
        #expect(model.silentHopCount == 1)
        #expect(model.row(id: 1)?.name == "passerelle")
        #expect(model.history.count == 1)
        guard case .finished(_, let reached) = model.state else {
            Issue.record("État attendu : terminé, obtenu \(model.state)")
            return
        }
        #expect(reached)
    }

    @Test("Un nombre de sauts hors bornes est refusé")
    func invalidHops() {
        let model = TracerouteViewModel(tracer: FakeTracer())
        model.host = "192.168.1.1"
        model.maximumHopsText = "200"
        model.start()
        guard case .failed = model.state else {
            Issue.record("État attendu : échec de validation, obtenu \(model.state)")
            return
        }
    }

    @Test("Un hôte introuvable devient un message")
    func hostNotFound() async {
        let model = TracerouteViewModel(tracer: FakeTracer(error: .hostNotFound))
        model.host = "hote.inexistant.example"
        model.start()
        await waitUntil { !model.isRunning }
        guard case .failed = model.state else {
            Issue.record("État attendu : échec, obtenu \(model.state)")
            return
        }
    }
}

@MainActor
@Suite("DNS : modèle de présentation")
struct DNSViewModelTests {

    @Test("Les enregistrements reçus sont affichés")
    func answers() async {
        let records = [
            DNSRecord(name: "example.com", typeCode: 1, ttl: 300, value: "203.0.113.10"),
            DNSRecord(name: "example.com", typeCode: 1, ttl: 300, value: "203.0.113.11")
        ]
        let model = DNSViewModel(client: FakeDNSClient(outcome: .answers(records)))
        model.name = "example.com"
        model.start()
        await waitUntil { !model.isRunning }

        #expect(model.records.count == 2)
        #expect(model.serverUsed == "192.0.2.53")
        guard case .done = model.status else {
            Issue.record("État attendu : terminé, obtenu \(model.status)")
            return
        }
    }

    @Test("Un domaine inexistant est un avertissement, pas une panne")
    func nonexistentDomain() async {
        let model = DNSViewModel(client: FakeDNSClient(outcome: .nonexistentDomain))
        model.name = "inexistant.example"
        model.start()
        await waitUntil { !model.isRunning }
        #expect(model.records.isEmpty)
        guard case .warning = model.status else {
            Issue.record("État attendu : avertissement, obtenu \(model.status)")
            return
        }
    }

    @Test("Un serveur muet est signalé comme un échec")
    func timedOut() async {
        let model = DNSViewModel(client: FakeDNSClient(outcome: .timedOut))
        model.name = "example.com"
        model.start()
        await waitUntil { !model.isRunning }
        guard case .failure = model.status else {
            Issue.record("État attendu : échec, obtenu \(model.status)")
            return
        }
    }

    @Test("Une question vide est refusée")
    func emptyQuestion() {
        let model = DNSViewModel(client: FakeDNSClient())
        model.name = "   "
        model.start()
        #expect(!model.isRunning)
        guard case .failure = model.status else {
            Issue.record("État attendu : échec de validation, obtenu \(model.status)")
            return
        }
    }

    @Test("La recherche inverse lancée depuis un autre outil passe au type PTR")
    func reverseLaunch() async {
        let model = DNSViewModel(client: FakeDNSClient(outcome: .noRecords))
        model.launchReverse(address: "192.168.1.20")
        await waitUntil { !model.isRunning }
        #expect(model.name == "192.168.1.20")
        #expect(model.type == .ptr)
    }
}

@MainActor
@Suite("HTTP : modèle de présentation")
struct HTTPViewModelTests {

    @Test("Une réponse 200 est affichée comme un succès")
    func success() async {
        let model = HTTPViewModel(probe: FakeHTTPProbe(statusCode: 200))
        model.urlText = "http://192.168.1.20/"
        model.start()
        await waitUntil { !model.isRunning }
        #expect(model.hasResult)
        #expect(model.statusCodeText.hasPrefix("200"))
        #expect(model.statusKind == .ok)
        #expect(model.headers.count == 1)
    }

    @Test("Une réponse 503 est affichée comme un échec du serveur, pas de l'outil")
    func serverError() async {
        let model = HTTPViewModel(probe: FakeHTTPProbe(statusCode: 503))
        model.urlText = "http://192.168.1.20/"
        model.start()
        await waitUntil { !model.isRunning }
        #expect(model.hasResult)
        #expect(model.statusKind == .failure)
    }

    @Test("Une URL invalide est refusée avant tout envoi")
    func invalidURL() {
        let model = HTTPViewModel(probe: FakeHTTPProbe())
        model.urlText = "ceci n'est pas une url"
        model.start()
        #expect(!model.isRunning)
        #expect(!model.hasResult)
        guard case .failure = model.status else {
            Issue.record("État attendu : échec de validation, obtenu \(model.status)")
            return
        }
    }

    @Test("Un délai dépassé devient un message, sans résultat")
    func timedOut() async {
        let model = HTTPViewModel(probe: FakeHTTPProbe(error: .timedOut))
        model.urlText = "http://192.168.1.20/"
        model.start()
        await waitUntil { !model.isRunning }
        #expect(!model.hasResult)
        guard case .failure = model.status else {
            Issue.record("État attendu : échec, obtenu \(model.status)")
            return
        }
    }
}

@MainActor
@Suite("TLS : modèle de présentation")
struct TLSViewModelTests {

    @Test("Un certificat approuvé est présenté comme tel")
    func trusted() async {
        let model = TLSViewModel(inspector: FakeTLSInspector(isTrusted: true))
        model.hostText = "example.com"
        model.start()
        await waitUntil { !model.isRunning }
        #expect(model.hasResult)
        #expect(model.chain.count == 1)
        #expect(model.trustKind == .ok)
        #expect(model.protocolText == "TLS 1.3")
    }

    @Test("Un certificat refusé est présenté comme refusé, avec son contenu")
    func untrusted() async {
        let model = TLSViewModel(inspector: FakeTLSInspector(isTrusted: false))
        model.hostText = "example.com:8443"
        model.start()
        await waitUntil { !model.isRunning }
        #expect(model.hasResult)
        #expect(model.trustKind == .failure)
    }

    @Test("Un port hors bornes est refusé")
    func invalidPort() {
        let model = TLSViewModel(inspector: FakeTLSInspector())
        model.hostText = "example.com"
        model.portText = "70000"
        model.start()
        #expect(!model.isRunning)
        guard case .failure = model.status else {
            Issue.record("État attendu : échec de validation, obtenu \(model.status)")
            return
        }
    }

    @Test("Une connexion impossible devient un message, sans résultat")
    func connectionFailed() async {
        let model = TLSViewModel(inspector: FakeTLSInspector(error: .timedOut))
        model.hostText = "example.com"
        model.start()
        await waitUntil { !model.isRunning }
        #expect(!model.hasResult)
        guard case .failure = model.status else {
            Issue.record("État attendu : échec, obtenu \(model.status)")
            return
        }
    }
}

@MainActor
@Suite("Découverte LAN : modèle de présentation")
struct LANDiscoveryViewModelTests {

    @Test("Les hôtes trouvés sont comptés selon leur réponse au ping")
    func hostsAreCounted() async throws {
        let first = try #require(IPAddressV4("192.168.1.10"))
        let second = try #require(IPAddressV4("192.168.1.20"))
        let hosts = [
            DiscoveredHost(address: first, hostname: "nas", responseMilliseconds: 2.5),
            DiscoveredHost(address: second)
        ]
        let model = LANDiscoveryViewModel(service: FakeLANDiscovery(hosts: hosts))
        model.rangeText = "192.168.1.0/24"
        model.requestScan()
        await waitUntil { !model.isRunning }

        #expect(model.hostCount == 2)
        #expect(model.pingReplyCount == 1)
        #expect(model.arpOnlyCount == 1)
        #expect(model.discoveredHosts.map(\.address) == ["192.168.1.10", "192.168.1.20"])
        #expect(model.discoveredHosts.first?.name == "nas")
    }

    @Test("Au-delà d'un /24, la découverte attend une confirmation")
    func largeRangeNeedsConfirmation() {
        let model = LANDiscoveryViewModel(service: FakeLANDiscovery())
        model.rangeText = "192.168.0.0/23"
        model.requestScan()
        #expect(model.pendingConfirmationCount != nil)
        #expect(!model.isRunning)
    }

    @Test("Une plage trop grande est refusée")
    func hugeRangeIsRefused() {
        let model = LANDiscoveryViewModel(service: FakeLANDiscovery())
        model.rangeText = "10.0.0.0/8"
        model.requestScan()
        #expect(model.pendingConfirmationCount == nil)
        guard case .failed = model.state else {
            Issue.record("État attendu : refus, obtenu \(model.state)")
            return
        }
    }

    @Test("Une plage IPv6 est refusée avec une explication")
    func ipv6IsRefused() {
        let model = LANDiscoveryViewModel(service: FakeLANDiscovery())
        model.rangeText = "fe80::/64"
        model.requestScan()
        guard case .failed = model.state else {
            Issue.record("État attendu : refus, obtenu \(model.state)")
            return
        }
    }
}
