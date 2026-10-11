import Foundation
import PingouinCore

/// Box ou équipement capable de fournir des volumes par appareil.
enum UsageSourceKind: String, CaseIterable, Identifiable {
    case freebox
    case livebox
    case bbox
    case snmp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .freebox: "Freebox"
        case .livebox: L("Livebox (Orange)")
        case .bbox: L("Bbox (Bouygues Telecom)")
        case .snmp: L("Switch ou routeur administrable (SNMP)")
        }
    }

    /// Vrai si Pingouin sait réellement interroger cette source.
    var isSupported: Bool { self == .freebox }

    var note: String {
        switch self {
        case .freebox: L("Wi-Fi par appareil, Ethernet par port de la box. L'accès se valide sur l'écran de la box.")
        case .livebox, .bbox, .snmp: L("Pas encore pris en charge.")
        }
    }
}

enum UsagePeriod: String, CaseIterable, Identifiable {
    case session
    case today
    case week

    var id: String { rawValue }

    var title: String {
        switch self {
        case .session: L("Depuis l'ouverture de Pingouin")
        case .today: L("Aujourd'hui")
        case .week: L("7 jours")
        }
    }
}

enum UsageConnection: Equatable {
    case disconnected
    case connecting
    /// La box attend que l'utilisateur valide la demande sur son écran.
    case awaitingApproval
    case connected(boxName: String)
    case failed(message: String)
}

/// Ligne du tableau « Par appareil ».
struct UsageRow: Identifiable, Hashable {
    let id: String
    let name: String
    /// Adresse IP, ou liste des appareils regroupés derrière un port.
    let detail: String
    let isShared: Bool
    let link: String
    let received: String
    let sent: String
    /// Part du total affiché, de 0 à 1.
    let share: Double
    let shareText: String
    let rate: String
    let isPresent: Bool
    /// Vrai pour un appareil listé sous un port partagé : la box ne mesure pas son trafic séparément.
    var isMember = false
}
