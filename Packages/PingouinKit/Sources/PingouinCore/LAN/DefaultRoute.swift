import Foundation

/// Route par défaut du système : la passerelle vers Internet et l'interface qui y mène.
public struct DefaultRoute: Hashable, Sendable {
    public let gateway: String
    public let interfaceName: String

    public init(gateway: String, interfaceName: String) {
        self.gateway = gateway
        self.interfaceName = interfaceName
    }
}

/// Lecture de la sortie de `route -n get default`, dont les lignes utiles ont la forme
/// `    gateway: 192.168.1.254` et `  interface: en0`.
public enum DefaultRouteParser {
    public static func parse(_ output: String) -> DefaultRoute? {
        var gateway: String?
        var interfaceName: String?
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[1].isEmpty else { continue }
            switch parts[0] {
            case "gateway": gateway = parts[1]
            case "interface": interfaceName = parts[1]
            default: break
            }
        }
        guard let gateway, let interfaceName else { return nil }
        return DefaultRoute(gateway: gateway, interfaceName: interfaceName)
    }
}
