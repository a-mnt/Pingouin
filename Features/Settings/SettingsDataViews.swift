import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PingouinCore

// MARK: Journal

/// Journal de la session : ce que l'application a fait et ce qui a échoué, sans aucun secret.
struct LogSettings: View {
    @State private var message: String?

    var body: some View {
        let log = AppLog.shared
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Journal de cette session. Il ne contient ni mot de passe ni jeton. Il est aussi visible dans Console.app, sous-système « fr.a-mnt.pingouin »."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(log.entries.reversed()) { entry in
                        Text(entry.line)
                            .font(.caption.monospaced())
                            .foregroundStyle(entry.level == .error ? Color.red : (entry.level == .warning ? Color.orange : Color.primary))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if log.entries.isEmpty {
                    Text(L("Rien à signaler pour l'instant."))
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("Effacer")) {
                    log.clear()
                    message = nil
                }
                .disabled(log.entries.isEmpty)
                Button(L("Copier")) {
                    Pasteboard.copy(log.exportText)
                    message = L("Journal copié.")
                }
                .disabled(log.entries.isEmpty)
                Button(L("Exporter…")) {
                    export(log.exportText)
                }
                .disabled(log.entries.isEmpty)
            }
        }
        .padding(16)
    }

    private func export(_ text: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "journal-pingouin.txt"
        panel.message = L("Choisir où enregistrer le journal")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
            message = L("Journal enregistré dans \(url.lastPathComponent).")
        } catch {
            message = L("L'enregistrement a échoué : \(error.localizedDescription)")
        }
    }
}

// MARK: Données

struct DataSettings: View {
    private enum Pending: String, Identifiable {
        case usage
        case journals
        case settings

        var id: String { rawValue }
    }

    @Environment(AppState.self) private var app
    @State private var pending: Pending?
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                LabeledContent(L("Dossier des données")) {
                    Button(L("Afficher dans le Finder")) {
                        showFolder()
                    }
                }
                Text(AppDataFolder.url?.path ?? L("Dossier introuvable"))
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Section {
                LabeledContent(L("Historique de consommation")) {
                    Button(L("Effacer…")) { pending = .usage }
                }
                LabeledContent(L("Événements de supervision et exécutions des tâches")) {
                    Button(L("Effacer…")) { pending = .journals }
                }
            }
            Section {
                LabeledContent(L("Tous les réglages")) {
                    Button(L("Rétablir par défaut…"), role: .destructive) { pending = .settings }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Les connexions SSH, les surveillances, le schéma et les tâches ne sont pas touchés."))
                        .foregroundStyle(.secondary)
                    if let message {
                        Text(message)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            title(for: pending),
            isPresented: Binding(
                get: { pending != nil },
                set: { isPresented in
                    if !isPresented { pending = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(pending == .settings ? L("Rétablir") : L("Effacer"), role: .destructive) {
                perform(pending)
                pending = nil
            }
            Button(L("Annuler"), role: .cancel) {
                pending = nil
            }
        } message: {
            Text(L("Cette action ne peut pas être annulée."))
        }
    }

    private func title(for pending: Pending?) -> String {
        switch pending {
        case .usage: L("Effacer l'historique de consommation ?")
        case .journals: L("Effacer les événements de supervision et les exécutions des tâches ?")
        case .settings: L("Rétablir tous les réglages par défaut ?")
        case nil: ""
        }
    }

    private func perform(_ pending: Pending?) {
        switch pending {
        case .usage:
            app.usage.clearHistory()
            message = L("Historique de consommation effacé.")
        case .journals:
            app.monitoring.clearEvents()
            app.automation.clearRuns()
            message = L("Événements et exécutions effacés.")
        case .settings:
            AppSettings.resetAll()
            app.ssh.setDefaultTheme(TerminalTheme.fallback.id)
            app.ssh.setFontSize(13)
            app.monitoring.setNotifications(false)
            app.applyDiagnosticsSettings()
            app.usage.applySettings()
            message = L("Réglages rétablis.")
        case nil:
            break
        }
    }

    private func showFolder() {
        guard let url = AppDataFolder.url else { return }
        // Le dossier n'existe qu'après un premier enregistrement : on le crée pour pouvoir le montrer.
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            message = L("Le dossier des données n'a pas pu être créé : \(error.localizedDescription)")
            AppLog.shared.error("Réglages", "Création du dossier des données en échec : \(error.localizedDescription)")
        }
    }
}
