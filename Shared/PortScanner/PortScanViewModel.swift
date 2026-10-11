import Foundation
import Observation
import PingouinCore
import PingouinNetwork

/// Ligne du tableau des ports. Tous les champs sont non optionnels pour rester triables.
struct PortRow: Identifiable, Hashable {
    let id: UInt16
    let port: Int
    let service: String
    let stateText: String
    let stateKind: StatusKind
    /// Ordre d'affichage des états : ouverts d'abord, puis indéterminés, puis fermés.
    let stateOrder: Int
    let timeText: String
    let timeSortKey: Double
    let detail: String
}

enum PortScanState: Equatable {
    case idle
    case running(done: Int, total: Int)
    case finished(summary: String)
    case failed(message: String)
}

enum PortFilter: String, CaseIterable, Identifiable {
    case notable
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notable: L("Ouverts et indéterminés")
        case .all: L("Tous")
        }
    }
}

@MainActor
@Observable
final class PortScanViewModel {
    private let scanner: any PortScanning

    var host = ""
    var portsText = "22, 80, 443, 445, 3389, 8080"
    /// Quand cette option est cochée, la saisie des ports est ignorée et les 65 535 ports sont testés.
    var scanAllPorts = false
    /// Délai par port et nombre de connexions simultanées, modifiables dans la fenêtre.
    /// Les dernières valeurs utilisées pour un scan sont retenues d'un lancement à l'autre.
    var timeoutText = String(PortScanOptions.defaultTimeoutMilliseconds)
    var concurrencyText = String(PortScanOptions.defaultConcurrency)
    var filter: PortFilter = .notable
    var sortOrder = [KeyPathComparator(\PortRow.port)]
    var selection: Set<UInt16> = []
    var state: PortScanState = .idle
    /// Renseigné quand le nombre de ports demande une confirmation explicite.
    var pendingConfirmationCount: Int?
    /// Durée du scan en attente de confirmation si aucun port ne répond, en minutes.
    var pendingWorstCaseMinutes = 0

    private var results: [UInt16: PortScanResult] = [:]
    private var scanTask: Task<Void, Never>?
    private var timeoutUsed = PortScanOptions.defaultTimeoutMilliseconds
    /// Hôte du dernier scan lancé : c'est lui que désignent les lignes du tableau,
    /// même si le champ de saisie a été modifié depuis.
    private(set) var scannedHost = ""
    /// Numéro du scan en cours : un scan remplacé ne doit plus toucher à l'affichage.
    private var generation = 0

    private static let timeoutKey = "portScan.timeoutMilliseconds"
    private static let concurrencyKey = "portScan.concurrency"

    init(scanner: any PortScanning = TCPPortScanner()) {
        self.scanner = scanner
        // Réglages retenus du dernier scan, s'ils sont encore dans les bornes admises.
        let defaults = UserDefaults.standard
        let savedTimeout = defaults.integer(forKey: Self.timeoutKey)
        if (100...10_000).contains(savedTimeout) {
            timeoutText = String(savedTimeout)
        }
        let savedConcurrency = defaults.integer(forKey: Self.concurrencyKey)
        if (1...128).contains(savedConcurrency) {
            concurrencyText = String(savedConcurrency)
        }
    }

    /// Remet le délai et le parallélisme à leurs valeurs d'origine.
    func resetTuning() {
        timeoutText = String(PortScanOptions.defaultTimeoutMilliseconds)
        concurrencyText = String(PortScanOptions.defaultConcurrency)
        UserDefaults.standard.removeObject(forKey: Self.timeoutKey)
        UserDefaults.standard.removeObject(forKey: Self.concurrencyKey)
    }

    var usesDefaultTuning: Bool {
        timeoutText == String(PortScanOptions.defaultTimeoutMilliseconds)
            && concurrencyText == String(PortScanOptions.defaultConcurrency)
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    var testedCount: Int { results.count }
    var openCount: Int { results.values.filter { $0.state == .open }.count }
    var closedCount: Int { results.values.filter { $0.state == .closed }.count }
    var undeterminedCount: Int { results.values.filter { $0.state == .undetermined }.count }

    var rows: [PortRow] {
        results.values
            .filter { filter == .all || $0.state != .closed }
            .map { row(for: $0) }
            .sorted(using: sortOrder)
    }

    func row(id: UInt16) -> PortRow? {
        results[id].map { row(for: $0) }
    }

    /// Lignes au format tabulé, pour le presse-papiers. Sans identifiants, toutes les lignes affichées.
    func text(for ids: Set<UInt16>? = nil) -> String {
        let header = L("Port\tService habituel\tÉtat\tTemps de connexion\tDétail")
        let lines = rows
            .filter { ids?.contains($0.id) ?? true }
            .map { "\($0.port)\t\($0.service)\t\($0.stateText)\t\($0.timeText)\t\($0.detail)" }
        return ([header] + lines).joined(separator: "\n")
    }

    /// Lance immédiatement un scan vers un hôte choisi dans un autre outil, avec les ports et les
    /// réglages affichés. Un scan déjà en cours est remplacé. La confirmation reste demandée
    /// quand le nombre de ports est élevé.
    func launch(host newHost: String) {
        scanTask?.cancel()
        generation += 1
        host = newHost
        results = [:]
        selection = []
        state = .idle
        requestScan()
    }

    // MARK: Lancement

    private struct Request {
        let host: String
        let ports: [UInt16]
        let options: PortScanOptions
    }

    private enum Validation {
        case success(Request)
        case failure(String)
    }

    func requestScan() {
        guard !isRunning else { return }
        switch validate() {
        case .failure(let message):
            state = .failed(message: message)
        case .success(let request):
            if request.ports.count > PortList.confirmationThreshold {
                // Pire cas : aucun port ne répond, chaque connexion attend donc tout le délai.
                let milliseconds = request.ports.count * request.options.timeoutMilliseconds / request.options.concurrency
                pendingWorstCaseMinutes = max(1, (milliseconds + 59_999) / 60_000)
                pendingConfirmationCount = request.ports.count
            } else {
                start(request)
            }
        }
    }

    /// Appelé quand l'utilisateur confirme un scan de grande ampleur.
    func confirmScan() {
        pendingConfirmationCount = nil
        guard !isRunning, case .success(let request) = validate() else { return }
        start(request)
    }

    func cancel() {
        scanTask?.cancel()
    }

    private func validate() -> Validation {
        let target = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard HostInput.isPlausible(target) else {
            return .failure(L("Saisir un nom d'hôte ou une adresse IP, sans espace ni préfixe « http:// »."))
        }

        let ports: [UInt16]
        if scanAllPorts {
            ports = PortList.all
        } else {
            switch PortList.parse(portsText) {
            case .success(let list):
                ports = list
            case .failure(let error):
                return .failure(Self.message(for: error))
            }
        }

        guard let timeout = Int(timeoutText.trimmingCharacters(in: .whitespaces)), (100...10_000).contains(timeout) else {
            return .failure(L("Le délai doit être un nombre entier de millisecondes compris entre 100 et 10 000."))
        }
        guard let concurrency = Int(concurrencyText.trimmingCharacters(in: .whitespaces)), (1...128).contains(concurrency) else {
            return .failure(L("Le nombre de connexions simultanées doit être compris entre 1 et 128."))
        }
        let options = PortScanOptions(timeoutMilliseconds: timeout, concurrency: concurrency)
        return .success(Request(host: target, ports: ports, options: options))
    }

    private func start(_ request: Request) {
        scanTask?.cancel()
        generation += 1
        let current = generation
        results = [:]
        selection = []
        timeoutUsed = request.options.timeoutMilliseconds
        scannedHost = request.host
        UserDefaults.standard.set(request.options.timeoutMilliseconds, forKey: Self.timeoutKey)
        UserDefaults.standard.set(request.options.concurrency, forKey: Self.concurrencyKey)
        let total = request.ports.count
        state = .running(done: 0, total: total)
        let stream = scanner.scan(host: request.host, ports: request.ports, options: request.options)

        scanTask = Task {
            // Les résultats sont appliqués par paquets : sur un scan de 65 535 ports,
            // rafraîchir le tableau à chaque port le rendrait inutilisable.
            var pending: [PortScanResult] = []
            var lastFlush = ContinuousClock.now
            do {
                for try await event in stream {
                    guard current == generation else { return }
                    switch event {
                    case .result(let result):
                        pending.append(result)
                        let now = ContinuousClock.now
                        if pending.count >= 256 || lastFlush.duration(to: now) > .milliseconds(120) {
                            apply(pending, total: total)
                            pending.removeAll(keepingCapacity: true)
                            lastFlush = now
                        }
                    case .finished(let duration):
                        apply(pending, total: total)
                        pending.removeAll()
                        state = .finished(summary: L("\(total.formatted()) ports testés en \(duration.formatted(.number.precision(.fractionLength(1)))) s sur \(request.host)."))
                    }
                }
                guard current == generation else { return }
                apply(pending, total: total)
                if Task.isCancelled || isRunning {
                    state = .finished(summary: L("Scan interrompu : \(results.count.formatted()) ports testés sur \(total.formatted())."))
                }
            } catch is CancellationError {
                guard current == generation else { return }
                apply(pending, total: total)
                state = .finished(summary: L("Scan interrompu : \(results.count.formatted()) ports testés sur \(total.formatted())."))
            } catch {
                guard current == generation else { return }
                state = .failed(message: Self.message(for: error))
            }
        }
    }

    private func apply(_ batch: [PortScanResult], total: Int) {
        guard !batch.isEmpty else { return }
        for result in batch {
            results[result.port] = result
        }
        if isRunning {
            state = .running(done: results.count, total: total)
        }
    }

    // MARK: Présentation

    private func row(for result: PortScanResult) -> PortRow {
        let stateText: String
        let kind: StatusKind
        let order: Int
        var timeText = "—"
        var timeKey = Double.infinity
        let detail: String

        switch result.detail {
        case .accepted(let milliseconds):
            stateText = L("Ouvert")
            kind = .ok
            order = 0
            timeText = milliseconds.formatted(.number.precision(.fractionLength(1))) + " ms"
            timeKey = milliseconds
            detail = L("Connexion acceptée")
        case .refused:
            stateText = L("Fermé")
            kind = .neutral
            order = 2
            detail = L("Connexion refusée par l'hôte")
        case .timedOut:
            stateText = L("Indéterminé")
            kind = .warning
            order = 1
            detail = L("Aucune réponse en \(timeoutUsed.formatted()) ms")
        case .networkError(let code):
            stateText = L("Indéterminé")
            kind = .warning
            order = 1
            detail = code == 0 ? L("Erreur réseau") : L("Erreur réseau (code système \(code))")
        }

        return PortRow(
            id: result.port,
            port: Int(result.port),
            service: PortList.usualService(for: result.port) ?? "",
            stateText: stateText,
            stateKind: kind,
            stateOrder: order,
            timeText: timeText,
            timeSortKey: timeKey,
            detail: detail
        )
    }

    private static func message(for error: PortListError) -> String {
        switch error {
        case .empty:
            return L("Saisir au moins un port, par exemple 22, 80, 443 ou une plage 8000-8100.")
        case .invalidToken(let token):
            return L("« \(token) » n'est ni un port ni une plage. Séparer les ports par des virgules et écrire les plages sous la forme 8000-8100.")
        case .outOfRange(let token):
            return L("« \(token) » sort de l'intervalle autorisé : un port est compris entre 1 et 65535.")
        case .reversedRange(let token):
            return L("La plage « \(token) » est inversée : le premier port doit être inférieur ou égal au second.")
        }
    }

    private static func message(for error: Error) -> String {
        guard let error = error as? PortScanError else {
            return L("Le scan a échoué : \(error.localizedDescription)")
        }
        switch error {
        case .invalidHost:
            return L("Le nom d'hôte ou l'adresse n'est pas valide.")
        case .noPorts:
            return L("Aucun port à tester.")
        case .hostNotFound:
            return L("Ce nom d'hôte est introuvable : la résolution DNS a échoué.")
        }
    }
}
