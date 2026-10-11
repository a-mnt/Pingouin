import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PingouinCore

/// Fenêtre de réglages (menu Pingouin > Réglages…, ⌘,). Chaque réglage agit aussitôt.
struct SettingsView: View {
    @AppStorage(AppSettings.Key.appearance) private var appearance = AppSettings.Default.appearance

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label(L("Général"), systemImage: "gearshape") }
            DiagnosticsSettings()
                .tabItem { Label(L("Diagnostics"), systemImage: "waveform.path.ecg") }
            SSHSettings()
                .tabItem { Label("SSH", systemImage: "terminal") }
            MonitoringSettings()
                .tabItem { Label(L("Supervision"), systemImage: "eye") }
            UsageSettings()
                .tabItem { Label(L("Consommation"), systemImage: "chart.bar") }
            DataSettings()
                .tabItem { Label(L("Données"), systemImage: "externaldrive") }
            LogSettings()
                .tabItem { Label(L("Journal"), systemImage: "list.bullet.rectangle") }
        }
        .frame(width: 600, height: 430)
        .preferredColorScheme(AppSettings.colorScheme(for: appearance))
    }
}

// MARK: Général

private struct GeneralSettings: View {
    @AppStorage(AppSettings.Key.startModule) private var startModule = AppSettings.Default.startModule
    @AppStorage(AppSettings.Key.appearance) private var appearance = AppSettings.Default.appearance
    @AppStorage(AppSettings.Key.showsSidebarLogo) private var showsSidebarLogo = true
    @AppStorage(AppSettings.Key.language) private var language = AppSettings.Default.language
    /// Vrai dès que la langue a été changée dans cette session : elle ne s'applique qu'au prochain lancement.
    @State private var languageChanged = false
    @State private var isOfferingRestart = false
    @State private var restartFailed = false

    var body: some View {
        Form {
            Picker(L("Langue"), selection: $language) {
                Text(L("Celle du système")).tag(AppSettings.Default.language)
                Divider()
                ForEach(AppSettings.languages, id: \.code) { item in
                    Text(verbatim: item.name).tag(item.code)
                }
            }
            .onChange(of: language) { _, choice in
                AppSettings.applyLanguage(choice)
                languageChanged = true
                restartFailed = false
                isOfferingRestart = true
            }
            if restartFailed {
                Text(L("Pingouin n'a pas pu redémarrer seul : le quitter puis le rouvrir pour changer de langue."))
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else if languageChanged {
                Text(L("Le changement de langue prend effet au prochain lancement de Pingouin."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Picker(L("Fenêtre affichée à l'ouverture"), selection: $startModule) {
                Text(L("Dernière fenêtre utilisée")).tag(AppSettings.Default.lastModuleChoice)
                Divider()
                ForEach(AppModule.allCases) { module in
                    Text(module.title).tag(module.rawValue)
                }
            }
            Picker(L("Apparence"), selection: $appearance) {
                Text(L("Comme le système")).tag("system")
                Text(L("Claire")).tag("light")
                Text(L("Sombre")).tag("dark")
            }
            Toggle(L("Afficher le logo dans la barre latérale"), isOn: $showsSidebarLogo)
        }
        .formStyle(.grouped)
        .alert(L("Redémarrer Pingouin pour changer de langue ?"), isPresented: $isOfferingRestart) {
            Button(L("Redémarrer maintenant")) {
                restartFailed = !AppRelaunch.relaunch()
            }
            Button(L("Plus tard"), role: .cancel) {}
        } message: {
            Text(L("La langue s'applique au lancement. Redémarrer met fin aux sessions SSH ouvertes, aux transferts de fichiers et aux opérations en cours ; les données enregistrées sont conservées."))
        }
    }
}

// MARK: Diagnostics

private struct DiagnosticsSettings: View {
    @Environment(AppState.self) private var app
    @AppStorage(AppSettings.Key.portScanTimeout) private var portScanTimeout = AppSettings.Default.portScanTimeout
    @AppStorage(AppSettings.Key.portScanConcurrency) private var portScanConcurrency = AppSettings.Default.portScanConcurrency
    @AppStorage(AppSettings.Key.pingCount) private var pingCount = AppSettings.Default.pingCount
    @AppStorage(AppSettings.Key.pingTimeout) private var pingTimeout = AppSettings.Default.pingTimeout
    @AppStorage(AppSettings.Key.tracerouteMaximumHops) private var maximumHops = AppSettings.Default.tracerouteMaximumHops
    @AppStorage(AppSettings.Key.lanResolveNames) private var resolveNames = true

    var body: some View {
        Form {
            Section(L("Scan de ports")) {
                TextField(L("Délai par port (100 à 10 000 ms)"), value: $portScanTimeout, format: .number.grouping(.never))
                TextField(L("Connexions simultanées (1 à 128)"), value: $portScanConcurrency, format: .number.grouping(.never))
            }
            Section(L("Ping et traceroute")) {
                TextField(L("Ping : tentatives (1 à 1 000)"), value: $pingCount, format: .number.grouping(.never))
                TextField(L("Ping : délai d'attente (100 à 10 000 ms)"), value: $pingTimeout, format: .number.grouping(.never))
                TextField(L("Traceroute : sauts au plus (1 à 64)"), value: $maximumHops, format: .number.grouping(.never))
            }
            Section {
                Toggle(L("Découverte LAN : rechercher les noms d'hôtes"), isOn: $resolveNames)
            } footer: {
                Text(L("Ces valeurs préremplissent les fenêtres des outils ; elles restent modifiables dans chaque fenêtre. Une valeur hors bornes est ramenée à la borne la plus proche."))
                    .foregroundStyle(.secondary)
            }
            ConnectionTestSettings()
        }
        .formStyle(.grouped)
        .onChange(of: [portScanTimeout, portScanConcurrency, pingCount, pingTimeout, maximumHops]) {
            app.applyDiagnosticsSettings()
        }
        .onChange(of: resolveNames) {
            app.applyDiagnosticsSettings()
        }
    }
}

// MARK: SSH

private struct SSHSettings: View {
    @Environment(AppState.self) private var app
    @AppStorage(AppSettings.Key.sshAutoPassword) private var autoPassword = true

    var body: some View {
        let ssh = app.ssh
        Form {
            Picker(L("Thème par défaut"), selection: Binding(
                get: { ssh.defaultThemeID },
                set: { ssh.setDefaultTheme($0) }
            )) {
                ForEach(TerminalTheme.all) { theme in
                    Text(theme.name).tag(theme.id)
                }
            }
            Stepper(
                L("Taille du texte : \(Int(ssh.fontSize)) points"),
                value: Binding(get: { ssh.fontSize }, set: { ssh.setFontSize($0) }),
                in: 9...24
            )
            Section {
                Toggle(L("Saisir automatiquement le mot de passe enregistré"), isOn: $autoPassword)
            } footer: {
                Text(L("Le mot de passe reste dans le Trousseau. Décoché, il n'est jamais envoyé au terminal : il faut le saisir à chaque connexion."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Supervision

private struct MonitoringSettings: View {
    @Environment(AppState.self) private var app
    @AppStorage(AppSettings.Key.monitorInterval) private var interval = AppSettings.Default.monitorInterval
    @AppStorage(AppSettings.Key.monitorFailures) private var failures = AppSettings.Default.monitorFailures

    var body: some View {
        let monitoring = app.monitoring
        Form {
            Section {
                Picker(L("Intervalle proposé"), selection: $interval) {
                    ForEach(MonitorDraft.intervals, id: \.seconds) { choice in
                        Text(choice.label).tag(choice.seconds)
                    }
                }
                Stepper(
                    L(count: failures, one: "Hors ligne après \(failures) échec de suite", other: "Hors ligne après \(failures) échecs de suite"),
                    value: $failures,
                    in: 1...10
                )
            } header: {
                Text(L("Nouvelle surveillance"))
            } footer: {
                Text(L("Ces valeurs sont proposées à la création ; les surveillances existantes ne changent pas."))
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(L("Notifications macOS"), isOn: Binding(
                    get: { monitoring.notificationsEnabled },
                    set: { monitoring.setNotifications($0) }
                ))
                if let message = monitoring.notificationMessage {
                    Text(message)
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text(L("Une notification à chaque panne et à chaque retour en ligne."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Consommation

private struct UsageSettings: View {
    @Environment(AppState.self) private var app
    @AppStorage(AppSettings.Key.usagePollSeconds) private var pollSeconds = AppSettings.Default.usagePollSeconds
    @AppStorage(AppSettings.Key.usageKeptDays) private var keptDays = AppSettings.Default.usageKeptDays
    @AppStorage(AppSettings.Key.freeboxUsesHTTPS) private var freeboxUsesHTTPS = true

    var body: some View {
        Form {
            Picker(L("Fréquence des relevés"), selection: $pollSeconds) {
                Text(L("30 secondes")).tag(30)
                Text(L("1 minute")).tag(60)
                Text(L("5 minutes")).tag(300)
            }
            Section {
                Picker(L("Conserver l'historique"), selection: $keptDays) {
                    Text(L("7 jours")).tag(7)
                    Text(L("30 jours")).tag(30)
                    Text(L("90 jours")).tag(90)
                }
            } footer: {
                Text(L("Réduire la durée efface les jours les plus anciens au prochain relevé."))
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(L("Chiffrer les échanges avec la Freebox (HTTPS)"), isOn: $freeboxUsesHTTPS)
            } footer: {
                Text(L("Le certificat de la box est vérifié avec les autorités de certification de Free. Décoché, les échanges passent en HTTP simple : le jeton de session circule alors en clair sur le réseau local."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: [pollSeconds, keptDays]) {
            app.usage.applySettings()
        }
        .onChange(of: freeboxUsesHTTPS) {
            app.usage.applySettings()
        }
    }
}
