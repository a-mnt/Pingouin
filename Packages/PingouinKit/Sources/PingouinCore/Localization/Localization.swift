import Foundation

/// Texte à traduire : son modèle en français, où chaque valeur insérée est notée « %@ »,
/// et les valeurs elles-mêmes, déjà mises en forme.
///
/// Toutes les insertions donnent « %@ », quel que soit leur type : la clé d'une traduction se déduit
/// donc du seul texte du code, sans connaître les types. C'est ce qui permet à l'outil
/// `Scripts/traductions.py` de tenir le catalogue à jour sans compilateur.
public struct LocalizedText: ExpressibleByStringInterpolation, Sendable {
    public struct StringInterpolation: StringInterpolationProtocol, Sendable {
        var key = ""
        var arguments: [String] = []

        public init(literalCapacity: Int, interpolationCount: Int) {
            key.reserveCapacity(literalCapacity + interpolationCount * 2)
            arguments.reserveCapacity(interpolationCount)
        }

        public mutating func appendLiteral(_ literal: String) {
            key += literal.replacingOccurrences(of: "%", with: "%%")
        }

        public mutating func appendInterpolation<Value>(_ value: Value) {
            key += "%@"
            arguments.append("\(value)")
        }
    }

    /// Clé du catalogue : le texte français, « %@ » à la place de chaque valeur, « % » doublé.
    public let key: String
    public let arguments: [String]

    public init(stringLiteral value: String) {
        key = value.replacingOccurrences(of: "%", with: "%%")
        arguments = []
    }

    public init(stringInterpolation: StringInterpolation) {
        key = stringInterpolation.key
        arguments = stringInterpolation.arguments
    }
}

/// Traduction des textes de l'application.
public enum Localization {
    /// Catalogue lu : celui de l'application. Dans les tests du paquet, il n'y en a pas,
    /// et les textes restent en français.
    static var bundle: Bundle { .main }

    /// Vrai si l'application s'affiche en français.
    public static var isFrench: Bool {
        (bundle.preferredLocalizations.first ?? "fr").hasPrefix("fr")
    }

    /// Texte traduit, valeurs insérées.
    public static func string(_ text: LocalizedText) -> String {
        // Sans traduction, la clé elle-même est rendue : le texte français.
        fill(bundle.localizedString(forKey: text.key, value: text.key, table: nil), with: text.arguments)
    }

    /// Remplace « %@ » (dans l'ordre) et « %1$@ » (par position) par les valeurs, et « %% » par « % ».
    /// Écrit à la main plutôt qu'avec `String(format:)` : une traduction mal formée ne peut pas faire
    /// lire une valeur qui n'existe pas.
    public static func fill(_ template: String, with arguments: [String]) -> String {
        guard template.contains("%") else { return template }
        var result = ""
        var next = 0
        var index = template.startIndex
        while index < template.endIndex {
            let character = template[index]
            guard character == "%" else {
                result.append(character)
                index = template.index(after: index)
                continue
            }
            var cursor = template.index(after: index)
            guard cursor < template.endIndex else {
                result.append("%")
                break
            }
            if template[cursor] == "%" {
                result.append("%")
                index = template.index(after: cursor)
                continue
            }
            var digits = ""
            while cursor < template.endIndex, template[cursor].isASCII, template[cursor].isNumber {
                digits.append(template[cursor])
                cursor = template.index(after: cursor)
            }
            if !digits.isEmpty, cursor < template.endIndex, template[cursor] == "$" {
                cursor = template.index(after: cursor)
            } else if !digits.isEmpty {
                // « %12 » sans « $ » : ce n'est pas une insertion.
                result.append("%")
                index = template.index(after: index)
                continue
            }
            guard cursor < template.endIndex, template[cursor] == "@" else {
                result.append("%")
                index = template.index(after: index)
                continue
            }
            let position = digits.isEmpty ? next : (Int(digits) ?? 0) - 1
            if digits.isEmpty {
                next += 1
            }
            if arguments.indices.contains(position) {
                result += arguments[position]
            }
            index = template.index(after: cursor)
        }
        return result
    }
}

/// Texte traduit dans la langue de l'application. Le texte du code est le français.
public func L(_ text: LocalizedText) -> String {
    Localization.string(text)
}

/// Texte accordé en nombre. En français, zéro s'accorde au singulier ; ailleurs, au pluriel.
public func L(count: Int, one: LocalizedText, other: LocalizedText) -> String {
    let singular = count == 1 || (count == 0 && Localization.isFrench)
    return Localization.string(singular ? one : other)
}
