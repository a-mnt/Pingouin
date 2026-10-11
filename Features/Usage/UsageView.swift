import SwiftUI
import PingouinCore

struct UsageView: View {
    @Bindable var model: UsageViewModel
    @State private var isAskingToForget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                StatTile(label: L("Reçu par les appareils"), value: model.totalReceived)
                StatTile(label: L("Envoyé par les appareils"), value: model.totalSent)
                StatTile(label: L("Appareils mesurés"), value: model.measuredCount.formatted())
                StatTile(label: L("Débit en ce moment"), value: model.currentRate)
            }
            HStack(alignment: .top, spacing: 14) {
                devices
                ScrollView {
                    VStack(spacing: 14) {
                        source
                        capabilities
                        limits
                    }
                }
                .frame(width: 310)
            }
        }
        .toolPage(L("Consommation"))
        .toolbar {
            ToolbarItem {
                Picker(L("Période"), selection: $model.period) {
                    ForEach(UsagePeriod.allCases) { period in
                        Text(period.title).tag(period)
                    }
                }
                .help(L("Période sur laquelle les volumes sont additionnés"))
            }
            CopyToolbarItem(title: L("Copier le tableau"), isDisabled: model.rows.isEmpty) {
                model.rowsAsText
            }
            ToolbarItem {
                Button(model.isRefreshing ? L("Relevé en cours…") : L("Actualiser")) {
                    model.refreshNow()
                }
                .disabled(!model.isConnected || model.isRefreshing)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(L("Connecter une box")) {
                    model.isChoosingSource = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isConnected || model.isBusy)
            }
        }
        .sheet(isPresented: $model.isChoosingSource) {
            UsageSourcePicker(model: model)
        }
        .confirmationDialog(L("Oublier l'accès à la box ?"), isPresented: $isAskingToForget, titleVisibility: .visible) {
            Button(L("Oublier l'accès"), role: .destructive) {
                model.forgetAccess()
            }
            Button(L("Annuler"), role: .cancel) {}
        } message: {
            Text(L("Pingouin ne pourra plus relever la consommation tant que l'accès n'aura pas été redemandé. Les volumes déjà relevés sont conservés."))
        }
    }

    // MARK: Par appareil

    private var devices: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L("Par appareil"))
                    .font(.headline)
                Spacer()
                Text(readingStatus)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if let error = model.readingError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            Table(model.rows) {
                TableColumn(L("Appareil")) { row in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.name)
                            .fontWeight(row.isMember ? .regular : .semibold)
                            .foregroundStyle(row.isPresent ? .primary : .secondary)
                        if !row.detail.isEmpty {
                            Text(row.detail)
                                .font(.callout)
                                .fontDesign(row.isShared ? .default : .monospaced)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .help(row.isShared ? L("Plusieurs appareils sont branchés derrière ce port : la box ne sait pas les départager.") : row.detail)
                        }
                    }
                    .padding(.vertical, 2)
                    // Les appareils d'un port partagé sont en retrait sous la ligne du port.
                    .padding(.leading, row.isMember ? 18 : 0)
                }
                .width(min: 150, ideal: 210)
                TableColumn(L("Liaison")) { row in
                    Text(row.link)
                }
                .width(min: 90, ideal: 120)
                TableColumn(L("Reçu")) { row in
                    Text(row.received)
                        .font(.body.monospaced())
                }
                .width(min: 70, ideal: 85)
                TableColumn(L("Envoyé")) { row in
                    Text(row.sent)
                        .font(.body.monospaced())
                }
                .width(min: 70, ideal: 85)
                TableColumn(L("Part du total")) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        if !row.isMember {
                            ProgressView(value: row.share)
                                .tint(.accentColor)
                                .accessibilityHidden(true)
                        }
                        Text(row.shareText)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .width(min: 110, ideal: 150)
                TableColumn(L("Débit actuel")) { row in
                    Text(row.rate)
                        .font(.body.monospaced())
                }
                .width(min: 80, ideal: 95)
            }
            .scrollContentBackground(.hidden)
            .overlay {
                if model.rows.isEmpty {
                    emptyState
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard()
    }

    private var readingStatus: String {
        guard let last = model.lastReading else {
            return model.isConnected ? L("Aucun relevé pour l'instant") : ""
        }
        return L("Relevé toutes les \(model.pollSeconds) s · dernier à \(last.formatted(date: .omitted, time: .standard))")
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.isConnected, model.lastReading == nil {
            ContentUnavailableView(
                model.readingError == nil ? L("Relevé en cours…") : L("Aucun relevé reçu"),
                systemImage: "chart.bar",
                description: Text(model.readingError == nil
                    ? L("La box est interrogée.")
                    : L("La box est connectée mais n'a pas fourni de relevé. Le message ci-dessus en donne la raison ; « Copier le diagnostic » rassemble ses réponses."))
            )
        } else if model.isConnected, model.lastReadingCount == 0 {
            ContentUnavailableView(
                L("La box n'a rendu aucun appareil"),
                systemImage: "chart.bar",
                description: Text(L("Le relevé a réussi, mais il ne contient ni appareil Wi-Fi ni port Ethernet occupé. « Copier le diagnostic » rassemble les réponses de la box."))
            )
        } else if model.isConnected {
            ContentUnavailableView(
                model.period == .session ? L("Premier relevé pris") : L("Aucun volume sur cette période"),
                systemImage: "chart.bar",
                description: Text(model.period == .session
                    ? L("Les volumes apparaissent à partir du deuxième relevé : Pingouin compte ce qui passe entre deux relevés.")
                    : L("Rien n'a été relevé sur cette période. Seul ce qui passe pendant que Pingouin est ouvert est compté."))
            )
        } else {
            ContentUnavailableView(
                L("Aucune box connectée"),
                systemImage: "chart.bar",
                description: Text(L("Connecter une box pour relever la consommation de chaque appareil."))
            )
        }
    }

    // MARK: Colonne de droite

    private var source: some View {
        SectionCard(L("Source des mesures")) {
            switch model.connection {
            case .disconnected:
                StatusLabel(kind: .neutral, text: L("Aucune box connectée"))
                Button(L("Connecter une box")) {
                    model.isChoosingSource = true
                }
            case .connecting:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L("Recherche de la Freebox…"))
                }
                Button(L("Annuler")) {
                    model.cancelConnecting()
                }
            case .awaitingApproval:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L("En attente de votre accord sur la Freebox"))
                        .fontWeight(.semibold)
                }
                Text(L("La demande de Pingouin est affichée sur l'écran de la Freebox. La valider sur la box elle-même."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L("Annuler")) {
                    model.cancelConnecting()
                }
            case .connected(let boxName):
                StatusLabel(kind: .ok, text: L("\(boxName) · connectée"))
                Text("mafreebox.freebox.fr")
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                HStack {
                    Button(L("Copier le diagnostic")) {
                        model.copyDiagnostic()
                    }
                    .help(L("Copier les réponses brutes de la box (elles contiennent des noms d'appareils et des adresses MAC)"))
                    Button(L("Oublier l'accès…")) {
                        isAskingToForget = true
                    }
                }
                if let message = model.diagnosticMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .failed(let message):
                StatusLabel(kind: .failure, text: L("Connexion impossible"))
                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(L("Réessayer")) {
                        model.retry()
                    }
                    Button(L("Oublier l'accès…")) {
                        isAskingToForget = true
                    }
                }
            }
        }
    }

    private var capabilities: some View {
        SectionCard(L("Ce que la Freebox sait mesurer")) {
            StatusLabel(kind: .ok, text: L("Wi-Fi : par appareil"))
            StatusLabel(kind: .warning, text: L("Ethernet : par port de la box"))
            StatusLabel(kind: .failure, text: L("Appareils derrière une autre borne : listés, non mesurés"))
        }
    }

    private var limits: some View {
        SectionCard(L("Limites")) {
            Text(L("La box ne garde pas d'historique par appareil. Pingouin additionne les relevés tant qu'il est ouvert : ce qui est consommé pendant qu'il est fermé n'est pas compté. Un appareil qui se reconnecte remet son compteur à zéro côté box ; Pingouin en tient compte. Un répéteur ou un switch branché sur un port de la box est compté sur ce port, en plus de ses propres appareils Wi-Fi : le total peut alors compter deux fois le même trafic."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Feuille de choix de la source. Les sources que Pingouin ne sait pas encore interroger sont
/// listées comme telles, sans bouton.
private struct UsageSourcePicker: View {
    @Bindable var model: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Connecter une box"))
                .font(.title3.weight(.bold))
            Text(L("Les volumes par appareil viennent de la box : elle seule voit passer le trafic de tous les appareils."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(UsageSourceKind.allCases) { kind in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title)
                                .fontWeight(.semibold)
                                .foregroundStyle(kind.isSupported ? .primary : .secondary)
                            Text(kind.note)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if kind == .freebox {
                            Button(L("Connecter")) {
                                model.connectFreebox()
                            }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                    if kind != UsageSourceKind.allCases.last {
                        Divider()
                    }
                }
            }

            Text(L("Pour la Freebox : après « Connecter », la box affiche la demande sur son écran. Il faut être à côté d'elle pour la valider. L'accès est ensuite gardé dans le Trousseau de macOS."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(L("Fermer"), role: .cancel) {
                    model.isChoosingSource = false
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
