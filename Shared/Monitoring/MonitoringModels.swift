import Foundation
import PingouinCore

/// Surveillance enregistrée : sa définition et son état courant.
struct MonitorRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var kind: MonitorCheckKind
    /// Hôte (ping, TCP), URL (HTTP) ou nom de domaine (DNS).
    var target: String
    var port: Int?
    var intervalSeconds: Int
    var thresholds: MonitorThresholds
    var isPaused = false

    var status: MonitorStatus = .unknown
    var consecutiveFailures = 0
    var lastCheck: Date?
    var lastMilliseconds: Double?
    var lastDetail = ""
}

struct MonitorEvent: Codable, Identifiable, Hashable {
    var id = UUID()
    let date: Date
    let monitorName: String
    let level: CheckResult.Level
    let text: String
}

/// Ligne du tableau des surveillances.
struct MonitorRow: Identifiable, Hashable {
    let id: UUID
    let name: String
    let target: String
    let test: String
    let every: String
    let statusText: String
    let statusKind: StatusKind
    let time: String
    let availability: String
    /// Disponibilité de 0 à 1 sur la période choisie. `nil` : aucune mesure sur la période.
    let availabilityFraction: Double?
    /// Résultat des derniers contrôles, du plus ancien au plus récent (vrai : réussi).
    let recentResults: [Bool]
    let detail: String
    let lastCheck: String
    let isPaused: Bool
}

/// Saisie d'une nouvelle surveillance.
struct MonitorDraft {
    var name = ""
    var kind: MonitorCheckKind = .ping
    var target = ""
    var portText = "443"
    var intervalSeconds = 60
    var failuresBeforeOffline = 3
    var degradedText = ""

    static let intervals: [(seconds: Int, label: String)] = [
        (30, L("30 secondes")), (60, L("1 minute")), (300, L("5 minutes")), (900, L("15 minutes")), (3_600, L("1 heure"))
    ]
}

enum MonitorPeriod: String, CaseIterable, Identifiable {
    case hour
    case day
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hour: L("1 heure")
        case .day: L("24 heures")
        case .week: L("7 jours")
        case .month: L("30 jours")
        }
    }

    func start(from now: Date) -> Date {
        switch self {
        case .hour: now.addingTimeInterval(-3_600)
        case .day: now.addingTimeInterval(-86_400)
        case .week: now.addingTimeInterval(-7 * 86_400)
        case .month: now.addingTimeInterval(-30 * 86_400)
        }
    }
}
