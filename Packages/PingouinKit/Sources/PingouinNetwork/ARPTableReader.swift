import Foundation
import PingouinCore

public enum ARPTableError: Error, Equatable, Sendable {
    case commandFailed(status: Int32)
    /// Le système ne laisse pas lire cette table (iOS).
    case unavailableOnThisSystem
}

/// Lecture de la table ARP du système par l'outil `/usr/sbin/arp`.
///
/// Le chemin et les arguments sont fixes : aucune donnée saisie par l'utilisateur n'entre dans la commande.
/// L'option `-n` évite toute résolution de nom, donc tout délai lié au DNS.
struct ARPTableReader: Sendable {
    func read() throws -> [ARPEntry] {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
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
        return ARPTableParser.parse(String(decoding: data, as: UTF8.self))
        #else
        // iOS n'a ni commande `arp` ni accès à la table : la découverte se passe des adresses MAC.
        throw ARPTableError.unavailableOnThisSystem
        #endif
    }
}
