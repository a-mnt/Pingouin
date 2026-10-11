import SwiftUI
import PingouinCore

/// « Pour commencer » : trois étapes, chacune avec son bouton. Le bloc disparaît quand elles sont faites.
struct MobileStartCard: View {
    @Environment(MobileAppState.self) private var state
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
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            step(1, done: steps.discoveryDone, title: L("Découvrir les appareils de mon réseau"), detail: discoveryDetail) {
                Button(L("Lancer la découverte")) {
                    state.show(.lanDiscovery)
                    state.lanDiscovery.refreshInterfaces()
                    state.lanDiscovery.requestScan()
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
                .buttonStyle(.bordered)
                .disabled(state.lanDiscovery.discoveredHosts.isEmpty)
            }
            Divider()
            step(
                3,
                done: steps.boxDone,
                title: L("Connecter ma box"),
                detail: L("Pour la consommation par appareil et les liens de la topologie. Freebox prise en charge.")
            ) {
                Button(L("Connecter…")) {
                    state.show(.usage)
                }
                .buttonStyle(.bordered)
            }
        }
        .glassCardPadded(cornerRadius: 22)
        .sheet(isPresented: $isChoosingMonitors) {
            MobileMonitorPicker()
        }
    }

    private var discoveryDetail: String {
        guard let network, !network.subnet.isEmpty else {
            return L("Balayage du réseau Wi-Fi raccordé à cet appareil.")
        }
        return L("Balayage de \(network.subnet), soit \(network.hostCount) adresses.")
    }

    private func step<Action: View>(_ number: Int, done: Bool, title: String, detail: String, @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                .font(.title2)
                .foregroundStyle(done ? Color.green : Color.accentColor)
                .accessibilityLabel(done ? L("Étape \(number), faite") : L("Étape \(number), à faire"))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if done {
                    Text(L("Fait"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    action()
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }
}

/// Choix, parmi les appareils de la dernière découverte, de ceux à surveiller par ping.
struct MobileMonitorPicker: View {
    @Environment(MobileAppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<String> = []

    var body: some View {
        let hosts = state.lanDiscovery.discoveredHosts
        NavigationStack {
            List {
                Section {
                    ForEach(hosts, id: \.address) { host in
                        Button {
                            if chosen.contains(host.address) {
                                chosen.remove(host.address)
                            } else {
                                chosen.insert(host.address)
                            }
                        } label: {
                            HStack {
                                Image(systemName: chosen.contains(host.address) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(chosen.contains(host.address) ? Color.accentColor : Color.secondary)
                                    .accessibilityHidden(true)
                                Text(host.name.isEmpty ? L("Sans nom") : host.name)
                                    .foregroundStyle(Color.primary)
                                Spacer()
                                Text(host.address)
                                    .font(.callout.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityAddTraits(chosen.contains(host.address) ? .isSelected : [])
                    }
                } footer: {
                    Text(L("Chaque appareil coché reçoit un ping à intervalle régulier. L'intervalle et le seuil d'alerte se règlent ensuite dans Supervision."))
                }
            }
            .navigationTitle(L("Appareils à surveiller"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Annuler")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Surveiller")) {
                        for host in hosts where chosen.contains(host.address) {
                            state.monitoring.addPingMonitor(name: host.name, host: host.address)
                        }
                        dismiss()
                    }
                    .disabled(chosen.isEmpty)
                }
            }
        }
    }
}

/// Champ de saisie et boutons pour lancer aussitôt un outil sur un hôte.
struct MobileQuickLaunch: View {
    @Environment(MobileAppState.self) private var state
    @Bindable var model: DashboardViewModel
    let recentTargets: [String]

    private static let tools: [AppModule] = [.ping, .traceroute, .dns, .portScanner, .http, .tls]
    private static let columns = [GridItem(.adaptive(minimum: 96), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Lancer un outil sur…"))
                .font(.headline)
            TextField(L("Hôte, adresse IP ou URL"), text: $model.quickTarget, prompt: Text(L("Hôte, adresse IP ou URL")))
                .hostEntry()
                .submitLabel(.go)
                .onSubmit {
                    launch(.ping)
                }
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 8) {
                ForEach(Self.tools) { tool in
                    Button {
                        launch(tool)
                    } label: {
                        Text(tool.title)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(target.isEmpty)
                }
            }
            if !suggestions.isEmpty {
                Text(recentTargets.isEmpty ? L("Suggestions :") : L("Récents :"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(suggestion) {
                        model.quickTarget = suggestion
                    }
                    .font(.callout.monospaced())
                    .lineLimit(1)
                }
            }
        }
        .glassCardPadded(cornerRadius: 22)
    }

    private var target: String {
        model.quickTarget.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Les cibles récentes de la session ; à défaut, la passerelle et la cible du test Internet.
    private var suggestions: [String] {
        if !recentTargets.isEmpty { return recentTargets }
        let gateway = model.network.flatMap { $0.gateway.isEmpty ? nil : $0.gateway }
        return [gateway, model.pingTarget].compactMap { $0 }
    }

    private func launch(_ tool: AppModule) {
        guard !target.isEmpty else { return }
        let host = Self.host(in: target)
        switch tool {
        case .http:
            state.open(.http, target: target.contains("://") ? target : "https://\(target)/")
        case .dns:
            // Un nom se résout ; une adresse se cherche à l'envers.
            if HostAddress(host) != nil {
                state.open(.dns, target: host)
            } else {
                state.resolve(host)
            }
        default:
            state.open(tool, target: host)
        }
    }

    /// L'hôte d'une saisie : celui de l'URL si c'en est une, sinon la saisie telle quelle.
    private static func host(in text: String) -> String {
        guard text.contains("://"), let host = URLComponents(string: text)?.host, !host.isEmpty else { return text }
        return host
    }
}
