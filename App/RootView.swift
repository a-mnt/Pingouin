import AppKit
import SwiftUI
import PingouinCore

struct RootView: View {
    @Environment(AppState.self) private var app
    @AppStorage(AppSettings.Key.appearance) private var appearance = AppSettings.Default.appearance
    @AppStorage(AppSettings.Key.showsSidebarLogo) private var showsSidebarLogo = true

    var body: some View {
        @Bindable var app = app

        NavigationSplitView {
            List(selection: $app.selection) {
                ForEach(ModuleGroup.allCases) { group in
                    Section(group.title) {
                        ForEach(group.modules) { module in
                            // Icône dans un cadre de largeur fixe et titre sur une ligne entière :
                            // la ligne garde la même mise en page, sélectionnée ou non.
                            Label {
                                Text(module.title)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            } icon: {
                                Image(systemName: module.systemImage)
                                    .frame(width: 22, alignment: .center)
                            }
                            .tag(module)
                        }
                    }
                }
            }
            // Le logo et le nom restent en haut de la barre latérale, au-dessus de la liste qui défile.
            .safeAreaInset(edge: .top, spacing: 0) {
                if showsSidebarLogo {
                    HStack(spacing: 10) {
                        PingouinLogo(size: 30)
                        Text("Pingouin")
                            .font(.title3.weight(.bold))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Pingouin")
                }
            }
            .navigationSplitViewColumnWidth(min: 230, ideal: 240, max: 320)
        } detail: {
            detail
                // Un fichier de données illisible est signalé ici, quelle que soit la fenêtre affichée.
                .safeAreaInset(edge: .top, spacing: 0) {
                    storageIssues
                }
        }
        .preferredColorScheme(AppSettings.colorScheme(for: appearance))
        .onChange(of: app.selection) { _, module in
            AppSettings.rememberLastModule(module)
        }
    }

    @ViewBuilder
    private var storageIssues: some View {
        let issues = StorageIssues.shared.issues
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(issues) { issue in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Label(issue.message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        if let url = issue.setAsideURL {
                            Button(L("Afficher dans le Finder")) {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                        }
                        Button(L("Fermer")) {
                            StorageIssues.shared.dismiss(issue.id)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 16)
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let module = app.selection {
            switch module {
            case .dashboard:
                DashboardView()
            case .ssh:
                SSHView(model: app.ssh)
            case .monitoring:
                MonitoringView(model: app.monitoring)
            case .usage:
                UsageView(model: app.usage)
            case .topology:
                TopologyView(model: app.topology)
            case .reports:
                ReportsView(model: app.reports)
            case .automation:
                AutomationView(model: app.automation)
            case .ipCalculator:
                IPCalculatorView(model: app.calculator)
            case .lanDiscovery:
                LANDiscoveryView(model: app.lanDiscovery)
            case .portScanner:
                PortScanView(model: app.portScanner)
            case .ping:
                PingView(model: app.ping)
            case .traceroute:
                TracerouteView(model: app.traceroute)
            case .dns:
                DNSView(model: app.dns)
            case .http:
                HTTPView(model: app.http)
            case .tls:
                TLSView(model: app.tls)
            }
        } else {
            ContentUnavailableView(
                L("Aucun outil sélectionné"),
                systemImage: "sidebar.left",
                description: Text(L("Choisir un outil dans la barre latérale."))
            )
            .background { PingouinBackdrop() }
        }
    }
}

/// Écran affiché pour un module qui n'est pas encore développé.
struct ModuleUnavailableView: View {
    let module: AppModule

    var body: some View {
        ContentUnavailableView(
            module.title,
            systemImage: module.systemImage,
            description: Text(L("Ce module n'est pas encore disponible dans cette version."))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { PingouinBackdrop() }
        .navigationTitle(module.title)
    }
}
