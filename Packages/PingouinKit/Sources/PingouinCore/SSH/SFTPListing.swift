import Foundation

/// Élément d'un dossier distant, lu dans la sortie de `sftp`.
public struct SFTPEntry: Identifiable, Hashable, Sendable {
    public enum Kind: Sendable {
        case directory
        case file
        case link
        case other
    }

    public let name: String
    public let kind: Kind
    public let size: UInt64
    /// Date de modification, à la minute près (ou au jour près pour un élément ancien).
    public let modified: Date?
    /// Droits tels que le serveur les donne, par exemple « drwxr-xr-x ».
    public let permissions: String

    public var id: String { name }

    public init(name: String, kind: Kind, size: UInt64, modified: Date?, permissions: String) {
        self.name = name
        self.kind = kind
        self.size = size
        self.modified = modified
        self.permissions = permissions
    }
}

/// Lecture de la sortie de la commande `ls -lan` de `sftp`.
///
/// Avec l'option `-n`, c'est le client `sftp` qui compose chaque ligne, dans un format fixe :
/// droits, liens, propriétaire, groupe, taille, date sur trois mots, puis le nom.
public enum SFTPListing {
    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    private static let directoryAnswer = "Remote working directory: "

    /// Éléments d'un dossier, dossiers d'abord puis par nom. Les entrées « . » et « .. » sont écartées.
    public static func parse(_ output: String, now: Date = Date(), calendar: Calendar = .current) -> [SFTPEntry] {
        let entries = output.split(whereSeparator: \.isNewline).compactMap { line -> SFTPEntry? in
            guard let entry = parseLine(String(line), now: now, calendar: calendar) else { return nil }
            return entry.name == "." || entry.name == ".." ? nil : entry
        }
        return sorted(entries)
    }

    public static func sorted(_ entries: [SFTPEntry]) -> [SFTPEntry] {
        entries.sorted { first, second in
            let firstIsFolder = first.kind == .directory
            let secondIsFolder = second.kind == .directory
            if firstIsFolder != secondIsFolder { return firstIsFolder }
            return first.name.localizedStandardCompare(second.name) == .orderedAscending
        }
    }

    /// Une ligne de la liste. `nil` pour toute autre ligne (écho de commande, message).
    public static func parseLine(_ line: String, now: Date = Date(), calendar: Calendar = .current) -> SFTPEntry? {
        guard !line.hasPrefix("sftp> ") else { return nil }
        var index = line.startIndex
        var words: [Substring] = []
        // Huit mots séparés par des espaces, puis un seul espace, puis le nom tel quel
        // (il peut contenir des espaces, y compris au début).
        while words.count < 8 {
            while index < line.endIndex, line[index] == " " {
                index = line.index(after: index)
            }
            let start = index
            while index < line.endIndex, line[index] != " " {
                index = line.index(after: index)
            }
            guard start < index else { return nil }
            words.append(line[start..<index])
        }
        guard index < line.endIndex else { return nil }
        // Selon la façon dont le dossier est demandé, `sftp` écrit le nom seul ou précédé du chemin.
        // Un nom ne contient jamais de barre : on ne garde que ce qui suit la dernière.
        var name = String(line[line.index(after: index)...])
        while name.count > 1, name.hasSuffix("/") {
            name.removeLast()
        }
        if let slash = name.lastIndex(of: "/") {
            name = String(name[name.index(after: slash)...])
        }
        guard !name.isEmpty else { return nil }

        let permissions = String(words[0])
        guard permissions.count >= 10, let size = UInt64(words[4]) else { return nil }
        let kind: SFTPEntry.Kind
        switch permissions.first {
        case "d": kind = .directory
        case "-": kind = .file
        case "l": kind = .link
        default: kind = .other
        }
        return SFTPEntry(
            name: name,
            kind: kind,
            size: size,
            modified: date(month: words[5], day: words[6], timeOrYear: words[7], now: now, calendar: calendar),
            permissions: permissions
        )
    }

    /// Dossier courant, lu dans la réponse à la commande `pwd`.
    public static func workingDirectory(in output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) where line.hasPrefix(directoryAnswer) {
            let path = String(line.dropFirst(directoryAnswer.count))
            return path.isEmpty ? nil : path
        }
        return nil
    }

    /// Date d'une ligne : « Oct 9 10:12 » pour un élément récent (l'année est déduite),
    /// « Oct 9 2024 » pour un élément plus ancien.
    static func date(month: Substring, day: Substring, timeOrYear: Substring, now: Date, calendar: Calendar) -> Date? {
        guard let monthIndex = months.firstIndex(of: month.lowercased()), let day = Int(day) else { return nil }
        var parts = DateComponents()
        parts.month = monthIndex + 1
        parts.day = day
        let clock = timeOrYear.split(separator: ":")
        if clock.count == 2, let hour = Int(clock[0]), let minute = Int(clock[1]) {
            parts.hour = hour
            parts.minute = minute
            parts.year = calendar.component(.year, from: now)
            // Une date récente ne peut pas être dans le futur : sinon, elle est de l'année passée.
            if let date = calendar.date(from: parts), date > now.addingTimeInterval(86_400) {
                parts.year = calendar.component(.year, from: now) - 1
            }
        } else if let year = Int(timeOrYear) {
            parts.year = year
        } else {
            return nil
        }
        return calendar.date(from: parts)
    }
}

/// Chemins distants, et leur écriture dans une commande `sftp`.
public enum SFTPPath {
    /// Caractères que `sftp` interprète dans un chemin (motifs, échappements, guillemets).
    /// Un nom qui en contient est affiché, mais aucune commande n'est construite avec lui.
    private static let unsupported: Set<Character> = ["\"", "\\", "*", "?", "["]
    private static let lengthLimit = 1_000

    /// Vrai si le texte peut être écrit sans risque dans une commande.
    public static func isSupported(_ text: String) -> Bool {
        !text.isEmpty && text.count <= lengthLimit && !text.contains { character in
            unsupported.contains(character) || character.isNewline
                || character.unicodeScalars.contains { $0.properties.generalCategory == .control }
        }
    }

    /// Vrai si le texte peut servir de nom à un fichier ou à un dossier.
    public static func isValidName(_ name: String) -> Bool {
        isSupported(name) && !name.contains("/") && name != "." && name != ".."
    }

    /// Chemin entre guillemets, prêt pour une commande. `nil` s'il contient un caractère non pris en charge.
    public static func quoted(_ path: String) -> String? {
        isSupported(path) ? "\"\(path)\"" : nil
    }

    public static func join(_ folder: String, _ name: String) -> String {
        folder.hasSuffix("/") ? folder + name : folder + "/" + name
    }

    /// Dossier parent. La racine est son propre parent.
    public static func parent(of path: String) -> String {
        let parts = path.split(separator: "/")
        guard parts.count > 1 else { return "/" }
        return "/" + parts.dropLast().joined(separator: "/")
    }

    /// Chemin absolu saisi par l'utilisateur, sans barre finale ni barres doublées.
    /// `nil` s'il n'est pas absolu ou contient un caractère non pris en charge.
    public static func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/"), isSupported(trimmed) else { return nil }
        let parts = trimmed.split(separator: "/")
        return "/" + parts.joined(separator: "/")
    }
}
