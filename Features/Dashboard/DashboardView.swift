import SwiftUI
import PingouinCore

/// Tableau de bord : le raccordement de ce Mac, l'état de la connexion, puis ce qui demande une action.
/// Hors raccordement et test de connexion, il ne détient aucune donnée : il lit l'état des autres modules.
struct DashboardView: View {
    @Environment(AppState.self) private var app

    private struct RunningTask: Identifiable {
        let id: AppModule
        let detail: String
        let cancel: () -> Void
    }

    var body: some View {
        let model = app.dashboard
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DashboardConnectionCard(model: model)
                if !onboarding.isComplete {
                    DashboardStartCard(steps: onboarding, network: model.network)
                }
                if onboarding.hasStarted {
                    tiles
                }
                HStack(alignment: .top, spacing: 14) {
                    if !app.monitoring.rows.isEmpty {
                        attention
                    }
                    VStack(spacing: 14) {
                        DashboardQuickLaunch(model: model, recentTargets: recentTargets)
                        if !runningTasks.isEmpty {
                            running
                        }
                    }
                    .frame(minWidth: 280, maxWidth: app.monitoring.rows.isEmpty ? .infinity : 420)
                }
                Text(L("Rien ne part sur le réseau à l'ouverture : le raccordement est lu sur ce Mac, et chaque contrôle se lance par un bouton."))
                    .footnoteStyle()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background { PingouinBackdrop() }
        .navigationTitle(L("Tableau de bord"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if model.isTesting {
                    Button(L("Arrêter"), role: .cancel) {
                        model.cancelTest()
                    }
                } else {
                    Button(L("Tester ma connexion")) {
                        model.runTest()
                    }
                    .buttonStyle(.borderedProminent)
                    .help(L("Quatre contrôles : la passerelle, Internet, le DNS, puis une page web"))
                }
            }
        }
        .task {
            model.refreshNetwork()
        }
    }

    // MARK: Données

    private var onboarding: DashboardSteps {
        DashboardSteps(
            discoveryDone: AppSettings.discoveryDone || app.lanDiscovery.hostCount > 0,
            monitoringDone: !app.monitoring.rows.isEmpty,
            boxDone: app.usage.isConnected
        )
    }

    private var runningTasks: [RunningTask] {
        var tasks: [RunningTask] = []
        if app.lanDiscovery.isRunning {
            tasks.append(RunningTask(id: .lanDiscovery, detail: app.lanDiscovery.rangeText) { app.lanDiscovery.cancel() })
        }
        if app.portScanner.isRunning {
            tasks.append(RunningTask(id: .portScanner, detail: app.portScanner.scannedHost) { app.portScanner.cancel() })
        }
        if app.ping.isRunning {
            tasks.append(RunningTask(id: .ping, detail: app.ping.host) { app.ping.cancel() })
        }
        if app.traceroute.isRunning {
            tasks.append(RunningTask(id: .traceroute, detail: app.traceroute.host) { app.traceroute.cancel() })
        }
        if app.automation.isRunning {
            tasks.append(RunningTask(id: .automation, detail: app.automation.runningTaskName) { app.automation.cancel() })
        }
        return tasks
    }

    /// Dernières cibles des diagnostics de la session, sans doublon, la plus récente d'abord.
    private var recentTargets: [String] {
        let entries = app.ping.history + app.traceroute.history + app.dns.history + app.http.history + app.tls.history
        var seen: Set<String> = []
        return entries
            .sorted { $0.date > $1.date }
            .map(\.target)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(3)
            .map { $0 }
    }

    // MARK: Blocs

    private var tiles: some View {
        let monitoring = app.monitoring
        let troubled = monitoring.offlineCount + monitoring.degradedCount
        return HStack(spacing: 10) {
            DashboardTile(
                label: L("Appareils découverts"),
                value: app.lanDiscovery.hostCount > 0 ? app.lanDiscovery.hostCount.formatted() : "—",
                detail: app.lanDiscovery.hostCount > 0 ? L("Dernière découverte de la session") : L("Aucune découverte depuis l'ouverture")
            ) {
                app.selection = .lanDiscovery
            }
            DashboardTile(
                label: L("Surveillés"),
                value: monitoring.activeCount.formatted(),
                detail: troubled > 0
                    ? L("\(monitoring.onlineCount) en ligne · \(troubled) à regarder")
                    : L("\(monitoring.onlineCount) en ligne"),
                tint: troubled > 0 ? .orange : nil
            ) {
                app.selection = .monitoring
            }
            DashboardTile(
                label: L("Alertes (24 h)"),
                value: monitoring.recentAlertCount.formatted(),
                detail: monitoring.recentAlertCount > 0 ? L("Voir les événements") : L("Aucune alerte."),
                tint: monitoring.recentAlertCount > 0 ? .red : nil
            ) {
                app.selection = .monitoring
            }
            DashboardTile(
                label: L("Consommation reçue"),
                value: app.usage.isConnected ? app.usage.totalReceived : "—",
                detail: app.usage.isConnected ? app.usage.period.title : L("Aucune box connectée")
            ) {
                app.selection = .usage
            }
        }
    }

    /// Surveillances hors ligne ou dégradées. Quand tout va bien, une seule ligne le dit.
    private var attention: some View {
        SectionCard(L("À regarder")) {
            let rows = app.monitoring.rows.filter { !$0.isPaused && ($0.statusKind == .failure || $0.statusKind == .warning) }
            if rows.isEmpty {
                StatusLabel(kind: .ok, text: L("Tout ce qui est surveillé répond."))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows.prefix(6)) { row in
                        HStack(spacing: 10) {
                            StatusLabel(kind: row.statusKind, text: row.statusText)
                            Text(row.name)
                                .lineLimit(1)
                            Text(row.target)
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if Self.isHost(row.target) {
                                Button(AppModule.ping.title) {
                                    app.open(.ping, target: row.target)
                                }
                                Button(AppModule.traceroute.title) {
                                    app.open(.traceroute, target: row.target)
                                }
                            }
                        }
                    }
                }
            }
            Button(L("Ouvrir la supervision")) {
                app.selection = .monitoring
            }
            .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity)
    }

    /// Vrai si la cible d'une surveillance est un hôte, qu'un ping ou un traceroute peut viser tel quel.
    private static func isHost(_ target: String) -> Bool {
        HostInput.isPlausible(target) && !target.contains("://")
    }

    private var running: some View {
        SectionCard(L("En cours")) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(runningTasks) { task in
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(task.id.title)
                            Text(task.detail)
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button(L("Annuler"), action: task.cancel)
                    }
                }
            }
        }
    }
}

/// Tuile de synthèse cliquable : elle mène à la fenêtre qui détaille son chiffre.
struct DashboardTile: View {
    let label: String
    let value: String
    let detail: String
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2.weight(.bold))
                    .fontDesign(.monospaced)
                    .foregroundStyle(tint ?? Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .glassCard(cornerRadius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .help(L("Ouvrir la fenêtre correspondante"))
    }
}
