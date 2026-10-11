import SwiftUI
import PingouinCore

/// Réglages des cibles du test de connexion du tableau de bord.
struct ConnectionTestSettings: View {
    @AppStorage(AppSettings.Key.connectionPingTarget) private var pingTarget = AppSettings.Default.connectionPingTarget
    @AppStorage(AppSettings.Key.connectionWebName) private var webName = AppSettings.Default.connectionWebName

    var body: some View {
        Section {
            TextField(L("Adresse pinguée pour Internet"), text: $pingTarget, prompt: Text(verbatim: AppSettings.Default.connectionPingTarget))
                .font(.body.monospaced())
                .autocorrectionDisabled()
                .plainHostEntry()
            TextField(L("Nom résolu puis ouvert en HTTPS"), text: $webName, prompt: Text(verbatim: AppSettings.Default.connectionWebName))
                .font(.body.monospaced())
                .autocorrectionDisabled()
                .plainHostEntry()
            Button(L("Revenir aux cibles d'origine")) {
                pingTarget = AppSettings.Default.connectionPingTarget
                webName = AppSettings.Default.connectionWebName
            }
            .disabled(pingTarget == AppSettings.Default.connectionPingTarget && webName == AppSettings.Default.connectionWebName)
        } header: {
            Text(L("Test de connexion du tableau de bord"))
        } footer: {
            Text(L("« Tester ma connexion » pingue la passerelle, puis cette adresse, résout ce nom et ouvre sa page en HTTPS. Une saisie vide ou invalide est remplacée par la cible d'origine."))
                .foregroundStyle(.secondary)
        }
    }
}

private extension View {
    /// Sur iOS, le clavier ne met pas de majuscule à un nom d'hôte. Sans effet sur le Mac.
    @ViewBuilder
    func plainHostEntry() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
            .keyboardType(.URL)
        #else
        self
        #endif
    }
}
