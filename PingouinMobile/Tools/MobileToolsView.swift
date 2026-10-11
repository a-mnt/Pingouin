import SwiftUI
import PingouinCore

/// Liste de modules d'un onglet. Seuls les modules réellement utilisables y figurent.
struct MobileModuleList: View {
    @Environment(MobileAppState.self) private var state
    let title: String
    let modules: [AppModule]
    let footnote: String

    var body: some View {
        MobilePage(title) {
            ForEach(modules) { module in
                NavigationLink(value: module) {
                    MobileToolRow(
                        systemImage: module.systemImage,
                        title: module.title,
                        detail: Self.detail(of: module),
                        isRunning: isRunning(module)
                    )
                }
                .buttonStyle(.plain)
            }
            MobileFootnote(text: footnote)
        }
    }

    private func isRunning(_ module: AppModule) -> Bool {
        switch module {
        case .ping: state.ping.isRunning
        case .traceroute: state.traceroute.isRunning
        case .dns: state.dns.isRunning
        case .portScanner: state.portScanner.isRunning
        case .http: state.http.isRunning
        case .tls: state.tls.isRunning
        case .lanDiscovery: state.lanDiscovery.isRunning
        case .automation: state.automation.isRunning
        default: false
        }
    }

    private static func detail(of module: AppModule) -> String {
        switch module {
        case .ping: L("Temps de réponse et pertes, en IPv4 et en IPv6")
        case .traceroute: L("Le chemin jusqu'à une destination, saut par saut")
        case .dns: L("Enregistrements d'un nom, recherche inverse, comparaison de serveurs")
        case .portScanner: L("Ports TCP ouverts, fermés ou sans réponse sur un hôte")
        case .http: L("Code, redirections, en-têtes et décomposition du temps")
        case .tls: L("Certificat, chaîne de confiance et date d'expiration")
        case .ipCalculator: L("Réseau, masque, plage utilisable et découpage")
        case .lanDiscovery: L("Les appareils du réseau Wi-Fi qui répondent au ping")
        case .monitoring: L("Contrôles réguliers et alertes, application ouverte")
        case .usage: L("Trafic par appareil, relevé sur la box")
        case .topology: L("Schéma du réseau : appareils et liens")
        case .automation: L("Suites de contrôles à lancer d'un geste")
        case .reports: L("Les résultats de la session, en PDF, CSV ou JSON")
        case .dashboard, .ssh: ""
        }
    }
}

/// Ligne d'un outil : pictogramme, nom, description, et un repère quand l'outil tourne.
struct MobileToolRow: View {
    let systemImage: String
    let title: String
    let detail: String
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            if isRunning {
                ProgressView()
                    .accessibilityLabel(L("En cours"))
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .glassCard(cornerRadius: 22)
        .accessibilityElement(children: .combine)
    }
}
