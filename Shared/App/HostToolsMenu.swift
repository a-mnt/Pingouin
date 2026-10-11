import SwiftUI
import PingouinCore

/// Entrées de menu « lancer un outil sur cet hôte », communes aux menus contextuels de l'application.
///
/// Sur le Mac, un outil qui n'est pas encore développé apparaît grisé. L'action est fournie par la vue appelante
/// plutôt que lue dans l'environnement : le contenu d'un menu contextuel n'en hérite pas toujours.
struct HostToolsMenu: View {
    let address: String
    let open: (AppModule, String) -> Void

    /// Sur iOS, un outil absent n'est pas proposé du tout.
    private static var tools: [AppModule] {
        let all: [AppModule] = [.ping, .traceroute, .portScanner, .dns, .ssh]
        #if os(macOS)
        return all
        #else
        return all.filter(\.isAvailable)
        #endif
    }

    var body: some View {
        ForEach(Self.tools) { module in
            Button(Self.title(for: module)) {
                open(module, address)
            }
            .disabled(!module.isAvailable)
        }
    }

    private static func title(for module: AppModule) -> String {
        switch module {
        case .dns: L("Recherche DNS inverse")
        case .ssh: L("Connexion SSH")
        default: module.title
        }
    }
}
