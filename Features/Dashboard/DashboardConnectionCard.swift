import SwiftUI
import PingouinCore

/// Raccordement de ce Mac et chaîne du test de connexion : Ce Mac → Box → Internet → DNS → Web.
struct DashboardConnectionCard: View {
    @Environment(AppState.self) private var app
    let model: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("État de la connexion"))
                    .font(.headline)
                Spacer()
                Text(testedText)
                    .foregroundStyle(.secondary)
            }
            network
            HStack(alignment: .top, spacing: 6) {
                hop(title: L("Ce Mac"), detail: model.network?.interfaceName ?? "—") {
                    if model.network != nil {
                        StatusLabel(kind: .ok, text: L("Raccordé"))
                    } else {
                        StatusLabel(kind: .failure, text: L("Aucun réseau"))
                    }
                }
                ForEach(ConnectionStep.allCases) { step in
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 22)
                        .accessibilityHidden(true)
                    hop(title: title(of: step), detail: detail(of: step)) {
                        stateView(model.state(of: step))
                    }
                }
            }
            if let failed = model.firstFailure {
                failure(failed)
            } else if model.testedAt == nil, !model.isTesting {
                Text(L("« Tester ma connexion » fait quatre contrôles en quelques secondes. Le premier maillon en échec est désigné, avec l'outil pour creuser."))
                    .foregroundStyle(.secondary)
            }
        }
        .glassCardPadded()
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
            HStack(alignment: .top, spacing: 26) {
                fact(L("Interface"), [network.displayName, network.interfaceName].compactMap { $0 }.joined(separator: " · "))
                fact(L("Adresse"), network.address.isEmpty ? "—" : network.address)
                fact(L("Passerelle"), network.gateway)
                fact(L("Serveurs DNS"), network.dnsServers.isEmpty ? "—" : network.dnsServers.prefix(3).joined(separator: " · "))
                fact(L("IPv6"), network.ipv6Addresses.first ?? L("Aucune adresse"))
                Spacer(minLength: 0)
                Button {
                    model.refreshNetwork()
                } label: {
                    Label(L("Relire le raccordement"), systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help(L("Relire l'interface, la passerelle et les serveurs DNS de ce Mac"))
            }
        } else if model.networkWasRead {
            HStack {
                Label(L("Ce Mac n'a pas de route vers Internet : aucune interface n'est raccordée à un réseau."), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Spacer()
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
                .font(.body.monospaced())
                .lineLimit(1)
                .textSelection(.enabled)
        }
    }

    // MARK: Chaîne

    private func hop<Status: View>(title: String, detail: String, @ViewBuilder status: () -> Status) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .fontWeight(.semibold)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            status()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
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
        case .gateway: model.network?.gateway ?? "—"
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
                .foregroundStyle(.secondary)
        case .running:
            ProgressView()
                .controlSize(.small)
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
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Label(L("Premier maillon en échec : \(title(of: step)). \(reason)"), systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .lineLimit(2)
            Spacer(minLength: 0)
            switch step {
            case .gateway:
                Button(L("Creuser avec Ping")) {
                    app.open(.ping, target: model.network?.gateway ?? "")
                }
                .disabled(model.network == nil)
            case .internet:
                Button(L("Creuser avec Traceroute")) {
                    app.open(.traceroute, target: model.pingTarget)
                }
            case .dns:
                Button(L("Creuser avec DNS")) {
                    app.dns.name = model.webName
                    app.dns.type = .a
                    app.selection = .dns
                    app.dns.start()
                }
            case .web:
                Button(L("Creuser avec HTTP")) {
                    app.open(.http, target: "https://\(model.webName)/")
                }
            }
        }
    }
}
