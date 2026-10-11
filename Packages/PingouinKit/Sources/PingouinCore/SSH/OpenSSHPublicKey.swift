import CryptoKit
import Foundation

/// Clé publique au format d'OpenSSH : « type base64 commentaire », comme dans `authorized_keys`.
///
/// Rien de secret ici : seule la partie publique d'une clé est manipulée.
public enum OpenSSHPublicKey {
    public static let ed25519Type = "ssh-ed25519"

    /// Ligne à déposer sur un serveur pour une clé Ed25519. `nil` si la clé n'a pas 32 octets.
    public static func ed25519Line(publicKey: [UInt8], comment: String) -> String? {
        guard publicKey.count == 32 else { return nil }
        let blob = field(Array(ed25519Type.utf8)) + field(publicKey)
        let cleaned = sanitized(comment)
        let base = ed25519Type + " " + Data(blob).base64EncodedString()
        return cleaned.isEmpty ? base : base + " " + cleaned
    }

    /// Type annoncé par une ligne (« ssh-ed25519 », « ssh-rsa »…). `nil` si la ligne n'en est pas une.
    public static func keyType(ofLine line: String) -> String? {
        parts(of: line)?.type
    }

    /// Contenu binaire de la clé, tel qu'il circule dans le protocole. `nil` si la ligne est mal formée.
    public static func blob(ofLine line: String) -> [UInt8]? {
        parts(of: line)?.blob
    }

    /// Empreinte de la clé, écrite comme le fait `ssh-keygen -l` : « SHA256: » suivi de l'empreinte
    /// en base64 sans remplissage. `nil` si la ligne est mal formée.
    public static func fingerprint(ofLine line: String) -> String? {
        guard let blob = blob(ofLine: line) else { return nil }
        let digest = Data(SHA256.hash(data: Data(blob))).base64EncodedString()
        return "SHA256:" + digest.trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    /// Vrai si deux lignes désignent la même clé. Le commentaire ne compte pas.
    public static func isSameKey(_ first: String, _ second: String) -> Bool {
        guard let one = parts(of: first), let two = parts(of: second) else { return false }
        return one.type == two.type && one.blob == two.blob
    }

    /// Commentaire sans espace ni caractère de contrôle : il ne doit pas pouvoir couper la ligne.
    public static func sanitized(_ comment: String) -> String {
        let kept = comment.unicodeScalars.map { scalar -> Character in
            let isPlain = scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "@._-".unicodeScalars.contains(scalar))
            return isPlain ? Character(scalar) : "-"
        }
        return String(String(kept).prefix(64))
    }

    private static func parts(of line: String) -> (type: String, blob: [UInt8])? {
        let words = line.split(separator: " ", omittingEmptySubsequences: true)
        guard words.count >= 2, let data = Data(base64Encoded: String(words[1])), !data.isEmpty else { return nil }
        let blob = [UInt8](data)
        // Le contenu commence par le type, précédé de sa longueur : il doit être celui qu'annonce la ligne.
        guard blob.count >= 4 else { return nil }
        let length = Int(blob[0]) << 24 | Int(blob[1]) << 16 | Int(blob[2]) << 8 | Int(blob[3])
        guard length > 0, blob.count >= 4 + length,
              String(bytes: blob[4..<(4 + length)], encoding: .utf8) == String(words[0]) else { return nil }
        return (String(words[0]), blob)
    }

    /// Champ du protocole SSH : la longueur sur quatre octets, puis le contenu.
    private static func field(_ bytes: [UInt8]) -> [UInt8] {
        let count = UInt32(bytes.count)
        return [UInt8(count >> 24), UInt8(count >> 16 & 0xFF), UInt8(count >> 8 & 0xFF), UInt8(count & 0xFF)] + bytes
    }
}
