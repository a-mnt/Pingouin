import Foundation
import Security

/// Secrets gardés dans le Trousseau de macOS, sous le service de l'application :
/// mots de passe SSH et jeton d'accès à la box.
/// C'est le seul endroit où Pingouin conserve un secret.
enum KeychainStore {
    private static let service = "fr.a-mnt.pingouin"

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    /// Vrai si un mot de passe existe pour ce compte. Ne lit pas le secret lui-même.
    static func hasPassword(account: String) -> Bool {
        var query = baseQuery(account: account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func password(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Enregistre ou remplace le mot de passe. Renvoie faux si le Trousseau a refusé.
    ///
    /// `thisDeviceOnly` : le secret n'est lisible qu'appareil déverrouillé, et ne quitte jamais cet
    /// appareil (ni sauvegarde restaurée ailleurs, ni synchronisation).
    @discardableResult
    static func setPassword(
        _ password: String,
        account: String,
        label: String = "Pingouin — connexion SSH",
        thisDeviceOnly: Bool = false
    ) -> Bool {
        let data = Data(password.utf8)
        let query = baseQuery(account: account)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrLabel as String] = label
        if thisDeviceOnly {
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    /// Supprime le mot de passe. Vrai aussi s'il n'y en avait pas.
    @discardableResult
    static func deletePassword(account: String) -> Bool {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
