import Foundation

/// Couleurs et taille du texte du terminal.
extension SSHViewModel {
    /// Applique un thème à la session en cours, et l'enregistre : sur le profil connecté s'il y en a un,
    /// sinon comme thème par défaut.
    func chooseTheme(_ id: String) {
        let theme = TerminalTheme.named(id)
        if let profileID = session?.profileID ?? selectedProfileID,
           let index = profiles.firstIndex(where: { $0.id == profileID }) {
            profiles[index].themeID = theme.id
            store.save(profiles)
        } else {
            defaultThemeID = theme.id
            UserDefaults.standard.set(theme.id, forKey: Self.defaultThemeKey)
        }
        session?.themeID = theme.id
        session?.terminal.apply(theme: theme, fontSize: fontSize)
    }

    /// Choisit le thème par défaut des connexions qui n'ont pas le leur.
    func setDefaultTheme(_ id: String) {
        defaultThemeID = TerminalTheme.named(id).id
        UserDefaults.standard.set(defaultThemeID, forKey: Self.defaultThemeKey)
    }

    /// Fait du thème affiché le thème par défaut des nouvelles connexions.
    func makeCurrentThemeDefault() {
        defaultThemeID = currentTheme.id
        UserDefaults.standard.set(defaultThemeID, forKey: Self.defaultThemeKey)
    }

    func setFontSize(_ size: Double) {
        fontSize = min(max(size, 9), 24)
        UserDefaults.standard.set(fontSize, forKey: Self.fontSizeKey)
        for session in sessions {
            session.terminal.apply(theme: TerminalTheme.named(session.themeID), fontSize: fontSize)
        }
    }
}
