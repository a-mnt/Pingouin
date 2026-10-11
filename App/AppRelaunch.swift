import AppKit
import Foundation

/// Redémarrage de l'application, pour les réglages que macOS ne lit qu'au lancement (la langue).
@MainActor
enum AppRelaunch {
    /// Ouvre une nouvelle instance de Pingouin, puis quitte celle-ci. Renvoie faux si la nouvelle
    /// instance n'a pas pu être lancée : l'application reste alors ouverte.
    /// Le chemin du programme est fixe ; le seul argument variable est l'emplacement de l'application.
    @discardableResult
    static func relaunch() -> Bool {
        UserDefaults.standard.synchronize()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundlePath]
        do {
            try process.run()
        } catch {
            AppLog.shared.error("Réglages", "Redémarrage impossible : \(error.localizedDescription)")
            return false
        }
        NSApp.terminate(nil)
        return true
    }
}
