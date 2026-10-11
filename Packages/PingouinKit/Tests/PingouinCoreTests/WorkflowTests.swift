import Foundation
import Testing
@testable import PingouinCore

@Suite("Supervision : règles d'état")
struct MonitorLogicTests {

    private let origin = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func sample(_ success: Bool, _ milliseconds: Double? = nil, at offset: TimeInterval = 0) -> MonitorSample {
        MonitorSample(date: origin.addingTimeInterval(offset), success: success, milliseconds: milliseconds)
    }

    private let strict = MonitorThresholds(failuresBeforeOffline: 3, degradedAboveMilliseconds: 100)

    @Test func passeEnLigneAuPremierSucces() {
        let step = MonitorLogic.advance(from: .unknown, consecutiveFailures: 0, with: sample(true, 2), thresholds: strict)
        #expect(step == MonitorStep(status: .online, consecutiveFailures: 0, transition: nil))
    }

    @Test func attendTroisEchecsAvantDeDeclarerHorsLigne() {
        var status = MonitorStatus.online
        var failures = 0
        var transitions: [MonitorTransition] = []
        for _ in 1...4 {
            let step = MonitorLogic.advance(from: status, consecutiveFailures: failures, with: sample(false), thresholds: strict)
            status = step.status
            failures = step.consecutiveFailures
            if let transition = step.transition { transitions.append(transition) }
        }
        #expect(status == .offline)
        #expect(failures == 4)
        // La bascule n'est signalée qu'une fois, au troisième échec.
        #expect(transitions == [.wentOffline(consecutiveFailures: 3)])
    }

    @Test func conserveLEtatPendantLesPremiersEchecs() {
        let first = MonitorLogic.advance(from: .online, consecutiveFailures: 0, with: sample(false), thresholds: strict)
        #expect(first == MonitorStep(status: .online, consecutiveFailures: 1, transition: nil))
        let second = MonitorLogic.advance(from: .degraded, consecutiveFailures: 1, with: sample(false), thresholds: strict)
        #expect(second == MonitorStep(status: .degraded, consecutiveFailures: 2, transition: nil))
    }

    @Test func revientEnLigneAuPremierSucces() {
        let step = MonitorLogic.advance(from: .offline, consecutiveFailures: 7, with: sample(true, 3), thresholds: strict)
        #expect(step == MonitorStep(status: .online, consecutiveFailures: 0, transition: .cameBackOnline))
    }

    @Test func remetLeCompteurAZeroApresUnSucces() {
        let step = MonitorLogic.advance(from: .online, consecutiveFailures: 2, with: sample(true, 3), thresholds: strict)
        #expect(step.consecutiveFailures == 0)
        #expect(step.transition == nil)
    }

    @Test func signaleLeSeuilDeLenteur() {
        let slow = MonitorLogic.advance(from: .online, consecutiveFailures: 0, with: sample(true, 148), thresholds: strict)
        #expect(slow == MonitorStep(status: .degraded, consecutiveFailures: 0, transition: .becameDegraded(milliseconds: 148)))
        // Toujours lent : pas de nouvelle alerte.
        let stillSlow = MonitorLogic.advance(from: .degraded, consecutiveFailures: 0, with: sample(true, 160), thresholds: strict)
        #expect(stillSlow.transition == nil)
        #expect(stillSlow.status == .degraded)
        let recovered = MonitorLogic.advance(from: .degraded, consecutiveFailures: 0, with: sample(true, 40), thresholds: strict)
        #expect(recovered == MonitorStep(status: .online, consecutiveFailures: 0, transition: .recoveredFromDegraded))
        // Exactement au seuil : pas dégradé.
        let atLimit = MonitorLogic.advance(from: .online, consecutiveFailures: 0, with: sample(true, 100), thresholds: strict)
        #expect(atLimit.status == .online)
    }

    @Test func ignoreLaLenteurSansSeuil() {
        let lenient = MonitorThresholds(failuresBeforeOffline: 1, degradedAboveMilliseconds: nil)
        let step = MonitorLogic.advance(from: .online, consecutiveFailures: 0, with: sample(true, 5_000), thresholds: lenient)
        #expect(step.status == .online)
        let down = MonitorLogic.advance(from: .online, consecutiveFailures: 0, with: sample(false), thresholds: lenient)
        #expect(down == MonitorStep(status: .offline, consecutiveFailures: 1, transition: .wentOffline(consecutiveFailures: 1)))
    }

    @Test func traiteUnSeuilDEchecsInvalideCommeUn() {
        let odd = MonitorThresholds(failuresBeforeOffline: 0, degradedAboveMilliseconds: nil)
        let step = MonitorLogic.advance(from: .online, consecutiveFailures: 0, with: sample(false), thresholds: odd)
        #expect(step.status == .offline)
    }

    @Test func calculeLaDisponibiliteSurLaPeriode() throws {
        let samples = [
            sample(false, at: -7_200), sample(true, 1, at: -3_000), sample(true, 1, at: -2_000),
            sample(false, at: -1_000), sample(true, 1, at: -10)
        ]
        let lastHour = try #require(MonitorLogic.availabilityPercent(samples: samples, since: origin.addingTimeInterval(-3_600)))
        #expect(lastHour == 75)
        let everything = try #require(MonitorLogic.availabilityPercent(samples: samples, since: origin.addingTimeInterval(-86_400)))
        #expect(everything == 60)
        // Aucune mesure sur la période : pas de chiffre, surtout pas 0 %.
        #expect(MonitorLogic.availabilityPercent(samples: samples, since: origin) == nil)
        #expect(MonitorLogic.availabilityPercent(samples: [], since: origin) == nil)
    }

    @Test func detecteUnePeriodeSansMesure() {
        #expect(MonitorLogic.measurementGap(lastTick: nil, now: origin, expectedInterval: 1) == nil)
        #expect(MonitorLogic.measurementGap(lastTick: origin, now: origin.addingTimeInterval(2), expectedInterval: 1) == nil)
        #expect(MonitorLogic.measurementGap(lastTick: origin, now: origin.addingTimeInterval(29), expectedInterval: 1) == nil)
        #expect(MonitorLogic.measurementGap(lastTick: origin, now: origin.addingTimeInterval(27_660), expectedInterval: 1) == 27_660)
    }

    @Test func decideSiUnControleEstDu() {
        #expect(MonitorLogic.isDue(lastRun: nil, interval: 60, now: origin))
        #expect(!MonitorLogic.isDue(lastRun: origin, interval: 60, now: origin.addingTimeInterval(59)))
        #expect(MonitorLogic.isDue(lastRun: origin, interval: 60, now: origin.addingTimeInterval(60)))
    }

    @Test func limiteLHistorique() {
        let samples = (0..<10).map { sample(true, Double($0), at: Double($0)) }
        #expect(MonitorLogic.trimmed(samples, limit: 20) == samples)
        #expect(MonitorLogic.trimmed(samples, limit: 3).map(\.milliseconds) == [7, 8, 9])
    }
}

@Suite("Topologie : modèle")
struct TopologyTests {

    @Test("Les appareils vus par la box sont reliés à elle, sans doubler un lien existant")
    func linksObservedDevices() {
        let box = TopologyNode(name: "Box", address: "mafreebox.freebox.fr", kind: .router)
        let nas = TopologyNode(name: "nas", address: "192.168.1.20")
        let tv = TopologyNode(name: "tv", address: "192.168.1.31", notes: "Salon")
        let printer = TopologyNode(name: "imprimante", address: "192.168.1.45")
        var topology = Topology(nodes: [box, nas, tv, printer])
        // Le lien vers l'imprimante existe déjà, saisi à la main.
        topology.connect(box.id, printer.id, origin: .manual)

        let seen = [
            ObservedAttachment(name: "nas", address: "192.168.1.20", via: "Port Ethernet 2"),
            ObservedAttachment(name: "tv", address: "192.168.1.31", via: "Wi-Fi 5 GHz"),
            ObservedAttachment(name: "imprimante", address: "192.168.1.45", via: "Port Ethernet 1"),
            ObservedAttachment(name: "absent du schéma", address: "192.168.1.99", via: "Wi-Fi 5 GHz"),
            ObservedAttachment(name: "sans adresse", address: "", via: "Port Ethernet 3")
        ]
        let added = topology.linkObserved(seen, to: box.id)

        #expect(added == 2)
        #expect(topology.links.count == 3)
        #expect(topology.links.filter { $0.origin == .detected }.count == 2)
        #expect(topology.links.filter { $0.origin == .manual }.count == 1)
        // La note vide reçoit l'endroit où l'appareil est vu ; une note existante est conservée.
        #expect(topology.nodes[1].notes == "Vu par la box : Port Ethernet 2")
        #expect(topology.nodes[2].notes == "Salon")
        // Relancer ne change rien.
        #expect(topology.linkObserved(seen, to: box.id) == 0)
    }

    @Test("Sans nœud de box, aucun lien n'est tracé")
    func linkObservedNeedsHub() {
        var topology = Topology(nodes: [TopologyNode(name: "nas", address: "192.168.1.20")])
        let added = topology.linkObserved([ObservedAttachment(name: "nas", address: "192.168.1.20", via: "Port 1")], to: UUID())
        #expect(added == 0)
        #expect(topology.links.isEmpty)
    }

    @Test func relieDeuxNoeudsUneSeuleFois() {
        let router = TopologyNode(name: "routeur", address: "192.168.1.1", kind: .router)
        let nas = TopologyNode(name: "nas", address: "192.168.1.20", kind: .server)
        var topology = Topology(nodes: [router, nas])
        let first = topology.connect(router.id, nas.id)
        let again = topology.connect(router.id, nas.id)
        let reversed = topology.connect(nas.id, router.id)
        #expect(first)
        #expect(!again)
        #expect(!reversed)
        #expect(topology.links.count == 1)
        #expect(topology.links.first?.origin == .manual)
    }

    @Test func refuseUnLienInvalide() {
        let router = TopologyNode(name: "routeur")
        var topology = Topology(nodes: [router])
        let toItself = topology.connect(router.id, router.id)
        let toUnknown = topology.connect(router.id, UUID())
        #expect(!toItself)
        #expect(!toUnknown)
        #expect(topology.links.isEmpty)
    }

    @Test func retireUnNoeudEtSesLiens() {
        let a = TopologyNode(name: "a")
        let b = TopologyNode(name: "b")
        let c = TopologyNode(name: "c")
        var topology = Topology(nodes: [a, b, c])
        topology.connect(a.id, b.id)
        topology.connect(b.id, c.id)
        topology.connect(a.id, c.id, origin: .detected)
        topology.removeNode(b.id)
        #expect(topology.nodes.map(\.name) == ["a", "c"])
        #expect(topology.links.count == 1)
        #expect(topology.links.first?.origin == .detected)
    }

    @Test func survitAUnAllerRetourJSON() throws {
        let a = TopologyNode(name: "routeur", address: "192.168.1.1", kind: .router, notes: "Baie", origin: .detected, x: 120, y: 80)
        let b = TopologyNode(name: "Internet", kind: .internet)
        var topology = Topology(nodes: [a, b])
        topology.connect(a.id, b.id)
        let data = try JSONEncoder().encode(topology)
        let decoded = try JSONDecoder().decode(Topology.self, from: data)
        #expect(decoded == topology)
    }

    @Test func placeLesNouveauxNoeudsSurUneGrille() {
        var topology = Topology()
        let first = topology.nextGridPosition(columns: 2, spacing: 100, origin: 50)
        #expect(first.x == 50)
        #expect(first.y == 50)
        topology.nodes = [TopologyNode(name: "a"), TopologyNode(name: "b"), TopologyNode(name: "c")]
        let fourth = topology.nextGridPosition(columns: 2, spacing: 100, origin: 50)
        #expect(fourth.x == 150)
        #expect(fourth.y == 160)
    }
}

@Suite("Rapports : rendu")
struct ReportTests {

    private let report = Report(
        title: "Rapport de diagnostic réseau",
        generatedAt: Date(timeIntervalSince1970: 1_791_650_000),
        sections: [
            ReportSection(
                id: "lan",
                title: "Découverte LAN",
                parameters: ["Plage : 192.168.1.0/24"],
                columns: [ReportColumn("Adresse"), ReportColumn("Nom", kind: .hostname), ReportColumn("Adresse MAC", kind: .macAddress)],
                rows: [
                    ["192.168.1.1", "routeur.home", "30:7c:b2:4a:10:01"],
                    ["192.168.1.31", "", "da:a1:19:12:34:56"],
                    ["192.168.1.12", "mac; \"pro\"", "—"]
                ],
                notes: ["3 hôtes trouvés."]
            ),
            ReportSection(id: "resume", title: "Résumé", notes: ["Aucune erreur."])
        ]
    )

    @Test func masqueLesColonnesDemandees() {
        let masked = ReportRenderer.applying(ReportPrivacy(maskMACAddresses: true, maskHostnames: false), to: report)
        #expect(masked.sections[0].rows[0] == ["192.168.1.1", "routeur.home", "masqué"])
        // Une cellule vide ou sans valeur ne devient pas « masqué » : cela laisserait croire qu'il y avait une donnée.
        #expect(masked.sections[0].rows[2] == ["192.168.1.12", "mac; \"pro\"", "—"])

        let both = ReportRenderer.applying(ReportPrivacy(maskMACAddresses: true, maskHostnames: true), to: report)
        #expect(both.sections[0].rows[0] == ["192.168.1.1", "masqué", "masqué"])
        #expect(both.sections[0].rows[1] == ["192.168.1.31", "", "masqué"])
        #expect(both.sections[1] == report.sections[1])
    }

    @Test func neChangeRienSansMasquage() {
        #expect(ReportRenderer.applying(ReportPrivacy(), to: report) == report)
    }

    @Test func produitUnTexteAColonnesAlignees() {
        let text = ReportRenderer.text(report, dateText: "10/10/2026")
        let lines = text.components(separatedBy: "\n")
        #expect(lines[0] == "Rapport de diagnostic réseau")
        #expect(lines[1] == "10/10/2026")
        #expect(lines.contains("DÉCOUVERTE LAN"))
        #expect(lines.contains("Plage : 192.168.1.0/24"))
        #expect(lines.contains("Adresse       Nom           Adresse MAC"))
        #expect(lines.contains("192.168.1.1   routeur.home  30:7c:b2:4a:10:01"))
        #expect(lines.contains("192.168.1.31                da:a1:19:12:34:56"))
        #expect(lines.contains("3 hôtes trouvés."))
        #expect(lines.contains("Aucune erreur."))
        // Rendu reproductible.
        #expect(ReportRenderer.text(report, dateText: "10/10/2026") == text)
    }

    @Test func produitUnCSVCorrectementEchappe() {
        let csv = ReportRenderer.csv(report)
        let lines = csv.components(separatedBy: "\r\n")
        #expect(lines[0] == "Section;Adresse;Nom;Adresse MAC")
        #expect(lines[1] == "Découverte LAN;192.168.1.1;routeur.home;30:7c:b2:4a:10:01")
        #expect(lines[2] == "Découverte LAN;192.168.1.31;;da:a1:19:12:34:56")
        #expect(lines[3] == "Découverte LAN;192.168.1.12;\"mac; \"\"pro\"\"\";—")
        // La section sans tableau n'apparaît pas.
        #expect(!csv.contains("Résumé"))
    }

    @Test func echappeLesChampsCSV() {
        #expect(ReportRenderer.csvField("simple") == "simple")
        #expect(ReportRenderer.csvField("a;b") == "\"a;b\"")
        #expect(ReportRenderer.csvField("a,b") == "\"a,b\"")
        #expect(ReportRenderer.csvField("dit \"oui\"") == "\"dit \"\"oui\"\"\"")
        #expect(ReportRenderer.csvField("ligne 1\nligne 2") == "\"ligne 1\nligne 2\"")
        #expect(ReportRenderer.csvField("") == "")
    }

    @Test func produitUnJSONRelisibleEtReproductible() throws {
        let data = try ReportRenderer.json(report)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Report.self, from: data)
        let second = try ReportRenderer.json(report)
        #expect(decoded == report)
        #expect(second == data)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"title\" : \"Rapport de diagnostic réseau\""))
    }
}
