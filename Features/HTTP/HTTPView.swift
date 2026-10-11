import PingouinNetwork
import SwiftUI
import PingouinCore

struct HTTPView: View {
    @Bindable var model: HTTPViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            parameters
            HStack(spacing: 10) {
                StatTile(
                    label: L("Code HTTP"),
                    value: model.statusCodeText,
                    tint: codeTint,
                    monospaced: false
                )
                StatTile(label: L("Temps total"), value: model.totalTimeText)
                StatTile(label: L("Taille reçue"), value: model.sizeText)
                StatTile(label: L("Protocole"), value: model.protocolText)
            }
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 14) {
                    timing
                    redirects
                }
                .frame(minWidth: 320, maxWidth: 440)
                headers
            }
        }
        .toolPage("HTTP")
        .toolbar {
            CopyToolbarItem(title: L("Copier le résultat"), isDisabled: !model.hasResult) {
                model.resultAsText
            }
            RunToolbarItem(
                isRunning: model.isRunning,
                title: L("Envoyer"),
                run: { model.start() },
                stop: { model.cancel() }
            )
        }
    }

    private var codeTint: Color? {
        switch model.statusKind {
        case .ok: return .green
        case .neutral: return nil
        case .warning, .failure: return .orange
        }
    }

    private var parameters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                LabeledField(L("Méthode")) {
                    Picker(L("Méthode"), selection: $model.method) {
                        ForEach(HTTPProbeOptions.allowedMethods, id: \.self) { method in
                            Text(method).tag(method)
                        }
                    }
                    .labelsHidden()
                }
                .frame(width: 120)

                LabeledField("URL") {
                    TextField("URL", text: $model.urlText, prompt: Text("https://example.com/"))
                        .labelsHidden()
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                        .onSubmit { model.start() }
                    Toggle(L("Suivre les redirections"), isOn: $model.followRedirects)
                        .toggleStyle(.checkbox)
                }
                .frame(minWidth: 300)

                LabeledField(L("Redirections maximum")) {
                    TextField(L("Redirections maximum"), text: $model.maximumRedirectsText)
                        .labelsHidden()
                        .font(.body.monospaced())
                        .disabled(!model.followRedirects)
                }
                .frame(width: 150)
            }
            .disabled(model.isRunning)

            ToolStatusLine(content: model.status)
        }
        .glassCardPadded()
    }

    private var timing: some View {
        SectionCard(L("Décomposition du temps")) {
            if model.phases.isEmpty {
                Text(L("La répartition entre DNS, connexion, TLS et serveur apparaîtra ici."))
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    ForEach(model.phases) { phase in
                        GridRow {
                            Text(phase.label)
                            // Barre en cascade : chaque phase commence là où la précédente finit.
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(phase.isLongest ? Color.accentColor : Color.primary.opacity(0.8))
                                    .frame(width: max(proxy.size.width * phase.length, 3))
                                    .offset(x: proxy.size.width * phase.offset)
                            }
                            .frame(height: 10)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                            .accessibilityHidden(true)
                            Text(phase.milliseconds.formatted(.number.precision(.fractionLength(0))) + " ms")
                                .font(.body.monospaced())
                                .gridColumnAlignment(.trailing)
                        }
                    }
                }
                Text(L("Mesures de la dernière requête de la chaîne."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var redirects: some View {
        SectionCard(L("Parcours de la requête")) {
            if model.redirects.isEmpty {
                Text(L("Les redirections et la réponse finale apparaîtront ici."))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.redirects) { hop in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(hop.statusCode)
                                    .font(.body.monospaced().weight(.bold))
                                Text(hop.url)
                                    .font(.body.monospaced())
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                                    .help(hop.url)
                            }
                            Text(hop.note)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    private var headers: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("En-têtes de la réponse"))
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            Table(model.headers, selection: $model.headerSelection) {
                TableColumn(L("Nom")) { row in
                    Text(row.name)
                        .font(.body.monospaced())
                }
                .width(min: 120, ideal: 190, max: 260)
                TableColumn(L("Valeur")) { row in
                    Text(row.value)
                        .font(.body.monospaced())
                        .help(row.value)
                }
            }
            .scrollContentBackground(.hidden)
            .contextMenu(forSelectionType: Int.self) { ids in
                if ids.count == 1, let id = ids.first, let row = model.header(id: id) {
                    Button(L("Copier la valeur")) {
                        Pasteboard.copy(row.value)
                    }
                    Button(L("Copier l'en-tête")) {
                        Pasteboard.copy("\(row.name): \(row.value)")
                    }
                }
            }
            .overlay {
                if model.headers.isEmpty, !model.isRunning {
                    ContentUnavailableView(
                        L("Aucun en-tête"),
                        systemImage: "arrow.left.arrow.right",
                        description: Text(L("Les en-têtes de la réponse apparaîtront ici."))
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard()
    }
}
