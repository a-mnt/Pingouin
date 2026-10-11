import Foundation
import SwiftUI

/// Réglages de l'application, conservés dans les préférences de macOS (`UserDefaults`).
///
/// La fenêtre de réglages écrit ces clés avec `@AppStorage` ; le reste de l'application les lit ici.
/// Chaque lecture ramène la valeur dans ses bornes : une valeur saisie hors bornes est sans effet nocif.
enum AppSettings {
    enum Key {
        static let startModule = "general.startModule"
        static let lastModule = "general.lastModule"
        static let appearance = "general.appearance"
        static let showsSidebarLogo = "general.showsSidebarLogo"
        /// « system », ou le code d'une des langues de `AppSettings.languages`.
        static let language = "general.language"
        /// Préférence de macOS propre à l'application : la liste des langues à utiliser, lue au lancement.
        static let systemLanguages = "AppleLanguages"
        static let portScanTimeout = "portScan.timeoutMilliseconds"
        static let portScanConcurrency = "portScan.concurrency"
        static let pingCount = "ping.defaultCount"
        static let pingTimeout = "ping.defaultTimeoutMilliseconds"
        static let tracerouteMaximumHops = "traceroute.defaultMaximumHops"
        static let lanResolveNames = "lan.resolveNames"
        static let sshAutoPassword = "ssh.autoPassword"
        static let monitorInterval = "monitoring.defaultIntervalSeconds"
        static let monitorFailures = "monitoring.defaultFailuresBeforeOffline"
        static let usagePollSeconds = "usage.pollSeconds"
        static let usageKeptDays = "usage.keptDays"
        static let freeboxUsesHTTPS = "usage.freeboxUsesHTTPS"
        /// Cibles du test de connexion du tableau de bord.
        static let connectionPingTarget = "dashboard.pingTarget"
        static let connectionWebName = "dashboard.webName"
        /// Vrai dès qu'une découverte LAN a trouvé des hôtes : première étape de « Pour commencer ».
        static let discoveryDone = "onboarding.discoveryDone"

        /// Clés remises à zéro par « Rétablir tous les réglages par défaut ».
        static let resettable = [
            startModule, appearance, showsSidebarLogo, language, systemLanguages, portScanTimeout, portScanConcurrency, pingCount,
            pingTimeout, tracerouteMaximumHops, lanResolveNames, sshAutoPassword, monitorInterval,
            monitorFailures, usagePollSeconds, usageKeptDays, freeboxUsesHTTPS,
            connectionPingTarget, connectionWebName
        ]
    }

    /// Valeurs d'origine, partagées avec la fenêtre de réglages.
    enum Default {
        /// « dashboard », un autre module, ou « last » pour la dernière fenêtre utilisée.
        static let startModule = AppModule.dashboard.rawValue
        static let lastModuleChoice = "last"
        static let appearance = "system"
        static let language = "system"
        static let portScanTimeout = 400
        static let portScanConcurrency = 64
        static let pingCount = 20
        static let pingTimeout = 1_000
        static let tracerouteMaximumHops = 30
        static let monitorInterval = 60
        static let monitorFailures = 3
        static let usagePollSeconds = 30
        static let usageKeptDays = 30
        static let connectionPingTarget = "1.1.1.1"
        static let connectionWebName = "apple.com"
    }

    /// Langues proposées, chacune sous son propre nom (il ne se traduit pas).
    static let languages: [(code: String, name: String)] = [
        ("fr", "Français"), ("en", "English"), ("es", "Español"), ("de", "Deutsch"), ("it", "Italiano")
    ]

    /// Enregistre la langue choisie pour Pingouin. macOS la lit au lancement : elle vaut alors pour les
    /// textes de l'application comme pour ceux du système (dates, panneaux, menus standard).
    /// « system » rend la main au réglage de langue de macOS.
    static func applyLanguage(_ choice: String) {
        if languages.contains(where: { $0.code == choice }) {
            UserDefaults.standard.set([choice], forKey: Key.systemLanguages)
        } else {
            UserDefaults.standard.removeObject(forKey: Key.systemLanguages)
        }
    }

    static let monitorIntervals = [30, 60, 300, 900, 3_600]
    static let usagePollChoices = [30, 60, 300]
    static let usageKeptDayChoices = [7, 30, 90]

    // MARK: Lecture

    private static func integer(_ key: String, default value: Int, in range: ClosedRange<Int>) -> Int {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key) != nil else { return value }
        return min(max(defaults.integer(forKey: key), range.lowerBound), range.upperBound)
    }

    private static func choice(_ key: String, default value: Int, among choices: [Int]) -> Int {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key) != nil else { return value }
        let stored = defaults.integer(forKey: key)
        return choices.contains(stored) ? stored : value
    }

    private static func bool(_ key: String, default value: Bool) -> Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: key) == nil ? value : defaults.bool(forKey: key)
    }

    static var portScanTimeout: Int { integer(Key.portScanTimeout, default: Default.portScanTimeout, in: 100...10_000) }
    static var portScanConcurrency: Int { integer(Key.portScanConcurrency, default: Default.portScanConcurrency, in: 1...128) }
    static var pingCount: Int { integer(Key.pingCount, default: Default.pingCount, in: 1...1_000) }
    static var pingTimeout: Int { integer(Key.pingTimeout, default: Default.pingTimeout, in: 100...10_000) }
    static var tracerouteMaximumHops: Int { integer(Key.tracerouteMaximumHops, default: Default.tracerouteMaximumHops, in: 1...64) }
    static var lanResolveNames: Bool { bool(Key.lanResolveNames, default: true) }
    static var sshAutoPassword: Bool { bool(Key.sshAutoPassword, default: true) }
    static var monitorInterval: Int { choice(Key.monitorInterval, default: Default.monitorInterval, among: monitorIntervals) }
    static var monitorFailures: Int { integer(Key.monitorFailures, default: Default.monitorFailures, in: 1...10) }
    static var usagePollSeconds: Int { choice(Key.usagePollSeconds, default: Default.usagePollSeconds, among: usagePollChoices) }
    /// Échanges chiffrés avec la Freebox. Décoché, ils passent en HTTP simple sur le réseau local.
    static var freeboxUsesHTTPS: Bool { bool(Key.freeboxUsesHTTPS, default: true) }
    static var usageKeptDays: Int { choice(Key.usageKeptDays, default: Default.usageKeptDays, among: usageKeptDayChoices) }

    /// Module à afficher au lancement, d'après le réglage.
    static var startModule: AppModule {
        let defaults = UserDefaults.standard
        let stored = defaults.string(forKey: Key.startModule) ?? Default.startModule
        if stored == Default.lastModuleChoice {
            return defaults.string(forKey: Key.lastModule).flatMap(AppModule.init(rawValue:)) ?? .dashboard
        }
        return AppModule(rawValue: stored) ?? .dashboard
    }

    static func rememberLastModule(_ module: AppModule?) {
        guard let module else { return }
        UserDefaults.standard.set(module.rawValue, forKey: Key.lastModule)
    }

    /// Apparence imposée, ou `nil` pour suivre le système.
    static func colorScheme(for appearance: String) -> ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    /// Adresse pinguée pour vérifier l'accès à Internet. Une saisie vide ou invalide rend la valeur d'origine.
    static var connectionPingTarget: String {
        host(Key.connectionPingTarget, default: Default.connectionPingTarget)
    }

    /// Nom résolu puis ouvert en HTTPS pour vérifier le DNS et le Web.
    static var connectionWebName: String {
        host(Key.connectionWebName, default: Default.connectionWebName)
    }

    private static func host(_ key: String, default value: String) -> String {
        let stored = (UserDefaults.standard.string(forKey: key) ?? "").trimmingCharacters(in: .whitespaces)
        let valid = !stored.isEmpty && stored.count <= 253
            && !stored.contains { $0.isWhitespace || $0 == "/" || $0 == "?" || $0 == "#" || $0 == "@" }
        return valid ? stored : value
    }

    static var discoveryDone: Bool {
        get { UserDefaults.standard.bool(forKey: Key.discoveryDone) }
        set { UserDefaults.standard.set(newValue, forKey: Key.discoveryDone) }
    }

    static func resetAll() {
        for key in Key.resettable {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

/// Dossier où l'application range ses fichiers de données.
enum AppDataFolder {
    static var url: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("fr.a-mnt.pingouin", isDirectory: true)
    }
}
