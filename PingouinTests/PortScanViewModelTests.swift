import Foundation
import PingouinCore
import PingouinNetwork
import Testing
@testable import Pingouin

@MainActor
@Suite("Scan de ports : modèle de présentation")
struct PortScanViewModelTests {

    private let sampleResults = [
        PortScanResult(port: 22, detail: .accepted(milliseconds: 1.5)),
        PortScanResult(port: 80, detail: .refused),
        PortScanResult(port: 443, detail: .timedOut)
    ]

    @Test("Un hôte invalide est refusé avant tout scan")
    func invalidHost() {
        let model = PortScanViewModel(scanner: FakeScanner())
        model.host = "http://exemple invalide"
        model.requestScan()
        guard case .failed = model.state else {
            Issue.record("État attendu : échec de validation, obtenu \(model.state)")
            return
        }
        #expect(model.testedCount == 0)
    }

    @Test("Les résultats du service sont comptés et filtrés")
    func resultsAreCountedAndFiltered() async {
        let model = PortScanViewModel(scanner: FakeScanner(results: sampleResults))
        model.host = "192.168.1.10"
        model.portsText = "22, 80, 443"
        model.requestScan()
        await waitUntil { !model.isRunning }

        #expect(model.scannedHost == "192.168.1.10")
        #expect(model.testedCount == 3)
        #expect(model.openCount == 1)
        #expect(model.closedCount == 1)
        #expect(model.undeterminedCount == 1)

        // Par défaut, les ports fermés sont masqués.
        #expect(model.rows.map(\.port) == [22, 443])
        model.filter = .all
        #expect(model.rows.map(\.port) == [22, 80, 443])
        #expect(model.row(id: 22)?.stateText == "Ouvert")
        #expect(model.row(id: 80)?.stateText == "Fermé")
        #expect(model.row(id: 443)?.stateText == "Indéterminé")

        guard case .finished = model.state else {
            Issue.record("État attendu : terminé, obtenu \(model.state)")
            return
        }
    }

    @Test("Au-delà de 1 024 ports, le scan attend une confirmation")
    func largeScanNeedsConfirmation() async {
        let model = PortScanViewModel(scanner: FakeScanner())
        model.host = "192.168.1.10"
        model.portsText = "1-2000"
        model.requestScan()
        #expect(model.pendingConfirmationCount == 2_000)
        #expect(!model.isRunning)

        model.confirmScan()
        #expect(model.pendingConfirmationCount == nil)
        await waitUntil { !model.isRunning }
        guard case .finished = model.state else {
            Issue.record("État attendu : terminé après confirmation, obtenu \(model.state)")
            return
        }
    }

    @Test("Une erreur du service devient un message, pas un résultat")
    func serviceErrorIsReported() async {
        let model = PortScanViewModel(scanner: FakeScanner(error: .hostNotFound))
        model.host = "hote.inexistant.example"
        model.requestScan()
        await waitUntil { !model.isRunning }
        guard case .failed(let message) = model.state else {
            Issue.record("État attendu : échec, obtenu \(model.state)")
            return
        }
        #expect(!message.isEmpty)
        #expect(model.testedCount == 0)
    }

    @Test("Le lancement depuis un autre outil remplace l'hôte et démarre aussitôt")
    func launchFromAnotherTool() async {
        let model = PortScanViewModel(scanner: FakeScanner(results: sampleResults))
        model.host = "ancien-hote"
        model.portsText = "22"
        model.launch(host: "192.168.1.20")
        await waitUntil { !model.isRunning }
        #expect(model.host == "192.168.1.20")
        #expect(model.scannedHost == "192.168.1.20")
        #expect(model.openCount == 1)
    }

    @Test("Un délai hors bornes est refusé")
    func invalidTimeout() {
        let model = PortScanViewModel(scanner: FakeScanner())
        model.host = "192.168.1.10"
        model.timeoutText = "5"
        model.requestScan()
        guard case .failed = model.state else {
            Issue.record("État attendu : échec de validation, obtenu \(model.state)")
            return
        }
    }
}
