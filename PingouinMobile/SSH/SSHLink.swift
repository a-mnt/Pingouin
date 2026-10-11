@preconcurrency import Citadel
import CryptoKit
import Foundation
import NIOCore
@preconcurrency import NIOSSH
import PingouinCore

/// De quoi s'authentifier, déjà lu dans le Trousseau ou saisi. Jamais journalisé.
enum SSHCredential: Sendable {
    case password(String)
    /// Clé privée Ed25519 de l'appareil, sous sa forme brute de 32 octets.
    case deviceKey(Data)
}

/// Issue d'une tentative de connexion, quand elle n'est pas une erreur.
enum SSHConnectOutcome: Sendable {
    case connected
    /// Première connexion : le serveur a présenté cette clé, que personne n'a encore acceptée.
    case unknownHost(keyLine: String)
    /// Le serveur est connu sous une autre clé : la connexion a été refusée.
    case changedHost(presentedKeyLine: String)
}

enum SSHLinkError: Error {
    case notConnected
    case invalidDeviceKey
}

/// Erreur rendue à la bibliothèque quand la clé du serveur n'est pas celle attendue.
struct HostKeyRefused: Error {}

/// Contrôle de la clé du serveur pendant la négociation. Il n'accepte que la clé attendue ;
/// dans tous les cas, il retient la clé présentée pour pouvoir la montrer à l'utilisateur.
final class HostKeyProbe: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let expectedKeyLine: String?
    private var presented: String?
    private var accepted = false

    init(expectedKeyLine: String?) {
        self.expectedKeyLine = expectedKeyLine
    }

    /// Clé présentée par le serveur, s'il en a présenté une, et si elle a été acceptée.
    var result: (keyLine: String?, accepted: Bool) {
        lock.withLock { (presented, accepted) }
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let line = String(openSSHPublicKey: hostKey)
        let isExpected = expectedKeyLine.map { OpenSSHPublicKey.isSameKey($0, line) } ?? false
        lock.withLock {
            presented = line
            accepted = isExpected
        }
        if isExpected {
            validationCompletePromise.succeed(())
        } else {
            validationCompletePromise.fail(HostKeyRefused())
        }
    }
}

/// Une connexion SSH : la session, son terminal et son canal SFTP.
///
/// Toute la bibliothèque Citadel est enfermée ici. Ses objets ne sont pas faits pour passer d'un
/// fil d'exécution à l'autre : ils ne sortent jamais de cette classe, qui n'échange avec le reste
/// de l'application que des valeurs simples (textes, octets, entrées de dossier).
final class SSHLink: @unchecked Sendable {
    private enum Command: Sendable {
        case data([UInt8])
        case resize(columns: Int, rows: Int)
    }

    /// Taille des blocs lus et écrits en SFTP. Au-delà de 32 000 octets, un message ne tient plus
    /// dans un paquet du canal SSH.
    private static let chunkSize = 32_000

    private let lock = NSLock()
    private var client: SSHClient?
    private var sftp: SFTPClient?
    private var writer: TTYStdinWriter?
    private let commands: AsyncStream<Command>
    private let commandInput: AsyncStream<Command>.Continuation

    init() {
        let pipe = AsyncStream<Command>.makeStream()
        commands = pipe.stream
        commandInput = pipe.continuation
    }

    // MARK: Connexion

    /// Ouvre la connexion et s'authentifie. La clé du serveur n'est acceptée que si elle est
    /// celle de `expectedKeyLine` ; sinon l'issue dit pourquoi, sans erreur.
    func connect(
        host: String,
        port: Int,
        user: String,
        credential: SSHCredential,
        expectedKeyLine: String?
    ) async throws -> SSHConnectOutcome {
        let method: SSHAuthenticationMethod
        switch credential {
        case .password(let password):
            method = .passwordBased(username: user, password: password)
        case .deviceKey(let raw):
            guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
                throw SSHLinkError.invalidDeviceKey
            }
            method = .ed25519(username: user, privateKey: key)
        }
        let probe = HostKeyProbe(expectedKeyLine: expectedKeyLine)
        do {
            let opened = try await SSHClient.connect(
                host: host,
                port: port,
                authenticationMethod: method,
                hostKeyValidator: .custom(probe),
                reconnect: .never,
                connectTimeout: .seconds(15)
            )
            lock.withLock { client = opened }
            return .connected
        } catch {
            let seen = probe.result
            if let keyLine = seen.keyLine, !seen.accepted {
                return expectedKeyLine == nil ? .unknownHost(keyLine: keyLine) : .changedHost(presentedKeyLine: keyLine)
            }
            throw error
        }
    }

    /// Ferme le terminal, le canal SFTP et la connexion. Sans effet si tout est déjà fermé.
    func close() async {
        commandInput.finish()
        let (openClient, openSFTP) = lock.withLock { () -> (SSHClient?, SFTPClient?) in
            let pair = (client, sftp)
            client = nil
            sftp = nil
            writer = nil
            return pair
        }
        try? await openSFTP?.close()
        try? await openClient?.close()
    }

    // MARK: Terminal

    /// Ouvre un terminal interactif et ne rend la main qu'à sa fermeture (fin du shell distant,
    /// coupure, ou appel de `close`). Chaque bloc reçu est remis à `onOutput`, dans l'ordre.
    func runShell(columns: Int, rows: Int, onOutput: @escaping @MainActor @Sendable ([UInt8]) -> Void) async throws {
        guard let client = lock.withLock({ client }) else { throw SSHLinkError.notConnected }
        let request = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: "xterm-256color",
            terminalCharacterWidth: max(columns, 20),
            terminalRowHeight: max(rows, 5),
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: SSHTerminalModes([:])
        )
        // Les frappes sont transmises par une seule tâche, pour arriver dans l'ordre où elles ont été faites.
        let pump = Task { [commands] in
            for await command in commands {
                await self.perform(command)
            }
        }
        defer {
            pump.cancel()
            lock.withLock { writer = nil }
        }
        try await client.withPTY(request) { inbound, outbound in
            self.lock.withLock { self.writer = outbound }
            for try await chunk in inbound {
                switch chunk {
                case .stdout(let buffer), .stderr(let buffer):
                    await onOutput(Array(buffer.readableBytesView))
                }
            }
        }
    }

    /// Envoie des frappes au terminal. Sans attente : elles sont mises en file.
    func send(_ bytes: [UInt8]) {
        commandInput.yield(.data(bytes))
    }

    /// Annonce au serveur la nouvelle taille du terminal.
    func resize(columns: Int, rows: Int) {
        commandInput.yield(.resize(columns: columns, rows: rows))
    }

    private func perform(_ command: Command) async {
        guard let writer = lock.withLock({ writer }) else { return }
        switch command {
        case .data(let bytes):
            try? await writer.write(ByteBuffer(bytes: bytes))
        case .resize(let columns, let rows):
            try? await writer.changeSize(cols: columns, rows: rows, pixelWidth: 0, pixelHeight: 0)
        }
    }

    // MARK: Fichiers

    private func files() async throws -> SFTPClient {
        if let open = lock.withLock({ sftp }), open.isActive {
            return open
        }
        guard let client = lock.withLock({ client }) else { throw SSHLinkError.notConnected }
        let opened = try await client.openSFTP()
        lock.withLock { sftp = opened }
        return opened
    }

    /// Dossier d'arrivée de la session, en chemin absolu.
    func homeDirectory() async throws -> String {
        try await files().getRealPath(atPath: ".")
    }

    /// Contenu d'un dossier, dossiers d'abord puis par nom, sans « . » ni « .. ».
    func list(_ path: String) async throws -> [SFTPEntry] {
        let answers = try await files().listDirectory(atPath: path)
        var entries: [SFTPEntry] = []
        for answer in answers {
            for component in answer.components where component.filename != "." && component.filename != ".." {
                let attributes = component.attributes
                entries.append(SFTPEntry(
                    name: component.filename,
                    kind: SFTPMode.kind(mode: attributes.permissions),
                    size: attributes.size ?? 0,
                    modified: attributes.accessModificationTime?.modificationTime,
                    permissions: SFTPMode.permissionText(mode: attributes.permissions)
                ))
            }
        }
        return SFTPListing.sorted(entries)
    }

    func makeDirectory(_ path: String) async throws {
        try await files().createDirectory(atPath: path)
    }

    func rename(_ path: String, to newPath: String) async throws {
        try await files().rename(at: path, to: newPath)
    }

    /// Supprime un fichier, un lien, ou un dossier vide : le serveur refuse un dossier qui ne l'est pas.
    func remove(_ path: String, isDirectory: Bool) async throws {
        if isDirectory {
            try await files().rmdir(at: path)
        } else {
            try await files().remove(at: path)
        }
    }

    /// Télécharge un fichier dans `localURL`. En cas d'échec ou d'annulation, le fichier partiel est supprimé.
    func download(_ remotePath: String, to localURL: URL, progress: @escaping @MainActor @Sendable (UInt64) -> Void) async throws {
        let file = try await files().openFile(filePath: remotePath, flags: .read)
        var offset: UInt64 = 0
        do {
            FileManager.default.createFile(atPath: localURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: localURL)
            defer { try? handle.close() }
            while true {
                try Task.checkCancellation()
                let chunk = try await file.read(from: offset, length: UInt32(Self.chunkSize))
                if chunk.readableBytes == 0 { break }
                try handle.write(contentsOf: Data(chunk.readableBytesView))
                offset += UInt64(chunk.readableBytes)
                await progress(offset)
            }
        } catch {
            try? await file.close()
            try? FileManager.default.removeItem(at: localURL)
            throw error
        }
        try await file.close()
    }

    /// Envoie un fichier local vers `remotePath`, en remplaçant le fichier distant s'il existe.
    func upload(_ localURL: URL, to remotePath: String, progress: @escaping @MainActor @Sendable (UInt64) -> Void) async throws {
        let handle = try FileHandle(forReadingFrom: localURL)
        defer { try? handle.close() }
        let file = try await files().openFile(filePath: remotePath, flags: [.write, .create, .truncate])
        var offset: UInt64 = 0
        do {
            while true {
                try Task.checkCancellation()
                guard let data = try handle.read(upToCount: Self.chunkSize), !data.isEmpty else { break }
                try await file.write(ByteBuffer(bytes: data), at: offset)
                offset += UInt64(data.count)
                await progress(offset)
            }
        } catch {
            try? await file.close()
            throw error
        }
        try await file.close()
    }

    // MARK: Erreurs

    /// Vrai si le serveur a refusé ce qui lui a été présenté pour s'authentifier.
    static func isAuthenticationFailure(_ error: Error) -> Bool {
        if let failure = error as? SSHClientError, case .allAuthenticationOptionsFailed = failure { return true }
        return error is AuthenticationFailed
    }

    /// Message à montrer pour une erreur de connexion, de terminal ou de transfert.
    static func describe(_ error: Error) -> String {
        if error is CancellationError {
            return L("Opération annulée.")
        }
        if let failure = error as? SSHLinkError {
            switch failure {
            case .notConnected: return L("La session SSH est fermée.")
            case .invalidDeviceKey: return L("La clé de cet appareil est illisible. La remplacer dans SSH › Clé de cet appareil.")
            }
        }
        if let failure = error as? SSHClientError {
            switch failure {
            case .allAuthenticationOptionsFailed:
                return L("Le serveur a refusé l'authentification.")
            case .unsupportedPasswordAuthentication:
                return L("Ce serveur n'accepte pas l'authentification par mot de passe.")
            case .unsupportedPrivateKeyAuthentication:
                return L("Ce serveur n'accepte pas l'authentification par clé.")
            case .unsupportedHostBasedAuthentication, .channelCreationFailed:
                return L("Le serveur a refusé d'ouvrir la session.")
            }
        }
        if error is AuthenticationFailed {
            return L("Le serveur a refusé l'authentification.")
        }
        if let failure = error as? SFTPError {
            if case .errorStatus(let status) = failure {
                switch status.errorCode {
                case .noSuchFile: return L("Élément introuvable sur le serveur.")
                case .permissionDenied: return L("Le serveur refuse l'accès à cet élément.")
                default: return status.message.isEmpty ? L("Le serveur a refusé l'opération.") : status.message
                }
            }
            return L("Le serveur a donné une réponse SFTP inattendue, ou la session s'est fermée.")
        }
        if let failure = error as? ChannelError, case .connectTimeout = failure {
            return L("Délai dépassé : l'hôte n'a pas répondu.")
        }
        if let failure = error as? CitadelError, case .channelCreationFailed = failure {
            return L("Le serveur a refusé d'ouvrir la session.")
        }
        return L("La connexion a échoué : \(String(describing: error))")
    }
}
