import SwiftUI
import PingouinCore

/// Clé Ed25519 de l'appareil : sa partie publique, à déposer sur les serveurs, et son remplacement.
struct MobileDeviceKeyView: View {
    @Bindable var model: MobileSSHViewModel
    @State private var isAskingToReplace = false
    @State private var sharedFile: SharedFile?

    var body: some View {
        MobilePage(L("Clé de cet appareil")) {
            if let line = model.deviceKeyLine {
                present(line)
                explanation
                replacement
            } else {
                absent
                explanation
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sharedFile) { file in
            MobileShareSheet(file: file)
        }
        .confirmationDialog(L("Remplacer la clé de cet appareil ?"), isPresented: $isAskingToReplace, titleVisibility: .visible) {
            Button(L("Remplacer la clé"), role: .destructive) {
                model.createDeviceKey()
            }
            Button(L("Annuler"), role: .cancel) {}
        } message: {
            Text(L("L'ancienne clé est détruite et ne peut pas être retrouvée. Les serveurs qui la connaissent refuseront la connexion tant que la nouvelle clé publique n'y aura pas été déposée."))
        }
        .onAppear {
            model.refreshDeviceKey()
        }
    }

    private func present(_ line: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusLabel(kind: .ok, text: L("Clé Ed25519 présente"))
                .fontWeight(.semibold)
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(L("Clé publique, à déposer sur les serveurs"))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            Text(line)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }
            if let fingerprint = OpenSSHPublicKey.fingerprint(ofLine: line) {
                Text(L("Empreinte : \(fingerprint)"))
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            HStack(spacing: 8) {
                Button {
                    Pasteboard.copy(line)
                } label: {
                    Text(L("Copier"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    sharedFile = TemporaryFile.write(Data((line + "\n").utf8), named: "pingouin-cle-publique.pub")
                } label: {
                    Text(L("Partager…"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .padding(.top, 4)
        }
        .glassCardPadded(cornerRadius: 22)
    }

    private var summary: String {
        let usage = L(
            count: model.deviceKeyUsageCount,
            one: "utilisée par \(model.deviceKeyUsageCount) connexion",
            other: "utilisée par \(model.deviceKeyUsageCount) connexions"
        )
        guard let date = model.deviceKeyCreatedAt else { return usage }
        return L("Créée le \(date.formatted(date: .long, time: .omitted))") + " · " + usage
    }

    private var absent: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusLabel(kind: .neutral, text: L("Aucune clé pour l'instant"))
                .fontWeight(.semibold)
            Text(L("Une clé permet de se connecter sans mot de passe aux serveurs qui la connaissent. Elle est créée sur cet appareil et n'en sort pas."))
                .foregroundStyle(.secondary)
            Button {
                model.createDeviceKey()
            } label: {
                Text(L("Créer la clé de cet appareil"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            if let message = model.deviceKeyMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
        .glassCardPadded(cornerRadius: 22)
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Où est la clé privée"))
                .font(.headline)
            Text(L("Dans le Trousseau de cet appareil, et nulle part ailleurs : elle n'est ni affichée, ni exportée, ni synchronisée avec iCloud. Seule la clé publique se partage."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .glassCardPadded(cornerRadius: 22)
    }

    private var replacement: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Remplacer la clé"))
                .font(.headline)
            Text(L("Une nouvelle clé est créée et l'ancienne est détruite. Les serveurs qui connaissent l'ancienne refuseront la connexion tant que la nouvelle clé publique n'y aura pas été déposée."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(L("Remplacer la clé…"), role: .destructive) {
                isAskingToReplace = true
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
            if let message = model.deviceKeyMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
        .glassCardPadded(cornerRadius: 22)
    }
}

/// Réglages de SSH : apparence du terminal et hôtes connus.
struct MobileSSHSettingsSection: View {
    let model: MobileSSHViewModel

    var body: some View {
        Section {
            Picker(L("Thème par défaut"), selection: Binding(
                get: { model.defaultThemeID },
                set: { model.setDefaultTheme($0) }
            )) {
                ForEach(TerminalTheme.all) { theme in
                    Text(theme.name).tag(theme.id)
                }
            }
            Stepper(
                L("Taille du texte : \(Int(model.fontSize)) points"),
                value: Binding(
                    get: { model.fontSize },
                    set: { model.setFontSize($0) }
                ),
                in: MobileSSHViewModel.fontSizeRange,
                step: 1
            )
            NavigationLink {
                MobileKnownHostsView(model: model)
            } label: {
                LabeledContent(L("Hôtes connus"), value: model.knownHosts.hosts.count.formatted())
            }
        } header: {
            Text(verbatim: "SSH")
        }
    }
}

/// Serveurs dont la clé a été acceptée. En retirer un fait redemander l'accord à la prochaine connexion.
struct MobileKnownHostsView: View {
    let model: MobileSSHViewModel

    var body: some View {
        List {
            Section {
                ForEach(model.knownHosts.hosts) { host in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: host.port == 22 ? host.host : "\(host.host):\(host.port)")
                            .font(.body.monospaced())
                        Text(OpenSSHPublicKey.fingerprint(ofLine: host.keyLine) ?? "—")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text(L("\(OpenSSHPublicKey.keyType(ofLine: host.keyLine) ?? "—") · acceptée le \(host.addedAt.formatted(date: .abbreviated, time: .shortened))"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button(L("Oublier"), role: .destructive) {
                            model.forget(host)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            } footer: {
                Text(model.knownHosts.hosts.isEmpty
                    ? L("Aucun hôte connu : la clé de chaque serveur est demandée à sa première connexion.")
                    : L("Balayer une ligne vers la gauche pour oublier un hôte : sa clé sera redemandée à la prochaine connexion. C'est le seul moyen d'accepter un serveur dont la clé a changé."))
            }
        }
        .navigationTitle(L("Hôtes connus"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
