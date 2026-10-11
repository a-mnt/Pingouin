import SwiftUI
import PingouinCore

/// Calculateur IP sur iPhone et iPad. Le résultat suit la saisie : rien n'est envoyé sur le réseau.
struct MobileIPCalculatorView: View {
    @Bindable var model: IPCalculatorViewModel

    var body: some View {
        MobilePage(L("Calculateur IP")) {
            input
            if !model.summary.isEmpty {
                MobileFactsCard(title: nil, rows: model.highlights)
                MobileFactsCard(title: L("Détail"), rows: model.details)
                membership
                split
            }
        }
        .toolbar {
            MobileCopyItem(title: L("Copier le résumé"), isDisabled: model.summary.isEmpty) {
                model.summaryText
            }
        }
    }

    private var input: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledField(L("Adresse et préfixe (IPv4 ou IPv6)")) {
                TextField(L("Adresse et préfixe"), text: $model.input, prompt: Text(verbatim: "192.168.10.0/24"))
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.numbersAndPunctuation)
            }
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .glassCardPadded(cornerRadius: 22)
    }

    private var membership: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledField(L("Vérifier l'appartenance d'une adresse")) {
                TextField(L("Adresse à vérifier"), text: $model.probe, prompt: Text(verbatim: "192.168.10.57"))
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.numbersAndPunctuation)
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
        .glassCardPadded(cornerRadius: 22)
    }

    private var split: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Découpage en sous-réseaux"))
                .font(.headline)
            HStack {
                Text(L("Nouveau préfixe /"))
                    .foregroundStyle(.secondary)
                TextField(L("Nouveau préfixe"), text: $model.splitPrefix, prompt: Text(verbatim: "26"))
                    .numberEntry()
                    .frame(width: 72)
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
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.network)
                            .font(.body.monospaced().weight(.semibold))
                        Text(row.range)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                        if !row.detail.isEmpty {
                            Text(L("Broadcast") + " : " + row.detail)
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .textSelection(.enabled)
                    .accessibilityElement(children: .combine)
                }
                if truncated {
                    Text(L("Seuls les \(rows.count) premiers sous-réseaux sont affichés."))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .glassCardPadded(cornerRadius: 22)
    }
}
