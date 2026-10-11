import SwiftUI
import PingouinCore

/// Racine de l'application : des onglets sur iPhone, une barre latérale sur iPad
/// (c'est le même `TabView`, que le système adapte à la largeur disponible).
struct MobileRootView: View {
    @Environment(MobileAppState.self) private var state
    @AppStorage(AppSettings.Key.appearance) private var appearance = AppSettings.Default.appearance

    var body: some View {
        @Bindable var state = state
        TabView(selection: $state.tab) {
            Tab(L("Accueil"), systemImage: "house", value: MobileTab.home) {
                NavigationStack {
                    MobileHomeView()
                }
            }
            Tab(L("Outils"), systemImage: "wrench.and.screwdriver", value: MobileTab.tools) {
                NavigationStack(path: $state.toolsPath) {
                    MobileModuleList(
                        title: L("Outils"),
                        modules: MobileAppState.tools,
                        footnote: L("Rien ne part sur le réseau tant qu'un outil n'est pas lancé.")
                    )
                    .navigationDestination(for: AppModule.self) { module in
                        MobileModuleView(module: module)
                    }
                }
            }
            Tab(L("Réseau"), systemImage: "network", value: MobileTab.network) {
                NavigationStack(path: $state.networkPath) {
                    MobileModuleList(
                        title: L("Réseau"),
                        modules: MobileAppState.networkModules,
                        footnote: L("La supervision et les tâches planifiées ne tournent que lorsque Pingouin est à l'écran : iOS suspend les applications en arrière-plan.")
                    )
                    .navigationDestination(for: AppModule.self) { module in
                        MobileModuleView(module: module)
                    }
                }
            }
            Tab("SSH", systemImage: "terminal", value: MobileTab.ssh) {
                NavigationStack(path: $state.sshPath) {
                    MobileSSHView(model: state.ssh)
                        .navigationDestination(for: MobileSSHRoute.self) { route in
                            MobileSSHRouteView(route: route)
                        }
                }
            }
            Tab(L("Réglages"), systemImage: "gearshape", value: MobileTab.settings) {
                NavigationStack {
                    MobileSettingsView()
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .preferredColorScheme(AppSettings.colorScheme(for: appearance))
    }
}

/// Écran de l'onglet SSH auquel mène une route.
struct MobileSSHRouteView: View {
    @Environment(MobileAppState.self) private var state
    let route: MobileSSHRoute

    var body: some View {
        switch route {
        case .session(let id):
            if let session = state.ssh.session(id: id) {
                MobileSSHSessionView(model: state.ssh, session: session)
            } else {
                ContentUnavailableView(
                    L("Session fermée"),
                    systemImage: "bolt.horizontal.circle",
                    description: Text(L("Cette session n'existe plus. Revenir à la liste des connexions pour la rouvrir."))
                )
            }
        case .deviceKey:
            MobileDeviceKeyView(model: state.ssh)
        }
    }
}

/// Écran d'un module, choisi d'après le module demandé.
struct MobileModuleView: View {
    @Environment(MobileAppState.self) private var state
    let module: AppModule

    var body: some View {
        switch module {
        case .ping: MobilePingView(model: state.ping)
        case .traceroute: MobileTracerouteView(model: state.traceroute)
        case .dns: MobileDNSView(model: state.dns)
        case .portScanner: MobilePortScanView(model: state.portScanner)
        case .http: MobileHTTPView(model: state.http)
        case .tls: MobileTLSView(model: state.tls)
        case .ipCalculator: MobileIPCalculatorView(model: state.calculator)
        case .lanDiscovery: MobileLANDiscoveryView(model: state.lanDiscovery)
        case .monitoring: MobileMonitoringView(model: state.monitoring)
        case .usage: MobileUsageView(model: state.usage)
        case .topology: MobileTopologyView(model: state.topology)
        case .automation: MobileAutomationView(model: state.automation)
        case .reports: MobileReportsView(model: state.reports)
        case .dashboard, .ssh:
            ContentUnavailableView(
                L("Écran indisponible"),
                systemImage: module.systemImage,
                description: Text(L("Cet écran s'ouvre depuis son onglet."))
            )
        }
    }
}
