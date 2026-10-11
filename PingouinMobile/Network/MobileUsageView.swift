import SwiftUI
import PingouinCore

/// Consommation par appareil sur iPhone et iPad, relevée sur la box tant que Pingouin est à l'écran.
struct MobileUsageView: View {
    @Bindable var model: UsageViewModel
    @State private var isAskingToForget = false

    var body: some View {
        MobilePage(L("Consommation")) {
            source
            HStack(spacing: 10) {
                StatTile(label: L("Reçu par les appareils"), value: model.totalReceived)
                StatTile(label: L("Envoyé par les appareils"), value: model.totalSent)
            }
            HStack(spacing: 10) {
                StatTile(label: L("Appareils mesurés"), value: model.measuredCount.formatted())
                StatTile(label: L("Débit en ce moment"), value: model.currentRate)
            }
            devices
            capabilities
            MobileFootnote(text: L("La box ne garde pas d'historique par appareil. Pingouin additionne les relevés tant qu'il est à l'écran : ce qui est consommé le reste du temps n'est pas compté. Un répéteur ou un switch branché sur un port de la box est compté sur ce port, en plus de ses propres appareils Wi-Fi : le total peut alors compter deux fois le même trafic."))
        }
        .toolbar {
            MobileCopyItem(title: L("Copier le tableau"), isDisabled: model.rows.isEmpty) {
                model.rowsAsText
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.refreshNow()
                } label: {
                    Label(L("Actualiser"), systemImage: "arrow.clockwise")
                }
                .disabled(!model.isConnected || model.isRefreshing)
            }
        }
        .sheet(isPresented: $model.isChoosingSource) {
            MobileUsageSourcePicker(model: model)
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

    // MARK: Source

    private var source: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Source des mesures"))
                .font(.headline)
            switch model.connection {
            case .disconnected:
                StatusLabel(kind: .neutral, text: L("Aucune box connectée"))
                Button(L("Connecter une box")) {
                    model.isChoosingSource = true
                }
                .buttonStyle(.borderedProminent)
            case .connecting:
                HStack(spacing: 8) {
                    ProgressView()
                    Text(L("Recherche de la Freebox…"))
                }
                Button(L("Annuler")) {
                    model.cancelConnecting()
                }
                .buttonStyle(.bordered)
            case .awaitingApproval:
                HStack(spacing: 8) {
                    ProgressView()
                    Text(L("En attente de votre accord sur la Freebox"))
                        .fontWeight(.semibold)
                }
                Text(L("La demande de Pingouin est affichée sur l'écran de la Freebox. La valider sur la box elle-même."))
                    .foregroundStyle(.secondary)
                Button(L("Annuler")) {
                    model.cancelConnecting()
                }
                .buttonStyle(.bordered)
            case .connected(let boxName):
                StatusLabel(kind: .ok, text: L("\(boxName) · connectée"))
                Text(readingStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(L("Copier le diagnostic")) {
                        model.copyDiagnostic()
                    }
                    Button(L("Oublier l'accès…")) {
                        isAskingToForget = true
                    }
                }
                .buttonStyle(.bordered)
                if let message = model.diagnosticMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .failed(let message):
                StatusLabel(kind: .failure, text: L("Connexion impossible"))
                Text(message)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(L("Réessayer")) {
                        model.retry()
                    }
                    Button(L("Oublier l'accès…")) {
                        isAskingToForget = true
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .glassCardPadded(cornerRadius: 22)
    }

    private var readingStatus: String {
        guard let last = model.lastReading else {
            return L("Aucun relevé pour l'instant")
        }
        return L("Relevé toutes les \(model.pollSeconds) s · dernier à \(last.formatted(date: .omitted, time: .standard))")
    }

    // MARK: Par appareil

    private var devices: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L("Par appareil"))
                    .font(.headline)
                Spacer()
                Picker(L("Période"), selection: $model.period) {
                    ForEach(UsagePeriod.allCases) { period in
                        Text(period.title).tag(period)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            if let error = model.readingError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .padding(.vertical, 6)
            }
            if model.rows.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Divider()
                    }
                    deviceRow(row)
                }
            }
        }
        .glassCardPadded(cornerRadius: 22)
    }

    private func deviceRow(_ row: UsageRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.name)
                    .fontWeight(row.isMember ? .regular : .semibold)
                    .foregroundStyle(row.isPresent ? Color.primary : Color.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(row.link)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !row.detail.isEmpty {
                Text(row.detail)
                    .font(.footnote)
                    .fontDesign(row.isShared ? .default : .monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !row.isMember {
                ProgressView(value: row.share)
                    .accessibilityHidden(true)
                HStack(spacing: 12) {
                    Label(row.received, systemImage: "arrow.down")
                    Label(row.sent, systemImage: "arrow.up")
                    Spacer(minLength: 0)
                    Text(row.shareText)
                        .foregroundStyle(.secondary)
                    Text(row.rate)
                }
                .font(.footnote.monospaced())
            }
        }
        .padding(.vertical, 8)
        // Les appareils d'un port partagé sont en retrait sous la ligne du port.
        .padding(.leading, row.isMember ? 18 : 0)
        .accessibilityElement(children: .combine)
    }

    private var emptyText: String {
        if model.isConnected, model.lastReading == nil {
            return model.readingError == nil
                ? L("La box est interrogée.")
                : L("La box est connectée mais n'a pas fourni de relevé. Le message ci-dessus en donne la raison ; « Copier le diagnostic » rassemble ses réponses.")
        }
        if model.isConnected, model.lastReadingCount == 0 {
            return L("Le relevé a réussi, mais il ne contient ni appareil Wi-Fi ni port Ethernet occupé. « Copier le diagnostic » rassemble les réponses de la box.")
        }
        if model.isConnected {
            return model.period == .session
                ? L("Les volumes apparaissent à partir du deuxième relevé : Pingouin compte ce qui passe entre deux relevés.")
                : L("Rien n'a été relevé sur cette période. Seul ce qui passe pendant que Pingouin est ouvert est compté.")
        }
        return L("Connecter une box pour relever la consommation de chaque appareil.")
    }

    private var capabilities: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Ce que la Freebox sait mesurer"))
                .font(.headline)
            StatusLabel(kind: .ok, text: L("Wi-Fi : par appareil"))
            StatusLabel(kind: .warning, text: L("Ethernet : par port de la box"))
            StatusLabel(kind: .failure, text: L("Appareils derrière une autre borne : listés, non mesurés"))
        }
        .glassCardPadded(cornerRadius: 22)
    }
}

/// Feuille de choix de la source. Les sources que Pingouin ne sait pas encore interroger sont
/// listées comme telles, sans bouton.
private struct MobileUsageSourcePicker: View {
    @Bindable var model: UsageViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(UsageSourceKind.allCases) { kind in
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.title)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(kind.isSupported ? Color.primary : Color.secondary)
                                Text(kind.note)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            if kind == .freebox {
                                Button(L("Connecter")) {
                                    model.connectFreebox()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                } header: {
                    Text(L("Les volumes par appareil viennent de la box : elle seule voit passer le trafic de tous les appareils."))
                        .textCase(nil)
                } footer: {
                    Text(L("Pour la Freebox : après « Connecter », la box affiche la demande sur son écran. Il faut être à côté d'elle pour la valider. L'accès est ensuite gardé dans le Trousseau de l'appareil."))
                }
            }
            .navigationTitle(L("Connecter une box"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Fermer")) {
                        model.isChoosingSource = false
                    }
                }
            }
        }
    }
}
