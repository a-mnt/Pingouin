import SwiftUI
import PingouinCore

extension View {
    /// Habillage commun d'une fenêtre d'outil : marges, fond, titre.
    func toolPage(_ title: String) -> some View {
        padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background { PingouinBackdrop() }
            .navigationTitle(title)
    }

    /// Note de bas de page, en petit et en gris.
    func footnoteStyle() -> some View {
        font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
    }
}

/// Bouton principal d'un outil dans la barre d'outils : « Lancer » au repos, « Arrêter » pendant l'exécution.
struct RunToolbarItem: ToolbarContent {
    let isRunning: Bool
    let title: String
    let run: () -> Void
    let stop: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if isRunning {
                Button(L("Arrêter"), role: .cancel, action: stop)
            } else {
                Button(title, action: run)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// Bouton « Copier » de la barre d'outils.
struct CopyToolbarItem: ToolbarContent {
    let title: String
    let isDisabled: Bool
    let text: () -> String

    var body: some ToolbarContent {
        ToolbarItem {
            Button {
                Pasteboard.copy(text())
            } label: {
                Label(title, systemImage: "doc.on.doc")
            }
            .disabled(isDisabled)
            .help(title)
        }
    }
}

/// Carte de verre avec un titre.
struct SectionCard<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .glassCardPadded()
    }
}

/// Ligne d'état d'un outil : message d'attente, progression, résumé ou erreur.
struct ToolStatusLine: View {
    enum Content: Equatable {
        case hint(String)
        case progress(String, fraction: Double?)
        case done(String)
        case warning(String)
        case failure(String)
    }

    let content: Content

    var body: some View {
        switch content {
        case .hint(let text):
            Text(text)
                .foregroundStyle(.secondary)
        case .progress(let text, let fraction):
            HStack(spacing: 10) {
                if let fraction {
                    ProgressView(value: min(max(fraction, 0), 1))
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(text)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        case .done(let text):
            Label(text, systemImage: "checkmark.circle")
        case .warning(let text):
            Label(text, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .failure(let text):
            Label(text, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }
}

/// Entrée d'historique d'un outil, gardée en mémoire le temps de la session.
struct HistoryEntry: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let text: String
    /// Cible à réutiliser quand on relance depuis l'historique.
    let target: String

    init(text: String, target: String, date: Date = .now) {
        self.text = text
        self.target = target
        self.date = date
    }
}

/// Carte d'historique : les entrées les plus récentes en premier, cliquables pour relancer.
struct HistoryCard: View {
    let entries: [HistoryEntry]
    let rerun: (HistoryEntry) -> Void

    var body: some View {
        SectionCard(L("Historique")) {
            if entries.isEmpty {
                Text(L("Les opérations de cette session apparaîtront ici."))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entries.prefix(8)) { entry in
                        Button {
                            rerun(entry)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(entry.date.formatted(date: .omitted, time: .shortened))
                                    .font(.body.monospaced())
                                    .foregroundStyle(.secondary)
                                Text(entry.text)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .buttonStyle(.plain)
                        .help(L("Relancer sur \(entry.target)"))
                    }
                }
            }
        }
    }
}

/// Lecture d'un nombre saisi : accepte la virgule ou le point comme séparateur décimal.
enum NumberInput {
    static func integer(_ text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespaces))
    }

    static func decimal(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    static func milliseconds(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + " ms"
    }
}
