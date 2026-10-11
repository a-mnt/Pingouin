import SwiftUI
import PingouinCore

/// Page d'un outil sur iPhone et iPad : une colonne qui défile, de largeur bornée, sur le fond de l'application.
struct MobilePage<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(16)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { PingouinBackdrop() }
        .navigationTitle(title)
    }
}

/// Bouton principal d'un outil : il lance au repos, il arrête pendant l'exécution.
struct MobileRunButton: View {
    let isRunning: Bool
    let title: String
    let run: () -> Void
    let stop: () -> Void

    var body: some View {
        if isRunning {
            Button(role: .cancel, action: stop) {
                Text(L("Arrêter"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        } else {
            Button(action: run) {
                Text(title)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

/// Bouton « Copier » de la barre de navigation.
struct MobileCopyItem: ToolbarContent {
    let title: String
    let isDisabled: Bool
    let text: () -> String

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Pasteboard.copy(text())
            } label: {
                Label(title, systemImage: "doc.on.doc")
            }
            .disabled(isDisabled)
        }
    }
}

/// Carte « libellé : valeur », une ligne par information. Un appui long copie la valeur.
struct MobileFactsCard: View {
    let title: String?
    let rows: [SummaryRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.headline)
                    .padding(.bottom, 6)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Divider()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Text(row.value)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
                .contextMenu {
                    Button(L("Copier la valeur")) {
                        Pasteboard.copy(row.value)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .glassCardPadded(cornerRadius: 22)
    }
}

/// Texte d'attente d'une liste encore vide.
struct MobileEmptyNote: View {
    let text: String

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCardPadded(cornerRadius: 22)
    }
}

/// Note de bas de page d'un outil.
struct MobileFootnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
    }
}

extension View {
    /// Champ de saisie d'un hôte, d'une adresse ou d'une URL : pas de majuscule ni de correction automatiques.
    func hostEntry() -> some View {
        textFieldStyle(.roundedBorder)
            .font(.body.monospaced())
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
    }

    /// Champ de saisie d'un nombre entier.
    func numberEntry() -> some View {
        textFieldStyle(.roundedBorder)
            .font(.body.monospaced())
            .keyboardType(.numberPad)
    }
}

/// Couleur d'une valeur selon sa nature ; la couleur du texte par défaut quand rien n'est à signaler.
func mobileTint(_ kind: StatusKind) -> Color? {
    switch kind {
    case .ok: .green
    case .warning: .orange
    case .failure: .red
    case .neutral: nil
    }
}
