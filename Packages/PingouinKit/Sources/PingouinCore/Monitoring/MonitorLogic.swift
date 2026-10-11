import Foundation

/// Nature du contrôle effectué par une surveillance.
public enum MonitorCheckKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case ping
    case tcp
    case http
    case dns

    public var id: String { rawValue }
}

public enum MonitorStatus: String, Codable, Sendable {
    /// Aucun contrôle n'a encore eu lieu.
    case unknown
    case online
    /// L'hôte répond, mais plus lentement que le seuil fixé.
    case degraded
    case offline
}

/// Résultat d'un contrôle, horodaté.
public struct MonitorSample: Codable, Hashable, Sendable {
    public let date: Date
    public let success: Bool
    public let milliseconds: Double?

    public init(date: Date, success: Bool, milliseconds: Double?) {
        self.date = date
        self.success = success
        self.milliseconds = milliseconds
    }
}

public struct MonitorThresholds: Codable, Hashable, Sendable {
    /// Nombre d'échecs consécutifs avant de déclarer l'hôte hors ligne (au moins 1).
    public var failuresBeforeOffline: Int
    /// Temps de réponse au-delà duquel l'hôte est dit dégradé. `nil` : pas de seuil.
    public var degradedAboveMilliseconds: Double?

    public init(failuresBeforeOffline: Int = 3, degradedAboveMilliseconds: Double? = nil) {
        self.failuresBeforeOffline = failuresBeforeOffline
        self.degradedAboveMilliseconds = degradedAboveMilliseconds
    }
}

/// Changement d'état qui mérite d'être consigné et, éventuellement, notifié.
public enum MonitorTransition: Equatable, Sendable {
    case wentOffline(consecutiveFailures: Int)
    case cameBackOnline
    case becameDegraded(milliseconds: Double)
    case recoveredFromDegraded
}

public struct MonitorStep: Equatable, Sendable {
    public let status: MonitorStatus
    public let consecutiveFailures: Int
    public let transition: MonitorTransition?
}

/// Règles d'état de la supervision, sans horloge ni réseau.
public enum MonitorLogic {

    /// État suivant après un contrôle.
    ///
    /// Un échec isolé ne fait pas basculer hors ligne : il faut `failuresBeforeOffline` échecs de suite.
    /// En attendant, l'état précédent est conservé. Un seul succès suffit à revenir en ligne.
    public static func advance(
        from status: MonitorStatus,
        consecutiveFailures: Int,
        with sample: MonitorSample,
        thresholds: MonitorThresholds
    ) -> MonitorStep {
        guard sample.success else {
            let failures = consecutiveFailures + 1
            let limit = max(thresholds.failuresBeforeOffline, 1)
            if failures >= limit {
                let transition: MonitorTransition? = status == .offline ? nil : .wentOffline(consecutiveFailures: failures)
                return MonitorStep(status: .offline, consecutiveFailures: failures, transition: transition)
            }
            return MonitorStep(status: status, consecutiveFailures: failures, transition: nil)
        }

        let isSlow: Bool
        if let limit = thresholds.degradedAboveMilliseconds, let time = sample.milliseconds {
            isSlow = time > limit
        } else {
            isSlow = false
        }
        let next: MonitorStatus = isSlow ? .degraded : .online

        var transition: MonitorTransition?
        if status == .offline {
            transition = .cameBackOnline
        } else if next == .degraded, status != .degraded {
            transition = .becameDegraded(milliseconds: sample.milliseconds ?? 0)
        } else if next == .online, status == .degraded {
            transition = .recoveredFromDegraded
        }
        return MonitorStep(status: next, consecutiveFailures: 0, transition: transition)
    }

    /// Part des contrôles réussis depuis `start`, de 0 à 100. `nil` s'il n'y a aucun contrôle sur la période :
    /// une période sans mesure (veille, application fermée) n'est jamais comptée comme une panne.
    public static func availabilityPercent(samples: [MonitorSample], since start: Date) -> Double? {
        let inWindow = samples.filter { $0.date >= start }
        guard !inWindow.isEmpty else { return nil }
        let successes = inWindow.filter(\.success).count
        return Double(successes) / Double(inWindow.count) * 100
    }

    /// Durée sans mesure entre deux battements du moteur, quand elle dépasse nettement la cadence attendue
    /// (veille du Mac, application figée). `nil` si le battement est arrivé à l'heure.
    public static func measurementGap(lastTick: Date?, now: Date, expectedInterval: TimeInterval) -> TimeInterval? {
        guard let lastTick else { return nil }
        let elapsed = now.timeIntervalSince(lastTick)
        return elapsed > max(expectedInterval * 10, 30) ? elapsed : nil
    }

    /// Vrai si un contrôle est dû : jamais fait, ou fait depuis au moins `interval`.
    public static func isDue(lastRun: Date?, interval: TimeInterval, now: Date) -> Bool {
        guard let lastRun else { return true }
        return now.timeIntervalSince(lastRun) >= interval
    }

    /// Ne garde que les `limit` contrôles les plus récents.
    public static func trimmed(_ samples: [MonitorSample], limit: Int) -> [MonitorSample] {
        samples.count > limit ? Array(samples.suffix(limit)) : samples
    }
}
