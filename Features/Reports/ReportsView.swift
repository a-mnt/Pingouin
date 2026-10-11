import PingouinCore
import SwiftUI

struct ReportsView: View {
    @Environment(AppState.self) private var app
    @Bindable var model: ReportsViewModel

    var body: some View {
        let sections = model.availableSections(from: app)
        let preview = model.previewText(from: app)

        HStack(alignment: .top, spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SectionCard(L("Contenu du rapport")) {
                        if sections.isEmpty {
                            Text(L("Aucun résultat pour l'instant. Lancer un outil (ping, découverte LAN, scan de ports…) : ses résultats apparaîtront ici."))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ForEach(sections) { section in
                                Toggle(isOn: Binding(
                                    get: { model.isIncluded(section.id) },
                                    set: { model.setIncluded($0, id: section.id) }
                                )) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(section.title)
                                        Text(section.parameters.first ?? "")
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }

                    SectionCard(L("Confidentialité")) {
                        Toggle(L("Masquer les adresses MAC"), isOn: $model.maskMACAddresses)
                            .toggleStyle(.checkbox)
                        Toggle(L("Masquer les noms d'hôtes"), isOn: $model.maskHostnames)
                            .toggleStyle(.checkbox)
                    }

                    SectionCard(L("Format")) {
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
                            .fixedSize(horizontal: false, vertical: true)
                        Text(L("L'emplacement du fichier vous est toujours demandé au moment de l'export."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let message = model.message {
                        Text(message)
                            .footnoteStyle()
                    }
                }
            }
            .frame(width: 320)

            VStack(alignment: .leading, spacing: 0) {
                Text(L("Aperçu"))
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                ScrollView([.horizontal, .vertical]) {
                    Text(preview.isEmpty ? L("Le rapport est vide.") : preview)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.black)
                        .textSelection(.enabled)
                        .padding(28)
                        .frame(minWidth: 560, alignment: .topLeading)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                        .padding(20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glassCard()
        }
        .toolPage(L("Rapports"))
        .toolbar {
            CopyToolbarItem(title: L("Copier le texte du rapport"), isDisabled: preview.isEmpty) {
                preview
            }
            ToolbarItem(placement: .primaryAction) {
                Button(L("Exporter…")) {
                    model.export(from: app)
                }
                .buttonStyle(.borderedProminent)
                .disabled(preview.isEmpty)
            }
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
