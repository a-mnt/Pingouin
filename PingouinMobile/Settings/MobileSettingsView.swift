import SwiftUI
import UIKit
import PingouinCore

/// Réglages de l'application iOS. Chaque réglage agit aussitôt.
struct MobileSettingsView: View {
    @Environment(MobileAppState.self) private var state
    @AppStorage(AppSettings.Key.appearance) private var appearance = AppSettings.Default.appearance
    @AppStorage(AppSettings.Key.portScanTimeout) private var portScanTimeout = AppSettings.Default.portScanTimeout
    @AppStorage(AppSettings.Key.portScanConcurrency) private var portScanConcurrency = AppSettings.Default.portScanConcurrency
    @AppStorage(AppSettings.Key.pingCount) private var pingCount = AppSettings.Default.pingCount
    @AppStorage(AppSettings.Key.pingTimeout) private var pingTimeout = AppSettings.Default.pingTimeout
    @AppStorage(AppSettings.Key.tracerouteMaximumHops) private var maximumHops = AppSettings.Default.tracerouteMaximumHops
    @AppStorage(AppSettings.Key.lanResolveNames) private var resolveNames = true
    @AppStorage(AppSettings.Key.monitorInterval) private var monitorInterval = AppSettings.Default.monitorInterval
    @AppStorage(AppSettings.Key.monitorFailures) private var monitorFailures = AppSettings.Default.monitorFailures
    @AppStorage(AppSettings.Key.usagePollSeconds) private var pollSeconds = AppSettings.Default.usagePollSeconds
    @AppStorage(AppSettings.Key.usageKeptDays) private var keptDays = AppSettings.Default.usageKeptDays
    @AppStorage(AppSettings.Key.freeboxUsesHTTPS) private var freeboxUsesHTTPS = true
    @State private var isAskingToReset = false

    var body: some View {
        Form {
            general
            diagnostics
            ConnectionTestSettings()
            monitoring
            usage
            MobileSSHSettingsSection(model: state.ssh)
            Section {
                NavigationLink(L("Journal")) {
                    MobileLogView()
                }
                Button(L("Rétablir par défaut…"), role: .destructive) {
                    isAskingToReset = true
                }
            } footer: {
                Text(L("Les surveillances, le schéma et les tâches ne sont pas touchés."))
            }
            Section {
                LabeledContent(L("Version"), value: Self.version)
            } header: {
                Text(L("À propos"))
            } footer: {
                Text(L("Pingouin n'envoie aucune donnée d'usage. Les contrôles ne partent que quand vous les lancez."))
            }
        }
        .navigationTitle(L("Réglages"))
        .onChange(of: [portScanTimeout, portScanConcurrency, pingCount, pingTimeout, maximumHops]) {
            state.applyDiagnosticsSettings()
        }
        .onChange(of: resolveNames) {
            state.applyDiagnosticsSettings()
        }
        .onChange(of: [pollSeconds, keptDays]) {
            state.usage.applySettings()
        }
        .onChange(of: freeboxUsesHTTPS) {
            state.usage.applySettings()
        }
        .confirmationDialog(L("Rétablir tous les réglages par défaut ?"), isPresented: $isAskingToReset, titleVisibility: .visible) {
            Button(L("Rétablir"), role: .destructive) {
                AppSettings.resetAll()
                state.applyDiagnosticsSettings()
                state.usage.applySettings()
            }
            Button(L("Annuler"), role: .cancel) {}
        } message: {
            Text(L("Cette action ne peut pas être annulée."))
        }
    }

    private var general: some View {
        Section {
            Picker(L("Apparence"), selection: $appearance) {
                Text(L("Comme le système")).tag("system")
                Text(L("Claire")).tag("light")
                Text(L("Sombre")).tag("dark")
            }
            Button(L("Changer la langue de Pingouin…")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } footer: {
            Text(L("Ouvre la page de Pingouin dans les Réglages d'iOS. Français, anglais, espagnol, allemand et italien sont disponibles."))
        }
    }

    @ViewBuilder
    private var diagnostics: some View {
        Section {
            number(L("Délai par port (100 à 10 000 ms)"), $portScanTimeout)
            number(L("Connexions simultanées (1 à 128)"), $portScanConcurrency)
        } header: {
            Text(L("Scan de ports"))
        }
        Section {
            number(L("Ping : tentatives (1 à 1 000)"), $pingCount)
            number(L("Ping : délai d'attente (100 à 10 000 ms)"), $pingTimeout)
            number(L("Traceroute : sauts au plus (1 à 64)"), $maximumHops)
            Toggle(L("Découverte LAN : rechercher les noms d'hôtes"), isOn: $resolveNames)
        } header: {
            Text(L("Ping et traceroute"))
        } footer: {
            Text(L("Ces valeurs préremplissent les écrans des outils ; elles restent modifiables dans chaque écran. Une valeur hors bornes est ramenée à la borne la plus proche."))
        }
    }

    private func number(_ label: String, _ value: Binding<Int>) -> some View {
        LabeledContent(label) {
            TextField(label, value: value, format: .number.grouping(.never))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .font(.body.monospaced())
                .keyboardType(.numberPad)
                .frame(maxWidth: 90)
        }
    }

    private var monitoring: some View {
        Section {
            Picker(L("Intervalle proposé"), selection: $monitorInterval) {
                ForEach(MonitorDraft.intervals, id: \.seconds) { choice in
                    Text(choice.label).tag(choice.seconds)
                }
            }
            Stepper(
                L(count: monitorFailures, one: "Hors ligne après \(monitorFailures) échec de suite", other: "Hors ligne après \(monitorFailures) échecs de suite"),
                value: $monitorFailures,
                in: 1...10
            )
        } header: {
            Text(L("Supervision"))
        } footer: {
            Text(L("Ces valeurs sont proposées à la création ; les surveillances existantes ne changent pas."))
        }
    }

    private var usage: some View {
        Section {
            Picker(L("Fréquence des relevés"), selection: $pollSeconds) {
                Text(L("30 secondes")).tag(30)
                Text(L("1 minute")).tag(60)
                Text(L("5 minutes")).tag(300)
            }
            Picker(L("Conserver l'historique"), selection: $keptDays) {
                Text(L("7 jours")).tag(7)
                Text(L("30 jours")).tag(30)
                Text(L("90 jours")).tag(90)
            }
            Toggle(L("Chiffrer les échanges avec la Freebox (HTTPS)"), isOn: $freeboxUsesHTTPS)
        } header: {
            Text(L("Consommation"))
        } footer: {
            Text(L("Le certificat de la box est vérifié avec les autorités de certification de Free. Décoché, les échanges passent en HTTP simple : le jeton de session circule alors en clair sur le réseau local."))
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}

/// Journal de la session : ce que l'application a fait et ce qui a échoué, sans aucun secret.
struct MobileLogView: View {
    @State private var sharedFile: SharedFile?

    var body: some View {
        let log = AppLog.shared
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                Text(L("Journal de cette session. Il ne contient ni mot de passe ni jeton."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if log.entries.isEmpty {
                    Text(L("Rien à signaler pour l'instant."))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                ForEach(log.entries.reversed()) { entry in
                    Text(entry.line)
                        .font(.caption.monospaced())
                        .foregroundStyle(entry.level == .error ? Color.red : (entry.level == .warning ? Color.orange : Color.primary))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
        .background { PingouinBackdrop() }
        .navigationTitle(L("Journal"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(L("Copier")) {
                        Pasteboard.copy(log.exportText)
                    }
                    Button(L("Exporter…")) {
                        sharedFile = TemporaryFile.write(Data(log.exportText.utf8), named: "journal-pingouin.txt")
                    }
                    Divider()
                    Button(L("Effacer"), role: .destructive) {
                        log.clear()
                    }
                } label: {
                    Label(L("Actions sur le journal"), systemImage: "ellipsis.circle")
                }
                .disabled(log.entries.isEmpty)
            }
        }
        .sheet(item: $sharedFile) { file in
            MobileShareSheet(file: file)
        }
    }
}
