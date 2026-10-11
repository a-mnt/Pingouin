import SwiftUI
import PingouinCore

/// Raccordement de l'appareil et chaîne du test de connexion : Cet appareil → Box → Internet → DNS → Web.
struct MobileConnectionCard: View {
    @Environment(MobileAppState.self) private var state
    let model: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("État de la connexion"))
                    .font(.headline)
                Spacer(minLength: 8)
                Text(testedText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            network
            VStack(spacing: 0) {
                hop(title: L("Cet appareil"), detail: model.network?.interfaceName ?? "—") {
                    if model.network != nil {
                        StatusLabel(kind: .ok, text: L("Raccordé"))
                    } else {
                        StatusLabel(kind: .failure, text: L("Aucun réseau"))
                    }
                }
                ForEach(ConnectionStep.allCases) { step in
                    Divider()
                    hop(title: title(of: step), detail: detail(of: step)) {
                        stateView(model.state(of: step))
                    }
                }
            }
            if let failed = model.firstFailure {
                failure(failed)
            }
            if model.isTesting {
                Button(role: .cancel) {
                    model.cancelTest()
                } label: {
                    Text(L("Arrêter"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                Button {
                    model.runTest()
                } label: {
                    Text(L("Tester ma connexion"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            if model.testedAt == nil, !model.isTesting {
                Text(L("« Tester ma connexion » fait quatre contrôles en quelques secondes. Le premier maillon en échec est désigné, avec l'outil pour creuser."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .glassCardPadded(cornerRadius: 22)
    }

    private var testedText: String {
        if model.isTesting { return L("Test en cours…") }
        if let date = model.testedAt {
            return L("Testé à \(date.formatted(date: .omitted, time: .shortened))")
        }
        return L("Aucun test depuis l'ouverture")
    }

    // MARK: Raccordement

    @ViewBuilder
    private var network: some View {
        if let network = model.network {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    fact(L("Interface"), [network.displayName, network.interfaceName].compactMap { $0 }.joined(separator: " · "))
                    fact(L("Adresse"), network.address.isEmpty ? "—" : network.address)
                }
                HStack(alignment: .top, spacing: 12) {
                    fact(L("Passerelle"), network.gateway.isEmpty ? "—" : network.gateway)
                    fact(L("Serveurs DNS"), network.dnsServers.isEmpty ? "—" : network.dnsServers.prefix(2).joined(separator: " · "))
                }
                fact(L("IPv6"), network.ipv6Addresses.first ?? L("Aucune adresse"))
            }
        } else if model.networkWasRead {
            HStack {
                Label(L("Cet appareil n'est raccordé à aucun réseau Wi-Fi. En données cellulaires, le test de connexion reste possible, sans passerelle."), systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                Spacer(minLength: 0)
                Button(L("Relire")) {
                    model.refreshNetwork()
                }
            }
        } else {
            Text(L("Lecture du raccordement…"))
                .foregroundStyle(.secondary)
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospaced())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Chaîne

    private func hop<Status: View>(title: String, detail: String, @ViewBuilder status: () -> Status) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            status()
                .lineLimit(1)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func title(of step: ConnectionStep) -> String {
        switch step {
        case .gateway: L("Box")
        case .internet: L("Internet")
        case .dns: "DNS"
        case .web: L("Web")
        }
    }

    /// Ce que le maillon interroge, tel qu'il sera ou a été interrogé.
    private func detail(of step: ConnectionStep) -> String {
        switch step {
        case .gateway: model.network.flatMap { $0.gateway.isEmpty ? nil : $0.gateway } ?? "—"
        case .internet: model.pingTarget
        case .dns: model.webName
        case .web: "https://\(model.webName)"
        }
    }

    @ViewBuilder
    private func stateView(_ state: ConnectionStepState) -> some View {
        switch state {
        case .untested:
            Text(L("Pas encore testé"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .running:
            ProgressView()
        case .ok(let milliseconds):
            StatusLabel(kind: .ok, text: milliseconds.map { NumberInput.milliseconds($0) } ?? L("Répond"))
        case .failed:
            StatusLabel(kind: .failure, text: L("Échec"))
        }
    }

    // MARK: Échec

    /// Premier maillon en échec : ce qu'il a répondu, et l'outil qui permet de creuser.
    private func failure(_ step: ConnectionStep) -> some View {
        var reason = ""
        if case .failed(let detail) = model.state(of: step) {
            reason = detail
        }
        let gateway = model.network?.gateway ?? ""
        return VStack(alignment: .leading, spacing: 8) {
            Label(L("Premier maillon en échec : \(title(of: step)). \(reason)"), systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(.red)
            switch step {
            case .gateway:
                Button(L("Creuser avec Ping")) {
                    state.open(.ping, target: gateway)
                }
                .disabled(gateway.isEmpty)
            case .internet:
                Button(L("Creuser avec Traceroute")) {
                    state.open(.traceroute, target: model.pingTarget)
                }
            case .dns:
                Button(L("Creuser avec DNS")) {
                    state.resolve(model.webName)
                }
            case .web:
                Button(L("Creuser avec HTTP")) {
                    state.open(.http, target: "https://\(model.webName)/")
                }
            }
        }
        .buttonStyle(.bordered)
    }
}
