import Foundation

/// Types d'enregistrements que l'application sait interroger.
public enum DNSRecordType: UInt16, CaseIterable, Sendable, Identifiable {
    case a = 1
    case ns = 2
    case cname = 5
    case soa = 6
    case ptr = 12
    case mx = 15
    case txt = 16
    case aaaa = 28

    public var id: UInt16 { rawValue }

    public var name: String {
        switch self {
        case .a: "A"
        case .ns: "NS"
        case .cname: "CNAME"
        case .soa: "SOA"
        case .ptr: "PTR"
        case .mx: "MX"
        case .txt: "TXT"
        case .aaaa: "AAAA"
        }
    }

    /// Ordre de présentation dans l'interface.
    public static let displayOrder: [DNSRecordType] = [.a, .aaaa, .cname, .mx, .txt, .ns, .soa, .ptr]

    /// Nom d'un type quelconque, y compris ceux que l'application n'interroge pas.
    public static func name(forCode code: UInt16) -> String {
        DNSRecordType(rawValue: code)?.name ?? "TYPE\(code)"
    }
}

public struct DNSRecord: Hashable, Sendable {
    public let name: String
    public let typeCode: UInt16
    public let ttl: UInt32
    /// Valeur sous forme lisible : adresse, nom, « priorité nom » pour un MX, texte entre guillemets pour un TXT.
    public let value: String

    public init(name: String, typeCode: UInt16, ttl: UInt32, value: String) {
        self.name = name
        self.typeCode = typeCode
        self.ttl = ttl
        self.value = value
    }

    public var typeName: String { DNSRecordType.name(forCode: typeCode) }
}

public struct DNSResponse: Equatable, Sendable {
    public let id: UInt16
    /// Code de réponse : 0 pas d'erreur, 2 échec du serveur, 3 domaine inexistant, 5 refusé…
    public let responseCode: Int
    /// La réponse ne tenait pas dans un datagramme UDP : elle est incomplète.
    public let isTruncated: Bool
    public let answers: [DNSRecord]
}

/// Construction des questions et lecture des réponses DNS (RFC 1035), sans aucun accès réseau.
public enum DNSMessage {

    // MARK: Question

    /// Encode un nom de domaine en labels. Renvoie `nil` si le nom est vide, trop long,
    /// contient un label vide ou de plus de 63 octets, ou des caractères non ASCII.
    public static func encodeName(_ name: String) -> [UInt8]? {
        var trimmed = name
        if trimmed.hasSuffix(".") { trimmed.removeLast() }
        guard !trimmed.isEmpty, trimmed.utf8.count <= 253 else { return nil }
        var bytes: [UInt8] = []
        for label in trimmed.split(separator: ".", omittingEmptySubsequences: false) {
            let content = Array(label.utf8)
            guard !content.isEmpty, content.count <= 63 else { return nil }
            guard content.allSatisfy({ $0 > 0x20 && $0 < 0x7F }) else { return nil }
            bytes.append(UInt8(content.count))
            bytes.append(contentsOf: content)
        }
        bytes.append(0)
        return bytes
    }

    /// Nom réellement interrogé. Pour une recherche PTR sur une adresse IP, c'est le nom inverse
    /// (`in-addr.arpa` ou `ip6.arpa`) ; sinon la saisie telle quelle.
    public static func questionName(for input: String, type: DNSRecordType) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard type == .ptr else { return trimmed }
        if let address = IPAddressV4(trimmed) {
            return DNSWireName.reverseLookupName(for: address)
        }
        if let address = IPAddressV6(trimmed) {
            let digits = address.expandedDescription.filter { $0 != ":" }
            return digits.reversed().map { String($0) }.joined(separator: ".") + ".ip6.arpa."
        }
        return trimmed
    }

    /// Message de question complet, avec demande de récursion. `nil` si le nom n'est pas encodable.
    public static func query(id: UInt16, name: String, type: DNSRecordType) -> [UInt8]? {
        guard let encodedName = encodeName(name) else { return nil }
        var bytes: [UInt8] = [
            UInt8(truncatingIfNeeded: id >> 8), UInt8(truncatingIfNeeded: id),
            0x01, 0x00,   // drapeaux : récursion demandée
            0x00, 0x01,   // une question
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        ]
        bytes.append(contentsOf: encodedName)
        bytes.append(UInt8(truncatingIfNeeded: type.rawValue >> 8))
        bytes.append(UInt8(truncatingIfNeeded: type.rawValue))
        bytes.append(contentsOf: [0x00, 0x01])   // classe IN
        return bytes
    }

    // MARK: Réponse

    /// Lit une réponse. Renvoie `nil` si le message est tronqué ou incohérent
    /// (longueurs dépassant les données, pointeurs de compression en boucle).
    public static func parse(_ bytes: [UInt8]) -> DNSResponse? {
        guard bytes.count >= 12 else { return nil }
        func word(_ index: Int) -> Int { Int(bytes[index]) << 8 | Int(bytes[index + 1]) }

        let flags = word(2)
        guard flags & 0x8000 != 0 else { return nil }   // ce doit être une réponse
        let questionCount = word(4)
        let answerCount = word(6)

        var offset = 12
        for _ in 0..<questionCount {
            guard let (_, next) = readName(bytes, at: offset), next + 4 <= bytes.count else { return nil }
            offset = next + 4
        }

        var answers: [DNSRecord] = []
        for _ in 0..<answerCount {
            guard let (name, next) = readName(bytes, at: offset), next + 10 <= bytes.count else { return nil }
            let typeCode = UInt16(word(next))
            let ttl = UInt32(word(next + 4)) << 16 | UInt32(word(next + 6))
            let dataLength = word(next + 8)
            let dataStart = next + 10
            guard dataStart + dataLength <= bytes.count else { return nil }
            guard let value = describe(bytes, typeCode: typeCode, start: dataStart, length: dataLength) else { return nil }
            answers.append(DNSRecord(name: name, typeCode: typeCode, ttl: ttl, value: value))
            offset = dataStart + dataLength
        }

        return DNSResponse(
            id: UInt16(word(0)),
            responseCode: flags & 0x000F,
            isTruncated: flags & 0x0200 != 0,
            answers: answers
        )
    }

    /// Lit un nom à partir d'une position, en suivant les pointeurs de compression.
    /// Renvoie le nom et la position qui suit le nom dans le flux d'origine.
    static func readName(_ bytes: [UInt8], at start: Int) -> (name: String, next: Int)? {
        var labels: [String] = []
        var position = start
        var next: Int?
        var jumps = 0
        while true {
            guard position < bytes.count else { return nil }
            let length = Int(bytes[position])
            if length == 0 {
                let name = labels.isEmpty ? "." : labels.joined(separator: ".")
                return (name, next ?? position + 1)
            }
            if length & 0xC0 == 0xC0 {
                guard position + 1 < bytes.count else { return nil }
                let target = (length & 0x3F) << 8 | Int(bytes[position + 1])
                if next == nil { next = position + 2 }
                jumps += 1
                // Un pointeur ne peut viser qu'en arrière ; la limite coupe court aux boucles.
                guard jumps <= 32, target < position else { return nil }
                position = target
                continue
            }
            guard length & 0xC0 == 0, position + 1 + length <= bytes.count else { return nil }
            labels.append(String(decoding: bytes[(position + 1)..<(position + 1 + length)], as: UTF8.self))
            position += 1 + length
        }
    }

    private static func describe(_ bytes: [UInt8], typeCode: UInt16, start: Int, length: Int) -> String? {
        let end = start + length
        func word(_ index: Int) -> Int { Int(bytes[index]) << 8 | Int(bytes[index + 1]) }
        func long(_ index: Int) -> UInt32 { UInt32(word(index)) << 16 | UInt32(word(index + 2)) }

        switch DNSRecordType(rawValue: typeCode) {
        case .a:
            guard length == 4 else { return nil }
            return bytes[start..<end].map { String($0) }.joined(separator: ".")
        case .aaaa:
            guard length == 16 else { return nil }
            var value: UInt128 = 0
            for byte in bytes[start..<end] {
                value = (value << 8) | UInt128(byte)
            }
            return IPAddressV6(rawValue: value).description
        case .ns, .cname, .ptr:
            return readName(bytes, at: start)?.name
        case .mx:
            guard length >= 3, let exchange = readName(bytes, at: start + 2) else { return nil }
            return "\(word(start)) \(exchange.name)"
        case .txt:
            var parts: [String] = []
            var position = start
            while position < end {
                let partLength = Int(bytes[position])
                guard position + 1 + partLength <= end else { return nil }
                parts.append(String(decoding: bytes[(position + 1)..<(position + 1 + partLength)], as: UTF8.self))
                position += 1 + partLength
            }
            return "\"" + parts.joined() + "\""
        case .soa:
            guard let primary = readName(bytes, at: start),
                  let mailbox = readName(bytes, at: primary.next),
                  mailbox.next + 20 <= end else { return nil }
            let numbers = mailbox.next
            return L("\(primary.name) \(mailbox.name) série \(long(numbers)) rafraîchissement \(long(numbers + 4)) s ")
                + L("nouvel essai \(long(numbers + 8)) s expiration \(long(numbers + 12)) s minimum \(long(numbers + 16)) s")
        case nil:
            return L("\(length) octets")
        }
    }
}
