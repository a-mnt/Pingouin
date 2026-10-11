import SwiftUI
import PingouinCore

/// « Pour commencer » : trois étapes, chacune avec son bouton. Le bloc disparaît quand elles sont faites.
struct DashboardStartCard: View {
    @Environment(AppState.self) private var app
    let steps: DashboardSteps
    let network: LocalNetworkInfo?
    @State private var isChoosingMonitors = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Pour commencer"))
                    .font(.headline)
                Spacer()
                Text(L("\(steps.doneCount) étape(s) faite(s) sur 3"))
                    .foregroundStyle(.secondary)
            }
            step(1, done: steps.discoveryDone, title: L("Découvrir les appareils de mon réseau"), detail: discoveryDetail) {
                Button(L("Lancer la découverte")) {
                    app.selection = .lanDiscovery
                    app.lanDiscovery.refreshInterfaces()
                    app.lanDiscovery.requestScan()
                }
                .buttonStyle(.borderedProminent)
            }
            Divider()
            step(
                2,
                done: steps.monitoringDone,
                title: L("Surveiller mes appareils importants"),
                detail: L("Après la découverte : choisir la box, le NAS, l'imprimante… Pingouin prévient quand l'un d'eux ne répond plus.")
            ) {
                Button(L("Choisir…")) {
                    isChoosingMonitors = true
                }
                .disabled(app.lanDiscovery.discoveredHosts.isEmpty)
                .help(app.lanDiscovery.discoveredHosts.isEmpty ? L("Lancer d'abord une découverte dans cette session") : L("Choisir parmi les appareils découverts"))
            }
            Divider()
            step(
                3,
                done: steps.boxDone,
                title: L("Connecter ma box"),
                detail: L("Pour la consommation par appareil et les liens de la topologie. Freebox prise en charge.")
            ) {
                Button(L("Connecter…")) {
                    app.selection = .usage
                }
            }
        }
        .glassCardPadded()
        .sheet(isPresented: $isChoosingMonitors) {
            DashboardMonitorPicker()
        }
    }

    private var discoveryDetail: String {
        guard let network, !network.subnet.isEmpty else {
            return L("Balayage du réseau raccordé à ce Mac.")
        }
        return L("Balayage de \(network.subnet), soit \(network.hostCount) adresses.")
    }

    private func step<Action: View>(_ number: Int, done: Bool, title: String, detail: String, @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                .font(.title2)
                .foregroundStyle(done ? Color.green : Color.accentColor)
                .accessibilityLabel(done ? L("Étape \(number), faite") : L("Étape \(number), à faire"))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .fontWeight(.semibold)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if done {
                Text(L("Fait"))
                    .foregroundStyle(.secondary)
            } else {
                action()
            }
        }
        .padding(.vertical, 8)
    }
}

/// Choix, parmi les appareils de la dernière découverte, de ceux à surveiller par ping.
struct DashboardMonitorPicker: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<String> = []

    var body: some View {
        let hosts = app.lanDiscovery.discoveredHosts
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Appareils à surveiller"))
                .font(.title3.weight(.bold))
            Text(L("Chaque appareil coché reçoit un ping à intervalle régulier. L'intervalle et le seuil d'alerte se règlent ensuite dans Supervision."))
                .foregroundStyle(.secondary)
                .lineLimit(3)
            List(hosts, id: \.address, selection: $chosen) { host in
                HStack {
                    Text(host.name.isEmpty ? L("Sans nom") : host.name)
                    Spacer()
                    Text(host.address)
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 260)
            HStack {
                Text(L("\(chosen.count) sélectionné(s) · clic avec ⌘ pour en choisir plusieurs"))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L("Annuler"), role: .cancel) {
                    dismiss()
                }
                Button(L("Surveiller")) {
                    for host in hosts where chosen.contains(host.address) {
                        app.monitoring.addPingMonitor(name: host.name, host: host.address)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(chosen.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

/// Champ de saisie et boutons pour lancer aussitôt un outil sur un hôte.
struct DashboardQuickLaunch: View {
    @Environment(AppState.self) private var app
    @Bindable var model: DashboardViewModel
    let recentTargets: [String]

    private static let tools: [AppModule] = [.ping, .traceroute, .dns, .portScanner, .http, .tls]

    var body: some View {
        SectionCard(L("Lancer un outil sur…")) {
            TextField(L("Hôte, adresse IP ou URL"), text: $model.quickTarget, prompt: Text(L("Hôte, adresse IP ou URL")))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .autocorrectionDisabled()
                .onSubmit {
                    launch(.ping)
                }
            HStack(spacing: 6) {
                ForEach(Self.tools) { tool in
                    Button(tool.title) {
                        launch(tool)
                    }
                    .disabled(target.isEmpty)
                }
            }
            if !suggestions.isEmpty {
                HStack(spacing: 8) {
                    Text(recentTargets.isEmpty ? L("Suggestions :") : L("Récents :"))
                        .foregroundStyle(.secondary)
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) {
                            model.quickTarget = suggestion
                        }
                        .buttonStyle(.link)
                        .lineLimit(1)
                    }
                }
            }
        }
    }

    private var target: String {
        model.quickTarget.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Les cibles récentes de la session ; à défaut, la passerelle et la cible du test Internet.
    private var suggestions: [String] {
        if !recentTargets.isEmpty { return recentTargets }
        return [model.network?.gateway, model.pingTarget].compactMap { $0 }
    }

    private func launch(_ tool: AppModule) {
        guard !target.isEmpty else { return }
        let host = Self.host(in: target)
        switch tool {
        case .http:
            app.open(.http, target: target.contains("://") ? target : "https://\(target)/")
        case .dns:
            // Un nom se résout ; une adresse se cherche à l'envers.
            if HostAddress(host) != nil {
                app.open(.dns, target: host)
            } else {
                app.dns.name = host
                app.dns.type = .a
                app.selection = .dns
                app.dns.start()
            }
        default:
            app.open(tool, target: host)
        }
    }

    /// L'hôte d'une saisie : celui de l'URL si c'en est une, sinon la saisie telle quelle.
    private static func host(in text: String) -> String {
        guard text.contains("://"), let host = URLComponents(string: text)?.host, !host.isEmpty else { return text }
        return host
    }
}
