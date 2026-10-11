import CPingouinSystem
import Foundation
import PingouinCore

/// Lecture de la route par défaut : par l'outil `/sbin/route` sur macOS, dans la table de routage
/// du noyau sur iOS, qui n'a pas cette commande.
///
/// Le chemin et les arguments sont fixes : aucune donnée saisie par l'utilisateur n'entre dans la commande.
/// Rien n'est envoyé sur le réseau : seule la table de routage de l'appareil est lue.
public enum DefaultRouteReader {
    /// Appel **bloquant**, bref. `nil` si le Mac n'a pas de route par défaut (aucun réseau) ou si la lecture échoue.
    public static func read() -> DefaultRoute? {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/route")
        process.arguments = ["-n", "get", "default"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return DefaultRouteParser.parse(String(decoding: data, as: UTF8.self))
        #else
        return readFromKernel()
        #endif
    }

    /// Passerelle IPv4 de la route par défaut, lue par `sysctl`. `nil` sans réseau (ou en cellulaire seul,
    /// où la liaison n'a pas de passerelle).
    public static func readFromKernel() -> DefaultRoute? {
        var gateway = [CChar](repeating: 0, count: 64)
        var interfaceName = [CChar](repeating: 0, count: 64)
        guard pingouin_default_gateway(&gateway, gateway.count, &interfaceName, interfaceName.count) == 1 else { return nil }
        let address = CText.string(gateway)
        guard !address.isEmpty else { return nil }
        return DefaultRoute(gateway: address, interfaceName: CText.string(interfaceName))
    }
}

/// Lecture d'un texte écrit par une fonction C dans un tampon terminé par un zéro.
enum CText {
    static func string(_ buffer: [CChar]) -> String {
        String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
