import AppKit
import SwiftUI
import PingouinCore

struct SSHView: View {
    @Bindable var model: SSHViewModel
    @State private var pendingRemoval: UUID?
    @State private var isAskingWhatToAdd = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            profiles
                .frame(width: 250)
            VStack(alignment: .leading, spacing: 14) {
                header
                if !model.sessions.isEmpty {
                    tabs
                }
                content
                Text(L("La vérification de la clé d'hôte est celle d'OpenSSH : une clé inconnue demande votre accord dans le terminal, une clé modifiée bloque la connexion. Un mot de passe n'est enregistré que si vous le saisissez dans la fiche d'une connexion ; il est alors gardé dans le Trousseau de macOS. Les fichiers passent par la connexion ouverte dans le terminal de l'onglet."))
                    .footnoteStyle()
            }
        }
        .toolPage("SSH")
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker(L("Thème"), selection: Binding(
                        get: { model.currentTheme.id },
                        set: { model.chooseTheme($0) }
                    )) {
                        ForEach(TerminalTheme.all) { theme in
                            Text(theme.name).tag(theme.id)
                        }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Button(L("Utiliser ce thème par défaut")) {
                        model.makeCurrentThemeDefault()
                    }
                    Divider()
                    Button(L("Agrandir le texte")) {
                        model.setFontSize(model.fontSize + 1)
                    }
                    Button(L("Réduire le texte")) {
                        model.setFontSize(model.fontSize - 1)
                    }
                } label: {
                    Label(L("Couleurs"), systemImage: "paintpalette")
                }
                .help(L("Choisir les couleurs et la taille du texte du terminal"))
            }
            ToolbarItem {
                Button(L("Déconnecter")) {
                    model.disconnect()
                }
                .disabled(model.session?.isActive != true)
                .help(L("Mettre fin à la session de l'onglet affiché"))
            }
            ToolbarItem(placement: .primaryAction) {
                Button(L("Se connecter")) {
                    if let id = model.selectedProfileID {
                        model.connect(id)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedProfile == nil)
                .help(L("Ouvrir la connexion choisie dans son onglet, ou la relancer si elle est terminée"))
            }
        }
        .sheet(isPresented: $model.isEditing) {
            SSHProfileEditor(model: model)
        }
        .confirmationDialog(
            L("Supprimer cette connexion enregistrée ?"),
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { isPresented in
                    if !isPresented { pendingRemoval = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(L("Supprimer"), role: .destructive) {
                if let id = pendingRemoval {
                    model.remove(id)
                }
                pendingRemoval = nil
            }
            Button(L("Annuler"), role: .cancel) {
                pendingRemoval = nil
            }
        }
    }

    // MARK: Connexions enregistrées

    private var profiles: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L("Connexions"))
                    .font(.headline)
                Spacer()
                Button {
                    // Session ouverte sans connexion enregistrée : on demande quoi ajouter.
                    if model.canSaveCurrentSession {
                        isAskingWhatToAdd = true
                    } else {
                        model.beginAdding()
                    }
                } label: {
                    Label(L("Ajouter une connexion"), systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .help(L("Enregistrer la connexion en cours ou en créer une nouvelle"))
                .confirmationDialog(
                    L("Enregistrer la connexion en cours ?"),
                    isPresented: $isAskingWhatToAdd,
                    titleVisibility: .visible
                ) {
                    Button(L("Enregistrer la connexion en cours")) {
                        model.beginSavingCurrentSession()
                    }
                    Button(L("Créer une nouvelle connexion")) {
                        model.beginAdding()
                    }
                    Button(L("Annuler"), role: .cancel) {}
                } message: {
                    Text(L("La session vers \(model.session?.target ?? "") n'est pas dans vos connexions enregistrées."))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            List(selection: $model.selectedProfileID) {
                ForEach(model.profiles) { profile in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(profile.displayName)
                            .fontWeight(.semibold)
                        Text(profile.summary)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .tag(profile.id)
                }
            }
            // Le double-clic sur une connexion l'ouvre, ou revient à son onglet si elle est déjà ouverte.
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let id = ids.first {
                    Button(L("Se connecter")) {
                        model.connect(id)
                    }
                    Button(L("Parcourir les fichiers")) {
                        model.connect(id, pane: .files)
                    }
                    Divider()
                    Button(L("Modifier…")) {
                        model.beginEditing(id)
                    }
                    Button(L("Dupliquer")) {
                        model.duplicate(id)
                    }
                    Divider()
                    Button(L("Supprimer…"), role: .destructive) {
                        pendingRemoval = id
                    }
                }
            } primaryAction: { ids in
                if let id = ids.first {
                    model.connect(id)
                }
            }
            .scrollContentBackground(.hidden)
            .overlay {
                if model.profiles.isEmpty {
                    ContentUnavailableView(
                        L("Aucune connexion"),
                        systemImage: "terminal",
                        description: Text(L("Enregistrer une connexion avec le bouton +."))
                    )
                }
            }
        }
        .frame(maxHeight: .infinity)
        .glassCard()
    }

    // MARK: Session

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            if let session = model.session {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.title3.weight(.bold))
                    StatusLabel(
                        kind: session.isActive ? .ok : .neutral,
                        text: session.endMessage ?? L("Session ouverte vers \(session.target)")
                    )
                }
            } else if let profile = model.selectedProfile {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName)
                        .font(.title3.weight(.bold))
                    Text(profile.summary)
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(L("Choisir ou créer une connexion."))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let session = model.session {
                // Un seul onglet par machine : il montre au choix son terminal ou ses fichiers.
                Picker(L("Affichage de l'onglet"), selection: Binding(
                    get: { session.pane },
                    set: { model.showPane($0) }
                )) {
                    Text(L("Terminal")).tag(SSHPane.terminal)
                    Text(L("Fichiers")).tag(SSHPane.files)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help(L("Afficher le terminal ou les fichiers de cette machine"))
            }
            if let id = model.selectedProfileID {
                Button(L("Modifier…")) {
                    model.beginEditing(id)
                }
            }
        }
        .glassCardPadded()
    }

    // MARK: Onglets

    private var tabs: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.sessions) { session in
                        tab(session)
                    }
                }
                .padding(.horizontal, 2)
            }
            if let message = model.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
            }
        }
    }

    private func tab(_ session: SSHSession) -> some View {
        let isSelected = session.id == model.selectedSessionID
        return HStack(spacing: 6) {
            Button {
                model.selectedSessionID = session.id
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(session.isActive ? Color.green : Color.secondary)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(session.title)
                        .lineLimit(1)
                        .fontWeight(isSelected ? .semibold : .regular)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(session.title), \(session.isActive ? L("session ouverte") : L("session terminée"))")
            Button {
                model.closeSession(session.id)
            } label: {
                Label(L("Fermer l'onglet"), systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .font(.caption.weight(.bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(session.isActive ? L("Mettre fin à la session et fermer l'onglet") : L("Fermer l'onglet"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: 220)
        .background {
            Capsule()
                .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.08))
        }
        .overlay {
            Capsule()
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
        }
    }

    /// Contenu de l'onglet affiché : son terminal ou ses fichiers.
    @ViewBuilder
    private var content: some View {
        if let session = model.session, session.pane == .files {
            SFTPBrowserView(
                browser: session.files,
                isSessionActive: session.isActive,
                showTerminal: { model.showPane(.terminal) },
                reconnect: { model.reconnectCurrentSession() }
            )
            .id(session.id)
        } else {
            terminal
        }
    }

    private var terminal: some View {
        let theme = model.currentTheme
        return ZStack {
            Color(nsColor: theme.backgroundColor)
            if !model.terminalIsAvailable {
                placeholder(
                    L("Terminal intégré indisponible"),
                    L("La bibliothèque SwiftTerm n'a pas été chargée. Dans Xcode : File > Packages > Resolve Package Versions."),
                    theme: theme
                )
            } else if let session = model.session {
                // Un terminal par onglet : l'identité de la vue suit la session affichée.
                TerminalHostView(controller: session.terminal, sessionNumber: session.terminal.sessionNumber)
                    .id(session.id)
                    .padding(10)
            } else {
                placeholder(
                    model.message ?? L("Aucune session"),
                    L("Double-cliquer sur une connexion, ou faire un clic droit sur un hôte dans un autre outil."),
                    theme: theme
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func placeholder(_ title: String, _ detail: String, theme: TerminalTheme) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(detail)
                .multilineTextAlignment(.center)
                .opacity(0.8)
        }
        .foregroundStyle(Color(nsColor: theme.foregroundColor))
        .padding(30)
    }
}
