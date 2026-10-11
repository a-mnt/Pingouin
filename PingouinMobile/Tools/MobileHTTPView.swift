import SwiftUI
import PingouinCore
import PingouinNetwork

/// HTTP sur iPhone et iPad : la requête, la synthèse, le temps par phase, le parcours, puis les en-têtes.
struct MobileHTTPView: View {
    @Bindable var model: HTTPViewModel
    @FocusState private var isEditing: Bool

    var body: some View {
        MobilePage("HTTP") {
            parameters
            HStack(spacing: 10) {
                StatTile(label: L("Code HTTP"), value: model.statusCodeText, tint: codeTint, monospaced: false)
                StatTile(label: L("Temps total"), value: model.totalTimeText)
            }
            HStack(spacing: 10) {
                StatTile(label: L("Taille reçue"), value: model.sizeText)
                StatTile(label: L("Protocole"), value: model.protocolText)
            }
            timing
            redirects
            headers
        }
        .toolbar {
            MobileCopyItem(title: L("Copier le résultat"), isDisabled: !model.hasResult) {
                model.resultAsText
            }
        }
    }

    private var codeTint: Color? {
        switch model.statusKind {
        case .ok: .green
        case .neutral: nil
        case .warning, .failure: .orange
        }
    }

    private var parameters: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledField("URL") {
                TextField("URL", text: $model.urlText, prompt: Text(verbatim: "https://example.com/"))
                    .hostEntry()
                    .submitLabel(.go)
                    .focused($isEditing)
                    .onSubmit(start)
            }
            HStack(alignment: .top, spacing: 12) {
                LabeledField(L("Méthode")) {
                    Picker(L("Méthode"), selection: $model.method) {
                        ForEach(HTTPProbeOptions.allowedMethods, id: \.self) { method in
                            Text(verbatim: method).tag(method)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                LabeledField(L("Redirections maximum")) {
                    TextField(L("Redirections maximum"), text: $model.maximumRedirectsText)
                        .numberEntry()
                        .focused($isEditing)
                        .disabled(!model.followRedirects)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Toggle(L("Suivre les redirections"), isOn: $model.followRedirects)
            MobileRunButton(isRunning: model.isRunning, title: L("Envoyer"), run: start) {
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

    private var timing: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Décomposition du temps"))
                .font(.headline)
            if model.phases.isEmpty {
                Text(L("La répartition entre DNS, connexion, TLS et serveur apparaîtra ici."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.phases) { phase in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(phase.label)
                            Spacer(minLength: 0)
                            Text(phase.milliseconds.formatted(.number.precision(.fractionLength(0))) + " ms")
                                .font(.body.monospaced())
                        }
                        // Barre en cascade : chaque phase commence là où la précédente finit.
                        GeometryReader { proxy in
                            Capsule()
                                .fill(phase.isLongest ? Color.accentColor : Color.primary.opacity(0.8))
                                .frame(width: max(proxy.size.width * phase.length, 3))
                                .offset(x: proxy.size.width * phase.offset)
                        }
                        .frame(height: 8)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                        .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text(L("Mesures de la dernière requête de la chaîne."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .glassCardPadded(cornerRadius: 22)
    }

    private var redirects: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Parcours de la requête"))
                .font(.headline)
            if model.redirects.isEmpty {
                Text(L("Les redirections et la réponse finale apparaîtront ici."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.redirects) { hop in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(hop.statusCode)
                                .font(.body.monospaced().weight(.bold))
                            Text(hop.url)
                                .font(.body.monospaced())
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        Text(hop.note)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            }
        }
        .glassCardPadded(cornerRadius: 22)
    }

    private var headers: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("En-têtes de la réponse"))
                .font(.headline)
                .padding(.bottom, 6)
            if model.headers.isEmpty {
                Text(L("Les en-têtes de la réponse apparaîtront ici."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.headers.enumerated()), id: \.element.id) { index, header in
                    if index > 0 {
                        Divider()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(header.name)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Text(header.value)
                            .font(.footnote.monospaced())
                            .lineLimit(4)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button(L("Copier la valeur")) {
                            Pasteboard.copy(header.value)
                        }
                        Button(L("Copier l'en-tête")) {
                            Pasteboard.copy("\(header.name): \(header.value)")
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .glassCardPadded(cornerRadius: 22)
    }
}
