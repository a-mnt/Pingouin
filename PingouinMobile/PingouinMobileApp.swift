import SwiftUI

/// Application iOS et iPadOS. Elle partage avec la version Mac le paquet PingouinKit, les modèles de
/// présentation du dossier `Shared`, les composants de `DesignSystem` et le catalogue de traductions.
@main
struct PingouinMobileApp: App {
    @State private var state = MobileAppState()

    var body: some Scene {
        WindowGroup {
            MobileRootView()
                .environment(state)
        }
    }
}
