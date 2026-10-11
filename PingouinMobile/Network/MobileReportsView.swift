import SwiftUI
import PingouinCore

/// Rapports sur iPhone et iPad : les résultats présents dans les outils, exportés par la feuille de partage.
struct MobileReportsView: View {
    @Environment(MobileAppState.self) private var state
    @Bindable var model: ReportsViewModel
    @State private var sharedFile: SharedFile?

    var body: some View {
        let sections = model.availableSections(from: state)
        let preview = model.previewText(from: state)

        MobilePage(L("Rapports")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Contenu du rapport"))
                    .font(.headline)
                if sections.isEmpty {
                    Text(L("Aucun résultat pour l'instant. Lancer un outil (ping, découverte LAN, scan de ports…) : ses résultats apparaîtront ici."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sections) { section in
                        Toggle(isOn: Binding(
                            get: { model.isIncluded(section.id) },
                            set: { model.setIncluded($0, id: section.id) }
                        )) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(section.title)
                                Text(section.parameters.first ?? "")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .glassCardPadded(cornerRadius: 22)

            VStack(alignment: .leading, spacing: 10) {
                Text(L("Confidentialité"))
                    .font(.headline)
                Toggle(L("Masquer les adresses MAC"), isOn: $model.maskMACAddresses)
                Toggle(L("Masquer les noms d'hôtes"), isOn: $model.maskHostnames)
            }
            .glassCardPadded(cornerRadius: 22)

            VStack(alignment: .leading, spacing: 10) {
                Text(L("Format"))
                    .font(.headline)
                Picker(L("Format"), selection: $model.format) {
                    ForEach(ReportFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(formatNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    if let url = model.exportFile(from: state) {
                        sharedFile = SharedFile(url: url)
                    }
                } label: {
                    Text(L("Exporter…"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(preview.isEmpty)
                if let message = model.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .glassCardPadded(cornerRadius: 22)

            VStack(alignment: .leading, spacing: 8) {
                Text(L("Aperçu"))
                    .font(.headline)
                ScrollView(.horizontal) {
                    Text(preview.isEmpty ? L("Le rapport est vide.") : preview)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.bottom, 6)
                }
            }
            .glassCardPadded(cornerRadius: 22)
        }
        .toolbar {
            MobileCopyItem(title: L("Copier le texte du rapport"), isDisabled: preview.isEmpty) {
                preview
            }
        }
        .sheet(item: $sharedFile) { file in
            MobileShareSheet(file: file)
        }
    }

    private var formatNote: String {
        switch model.format {
        case .pdf: L("PDF : le texte de l'aperçu, en pages A4 paysage numérotées.")
        case .csv: L("CSV : uniquement les tableaux, séparés par des points-virgules, pour un tableur.")
        case .json: L("JSON : toutes les sections, pour un traitement automatique.")
        }
    }
}
