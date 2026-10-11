import Foundation

/// Connexion d'un onglet, telle que `sftp` peut la réutiliser.
///
/// Le navigateur de fichiers ne s'authentifie pas lui-même : il emprunte la connexion déjà ouverte
/// par le terminal de l'onglet (partage de connexion d'OpenSSH, « ControlMaster »). Le mot de passe
/// et la vérification de la clé d'hôte ne passent donc que par le terminal.
struct SFTPConnection: Sendable, Equatable {
    let destination: String
    let port: Int
    /// Point de rendez-vous créé par `ssh` une fois la session ouverte.
    let controlPath: String

    /// Vrai quand la session du terminal est ouverte et peut être partagée.
    var isOpen: Bool {
        FileManager.default.fileExists(atPath: controlPath)
    }

    /// Chemin court et unique pour le point de rendez-vous : il est limité à une centaine de caractères,
    /// et `ssh` y interprète le signe « % ».
    static func newControlPath() -> String {
        let name = "pingouin-" + UUID().uuidString.prefix(8).lowercased()
        let folder = NSTemporaryDirectory()
        let path = (folder as NSString).appendingPathComponent(name)
        if path.count <= 90, !path.contains("%"), !path.contains(where: \.isWhitespace) {
            return path
        }
        return "/tmp/" + name
    }

    /// Options à ajouter à la commande `ssh` du terminal pour qu'elle partage sa connexion.
    var sharingArguments: [String] {
        ["-o", "ControlMaster=auto", "-o", "ControlPath=\(controlPath)", "-o", "ControlPersist=no"]
    }

    /// Arguments de `sftp` pour exécuter des commandes lues sur son entrée, sans aucune question.
    var batchArguments: [String] {
        [
            "-o", "ControlMaster=no", "-o", "ControlPath=\(controlPath)", "-o", "BatchMode=yes",
            "-P", String(port), "-b", "-", "--", destination
        ]
    }
}

struct SFTPResult: Sendable {
    let status: Int32
    /// Sortie et messages d'erreur de `sftp`, dans l'ordre où ils sont arrivés.
    let output: String
    let wasCancelled: Bool

    var succeeded: Bool { status == 0 && !wasCancelled }

    /// Raison de l'échec, telle que `sftp` la donne (en anglais) : son dernier message,
    /// hors rappel des commandes exécutées.
    var failureText: String {
        let lines = output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("sftp> ") }
        return lines.last ?? "sftp s'est arrêté avec le code \(status)."
    }
}

/// Une exécution de `/usr/bin/sftp` : quelques commandes, puis le programme s'arrête.
/// Le chemin du programme est fixe ; les chemins de fichiers sont contrôlés par `SFTPPath` avant d'arriver ici.
final class SFTPJob: @unchecked Sendable {
    /// Écrire vers un programme déjà arrêté ne doit pas arrêter l'application (signal SIGPIPE).
    private static let ignoresBrokenPipe: Bool = {
        signal(SIGPIPE, SIG_IGN)
        return true
    }()

    private let process = Process()
    private let lock = NSLock()
    private var cancelled = false

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    /// Interrompt l'exécution. Sans effet si elle est déjà terminée.
    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
        if process.isRunning {
            process.terminate()
        }
    }

    func run(connection: SFTPConnection, commands: [String]) async -> SFTPResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: self.runBlocking(connection: connection, commands: commands))
            }
        }
    }

    private func runBlocking(connection: SFTPConnection, commands: [String]) -> SFTPResult {
        _ = Self.ignoresBrokenPipe
        guard !isCancelled else {
            return SFTPResult(status: -1, output: "", wasCancelled: true)
        }
        let input = Pipe()
        // Un seul tuyau pour la sortie et les erreurs : rien ne peut rester bloqué faute de lecteur.
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sftp")
        process.arguments = connection.batchArguments
        process.environment = Self.environment()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
        } catch {
            return SFTPResult(status: -1, output: error.localizedDescription, wasCancelled: false)
        }

        // Si `sftp` s'arrête avant d'avoir lu ses commandes, l'écriture échoue : c'est sa sortie,
        // lue juste après, qui dit pourquoi.
        let script = commands.joined(separator: "\n") + "\n"
        try? input.fileHandleForWriting.write(contentsOf: Data(script.utf8))
        try? input.fileHandleForWriting.close()

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return SFTPResult(
            status: process.terminationStatus,
            output: String(decoding: outputData, as: UTF8.self),
            wasCancelled: isCancelled
        )
    }

    /// Environnement minimal. `LC_CTYPE` garde les noms accentués lisibles ; les dates restent
    /// au format fixe attendu par `SFTPListing`, car `sftp` ne suit pas la langue pour elles.
    private static func environment() -> [String: String] {
        let current = ProcessInfo.processInfo.environment
        var result = ["LC_CTYPE": "en_US.UTF-8"]
        for key in ["HOME", "USER", "LOGNAME", "PATH", "SSH_AUTH_SOCK", "TMPDIR"] {
            if let value = current[key] {
                result[key] = value
            }
        }
        return result
    }
}
