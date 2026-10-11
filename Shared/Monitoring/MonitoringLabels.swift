import Foundation
import PingouinCore

/// Libellés affichés par la supervision.
extension MonitoringViewModel {

    static func statusLabel(_ monitor: MonitorRecord) -> (text: String, kind: StatusKind) {
        if monitor.isPaused { return (L("En pause"), StatusKind.neutral) }
        switch monitor.status {
        case .unknown: return (L("En attente"), StatusKind.neutral)
        case .online: return (L("En ligne"), StatusKind.ok)
        case .degraded: return (L("Dégradé"), StatusKind.warning)
        case .offline: return (L("Hors ligne"), StatusKind.failure)
        }
    }

    static func kindLabel(_ kind: MonitorCheckKind) -> String {
        switch kind {
        case .ping: L("Ping")
        case .tcp: "TCP"
        case .http: "HTTP"
        case .dns: "DNS"
        }
    }

    static func intervalLabel(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds) s" : seconds < 3_600 ? L("\(seconds / 60) min") : "\(seconds / 3_600) h"
    }

    static var notificationsRefusedText: String {
        #if os(macOS)
        L("macOS n'autorise pas les notifications de Pingouin. Les activer dans Réglages Système > Notifications.")
        #else
        L("iOS n'autorise pas les notifications de Pingouin. Les activer dans Réglages > Notifications > Pingouin.")
        #endif
    }

    static func resumeText(after gap: TimeInterval) -> String {
        #if os(macOS)
        L("Reprise après \(durationLabel(gap)) sans mesure (veille du Mac ou application suspendue).")
        #else
        L("Reprise après \(durationLabel(gap)) sans mesure (application hors de l'écran ou appareil verrouillé).")
        #endif
    }

    static func durationLabel(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        if total < 120 { return "\(total) s" }
        if total < 7_200 { return L("\(total / 60) min") }
        return L("\(total / 3_600) h \(total % 3_600 / 60) min")
    }
}
