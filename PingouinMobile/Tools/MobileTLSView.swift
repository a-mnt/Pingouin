import SwiftUI
import PingouinCore

/// TLS sur iPhone et iPad : la cible, le verdict, la synthèse, le certificat, puis la chaîne.
struct MobileTLSView: View {
    @Bindable var model: TLSViewModel
    @FocusState private var isEditing: Bool

    var body: some View {
        MobilePage("TLS") {
            parameters
            if let verdict = model.verdict {
                verdictCard(verdict)
            }
            HStack(spacing: 10) {
                StatTile(label: L("Validation"), value: model.trustText, tint: mobileTint(model.trustKind), monospaced: false)
                StatTile(label: L("Nom d'hôte"), value: model.hostnameText, monospaced: false)
            }
            HStack(spacing: 10) {
                StatTile(label: L("Expiration"), value: model.expiryText, tint: mobileTint(model.expiryKind), monospaced: false)
                StatTile(label: L("Protocole négocié"), value: model.protocolText)
            }
            if model.hasResult {
                MobileFactsCard(title: L("Certificat du serveur"), rows: model.details)
                chain
            }
            MobileFootnote(text: L("Pour lire le certificat, la négociation est menée à son terme même s'il est invalide. Aucune donnée n'est échangée ensuite, et le verdict affiché est celui de l'évaluation de confiance normale de \(Platform.systemName)."))
        }
        .toolbar {
            MobileCopyItem(title: L("Copier le résultat"), isDisabled: !model.hasResult) {
                model.resultAsText
            }
        }
    }

    private var parameters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                LabeledField(L("Hôte")) {
                    TextField(L("Hôte"), text: $model.hostText, prompt: Text(verbatim: "example.com"))
                        .hostEntry()
                        .submitLabel(.go)
                        .focused($isEditing)
                        .onSubmit(start)
                }
                LabeledField(L("Port")) {
                    TextField(L("Port"), text: $model.portText)
                        .numberEntry()
                        .focused($isEditing)
                }
                .frame(width: 86)
            }
            LabeledField(L("Nom présenté (SNI)")) {
                TextField(L("Nom présenté"), text: $model.serverName, prompt: Text(L("Identique à l'hôte")))
                    .hostEntry()
                    .focused($isEditing)
            }
            MobileRunButton(isRunning: model.isRunning, title: L("Analyser"), run: start) {
                model.cancel()
            }
            ToolStatusLine(content: model.status)
                .font(.subheadline)
        }
        .glassCardPadded(cornerRadius: 22)
    }

    private func start() {
        isEditing = false
        model.start()
    }

    private func verdictCard(_ verdict: TLSVerdict) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: verdict.kind == .ok ? "checkmark.seal" : "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(mobileTint(verdict.kind) ?? Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verdict.title)
                    .font(.headline)
                Text(verdict.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .glassCardPadded(cornerRadius: 22)
    }

    private var chain: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Chaîne de certificats"))
                .font(.headline)
            ForEach(model.chain) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.role)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Text(item.subject)
                        .fontWeight(.semibold)
                        .textSelection(.enabled)
                    StatusLabel(kind: item.validityKind, text: item.validity)
                        .font(.callout)
                }
                .padding(.leading, CGFloat(min(item.id, 3)) * 12)
                .accessibilityElement(children: .combine)
            }
        }
        .glassCardPadded(cornerRadius: 22)
    }
}
