import Foundation
import Testing
@testable import PingouinCore

@Suite("Clés SSH, hôtes connus et droits SFTP")
struct SSHKeysTests {
    /// Clé d'essai : les octets 0 à 31. La ligne et l'empreinte attendues ont été calculées à part.
    private static let publicKey = [UInt8](0..<32)
    private static let line = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4f pingouin@essai"

    @Test("Ligne de clé publique Ed25519")
    func ed25519Line() {
        #expect(OpenSSHPublicKey.ed25519Line(publicKey: Self.publicKey, comment: "pingouin@essai") == Self.line)
        #expect(OpenSSHPublicKey.ed25519Line(publicKey: [1, 2, 3], comment: "") == nil)
    }

    @Test("Le commentaire ne peut pas couper la ligne")
    func commentIsSanitized() {
        let line = OpenSSHPublicKey.ed25519Line(publicKey: Self.publicKey, comment: "iPhone de Léa\nssh-rsa AAAA")
        #expect(line?.split(separator: " ").count == 3)
        #expect(line?.contains("\n") == false)
    }

    @Test("Empreinte SHA-256, écrite comme ssh-keygen")
    func fingerprint() {
        #expect(OpenSSHPublicKey.fingerprint(ofLine: Self.line) == "SHA256:ZkAslGjFiUHdGf/WUL8rQvkib4PTvQatUV0OUQSncCA")
        #expect(OpenSSHPublicKey.keyType(ofLine: Self.line) == "ssh-ed25519")
        #expect(OpenSSHPublicKey.fingerprint(ofLine: "ssh-ed25519 pas-du-base64") == nil)
        // Le type annoncé doit être celui que contient la clé.
        #expect(OpenSSHPublicKey.fingerprint(ofLine: Self.line.replacingOccurrences(of: "ssh-ed25519 ", with: "ssh-rsa ")) == nil)
    }

    @Test("Deux lignes de la même clé, commentaires différents")
    func sameKey() {
        let other = OpenSSHPublicKey.ed25519Line(publicKey: Self.publicKey, comment: "autre") ?? ""
        #expect(OpenSSHPublicKey.isSameKey(Self.line, other))
        let different = OpenSSHPublicKey.ed25519Line(publicKey: [UInt8](repeating: 7, count: 32), comment: "") ?? ""
        #expect(!OpenSSHPublicKey.isSameKey(Self.line, different))
    }

    @Test("Hôtes connus : inconnu, accepté, clé changée, oublié")
    func knownHosts() {
        var book = KnownHostsBook()
        #expect(book.verdict(host: "nas.local", port: 22, presentedKeyLine: Self.line) == .unknown)

        book.trust(host: "NAS.local", port: 22, keyLine: Self.line, now: Date(timeIntervalSince1970: 0))
        #expect(book.verdict(host: "nas.local", port: 22, presentedKeyLine: Self.line) == .trusted)
        // Un autre port est un autre hôte.
        #expect(book.verdict(host: "nas.local", port: 2222, presentedKeyLine: Self.line) == .unknown)

        let other = OpenSSHPublicKey.ed25519Line(publicKey: [UInt8](repeating: 7, count: 32), comment: "") ?? ""
        if case .changed(let known) = book.verdict(host: "nas.local", port: 22, presentedKeyLine: other) {
            #expect(known.keyLine == Self.line)
        } else {
            Issue.record("Une clé différente doit être signalée comme changée.")
        }

        book.forget(host: "nas.local", port: 22)
        #expect(book.hosts.isEmpty)
    }

    @Test("Destination « utilisateur@hôte:port »")
    func destination() {
        #expect(SSHDestination.parse("utilisateur@192.168.1.20") == SSHDestination(user: "utilisateur", host: "192.168.1.20", port: 22))
        #expect(SSHDestination.parse(" deploy@serveur.example:2222 ") == SSHDestination(user: "deploy", host: "serveur.example", port: 2222))
        #expect(SSHDestination.parse("utilisateur@[2001:db8::1]:2222") == SSHDestination(user: "utilisateur", host: "2001:db8::1", port: 2222))
        #expect(SSHDestination.parse("192.168.1.20") == nil)
        #expect(SSHDestination.parse("@hote") == nil)
        #expect(SSHDestination.parse("a b@hote") == nil)
        #expect(SSHDestination.parse("utilisateur@hote:port") == nil)
    }

    @Test("Type et droits d'un élément distant")
    func modes() {
        #expect(SFTPMode.kind(mode: 0o040755) == .directory)
        #expect(SFTPMode.kind(mode: 0o100644) == .file)
        #expect(SFTPMode.kind(mode: 0o120777) == .link)
        #expect(SFTPMode.kind(mode: 0o010644) == .other)
        #expect(SFTPMode.kind(mode: nil) == .other)
        #expect(SFTPMode.permissionText(mode: 0o100644) == "rw-r--r--")
        #expect(SFTPMode.permissionText(mode: 0o040750) == "rwxr-x---")
        #expect(SFTPMode.permissionText(mode: nil) == "—")
    }

    @Test("Noms acceptés pour un fichier distant")
    func names() {
        #expect(SFTPMode.isValidName("notes d'été [2026].txt"))
        #expect(!SFTPMode.isValidName(""))
        #expect(!SFTPMode.isValidName(".."))
        #expect(!SFTPMode.isValidName("a/b"))
        #expect(!SFTPMode.isValidName("a\nb"))
    }
}
