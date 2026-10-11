import SwiftUI
import PingouinCore

struct IPCalculatorView: View {
    @Bindable var model: IPCalculatorViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                input

                if !model.summary.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
                        ForEach(model.highlights) { row in
                            StatTile(label: row.label, value: row.value)
                        }
                    }

                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 14) {
                            details
                            membership
                        }
                        split
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background { PingouinBackdrop() }
        .navigationTitle(L("Calculateur IP"))
        .toolbar {
            ToolbarItem {
                Button {
                    Pasteboard.copy(model.summaryText)
                } label: {
                    Label(L("Copier le résumé"), systemImage: "doc.on.doc")
                }
                .disabled(model.summary.isEmpty)
                .help(L("Copier le résumé du réseau dans le presse-papiers"))
            }
        }
    }

    // MARK: Saisie

    private var input: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledField(L("Adresse et préfixe (IPv4 ou IPv6)")) {
                TextField(L("Adresse et préfixe"), text: $model.input, prompt: Text("192.168.10.0/24"))
                    .labelsHidden()
                    .font(.title3.monospaced())
                    .autocorrectionDisabled()
            }
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        }
        .glassCardPadded()
    }

    // MARK: Détail

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Détail"))
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                ForEach(model.details) { row in
                    GridRow {
                        Text(row.label)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Text(row.value)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .glassCardPadded()
    }

    // MARK: Appartenance

    private var membership: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledField(L("Vérifier l'appartenance d'une adresse")) {
                TextField(L("Adresse à vérifier"), text: $model.probe, prompt: Text("192.168.10.57"))
                    .labelsHidden()
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
            }
            switch model.membership {
            case .notAsked:
                EmptyView()
            case .invalidAddress:
                Label(L("Adresse non reconnue."), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            case .familyMismatch:
                Label(L("Cette adresse n'est pas de la même famille (IPv4 ou IPv6) que le réseau."), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            case .inside:
                Label(L("Oui, cette adresse appartient au réseau."), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .outside:
                Label(L("Non, cette adresse est hors du réseau."), systemImage: "xmark.circle")
                    .foregroundStyle(.red)
            }
        }
        .glassCardPadded()
    }

    private func columnHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
    }

    // MARK: Découpage

    private var split: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Découpage en sous-réseaux"))
                    .font(.headline)
                Spacer()
                Text(L("Nouveau préfixe /"))
                    .foregroundStyle(.secondary)
                TextField(L("Nouveau préfixe"), text: $model.splitPrefix, prompt: Text("26"))
                    .labelsHidden()
                    .font(.body.monospaced())
                    .frame(width: 64)
            }

            switch model.split {
            case .notAsked:
                Text(L("Saisir un préfixe plus long que celui du réseau pour obtenir la liste des sous-réseaux."))
                    .foregroundStyle(.secondary)
            case .invalid(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            case .result(let summary, let rows, let truncated):
                Text(summary)
                    .foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        columnHeader(L("Sous-réseau"))
                        columnHeader(L("Plage"))
                        columnHeader(L("Broadcast"))
                    }
                    ForEach(rows) { row in
                        GridRow {
                            Text(row.network)
                            Text(row.range)
                            Text(row.detail.isEmpty ? "—" : row.detail)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.body.monospaced())
                .textSelection(.enabled)
                if truncated {
                    Text(L("Seuls les \(rows.count) premiers sous-réseaux sont affichés."))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .glassCardPadded()
    }
}
