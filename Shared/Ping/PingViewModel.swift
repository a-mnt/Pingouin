import Foundation
import Observation
import PingouinCore
import PingouinNetwork

/// Ligne du tableau des réponses.
struct PingRow: Identifiable, Hashable {
    let id: Int
    let time: String
    let address: String
    let ttl: String
    let timeText: String
    let timeSortKey: Double
    let status: String
    let statusKind: StatusKind
}

/// Barre du graphique : une tentative, avec son temps ou l'absence de réponse.
struct PingBar: Identifiable, Hashable {
    let id: Int
    let milliseconds: Double?
}

enum PingState: Equatable {
    case idle
    case running(done: Int, total: Int)
    case finished(summary: String)
    case failed(message: String)
}

@MainActor
@Observable
final class PingViewModel {
    private let pinger: any Pinging

    var host = ""
    var countText = "20"
    var intervalText = "1"
    var timeoutText = "1000"
    var family = IPFamilyChoice.automatic
    var sortOrder = [KeyPathComparator(\PingRow.id, order: .reverse)]
    var state: PingState = .idle

    private(set) var bars: [PingBar] = []
    private(set) var history: [HistoryEntry] = []
    private var unsortedRows: [PingRow] = []
    private var roundTrips: [Double] = []
    private var sentCount = 0
    private var resolvedAddress = ""
    private var task: Task<Void, Never>?
    private var generation = 0

    init(pinger: any Pinging = ICMPPinger()) {
        self.pinger = pinger
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    var rows: [PingRow] { unsortedRows.sorted(using: sortOrder) }

    var statistics: PingStatistics { PingStatistics(sent: sentCount, roundTrips: roundTrips) }

    var hasResults: Bool { sentCount > 0 }

    /// Nombre de tentatives de la série affichée : il fixe la largeur de l'axe du graphique,
    /// pour que les barres se remplissent de gauche à droite au fil des réponses.
    private(set) var plannedCount = 20

    var status: ToolStatusLine.Content {
        switch state {
        case .idle:
            return .hint(L("Saisir un hôte, puis lancer le ping."))
        case .running(let done, let total):
            return .progress(L("\(done) sur \(total)"), fraction: total > 0 ? Double(done) / Double(total) : nil)
        case .finished(let summary):
            return .done(summary)
        case .failed(let message):
            return .failure(message)
        }
    }

    var resultsAsText: String {
        let header = L("N°\tHeure\tAdresse\tTTL\tTemps\tÉtat")
        let lines = rows.map { "\($0.id)\t\($0.time)\t\($0.address)\t\($0.ttl)\t\($0.timeText)\t\($0.status)" }
        return ([header] + lines).joined(separator: "\n")
    }

    // MARK: Lancement

    /// Lance aussitôt un ping vers un hôte choisi dans un autre outil, avec les réglages affichés.
    func launch(host newHost: String) {
        host = newHost
        start()
    }

    func start() {
        let target = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard HostInput.isPlausible(target) else {
            fail(L("Saisir un nom d'hôte ou une adresse IP, sans espace."))
            return
        }
        guard let count = NumberInput.integer(countText), (1...1_000).contains(count) else {
            fail(L("Le nombre de tentatives doit être compris entre 1 et 1 000."))
            return
        }
        guard let interval = NumberInput.decimal(intervalText), (0.2...60).contains(interval) else {
            fail(L("L'intervalle doit être compris entre 0,2 et 60 secondes."))
            return
        }
        guard let timeout = NumberInput.integer(timeoutText), (100...10_000).contains(timeout) else {
            fail(L("Le délai doit être compris entre 100 et 10 000 millisecondes."))
            return
        }

        task?.cancel()
        generation += 1
        let current = generation
        unsortedRows = []
        bars = []
        roundTrips = []
        sentCount = 0
        resolvedAddress = target
        plannedCount = count
        state = .running(done: 0, total: count)

        let options = PingOptions(count: count, intervalSeconds: interval, timeoutMilliseconds: timeout, family: family)
        let stream = pinger.ping(host: target, options: options)

        task = Task {
            do {
                for try await event in stream {
                    guard current == generation else { return }
                    handle(event, total: count)
                }
                guard current == generation else { return }
                finish(target: target, interrupted: Task.isCancelled)
            } catch is CancellationError {
                guard current == generation else { return }
                finish(target: target, interrupted: true)
            } catch {
                guard current == generation else { return }
                state = .failed(message: Self.message(for: error))
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func fail(_ message: String) {
        task?.cancel()
        generation += 1
        state = .failed(message: message)
    }

    private func handle(_ event: PingEvent, total: Int) {
        let now = Date.now.formatted(date: .omitted, time: .standard)
        switch event {
        case .resolved(let address):
            resolvedAddress = address.description
        case .reply(let sequence, let milliseconds, let ttl):
            sentCount += 1
            roundTrips.append(milliseconds)
            bars.append(PingBar(id: sequence, milliseconds: milliseconds))
            unsortedRows.append(PingRow(
                id: sequence,
                time: now,
                address: resolvedAddress,
                ttl: ttl.map { String($0) } ?? "—",
                timeText: NumberInput.milliseconds(milliseconds),
                timeSortKey: milliseconds,
                status: L("Réponse"),
                statusKind: .ok
            ))
            state = .running(done: sentCount, total: total)
        case .timeout(let sequence):
            recordLoss(sequence: sequence, time: now, status: L("Délai dépassé"), total: total)
        case .sendFailure(let sequence, let code):
            recordLoss(sequence: sequence, time: now, status: L("Envoi impossible (code \(code))"), total: total)
        case .finished:
            break
        }
    }

    private func recordLoss(sequence: Int, time: String, status: String, total: Int) {
        sentCount += 1
        bars.append(PingBar(id: sequence, milliseconds: nil))
        unsortedRows.append(PingRow(
            id: sequence,
            time: time,
            address: "—",
            ttl: "—",
            timeText: "—",
            timeSortKey: .infinity,
            status: status,
            statusKind: .warning
        ))
        state = .running(done: sentCount, total: total)
    }

    private func finish(target: String, interrupted: Bool) {
        let stats = statistics
        var summary = L("\(stats.received) réponses sur \(stats.sent)")
        if let average = stats.average {
            summary += L(", moyenne ") + NumberInput.milliseconds(average)
        }
        history.insert(HistoryEntry(text: "\(target) · \(summary)", target: target), at: 0)
        state = .finished(summary: (interrupted ? L("Ping interrompu. ") : "") + summary + ".")
    }

    private static func message(for error: Error) -> String {
        guard let error = error as? PingError else {
            return L("Le ping a échoué : \(error.localizedDescription)")
        }
        switch error {
        case .invalidHost:
            return L("Le nom d'hôte ou l'adresse n'est pas valide.")
        case .hostNotFound:
            return L("Ce nom d'hôte est introuvable : la résolution DNS a échoué.")
        case .familyUnavailable(let family):
            return family == .ipv6
                ? L("Cet hôte n'a pas d'adresse IPv6. Choisir « Automatique » ou « IPv4 ».")
                : L("Cet hôte n'a pas d'adresse IPv4. Choisir « Automatique » ou « IPv6 ».")
        case .socketUnavailable(let code):
            return L("Impossible d'ouvrir le socket ICMP (erreur système \(code)).")
        }
    }
}
