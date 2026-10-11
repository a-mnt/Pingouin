import Foundation

/// Champs d'un certificat X.509 lus directement dans son encodage DER.
///
/// Sert là où le système ne sait pas donner ces champs (iOS). Seul ce dont l'outil TLS a besoin est lu :
/// validité, émetteur et noms couverts. La signature n'est pas vérifiée ici : la confiance reste
/// l'affaire de l'évaluation du système.
public struct X509Fields: Equatable, Sendable {
    public let notBefore: Date?
    public let notAfter: Date?
    public let issuerCommonName: String?
    public let issuerOrganization: String?
    /// Noms DNS et adresses IP couverts (extension « subjectAltName »).
    public let subjectAlternativeNames: [String]
}

public enum X509Reader {
    private struct Element {
        let tag: UInt8
        let content: ArraySlice<UInt8>
    }

    private static let commonNameOID: [UInt8] = [0x55, 0x04, 0x03]
    private static let organizationOID: [UInt8] = [0x55, 0x04, 0x0A]
    private static let subjectAltNameOID: [UInt8] = [0x55, 0x1D, 0x11]

    /// Lit un certificat. `nil` si l'encodage n'est pas celui d'un certificat X.509.
    public static func parse(der: [UInt8]) -> X509Fields? {
        guard let certificate = elements(in: der[...])?.first, certificate.tag == 0x30,
              let outer = elements(in: certificate.content), let tbs = outer.first, tbs.tag == 0x30,
              var fields = elements(in: tbs.content) else { return nil }

        // Le numéro de version, facultatif, précède le numéro de série.
        if fields.first?.tag == 0xA0 {
            fields.removeFirst()
        }
        // Numéro de série, algorithme, émetteur, validité, sujet, clé publique.
        guard fields.count >= 6, fields[2].tag == 0x30, fields[3].tag == 0x30 else { return nil }

        let issuer = attributes(of: fields[2])
        let validity = elements(in: fields[3].content) ?? []
        var names: [String] = []
        for field in fields.dropFirst(6) where field.tag == 0xA3 {
            names = alternativeNames(inExtensions: field)
        }
        return X509Fields(
            notBefore: validity.first.flatMap(date),
            notAfter: validity.dropFirst().first.flatMap(date),
            issuerCommonName: issuer[commonNameOID],
            issuerOrganization: issuer[organizationOID],
            subjectAlternativeNames: names
        )
    }

    // MARK: Lecture DER

    /// Découpe une suite d'éléments « étiquette, longueur, contenu ». `nil` si une longueur déborde.
    private static func elements(in bytes: ArraySlice<UInt8>) -> [Element]? {
        var result: [Element] = []
        var index = bytes.startIndex
        while index < bytes.endIndex {
            let tag = bytes[index]
            index += 1
            guard index < bytes.endIndex else { return nil }
            var length = Int(bytes[index])
            index += 1
            if length & 0x80 != 0 {
                let count = length & 0x7F
                guard count >= 1, count <= 4, index + count <= bytes.endIndex else { return nil }
                length = 0
                for _ in 0..<count {
                    length = length << 8 | Int(bytes[index])
                    index += 1
                }
            }
            guard length >= 0, index + length <= bytes.endIndex else { return nil }
            result.append(Element(tag: tag, content: bytes[index..<(index + length)]))
            index += length
        }
        return result
    }

    /// Attributs d'un nom (émetteur ou sujet), par identifiant.
    private static func attributes(of name: Element) -> [[UInt8]: String] {
        var result: [[UInt8]: String] = [:]
        for set in elements(in: name.content) ?? [] {
            for attribute in elements(in: set.content) ?? [] {
                guard let parts = elements(in: attribute.content), parts.count >= 2, parts[0].tag == 0x06 else { continue }
                let key = Array(parts[0].content)
                if result[key] == nil, let text = string(parts[1]) {
                    result[key] = text
                }
            }
        }
        return result
    }

    private static func string(_ element: Element) -> String? {
        switch element.tag {
        case 0x0C, 0x13, 0x16, 0x14:
            // UTF8String, PrintableString, IA5String, TeletexString.
            return String(bytes: element.content, encoding: .utf8) ?? String(bytes: element.content, encoding: .isoLatin1)
        case 0x1E:
            return String(bytes: element.content, encoding: .utf16BigEndian)
        default:
            return nil
        }
    }

    /// Date d'une validité : « AAMMJJHHMMSSZ » (UTCTime) ou « AAAAMMJJHHMMSSZ » (GeneralizedTime).
    private static func date(_ element: Element) -> Date? {
        guard element.tag == 0x17 || element.tag == 0x18,
              let text = String(bytes: element.content, encoding: .ascii), text.hasSuffix("Z") else { return nil }
        let digits = text.dropLast().compactMap(\.wholeNumberValue)
        let yearDigits = element.tag == 0x17 ? 2 : 4
        guard digits.count == text.count - 1, digits.count == yearDigits + 10 else { return nil }

        func number(_ start: Int, _ count: Int) -> Int {
            digits[start..<(start + count)].reduce(0) { $0 * 10 + $1 }
        }
        var year = number(0, yearDigits)
        if yearDigits == 2 {
            // RFC 5280 : de 50 à 99, années 1950 à 1999 ; de 00 à 49, années 2000 à 2049.
            year += year >= 50 ? 1_900 : 2_000
        }
        var components = DateComponents()
        components.year = year
        components.month = number(yearDigits, 2)
        components.day = number(yearDigits + 2, 2)
        components.hour = number(yearDigits + 4, 2)
        components.minute = number(yearDigits + 6, 2)
        components.second = number(yearDigits + 8, 2)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.date(from: components)
    }

    /// Noms DNS et adresses IP de l'extension « subjectAltName », s'il y en a une.
    private static func alternativeNames(inExtensions wrapper: Element) -> [String] {
        guard let list = elements(in: wrapper.content)?.first, list.tag == 0x30 else { return [] }
        for item in elements(in: list.content) ?? [] {
            // Identifiant, indicateur « critique » facultatif, puis la valeur dans une chaîne d'octets.
            guard let parts = elements(in: item.content), let oid = parts.first, oid.tag == 0x06,
                  Array(oid.content) == subjectAltNameOID,
                  let value = parts.last, value.tag == 0x04,
                  let names = elements(in: value.content)?.first, names.tag == 0x30 else { continue }
            return (elements(in: names.content) ?? []).compactMap { name -> String? in
                switch name.tag {
                case 0x82:
                    return String(bytes: name.content, encoding: .utf8)
                case 0x87 where name.content.count == 4:
                    return name.content.map(String.init).joined(separator: ".")
                case 0x87 where name.content.count == 16:
                    let raw = name.content.reduce(UInt128(0)) { $0 << 8 | UInt128($1) }
                    return IPAddressV6(rawValue: raw).description
                default:
                    return nil
                }
            }
        }
        return []
    }
}
