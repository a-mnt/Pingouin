import Foundation
import Observation

/// État partagé de l'application : module affiché et modèles de présentation.
///
/// Les modèles vivent ici, et non dans les vues, pour que les résultats d'un outil
/// restent en place quand on passe à un autre (par exemple de la découverte LAN au scan de ports).
@MainActor
@Observable
final class AppState: ReportSource {
    var selection: AppModule? = AppSettings.startModule

    let calculator = IPCalculatorViewModel()
    let lanDiscovery = LANDiscoveryViewModel()
    let portScanner = PortScanViewModel()
    let ping = PingViewModel()
    let traceroute = TracerouteViewModel()
    let dns = DNSViewModel()
    let http = HTTPViewModel()
    let tls = TLSViewModel()
    let ssh = SSHViewModel()
    let monitoring = MonitoringViewModel()
    let usage = UsageViewModel()
    let topology = TopologyViewModel()
    let reports = ReportsViewModel()
    let automation = AutomationViewModel()
    let dashboard = DashboardViewModel()

    init() {
        applyDiagnosticsSettings()
    }

    /// Reporte les réglages par défaut dans les fenêtres des outils. Un outil en cours n'est pas touché.
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

    /// Ouvre la fenêtre SSH et lance aussitôt une session vers cet hôte, sur ce port.
    func openSSH(host: String, port: Int) {
        selection = .ssh
        ssh.quickConnect(host: host, port: port)
    }

    /// Ouvre un outil sur une cible et le lance aussitôt, avec les réglages affichés dans cet outil.
    /// L'outil garde ses propres garde-fous : il redemande confirmation si l'opération est lourde.
    ///
    /// `target` est une adresse ou un nom d'hôte, sauf pour HTTP (une URL) et TLS (« hôte:port »).
    func open(_ module: AppModule, target: String) {
        guard module.isAvailable else { return }
        selection = module
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
            ssh.quickConnect(host: target)
        default:
            break
        }
    }
}
