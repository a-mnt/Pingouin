import Foundation

/// Lecture des droits d'un fichier distant, tels que le protocole SFTP les transmet (un nombre,
/// comme le champ `st_mode` d'Unix : le type de l'élément dans les bits de poids fort, puis les droits).
public enum SFTPMode {
    private static let typeMask: UInt32 = 0o170000

    public static func kind(mode: UInt32?) -> SFTPEntry.Kind {
        guard let mode else { return .other }
        switch mode & typeMask {
        case 0o040000: return .directory
        case 0o100000: return .file
        case 0o120000: return .link
        default: return .other
        }
    }

    /// Droits en neuf lettres, par exemple « rw-r--r-- ». « — » si le serveur ne les a pas donnés.
    public static func permissionText(mode: UInt32?) -> String {
        guard let mode else { return "—" }
        let letters: [Character] = ["r", "w", "x"]
        var text = ""
        for position in 0..<9 {
            let bit: UInt32 = 1 << UInt32(8 - position)
            text.append(mode & bit != 0 ? letters[position % 3] : "-")
        }
        return text
    }

    /// Vrai si le nom peut désigner un élément d'un dossier : ni vide, ni « . », ni « .. », sans barre
    /// ni caractère de contrôle.
    public static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 255 && name != "." && name != ".." && !name.contains("/")
            && !name.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }
}
