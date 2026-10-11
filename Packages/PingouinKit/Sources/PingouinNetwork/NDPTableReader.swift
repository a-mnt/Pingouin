import Foundation
import PingouinCore

/// Lecture de la table des voisins IPv6 du système par l'outil `/usr/sbin/ndp`.
///
/// Le chemin et les arguments sont fixes : aucune donnée saisie par l'utilisateur n'entre dans la commande.
/// L'option `-n` évite toute résolution de nom.
struct NDPTableReader: Sendable {
    func read() throws -> [NDPEntry] {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ndp")
        process.arguments = ["-an"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ARPTableError.commandFailed(status: process.terminationStatus)
        }
        return NDPTableParser.parse(String(decoding: data, as: UTF8.self))
        #else
        throw ARPTableError.unavailableOnThisSystem
        #endif
    }
}

/// Sollicitation des voisins IPv6 d'une interface, pour remplir la table des voisins avant de la lire.
enum IPv6NeighborProbe {
    /// Envoie un ping à l'adresse « tous les nœuds » (ff02::1) de l'interface, puis laisse aux réponses
    /// le temps d'arriver. Appel **bloquant**. Renvoie faux si rien n'a pu partir : la table est alors
    /// lue telle quelle, avec les seuls voisins déjà connus du système.
    @discardableResult
    static func solicit(interfaceName: String, waitSeconds: Double, isCancelled: () -> Bool) -> Bool {
        let index = if_nametoindex(interfaceName)
        guard index != 0, let socket = try? ICMPSocket(ipv6: true) else { return false }
        // ff02::1
        let allNodes = IPAddressV6(rawValue: (UInt128(0xFF02) << 112) | 1)
        let target = ICMPTarget(address: .v6(allNodes), scopeID: index)
        guard socket.sendEcho(to: target, sequence: 1) == 0 else { return false }

        let deadline = monotonicMilliseconds() + waitSeconds * 1_000
        while monotonicMilliseconds() < deadline, !isCancelled() {
            // Les réponses ne sont pas exploitées ici : c'est la table des voisins qui fait foi.
            _ = socket.receive(waitMilliseconds: 100)
        }
        return true
    }
}
