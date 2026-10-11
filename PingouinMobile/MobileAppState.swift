import Foundation
import Observation
import PingouinCore

/// Onglets de l'application iOS.
enum MobileTab: Hashable {
    case home
    case tools
    case network
    case ssh
    case settings
}

/// État de l'application iOS : l'onglet affiché, la pile de chaque onglet, et les modèles de présentation
/// des outils, gardés tant que l'application est ouverte, pour qu'un outil lancé continue quand on
/// change d'écran.
@MainActor
@Observable
final class MobileAppState: ReportSource {
    var tab: MobileTab = .home
    var toolsPath: [AppModule] = []
    var networkPath: [AppModule] = []
    var sshPath: [MobileSSHRoute] = []

    let calculator = IPCalculatorViewModel()
    let lanDiscovery = LANDiscoveryViewModel()
    let portScanner = PortScanViewModel()
    let ping = PingViewModel()
    let traceroute = TracerouteViewModel()
    let dns = DNSViewModel()
    let http = HTTPViewModel()
    let tls = TLSViewModel()
    let monitoring = MonitoringViewModel()
    let usage = UsageViewModel()
    let topology = TopologyViewModel()
    let reports = ReportsViewModel()
    let automation = AutomationViewModel()
    let dashboard = DashboardViewModel()
    let ssh = MobileSSHViewModel()

    /// Outils de l'onglet « Outils » ; les autres modules sont dans l'onglet « Réseau ».
    static let tools: [AppModule] = [.ping, .traceroute, .dns, .portScanner, .http, .tls, .ipCalculator]
    static let networkModules: [AppModule] = [.lanDiscovery, .monitoring, .usage, .topology, .automation, .reports]

    init() {
        applyDiagnosticsSettings()
    }

    /// Reporte les réglages par défaut dans les écrans des outils. Un outil en cours n'est pas touché.
    func applyDiagnosticsSettings() {
        if !portScanner.isRunning {
            portScanner.timeoutText = String(AppSettings.portScanTimeout)
            portScanner.concurrencyText = String(AppSettings.portScanConcurrency)
        }
        if !ping.isRunning {
            ping.countText = String(AppSettings.pingCount)
            ping.timeoutText = String(AppSettings.pingTimeout)
        }
        if !traceroute.isRunning {
            traceroute.maximumHopsText = String(AppSettings.tracerouteMaximumHops)
        }
        if !lanDiscovery.isRunning {
            lanDiscovery.resolveNames = AppSettings.lanResolveNames
        }
    }

    /// Affiche l'écran d'un module, dans l'onglet qui le contient.
    func show(_ module: AppModule) {
        guard module.isAvailable else { return }
        if Self.tools.contains(module) {
            toolsPath = [module]
            tab = .tools
        } else if Self.networkModules.contains(module) {
            networkPath = [module]
            tab = .network
        } else if module == .dashboard {
            tab = .home
        } else if module == .ssh {
            tab = .ssh
        }
    }

    /// Ouvre un outil sur une cible et le lance aussitôt, avec les réglages affichés dans cet outil.
    /// L'outil garde ses propres garde-fous : il redemande confirmation si l'opération est lourde.
    ///
    /// `target` est une adresse ou un nom d'hôte, sauf pour HTTP (une URL) et TLS (« hôte:port »).
    func open(_ module: AppModule, target: String) {
        guard module.isAvailable else { return }
        show(module)
        switch module {
        case .portScanner:
            portScanner.launch(host: target)
        case .ping:
            ping.launch(host: target)
        case .traceroute:
            traceroute.launch(host: target)
        case .dns:
            dns.launchReverse(address: target)
        case .http:
            http.launch(url: target)
        case .tls:
            tls.launch(target: target)
        case .ssh:
            openSSH(host: target)
        default:
            break
        }
    }

    /// Ouvre SSH sur un hôte : la connexion enregistrée pour cet hôte s'il n'y en a qu'une, sinon la
    /// connexion rapide, où il reste à saisir le compte. Rien n'est envoyé avant que l'écran s'ouvre.
    private func openSSH(host: String) {
        let matches = ssh.profiles.filter { $0.host.caseInsensitiveCompare(host) == .orderedSame }
        if matches.count == 1 {
            ssh.session(for: matches[0])
            sshPath = [.session(matches[0].id)]
        } else {
            sshPath = []
            ssh.prepareQuick(host: host)
        }
    }

    /// Ouvre l'outil DNS sur un nom et le résout aussitôt (enregistrements A).
    func resolve(_ name: String) {
        dns.name = name
        dns.type = .a
        show(.dns)
        dns.start()
    }
}
