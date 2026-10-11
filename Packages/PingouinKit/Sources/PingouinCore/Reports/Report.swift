import Foundation

/// Nature d'une colonne, pour savoir ce qu'il faut masquer à l'export.
public enum ReportColumnKind: String, Codable, Sendable {
    case plain
    case macAddress
    case hostname
}

public struct ReportColumn: Codable, Hashable, Sendable {
    public let title: String
    public let kind: ReportColumnKind

    public init(_ title: String, kind: ReportColumnKind = .plain) {
        self.title = title
        self.kind = kind
    }
}

/// Section d'un rapport : les paramètres du test, un tableau de résultats, des remarques.
public struct ReportSection: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    /// Paramètres du test, sous la forme « libellé : valeur ».
    public let parameters: [String]
    public let columns: [ReportColumn]
    public let rows: [[String]]
    /// Résumé, avertissements et erreurs.
    public let notes: [String]

    public init(id: String, title: String, parameters: [String] = [], columns: [ReportColumn] = [], rows: [[String]] = [], notes: [String] = []) {
        self.id = id
        self.title = title
        self.parameters = parameters
        self.columns = columns
        self.rows = rows
        self.notes = notes
    }
}

public struct Report: Codable, Hashable, Sendable {
    public let title: String
    public let generatedAt: Date
    public let sections: [ReportSection]

    public init(title: String, generatedAt: Date, sections: [ReportSection]) {
        self.title = title
        self.generatedAt = generatedAt
        self.sections = sections
    }
}

public struct ReportPrivacy: Equatable, Sendable {
    public var maskMACAddresses: Bool
    public var maskHostnames: Bool

    public init(maskMACAddresses: Bool = false, maskHostnames: Bool = false) {
        self.maskMACAddresses = maskMACAddresses
        self.maskHostnames = maskHostnames
    }
}

/// Mise en forme des rapports, sans accès au disque. Une même entrée donne toujours la même sortie.
public enum ReportRenderer {
    public static let maskedValue = L("masqué")

    /// Applique les choix de confidentialité : les cellules des colonnes concernées sont remplacées,
    /// les cellules vides restent vides.
    public static func applying(_ privacy: ReportPrivacy, to report: Report) -> Report {
        guard privacy.maskMACAddresses || privacy.maskHostnames else { return report }
        let sections = report.sections.map { section -> ReportSection in
            let hidden = section.columns.map { column -> Bool in
                (column.kind == .macAddress && privacy.maskMACAddresses)
                    || (column.kind == .hostname && privacy.maskHostnames)
            }
            let rows = section.rows.map { row -> [String] in
                row.enumerated().map { index, cell -> String in
                    let isHidden = index < hidden.count && hidden[index]
                    let hasValue = !cell.isEmpty && cell != "—"
                    return isHidden && hasValue ? maskedValue : cell
                }
            }
            return ReportSection(
                id: section.id, title: section.title, parameters: section.parameters,
                columns: section.columns, rows: rows, notes: section.notes
            )
        }
        return Report(title: report.title, generatedAt: report.generatedAt, sections: sections)
    }

    /// Texte brut à colonnes alignées, pour l'aperçu et le PDF. `dateText` est fourni par l'appelant
    /// pour que le rendu ne dépende ni de la langue ni du fuseau de la machine.
    public static func text(_ report: Report, dateText: String) -> String {
        var lines: [String] = [report.title, dateText, ""]
        for section in report.sections {
            lines.append(section.title.uppercased())
            lines.append(String(repeating: "─", count: max(section.title.count, 8)))
            lines.append(contentsOf: section.parameters)
            if !section.parameters.isEmpty { lines.append("") }

            if !section.columns.isEmpty {
                let table = [section.columns.map(\.title)] + section.rows
                var widths = [Int](repeating: 0, count: section.columns.count)
                for row in table {
                    for (index, cell) in row.enumerated() where index < widths.count {
                        widths[index] = max(widths[index], cell.count)
                    }
                }
                for (rowIndex, row) in table.enumerated() {
                    let cells = widths.indices.map { index -> String in
                        let cell = index < row.count ? row[index] : ""
                        return cell + String(repeating: " ", count: widths[index] - cell.count)
                    }
                    lines.append(cells.joined(separator: "  ").trimmingTrailingSpaces())
                    if rowIndex == 0 {
                        lines.append(widths.map { String(repeating: "─", count: $0) }.joined(separator: "  "))
                    }
                }
                if section.rows.isEmpty { lines.append(L("(aucune ligne)")) }
                lines.append("")
            }
            lines.append(contentsOf: section.notes)
            if !section.notes.isEmpty { lines.append("") }
        }
        return lines.joined(separator: "\n")
    }

    /// CSV (RFC 4180) : une ligne par résultat, précédée du titre de sa section. Séparateur point-virgule,
    /// celui qu'attendent les tableurs réglés en français ; fins de ligne CRLF.
    public static func csv(_ report: Report) -> String {
        var lines: [String] = []
        for section in report.sections where !section.columns.isEmpty {
            lines.append(([L("Section")] + section.columns.map(\.title)).map(csvField).joined(separator: ";"))
            for row in section.rows {
                lines.append(([section.title] + row).map(csvField).joined(separator: ";"))
            }
            lines.append("")
        }
        return lines.joined(separator: "\r\n")
    }

    static func csvField(_ value: String) -> String {
        let needsQuotes = value.contains { $0 == ";" || $0 == "\"" || $0 == "," || $0.isNewline }
        guard needsQuotes else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// JSON lisible, aux clés triées et aux dates ISO 8601, pour un résultat reproductible.
    public static func json(_ report: Report) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }
}

private extension String {
    func trimmingTrailingSpaces() -> String {
        var result = self
        while result.hasSuffix(" ") { result.removeLast() }
        return result
    }
}
