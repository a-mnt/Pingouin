import Foundation
import Observation
import PingouinCore

/// Nature d'une étape de tâche.
enum AutomationStepKind: String, Codable, CaseIterable, Identifiable {
    case ping
    case dns
    case tcp
    case http
    case tls

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ping: L("Ping")
        case .dns: "DNS"
        case .tcp: L("Port TCP")
        case .http: "HTTP"
        case .tls: L("Certificat TLS")
        }
    }

    var targetPrompt: String {
        switch self {
        case .ping, .tcp: "192.168.1.1"
        case .dns: "example.com"
        case .http: "https://example.com/"
        case .tls: "example.com:443"
        }
    }
}

/// Étape d'une tâche : un contrôle sur une cible.
struct AutomationStep: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: AutomationStepKind = .ping
    /// Hôte (ping, TCP), nom de domaine (DNS), URL (HTTP) ou « hôte:port » (TLS).
    var target = ""
    /// Port, pour une étape TCP uniquement. Gardé en texte : c'est la saisie de l'utilisateur.
    var portText = "443"

    var summary: String {
        kind == .tcp ? "\(target):\(portText)" : target
    }
}

/// Tâche enregistrée : une suite ordonnée d'étapes.
struct AutomationTask: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = ""
    var steps: [AutomationStep] = [AutomationStep()]
    /// Intervalle entre deux exécutions planifiées. `nil` : exécution manuelle uniquement.
    var scheduleSeconds: Int?
    var stopOnFailure = false
    var createdAt = Date()
    var lastRun: Date?

    static let schedules: [(seconds: Int?, label: String)] = [
        (nil, L("Manuelle uniquement")), (300, L("Toutes les 5 minutes")), (900, L("Toutes les 15 minutes")),
        (3_600, L("Toutes les heures")), (21_600, L("Toutes les 6 heures")), (86_400, L("Toutes les 24 heures"))
    ]

    var scheduleLabel: String {
        Self.schedules.first { $0.seconds == scheduleSeconds }?.label ?? L("Manuelle uniquement")
    }
}

/// Résultat d'une étape lors d'une exécution.
struct AutomationStepResult: Codable, Identifiable, Hashable {
    var id = UUID()
    let stepID: UUID
    let label: String
    let level: CheckResult.Level
    let detail: String
    let milliseconds: Double?
}

/// Exécution passée d'une tâche.
struct AutomationRun: Codable, Identifiable, Hashable {
    var id = UUID()
    let taskID: UUID
    let taskName: String
    let date: Date
    let wasScheduled: Bool
    let wasCancelled: Bool
    let stepCount: Int
    let results: [AutomationStepResult]

    var successCount: Int { results.filter { $0.level != .failure }.count }

    var failureCount: Int { results.filter { $0.level == .failure }.count }
}

/// Automatisation locale : des tâches faites de contrôles, lancées à la main ou à intervalle régulier
/// tant que l'application est ouverte. Une seule tâche s'exécute à la fois.
@MainActor
@Observable
final class AutomationViewModel {
    private struct Saved: Codable {
        var tasks: [AutomationTask]
        var runs: [AutomationRun]
    }

    static let stepLimit = 20
    private static let runLimit = 100

    private let store = JSONStore<Saved>(fileName: "automatisation")
    private let runner = CheckRunner()

    private(set) var tasks: [AutomationTask] = []
    private(set) var runs: [AutomationRun] = []
    var selectedTaskID: UUID?

    var draft = AutomationTask()
    var isEditing = false
    private(set) var isEditingExisting = false
    var draftError: String?

    private(set) var runningTaskID: UUID?
    private(set) var currentStepID: UUID?
    private(set) var liveResults: [AutomationStepResult] = []

    private var runTask: Task<Void, Never>?
    private var engine: Task<Void, Never>?

    init() {
        if let saved = store.load() {
            tasks = saved.tasks
            runs = saved.runs
        }
        selectedTaskID = tasks.first?.id
        engine = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                self?.tick()
            }
        }
    }

    // MARK: Lecture

    var isRunning: Bool { runningTaskID != nil }

    var runningTaskName: String {
        task(id: runningTaskID)?.name ?? ""
    }

    var selectedTask: AutomationTask? {
        task(id: selectedTaskID)
    }

    func task(id: UUID?) -> AutomationTask? {
        guard let id else { return nil }
        return tasks.first { $0.id == id }
    }

    /// Dernière exécution enregistrée d'une tâche.
    func lastRun(of id: UUID) -> AutomationRun? {
        runs.first { $0.taskID == id }
    }

    /// Résultats à afficher pour une tâche : ceux de l'exécution en cours, sinon ceux de la dernière.
    func results(for id: UUID) -> [UUID: AutomationStepResult] {
        let source = runningTaskID == id ? liveResults : (lastRun(of: id)?.results ?? [])
        return Dictionary(source.map { ($0.stepID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Édition

    func beginAdding() {
        draft = AutomationTask()
        draftError = nil
        isEditingExisting = false
        isEditing = true
    }

    func beginEditing(_ id: UUID) {
        guard let task = self.task(id: id) else { return }
        draft = task
        draftError = nil
        isEditingExisting = true
        isEditing = true
    }

    func addDraftStep() {
        guard draft.steps.count < Self.stepLimit else { return }
        draft.steps.append(AutomationStep())
    }

    func removeDraftStep(_ id: UUID) {
        draft.steps.removeAll { $0.id == id }
    }

    func moveDraftStep(_ id: UUID, by offset: Int) {
        guard let index = draft.steps.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + offset
        guard draft.steps.indices.contains(destination) else { return }
        draft.steps.swapAt(index, destination)
    }

    /// Valide la saisie et enregistre la tâche. Renvoie faux, avec un message, si la saisie est incomplète.
    @discardableResult
    func commitDraft() -> Bool {
        var task = draft
        task.name = task.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.name.isEmpty else {
            draftError = L("Donner un nom à la tâche.")
            return false
        }
        guard !task.steps.isEmpty else {
            draftError = L("Ajouter au moins une étape.")
            return false
        }
        for index in task.steps.indices {
            task.steps[index].target = task.steps[index].target.trimmingCharacters(in: .whitespacesAndNewlines)
            if let problem = Self.problem(in: task.steps[index]) {
                draftError = L("Étape \(index + 1) : \(problem)")
                return false
            }
        }

        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }
        selectedTaskID = task.id
        isEditing = false
        save()
        return true
    }

    func duplicate(_ id: UUID) {
        guard let original = task(id: id) else { return }
        var copy = original
        copy.id = UUID()
        copy.name = original.name + L(" (copie)")
        copy.steps = original.steps.map { step in
            var step = step
            step.id = UUID()
            return step
        }
        copy.createdAt = Date()
        copy.lastRun = nil
        tasks.append(copy)
        selectedTaskID = copy.id
        save()
    }

    func remove(_ id: UUID) {
        if runningTaskID == id {
            cancel()
        }
        tasks.removeAll { $0.id == id }
        if selectedTaskID == id {
            selectedTaskID = tasks.first?.id
        }
        save()
    }

    func clearRuns() {
        runs = []
        save()
    }

    private static func problem(in step: AutomationStep) -> String? {
        switch step.kind {
        case .ping, .dns:
            return HostInput.isPlausible(step.target) ? nil : L("saisir un nom d'hôte ou une adresse, sans espace.")
        case .tcp:
            guard HostInput.isPlausible(step.target) else { return L("saisir un nom d'hôte ou une adresse, sans espace.") }
            guard let port = NumberInput.integer(step.portText), (1...65_535).contains(port) else {
                return L("le port doit être compris entre 1 et 65535.")
            }
            return nil
        case .http:
            return HTTPTarget.url(from: step.target) == nil ? L("saisir une URL en http:// ou https://.") : nil
        case .tls:
            return HostPort.split(step.target, defaultPort: 443) == nil ? L("saisir un hôte, éventuellement suivi de « :port ».") : nil
        }
    }

    // MARK: Exécution

    func runSelected() {
        guard let selectedTaskID else { return }
        run(selectedTaskID, scheduled: false)
    }

    /// Lance une tâche, si aucune autre n'est en cours.
    func run(_ id: UUID, scheduled: Bool) {
        guard runTask == nil, let task = self.task(id: id), !task.steps.isEmpty else { return }
        runningTaskID = id
        currentStepID = nil
        liveResults = []
        let runner = self.runner
        let started = Date()

        runTask = Task {
            var results: [AutomationStepResult] = []
            var cancelled = false
            for step in task.steps {
                if Task.isCancelled {
                    cancelled = true
                    break
                }
                currentStepID = step.id
                let result = await Self.perform(step, with: runner)
                // Une étape interrompue n'est pas consignée : son résultat ne voudrait rien dire.
                if Task.isCancelled {
                    cancelled = true
                    break
                }
                results.append(AutomationStepResult(
                    stepID: step.id,
                    label: "\(step.kind.title) · \(step.summary)",
                    level: result.level,
                    detail: result.detail,
                    milliseconds: result.milliseconds
                ))
                liveResults = results
                if result.level == .failure, task.stopOnFailure {
                    break
                }
            }
            finish(task: task, started: started, scheduled: scheduled, cancelled: cancelled, results: results)
        }
    }

    func cancel() {
        runTask?.cancel()
    }

    private func finish(task: AutomationTask, started: Date, scheduled: Bool, cancelled: Bool, results: [AutomationStepResult]) {
        runs.insert(AutomationRun(
            taskID: task.id,
            taskName: task.name,
            date: started,
            wasScheduled: scheduled,
            wasCancelled: cancelled,
            stepCount: task.steps.count,
            results: results
        ), at: 0)
        let failures = results.filter { $0.level == .failure }.count
        AppLog.shared.record(
            failures > 0 ? .warning : .info,
            "Automatisation",
            "Tâche « \(task.name) » \(cancelled ? "interrompue" : "terminée") : \(results.count) étape(s) sur \(task.steps.count), \(failures) en échec."
        )
        if runs.count > Self.runLimit {
            runs.removeLast(runs.count - Self.runLimit)
        }
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index].lastRun = started
        }
        runningTaskID = nil
        currentStepID = nil
        liveResults = []
        runTask = nil
        save()
    }

    private static func perform(_ step: AutomationStep, with runner: CheckRunner) async -> CheckResult {
        switch step.kind {
        case .ping:
            return await runner.ping(host: step.target)
        case .dns:
            return await runner.dns(name: step.target)
        case .tcp:
            let port = UInt16(clamping: NumberInput.integer(step.portText) ?? 0)
            return await runner.tcp(host: step.target, port: port)
        case .http:
            return await runner.http(urlText: step.target)
        case .tls:
            return await runner.tls(target: step.target)
        }
    }

    // MARK: Planification

    /// Lance la première tâche planifiée arrivée à échéance. Les autres attendent le battement suivant.
    private func tick() {
        guard runTask == nil, !isEditing else { return }
        let now = Date()
        for task in tasks {
            guard let seconds = task.scheduleSeconds else { continue }
            // Une tâche jamais exécutée attend un intervalle complet après sa création.
            if MonitorLogic.isDue(lastRun: task.lastRun ?? task.createdAt, interval: Double(seconds), now: now) {
                run(task.id, scheduled: true)
                return
            }
        }
    }

    private func save() {
        store.save(Saved(tasks: tasks, runs: runs))
    }
}
