import Foundation
import PingouinCore
import PingouinNetwork
import Testing
@testable import Pingouin

@MainActor
@Suite("Ping : modèle de présentation")
struct PingViewModelTests {

    @Test("Les réponses et les délais dépassés alimentent les statistiques")
    func statistics() async {
        let events: [PingEvent] = [
            .reply(sequence: 1, milliseconds: 10, ttl: 64),
            .reply(sequence: 2, milliseconds: 30, ttl: 64),
            .timeout(sequence: 3),
            .finished
        ]
        let model = PingViewModel(pinger: FakePinger(events: events))
        model.host = "192.168.1.1"
        model.countText = "3"
        model.start()
        await waitUntil { !model.isRunning }

        #expect(model.hasResults)
        #expect(model.statistics.sent == 3)
        #expect(model.statistics.received == 2)
        #expect(model.statistics.minimum == 10)
        #expect(model.statistics.maximum == 30)
        #expect(model.statistics.average == 20)
        #expect(model.rows.count == 3)
        guard case .finished = model.state else {
            Issue.record("État attendu : terminé, obtenu \(model.state)")
            return
        }
    }

    @Test("Un nombre de tentatives hors bornes est refusé")
    func invalidCount() {
        let model = PingViewModel(pinger: FakePinger())
        model.host = "192.168.1.1"
        model.countText = "0"
        model.start()
        guard case .failed = model.state else {
            Issue.record("État attendu : échec de validation, obtenu \(model.state)")
            return
        }
        #expect(!model.hasResults)
    }

    @Test("Un hôte introuvable devient un message")
    func hostNotFound() async {
        let model = PingViewModel(pinger: FakePinger(error: .hostNotFound))
        model.host = "hote.inexistant.example"
        model.start()
        await waitUntil { !model.isRunning }
        guard case .failed(let message) = model.state else {
            Issue.record("État attendu : échec, obtenu \(model.state)")
            return
        }
        #expect(!message.isEmpty)
    }

    @Test("Le lancement depuis un autre outil démarre aussitôt sur l'hôte donné")
    func launch() async {
        let model = PingViewModel(pinger: FakePinger(events: [.reply(sequence: 1, milliseconds: 5, ttl: 64), .finished]))
        model.countText = "1"
        model.launch(host: "192.168.1.50")
        await waitUntil { !model.isRunning }
        #expect(model.host == "192.168.1.50")
        #expect(model.statistics.received == 1)
    }
}
