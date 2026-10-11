import SwiftUI
import PingouinCore

struct TLSView: View {
    @Bindable var model: TLSViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                parameters
                if let verdict = model.verdict {
                    verdictCard(verdict)
                }
                HStack(spacing: 10) {
                    StatTile(label: L("Validation"), value: model.trustText, tint: tint(model.trustKind), monospaced: false)
                    StatTile(label: L("Nom d'hôte"), value: model.hostnameText, monospaced: false)
                    StatTile(label: L("Expiration"), value: model.expiryText, tint: tint(model.expiryKind), monospaced: false)
                    StatTile(label: L("Protocole négocié"), value: model.protocolText)
                }
                if model.hasResult {
                    HStack(alignment: .top, spacing: 14) {
                        certificate
                        chain
                            .frame(minWidth: 280, maxWidth: 360)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                HistoryCard(entries: model.history) { entry in
                    model.launch(target: entry.target)
                }
                Text(L("Pour lire le certificat, la négociation est menée à son terme même s'il est invalide. Aucune donnée n'est échangée ensuite, et le verdict affiché est celui de l'évaluation de confiance normale de \(Platform.systemName)."))
                    .footnoteStyle()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background { PingouinBackdrop() }
        .navigationTitle("TLS")
        .toolbar {
            CopyToolbarItem(title: L("Copier le résultat"), isDisabled: !model.hasResult) {
                model.resultAsText
            }
            RunToolbarItem(
                isRunning: model.isRunning,
                title: L("Analyser"),
                run: { model.start() },
                stop: { model.cancel() }
            )
        }
    }

    private func tint(_ kind: StatusKind) -> Color? {
        switch kind {
        case .ok: return .green
        case .warning: return .orange
        case .failure: return .red
        case .neutral: return nil
        }
    }

    private var parameters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                LabeledField(L("Hôte")) {
                    TextField(L("Hôte"), text: $model.hostText, prompt: Text("example.com"))
                        .labelsHidden()
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                        .onSubmit { model.start() }
                }
                .frame(minWidth: 240)
                LabeledField(L("Port")) {
                    TextField(L("Port"), text: $model.portText)
                        .labelsHidden()
                        .font(.body.monospaced())
                }
                .frame(width: 90)
                LabeledField(L("Nom présenté (SNI)")) {
                    TextField(L("Nom présenté"), text: $model.serverName, prompt: Text(L("Identique à l'hôte")))
                        .labelsHidden()
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                }
                .frame(minWidth: 180, maxWidth: 260)
            }
            .disabled(model.isRunning)

            ToolStatusLine(content: model.status)
        }
        .glassCardPadded()
    }

    private func verdictCard(_ verdict: TLSVerdict) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: verdict.kind == .ok ? "checkmark.seal" : "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundStyle(tint(verdict.kind) ?? Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verdict.title)
                    .font(.title3.weight(.bold))
                Text(verdict.detail)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .glassCardPadded()
    }

    private var certificate: some View {
        SectionCard(L("Certificat du serveur")) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.details) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.label)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Text(row.value)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var chain: some View {
        SectionCard(L("Chaîne de certificats")) {
            VStack(alignment: .leading, spacing: 10) {
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
                    .padding(.leading, CGFloat(item.id) * 14)
                }
            }
        }
    }
}
