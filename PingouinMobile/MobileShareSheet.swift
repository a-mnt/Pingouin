import SwiftUI
import UIKit

/// Fichier à remettre à la feuille de partage d'iOS.
struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Feuille de partage d'iOS (Fichiers, AirDrop, Mail…) pour un fichier produit par Pingouin.
struct MobileShareSheet: UIViewControllerRepresentable {
    let file: SharedFile

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [file.url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Écrit un texte dans le dossier temporaire de l'application, pour le partager. `nil` si l'écriture échoue.
enum TemporaryFile {
    static func write(_ data: Data, named fileName: String) -> SharedFile? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            return SharedFile(url: url)
        } catch {
            return nil
        }
    }
}
