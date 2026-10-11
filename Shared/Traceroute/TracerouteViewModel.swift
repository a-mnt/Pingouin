import Foundation
import Observation
import PingouinCore
import PingouinNetwork

/// Ligne du tableau des sauts.
struct HopRow: Identifiable, Hashable {
    let id: Int
    /// Adresse de l'équipement, vide si aucune sonde n'a obtenu de réponse.
    let address: String
    let name: String
    /// Temps de chaque sonde, « * » pour une sonde sans réponse.
    let probes: String
    let averageText: String
    let averageSortKey: Double
    /// Temps moyen rapporté au plus grand temps moyen du parcours, de 0 à 1.
    let fraction: Double
    let answered: Bool
}

enum TracerouteState: Equatable {
    case idle
    case running(hop: Int, maximum: Int)
    case finished(summary: String, reached: Bool)
    case failed(message: String)
}

@MainActor
@Observable
final class TracerouteViewModel {
    private struct Hop {
        var address: HostAddress?
        var name: String?
        var times: [Double?] = []
    }

    private let tracer: any Tracing

    var host = ""
    var maximumHopsText = "30"
    var probesText = "3"
    var timeoutText = "1000"
    var family = IPFamilyChoice.automatic
    var selection: Set<Int> = []
    var state: TracerouteState = .idle

    private(set) var history: [HistoryEntry] = []
    private var hops: [Int: Hop] = [:]
    private var task: Task<Void, Never>?
    private var generation = 0

    init(tracer: any Tracing = ICMPTracer()) {
        self.tracer = tracer
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    var hopCount: Int { hops.count }

    var silentHopCount: Int { hops.values.filter { $0.address == nil }.count }

    var lastHopTimeText: String {
        guard let last = hops.keys.max(), let average = Self.average(hops[last]?.times ?? []) else { return "—" }
        return NumberInput.milliseconds(average)
    }

    var rows: [HopRow] {
        let slowest = hops.values.compactMap { Self.average($0.times) }.max() ?? 0
        return hops.keys.sorted().compactMap { index in
            guard let hop = hops[index] else { return nil }
            let average = Self.average(hop.times)
            return HopRow(
                id: index,
                address: hop.address?.description ?? "",
                name: hop.name ?? "",
                probes: hop.times
                    .map { $0.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "*" }
                    .joined(separator: "   "),
                averageText: average.map { NumberInput.milliseconds($0) } ?? "—",
                averageSortKey: average ?? .infinity,
                fraction: slowest > 0 ? (average ?? 0) / slowest : 0,
                answered: hop.address != nil
            )
        }
    }

    func row(id: Int) -> HopRow? {
        rows.first { $0.id == id }
    }

    var status: ToolStatusLine.Content {
        switch state {
        case .idle:
            return .hint(L("Saisir une destination, puis lancer le traceroute."))
        case .running(let hop, let maximum):
            return .progress(L("Saut \(hop) sur \(maximum) au plus"), fraction: nil)
        case .finished(let summary, let reached):
            return reached ? .done(summary) : .warning(summary)
        case .failed(let message):
            return .failure(message)
        }
    }

    var resultsAsText: String {
        let header = L("Saut\tAdresse\tNom\tSondes (ms)\tMoyenne")
        let lines = rows.map { "\($0.id)\t\($0.address.isEmpty ? "*" : $0.address)\t\($0.name)\t\($0.probes)\t\($0.averageText)" }
        return ([header] + lines).joined(separator: "\n")
    }

    // MARK: Lancement

    /// Lance aussitôt un traceroute vers un hôte choisi dans un autre outil.
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
        guard let maximumHops = NumberInput.integer(maximumHopsText), (1...64).contains(maximumHops) else {
            fail(L("Le nombre maximal de sauts doit être compris entre 1 et 64."))
            return
        }
        guard let probes = NumberInput.integer(probesText), (1...5).contains(probes) else {
            fail(L("Le nombre de sondes par saut doit être compris entre 1 et 5."))
            return
        }
        guard let timeout = NumberInput.integer(timeoutText), (100...10_000).contains(timeout) else {
            fail(L("Le délai doit être compris entre 100 et 10 000 millisecondes."))
            return
        }

        task?.cancel()
        generation += 1
        let current = generation
        hops = [:]
        selection = []
        state = .running(hop: 1, maximum: maximumHops)

        let options = TracerouteOptions(maximumHops: maximumHops, probesPerHop: probes, timeoutMilliseconds: timeout, family: family)
        let stream = tracer.trace(host: target, options: options)

        task = Task {
            do {
                for try await event in stream {
                    guard current == generation else { return }
                    handle(event, target: target, maximumHops: maximumHops)
                }
                guard current == generation else { return }
                if isRunning {
                    state = .finished(summary: L("Traceroute interrompu après \(hops.count) sauts."), reached: false)
                }
            } catch is CancellationError {
                guard current == generation else { return }
                state = .finished(summary: L("Traceroute interrompu après \(hops.count) sauts."), reached: false)
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

    private func handle(_ event: TracerouteEvent, target: String, maximumHops: Int) {
        switch event {
        case .resolved:
            break
        case .probe(let hop, _, let address, let milliseconds):
            var entry = hops[hop] ?? Hop()
            entry.address = entry.address ?? address
            entry.times.append(milliseconds)
            hops[hop] = entry
            if isRunning {
                state = .running(hop: hop, maximum: maximumHops)
            }
        case .hopName(let hop, let name):
            hops[hop]?.name = name
        case .finished(let outcome):
            let summary: String
            let reached: Bool
            switch outcome {
            case .destinationReached(let count):
                summary = L("Destination atteinte en \(count) sauts.")
                reached = true
            case .destinationUnreachable(let count):
                summary = L("Destination signalée injoignable au saut \(count).")
                reached = false
            case .hopLimitReached:
                summary = L("Destination non atteinte en \(maximumHops) sauts.")
                reached = false
            }
            history.insert(HistoryEntry(text: "\(target) · \(summary)", target: target), at: 0)
            state = .finished(summary: summary, reached: reached)
        }
    }

    private static func average(_ times: [Double?]) -> Double? {
        let values = times.compactMap { $0 }
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func message(for error: Error) -> String {
        guard let error = error as? TracerouteError else {
            return L("Le traceroute a échoué : \(error.localizedDescription)")
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
        case .timeToLiveNotSupported:
            return L("\(Platform.systemName) refuse de régler la durée de vie des paquets : le traceroute n'est pas possible sans droits administrateur sur ce système.")
        }
    }
}
