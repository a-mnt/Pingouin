import CryptoKit
import Foundation
import PingouinCore
import UIKit

/// Façon de s'authentifier d'une connexion enregistrée.
enum MobileSSHAuth: String, Codable, CaseIterable, Identifiable {
    case password
    case deviceKey

    var id: String { rawValue }

    var title: String {
        switch self {
        case .password: L("Mot de passe")
        case .deviceKey: L("Clé de cet appareil")
        }
    }
}

/// Connexion SSH enregistrée sur cet appareil. Aucun secret n'y figure : le mot de passe, s'il est
/// gardé, est dans le Trousseau, comme la clé privée de l'appareil.
struct MobileSSHProfile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = ""
    var host = ""
    var port = 22
    var user = ""
    var auth: MobileSSHAuth = .password
    /// Thème propre à cette connexion. `nil` : thème par défaut.
    var themeID: String?

    var displayName: String { name.isEmpty ? host : name }

    var destination: String { "\(user)@\(host)" }

    var summary: String { port == 22 ? destination : "\(destination):\(port)" }

    /// Compte sous lequel le mot de passe de cette connexion est rangé dans le Trousseau.
    var keychainAccount: String { "ssh:\(id.uuidString)" }
}

/// Écran de l'onglet SSH auquel la navigation peut mener.
enum MobileSSHRoute: Hashable {
    case session(UUID)
    case deviceKey
}

/// Ce que montre l'écran d'une session : son terminal ou ses fichiers.
enum MobileSSHPane: Hashable {
    case terminal
    case files
}

/// Clé Ed25519 de l'appareil. La partie privée ne quitte jamais le Trousseau de cet appareil :
/// elle n'est ni affichée, ni exportée, ni synchronisée. Seule la partie publique se partage.
enum DeviceKeyStore {
    private static let account = "ssh:cle-appareil-ed25519"
    private static let createdKey = "ssh.deviceKeyCreatedAt"

    /// Clé privée sous sa forme brute, pour s'authentifier. `nil` s'il n'y a pas de clé.
    static func privateKeyData() -> Data? {
        guard let text = KeychainStore.password(account: account), let data = Data(base64Encoded: text),
              data.count == 32 else { return nil }
        return data
    }

    static var exists: Bool {
        KeychainStore.hasPassword(account: account)
    }

    static var createdAt: Date? {
        UserDefaults.standard.object(forKey: createdKey) as? Date
    }

    /// Crée une clé, ou remplace celle qui existe : l'ancienne est alors perdue. Faux si le Trousseau refuse.
    @discardableResult
    static func create() -> Bool {
        let key = Curve25519.Signing.PrivateKey()
        let stored = KeychainStore.setPassword(
            key.rawRepresentation.base64EncodedString(),
            account: account,
            label: "Pingouin — clé SSH de cet appareil",
            thisDeviceOnly: true
        )
        if stored {
            UserDefaults.standard.set(Date(), forKey: createdKey)
        }
        return stored
    }

    /// Ligne de clé publique à déposer dans `authorized_keys`. `nil` s'il n'y a pas de clé.
    @MainActor
    static func publicKeyLine() -> String? {
        guard let data = privateKeyData(), let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) else {
            return nil
        }
        return OpenSSHPublicKey.ed25519Line(
            publicKey: [UInt8](key.publicKey.rawRepresentation),
            comment: "pingouin@" + UIDevice.current.name
        )
    }
}

extension TerminalTheme {
    var backgroundColor: UIColor { UIColor(rgb: background) }
    var foregroundColor: UIColor { UIColor(rgb: foreground) }
    var cursorColor: UIColor { UIColor(rgb: cursor) }
}

extension UIColor {
    /// Couleur sRGB à partir d'une valeur 0xRRGGBB.
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
