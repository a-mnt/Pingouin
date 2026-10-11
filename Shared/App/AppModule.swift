import Foundation
import PingouinCore

/// Groupes de la barre latérale.
enum ModuleGroup: String, CaseIterable, Identifiable {
    case overview
    case diagnostics
    case analysis
    case tools
    case administration
    case production

    var id: String { rawValue }

    /// Titre affiché au-dessus du groupe. Le premier groupe n'en a pas.
    var title: String {
        switch self {
        case .overview: ""
        case .diagnostics: L("Diagnostics")
        case .analysis: L("Analyse")
        case .tools: L("Outils")
        case .administration: L("Administration")
        case .production: L("Production")
        }
    }

    var modules: [AppModule] {
        AppModule.allCases.filter { $0.group == self }
    }
}

/// Modules de l'application. `isAvailable` reflète l'état réel du code :
/// un module non disponible est affiché comme tel, jamais simulé.
enum AppModule: String, CaseIterable, Identifiable {
    // L'ordre des cas est l'ordre d'affichage dans la barre latérale.
    case dashboard
    case lanDiscovery
    case portScanner
    case ping
    case traceroute
    case dns
    case http
    case tls
    case ipCalculator
    case ssh
    case monitoring
    case usage
    case topology
    case reports
    case automation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: L("Tableau de bord")
        case .ping: L("Ping")
        case .traceroute: L("Traceroute")
        case .dns: "DNS"
        case .portScanner: L("Scan de ports")
        case .lanDiscovery: L("Découverte LAN")
        case .http: "HTTP"
        case .tls: "TLS"
        case .ipCalculator: L("Calculateur IP")
        case .ssh: "SSH"
        case .monitoring: L("Supervision")
        case .usage: L("Consommation")
        case .topology: L("Topologie")
        case .reports: L("Rapports")
        case .automation: L("Automatisation")
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .ping: "waveform.path.ecg"
        case .traceroute: "arrow.triangle.turn.up.right.diamond"
        case .dns: "globe"
        case .portScanner: "cable.connector"
        case .lanDiscovery: "dot.radiowaves.left.and.right"
        case .http: "arrow.left.arrow.right"
        case .tls: "lock.shield"
        case .ipCalculator: "number"
        case .ssh: "terminal"
        case .monitoring: "eye"
        case .usage: "chart.bar"
        case .topology: "point.3.connected.trianglepath.dotted"
        case .reports: "doc.text"
        case .automation: "bolt"
        }
    }

    var group: ModuleGroup {
        switch self {
        case .dashboard: .overview
        case .ping, .traceroute, .dns, .portScanner, .lanDiscovery: .diagnostics
        case .http, .tls: .analysis
        case .ipCalculator: .tools
        case .ssh, .monitoring, .usage, .topology: .administration
        case .reports, .automation: .production
        }
    }

    var isAvailable: Bool {
        // Tous les modules sont développés, sur le Mac comme sur iOS. Le commutateur reste en place
        // pour pouvoir en désactiver un.
        true
    }
}
