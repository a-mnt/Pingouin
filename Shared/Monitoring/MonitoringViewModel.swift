#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import Foundation
import Observation
import PingouinCore
import UserNotifications

/// Supervision locale : contrôles périodiques tant que l'application est ouverte et l'appareil éveillé.
/// Aucun mécanisme ne tourne en arrière-plan une fois l'application fermée. Sur iOS, les contrôles
/// s'arrêtent dès que l'application quitte l'écran : le système la suspend.
@MainActor
@Observable
final class MonitoringViewModel {
    private struct Saved: Codable {
        var monitors: [MonitorRecord]
        var events: [MonitorEvent]
    }

    /// Ancien format de « supervision.json », où chaque surveillance portait toutes ses mesures.
    /// Il ne sert qu'à les reprendre une fois, pour les convertir en mémoire par heure.
    private struct LegacySaved: Codable {
        struct Record: Codable {
            var id: UUID
            var samples: [MonitorSample]?
        }

        var monitors: [Record]
    }

    /// Écart entre deux enregistrements des mesures.
    private static let historySaveSeconds: TimeInterval = 300
    private static let eventLimit = 300
    /// Nombre de contrôles récents montrés sur une tuile.
    static let recentResultCount = 30
    private static let notificationsKey = "monitoring.notificationsEnabled"

    // Version 2 : les mesures ont quitté ce fichier pour « supervision-mesures.json » (ADR 0009).
    private let store = JSONStore<Saved>(fileName: "supervision", version: 2)
    private let historyStore = JSONStore<[String: MonitorHistory]>(fileName: "supervision-mesures")
    private let runner = CheckRunner()

    private(set) var monitors: [MonitorRecord] = []
    private(set) var events: [MonitorEvent] = []
    var selection: Set<UUID> = []
    var period: MonitorPeriod = .day
    var draft = MonitorDraft()
    var isEditing = false
    var draftError: String?
    private(set) var notificationsEnabled = UserDefaults.standard.bool(forKey: MonitoringViewModel.notificationsKey)
    private(set) var notificationMessage: String?

    private var inFlight: Set<UUID> = []
    private var lastTick: Date?
    /// Mémoire de chaque surveillance (derniers contrôles et résumés par heure), par identifiant.
    private var histories: [String: MonitorHistory] = [:]
    private var lastSave = Date()
    private var needsSave = false
    private var engine: Task<Void, Never>?

    init() {
        if let saved = store.load() {
            monitors = saved.monitors
            events = saved.events
        }
        if let savedHistories = historyStore.load() {
            histories = savedHistories
        } else if let legacy = JSONStore<LegacySaved>(fileName: "supervision", version: 2).load() {
            // Premier lancement après le changement de stockage : les mesures de l'ancien fichier
            // deviennent des résumés par heure, enregistrés avant que l'ancien fichier soit réécrit.
            for record in legacy.monitors {
                if let samples = record.samples, !samples.isEmpty {
                    histories[record.id.uuidString] = MonitorHistory(samples: samples)
                }
            }
            if !histories.isEmpty {
                historyStore.save(histories)
                save()
            }
        }
        // Les mesures en attente sont écrites à la fermeture de l'application ; sur iOS, dès qu'elle
        // quitte l'écran, car le système peut ensuite l'arrêter sans prévenir.
        #if canImport(AppKit)
        let lastChance = NSApplication.willTerminateNotification
        #else
        let lastChance = UIApplication.didEnterBackgroundNotification
        #endif
        NotificationCenter.default.addObserver(forName: lastChance, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.flush()
            }
        }
        engine = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    // MARK: Synthèse

    var onlineCount: Int { monitors.filter { $0.status == .online && !$0.isPaused }.count }
    var degradedCount: Int { monitors.filter { $0.status == .degraded && !$0.isPaused }.count }
    var offlineCount: Int { monitors.filter { $0.status == .offline && !$0.isPaused }.count }
    var activeCount: Int { monitors.filter { !$0.isPaused }.count }
    var allPaused: Bool { !monitors.isEmpty && monitors.allSatisfy(\.isPaused) }

    /// Alertes (avertissements et pannes) des dernières 24 heures.
    var recentAlertCount: Int {
        let since = Date().addingTimeInterval(-86_400)
        return events.filter { $0.date >= since && $0.level != .ok }.count
    }

    var rows: [MonitorRow] {
        let start = period.start(from: Date())
        let usesDetail = period == .hour
        return monitors.map { monitor in
            let status = Self.statusLabel(monitor)
            let history = histories[monitor.id.uuidString] ?? MonitorHistory()
            // Sur une heure, le détail des contrôles ; au-delà, les résumés par heure.
            let availability = usesDetail
                ? history.recentAvailabilityPercent(since: start)
                : history.hourlyAvailabilityPercent(since: start)
            return MonitorRow(
                id: monitor.id,
                name: monitor.name,
                target: monitor.kind == .tcp ? "\(monitor.target):\(monitor.port ?? 0)" : monitor.target,
                test: Self.kindLabel(monitor.kind),
                every: Self.intervalLabel(monitor.intervalSeconds),
                statusText: status.text,
                statusKind: status.kind,
                time: monitor.lastMilliseconds.map { NumberInput.milliseconds($0) } ?? "—",
                availability: availability.map { ($0 / 100).formatted(.percent.precision(.fractionLength(0...1))) } ?? "—",
                availabilityFraction: availability.map { $0 / 100 },
                recentResults: history.recent.suffix(Self.recentResultCount).map(\.success),
                detail: monitor.lastDetail,
                lastCheck: monitor.lastCheck?.formatted(date: .omitted, time: .standard) ?? "—",
                isPaused: monitor.isPaused
            )
        }
    }

    func monitor(id: UUID) -> MonitorRecord? {
        monitors.first { $0.id == id }
    }

    // MARK: Gestion

    func beginAdding() {
        draft = MonitorDraft()
        draft.intervalSeconds = AppSettings.monitorInterval
        draft.failuresBeforeOffline = AppSettings.monitorFailures
        draftError = nil
        isEditing = true
    }

    /// Valide la saisie et crée la surveillance. Renvoie faux, avec un message, si la saisie est incomplète.
    @discardableResult
    func commitDraft() -> Bool {
        let target = draft.target.trimmingCharacters(in: .whitespacesAndNewlines)
        var port: Int?
        switch draft.kind {
        case .ping, .dns:
            guard HostInput.isPlausible(target) else {
                draftError = L("Saisir un nom d'hôte ou une adresse, sans espace.")
                return false
            }
        case .tcp:
            guard HostInput.isPlausible(target) else {
                draftError = L("Saisir un nom d'hôte ou une adresse, sans espace.")
                return false
            }
            guard let value = NumberInput.integer(draft.portText), (1...65_535).contains(value) else {
                draftError = L("Le port doit être compris entre 1 et 65535.")
                return false
            }
            port = value
        case .http:
            guard HTTPTarget.url(from: target) != nil else {
                draftError = L("Saisir une URL en http:// ou https://.")
                return false
            }
        }

        var degraded: Double?
        let degradedText = draft.degradedText.trimmingCharacters(in: .whitespaces)
        if !degradedText.isEmpty {
            guard let value = NumberInput.decimal(degradedText), value > 0 else {
                draftError = L("Le seuil de lenteur doit être un nombre de millisecondes, ou rester vide.")
                return false
            }
            degraded = value
        }

        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        monitors.append(MonitorRecord(
            name: name.isEmpty ? target : name,
            kind: draft.kind,
            target: target,
            port: port,
            intervalSeconds: draft.intervalSeconds,
            thresholds: MonitorThresholds(
                failuresBeforeOffline: min(max(draft.failuresBeforeOffline, 1), 10),
                degradedAboveMilliseconds: degraded
            )
        ))
        isEditing = false
        save()
        return true
    }

    /// Ajoute directement une surveillance par ping, depuis un autre outil.
    func addPingMonitor(name: String, host: String) {
        guard !monitors.contains(where: { $0.kind == .ping && $0.target == host }) else { return }
        monitors.append(MonitorRecord(
            name: name.isEmpty ? host : name,
            kind: .ping,
            target: host,
            port: nil,
            intervalSeconds: AppSettings.monitorInterval,
            thresholds: MonitorThresholds(failuresBeforeOffline: AppSettings.monitorFailures)
        ))
        save()
    }

    func setPaused(_ paused: Bool, ids: Set<UUID>) {
        for index in monitors.indices where ids.contains(monitors[index].id) {
            monitors[index].isPaused = paused
        }
        save()
    }

    func toggleAllPaused() {
        let pause = !allPaused
        for index in monitors.indices {
            monitors[index].isPaused = pause
        }
        save()
    }

    func remove(ids: Set<UUID>) {
        monitors.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
        for id in ids {
            histories[id.uuidString] = nil
        }
        flush()
    }

    func checkNow(ids: Set<UUID>) {
        for id in ids {
            run(id)
        }
    }

    func clearEvents() {
        events = []
        save()
    }

    // MARK: Notifications

    func setNotifications(_ enabled: Bool) {
        guard enabled else {
            notificationsEnabled = false
            notificationMessage = nil
            UserDefaults.standard.set(false, forKey: Self.notificationsKey)
            return
        }
        Task {
            var granted = false
            do {
                granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                notificationMessage = granted ? nil : Self.notificationsRefusedText
            } catch {
                // Une erreur n'est pas un refus : elle est montrée telle quelle, et journalisée.
                notificationMessage = L("La demande d'autorisation des notifications a échoué : \(error.localizedDescription)")
                AppLog.shared.error("Supervision", "Demande d'autorisation des notifications en échec : \(error.localizedDescription)")
            }
            notificationsEnabled = granted
            UserDefaults.standard.set(granted, forKey: Self.notificationsKey)
        }
    }

    private func notify(title: String, body: String) {
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: Moteur

    private func tick() {
        let now = Date()
        if let gap = MonitorLogic.measurementGap(lastTick: lastTick, now: now, expectedInterval: 1), activeCount > 0 {
            addEvent(name: L("Supervision"), level: .warning, text: Self.resumeText(after: gap))
        }
        lastTick = now

        for monitor in monitors where !monitor.isPaused && !inFlight.contains(monitor.id) {
            if MonitorLogic.isDue(lastRun: monitor.lastCheck, interval: Double(monitor.intervalSeconds), now: now) {
                run(monitor.id)
            }
        }
        if needsSave, now.timeIntervalSince(lastSave) >= Self.historySaveSeconds {
            flush()
        }
    }

    private func run(_ id: UUID) {
        guard !inFlight.contains(id), let monitor = self.monitor(id: id) else { return }
        inFlight.insert(id)
        let runner = self.runner
        let kind = monitor.kind
        let target = monitor.target
        let port = UInt16(clamping: monitor.port ?? 0)
        Task {
            let result: CheckResult
            switch kind {
            case .ping:
                result = await runner.ping(host: target)
            case .tcp:
                result = await runner.tcp(host: target, port: port)
            case .http:
                result = await runner.http(urlText: target)
            case .dns:
                result = await runner.dns(name: target)
            }
            apply(result, to: id)
            inFlight.remove(id)
        }
    }

    private func apply(_ result: CheckResult, to id: UUID) {
        guard let index = monitors.firstIndex(where: { $0.id == id }) else { return }
        let now = Date()
        let sample = MonitorSample(date: now, success: result.succeeded, milliseconds: result.milliseconds)
        let step = MonitorLogic.advance(
            from: monitors[index].status,
            consecutiveFailures: monitors[index].consecutiveFailures,
            with: sample,
            thresholds: monitors[index].thresholds
        )
        monitors[index].status = step.status
        monitors[index].consecutiveFailures = step.consecutiveFailures
        monitors[index].lastCheck = now
        monitors[index].lastMilliseconds = result.milliseconds
        monitors[index].lastDetail = result.detail
        histories[id.uuidString, default: MonitorHistory()].add(sample)
        needsSave = true

        let name = monitors[index].name
        switch step.transition {
        case .wentOffline(let failures):
            addEvent(name: name, level: .failure, text: L("Hors ligne après \(failures) échecs consécutifs. \(result.detail)."))
            notify(title: L("\(name) est hors ligne"), body: result.detail)
        case .cameBackOnline:
            addEvent(name: name, level: .ok, text: L("Retour en ligne."))
            notify(title: L("\(name) est de nouveau en ligne"), body: result.detail)
        case .becameDegraded(let milliseconds):
            let limit = monitors[index].thresholds.degradedAboveMilliseconds ?? 0
            addEvent(name: name, level: .warning, text: L("Seuil dépassé : \(NumberInput.milliseconds(milliseconds)) pour un seuil de \(NumberInput.milliseconds(limit))."))
        case .recoveredFromDegraded:
            addEvent(name: name, level: .ok, text: L("Temps de réponse revenu sous le seuil."))
        case nil:
            break
        }
    }

    private func addEvent(name: String, level: CheckResult.Level, text: String) {
        events.insert(MonitorEvent(date: Date(), monitorName: name, level: level, text: text), at: 0)
        AppLog.shared.record(level == .ok ? .info : (level == .warning ? .warning : .error), "Supervision", "\(name) : \(text)")
        if events.count > Self.eventLimit {
            events.removeLast(events.count - Self.eventLimit)
        }
        // Un événement (panne, retour en ligne) est écrit aussitôt : le fichier d'état est petit.
        save()
    }

    /// Écrit l'état des surveillances et les événements. Les mesures ont leur propre fichier.
    private func save() {
        store.save(Saved(monitors: monitors, events: events))
    }

    /// Écrit l'état et les mesures. Appelé toutes les cinq minutes, et à la fermeture.
    private func flush() {
        save()
        historyStore.save(histories)
        lastSave = Date()
        needsSave = false
    }
}
