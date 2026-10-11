import SwiftUI
import PingouinCore

/// Accueil : le raccordement de l'appareil, le test de connexion, puis ce qui demande une action.
/// Rien ne part sur le réseau à l'ouverture : le raccordement est lu sur l'appareil.
struct MobileHomeView: View {
    @Environment(MobileAppState.self) private var state

    var body: some View {
        let model = state.dashboard
        MobilePage(L("Accueil")) {
            // Un fichier de données illisible est toujours signalé, jamais écrasé en silence.
            ForEach(StorageIssues.shared.issues) { issue in
                HStack(alignment: .top, spacing: 10) {
                    Label(issue.message, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    Spacer(minLength: 8)
                    Button(L("Fermer")) {
                        StorageIssues.shared.dismiss(issue.id)
                    }
                }
                .glassCardPadded(cornerRadius: 22)
            }
            MobileConnectionCard(model: model)
            if !steps.isComplete {
                MobileStartCard(steps: steps, network: model.network)
            }
            if steps.hasStarted {
                tiles
            }
            if !troubled.isEmpty {
                attention
            }
            MobileQuickLaunch(model: model, recentTargets: recentTargets)
            MobileFootnote(text: L("Rien ne part sur le réseau à l'ouverture : le raccordement est lu sur l'appareil, et chaque contrôle se lance par un bouton."))
        }
        .task {
            model.refreshNetwork()
        }
    }

    private var steps: DashboardSteps {
        DashboardSteps(
            discoveryDone: AppSettings.discoveryDone || state.lanDiscovery.hostCount > 0,
            monitoringDone: !state.monitoring.rows.isEmpty,
            boxDone: state.usage.isConnected
        )
    }

    /// Dernières cibles des diagnostics de la session, sans doublon, la plus récente d'abord.
    private var recentTargets: [String] {
        let entries = state.ping.history + state.traceroute.history + state.dns.history + state.http.history + state.tls.history
        var seen: Set<String> = []
        return entries
            .sorted { $0.date > $1.date }
            .map(\.target)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(3)
            .map { $0 }
    }

    private var troubled: [MonitorRow] {
        state.monitoring.rows.filter { !$0.isPaused && ($0.statusKind == .failure || $0.statusKind == .warning) }
    }

    private var tiles: some View {
        let monitoring = state.monitoring
        let count = monitoring.offlineCount + monitoring.degradedCount
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                MobileHomeTile(
                    label: L("Appareils découverts"),
                    value: state.lanDiscovery.hostCount > 0 ? state.lanDiscovery.hostCount.formatted() : "—",
                    detail: state.lanDiscovery.hostCount > 0 ? L("Dernière découverte de la session") : L("Aucune découverte depuis l'ouverture")
                ) {
                    state.show(.lanDiscovery)
                }
                MobileHomeTile(
                    label: L("Surveillés"),
                    value: monitoring.activeCount.formatted(),
                    detail: count > 0
                        ? L("\(monitoring.onlineCount) en ligne · \(count) à regarder")
                        : L("\(monitoring.onlineCount) en ligne"),
                    tint: count > 0 ? .orange : nil
                ) {
                    state.show(.monitoring)
                }
            }
            HStack(spacing: 10) {
                MobileHomeTile(
                    label: L("Alertes (24 h)"),
                    value: monitoring.recentAlertCount.formatted(),
                    detail: monitoring.recentAlertCount > 0 ? L("Voir les événements") : L("Aucune alerte."),
                    tint: monitoring.recentAlertCount > 0 ? .red : nil
                ) {
                    state.show(.monitoring)
                }
                MobileHomeTile(
                    label: L("Consommation reçue"),
                    value: state.usage.isConnected ? state.usage.totalReceived : "—",
                    detail: state.usage.isConnected ? state.usage.period.title : L("Aucune box connectée")
                ) {
                    state.show(.usage)
                }
            }
        }
    }

    /// Surveillances hors ligne ou dégradées, avec les outils pour creuser.
    private var attention: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("À regarder"))
                .font(.headline)
            ForEach(troubled.prefix(6)) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        StatusLabel(kind: row.statusKind, text: row.statusText)
                        Text(row.name)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 10) {
                        Text(row.target)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if HostInput.isPlausible(row.target), !row.target.contains("://") {
                            Button(AppModule.ping.title) {
                                state.open(.ping, target: row.target)
                            }
                            Button(AppModule.traceroute.title) {
                                state.open(.traceroute, target: row.target)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            Button(L("Ouvrir la supervision")) {
                state.show(.monitoring)
            }
        }
        .glassCardPadded(cornerRadius: 22)
    }
}

/// Tuile de synthèse de l'accueil : elle mène à l'écran qui détaille son chiffre.
struct MobileHomeTile: View {
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(value)
                    .font(.title2.weight(.bold))
                    .fontDesign(.monospaced)
                    .foregroundStyle(tint ?? Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
    }
}
