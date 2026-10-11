import SwiftUI

@main
struct PingouinApp: App {
    /// État partagé par la fenêtre principale et la fenêtre de réglages.
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 1000, minHeight: 560)
                .environment(app)
        }
        .defaultSize(width: 1180, height: 760)

        Settings {
            SettingsView()
                .environment(app)
        }
    }
}
