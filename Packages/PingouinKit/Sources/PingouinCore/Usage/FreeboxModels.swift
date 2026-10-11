import CryptoKit
import Foundation

/// Enveloppe commune à toutes les réponses de l'API de Freebox OS.
public struct FreeboxEnvelope<Payload: Decodable & Sendable>: Decodable, Sendable {
    public let success: Bool
    public let result: Payload?
    public let message: String?
    public let errorCode: String?

    private enum CodingKeys: String, CodingKey {
        case success
        case result
        case message = "msg"
        case errorCode = "error_code"
    }
}

/// État d'une réponse, lu sans son contenu : une réponse d'erreur peut porter un `result`
/// d'une autre forme que celui attendu en cas de succès (un défi de connexion, par exemple).
public struct FreeboxStatus: Decodable, Sendable {
    public let success: Bool
    public let message: String?
    public let errorCode: String?

    private enum CodingKeys: String, CodingKey {
        case success
        case message = "msg"
        case errorCode = "error_code"
    }
}

/// Élément d'une liste, lu sans faire échouer la liste entière : un élément au format inattendu vaut `nil`.
public struct FreeboxLossy<Value: Decodable & Sendable>: Decodable, Sendable {
    public let value: Value?

    public init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// Nombre entier que l'API écrit tantôt comme un nombre, tantôt comme un texte.
public struct FreeboxNumber: Decodable, Sendable, Hashable {
    public let value: UInt64

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let integer = try? container.decode(UInt64.self) {
            value = integer
        } else if let double = try? container.decode(Double.self) {
            value = double > 0 ? UInt64(double) : 0
        } else if let text = try? container.decode(String.self) {
            value = UInt64(text) ?? 0
        } else {
            value = 0
        }
    }
}

public struct FreeboxAPIVersion: Decodable, Sendable {
    public let apiBaseURL: String?
    public let apiVersion: String?
    public let deviceName: String?

    private enum CodingKeys: String, CodingKey {
        case apiBaseURL = "api_base_url"
        case apiVersion = "api_version"
        case deviceName = "device_name"
    }

    /// Chemin de base des appels, par exemple « /api/v8/ ». `nil` si la réponse est incomplète.
    public var basePath: String? {
        guard let apiBaseURL, let apiVersion,
              let major = apiVersion.split(separator: ".").first, Int(major) != nil else {
            return nil
        }
        let prefix = apiBaseURL.hasSuffix("/") ? apiBaseURL : apiBaseURL + "/"
        return "\(prefix)v\(major)/"
    }
}

public struct FreeboxAuthorization: Decodable, Sendable {
    public let appToken: String
    public let trackID: Int

    private enum CodingKeys: String, CodingKey {
        case appToken = "app_token"
        case trackID = "track_id"
    }
}

public struct FreeboxAuthorizationStatus: Decodable, Sendable {
    public let status: String
}

public struct FreeboxLogin: Decodable, Sendable {
    public let challenge: String?
}

public struct FreeboxSession: Decodable, Sendable {
    public let sessionToken: String?

    private enum CodingKeys: String, CodingKey {
        case sessionToken = "session_token"
    }
}

extension KeyedDecodingContainer {
    /// Valeur d'un champ facultatif, ou `nil` s'il est absent ou d'un type inattendu.
    /// Un champ secondaire mal formé ne doit pas faire perdre tout l'objet.
    fileprivate func lenient<Value: Decodable>(_ type: Value.Type, _ key: Key) -> Value? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }

    /// Identifiant entier, écrit comme un nombre ou comme un texte.
    fileprivate func identifier(_ key: Key) throws -> Int {
        guard let number = lenient(FreeboxNumber.self, key) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Identifiant illisible")
        }
        return Int(clamping: number.value)
    }
}

public struct FreeboxAccessPoint: Decodable, Sendable {
    public struct Config: Decodable, Sendable {
        public let band: String?

        private enum CodingKeys: String, CodingKey {
            case band
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            band = container.lenient(String.self, .band)
        }
    }

    public let id: Int
    public let name: String?
    public let config: Config?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case config
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.identifier(.id)
        name = container.lenient(String.self, .name)
        config = container.lenient(Config.self, .config)
    }
}

public struct FreeboxLanHost: Decodable, Sendable {
    public struct Connectivity: Decodable, Sendable {
        public let addr: String?
        public let af: String?
        public let active: Bool?

        private enum CodingKeys: String, CodingKey {
            case addr
            case af
            case active
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            addr = container.lenient(String.self, .addr)
            af = container.lenient(String.self, .af)
            active = container.lenient(Bool.self, .active)
        }
    }

    /// Identifiant de niveau 2 d'un appareil : en pratique son adresse MAC.
    public struct Identifier: Decodable, Sendable {
        public let id: String?
        public let type: String?

        private enum CodingKeys: String, CodingKey {
            case id
            case type
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = container.lenient(String.self, .id)
            type = container.lenient(String.self, .type)
        }
    }

    public let primaryName: String?
    public let connectivities: [Connectivity]?
    public let identifiers: [Identifier]?

    private enum CodingKeys: String, CodingKey {
        case primaryName = "primary_name"
        case connectivities = "l3connectivities"
        case identifiers = "l2ident"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primaryName = container.lenient(String.self, .primaryName)
        connectivities = container.lenient([FreeboxLossy<Connectivity>].self, .connectivities)?.compactMap(\.value)
        identifiers = container.lenient([FreeboxLossy<Identifier>].self, .identifiers)?.compactMap(\.value)
    }

    /// Adresses MAC de l'appareil, en minuscules.
    public var macAddresses: [String] {
        (identifiers ?? []).filter { $0.type == "mac_address" }.compactMap { $0.id?.lowercased() }
    }

    /// Adresse IPv4 en service, sinon la première adresse IPv4 connue.
    public var ipv4Address: String? {
        let v4 = (connectivities ?? []).filter { $0.af == "ipv4" && $0.addr != nil }
        return (v4.first { $0.active == true } ?? v4.first)?.addr
    }
}

public struct FreeboxStation: Decodable, Sendable {
    public let mac: String?
    public let hostname: String?
    /// Octets reçus par la Freebox en provenance de l'appareil : ce que l'appareil a envoyé.
    public let rxBytes: FreeboxNumber?
    /// Octets envoyés par la Freebox à l'appareil : ce que l'appareil a reçu.
    public let txBytes: FreeboxNumber?
    public let host: FreeboxLanHost?

    private enum CodingKeys: String, CodingKey {
        case mac
        case hostname
        case rxBytes = "rx_bytes"
        case txBytes = "tx_bytes"
        case host
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mac = container.lenient(String.self, .mac)
        hostname = container.lenient(String.self, .hostname)
        rxBytes = container.lenient(FreeboxNumber.self, .rxBytes)
        txBytes = container.lenient(FreeboxNumber.self, .txBytes)
        host = container.lenient(FreeboxLanHost.self, .host)
    }
}

public struct FreeboxSwitchPort: Decodable, Sendable {
    public struct Neighbor: Decodable, Sendable {
        public let mac: String?
        public let hostname: String?
        public let name: String?

        private enum CodingKeys: String, CodingKey {
            case mac
            case hostname
            case name
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            mac = container.lenient(String.self, .mac)
            hostname = container.lenient(String.self, .hostname)
            name = container.lenient(String.self, .name)
        }
    }

    public let id: Int
    public let link: String?
    public let speed: FreeboxNumber?
    public let neighbors: [Neighbor]?

    private enum CodingKeys: String, CodingKey {
        case id
        case link
        case speed
        case neighbors = "mac_list"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.identifier(.id)
        link = container.lenient(String.self, .link)
        speed = container.lenient(FreeboxNumber.self, .speed)
        neighbors = container.lenient([FreeboxLossy<Neighbor>].self, .neighbors)?.compactMap(\.value)
    }
}

public struct FreeboxPortStats: Decodable, Sendable {
    public let rxGoodBytes: FreeboxNumber?
    public let txBytes: FreeboxNumber?

    private enum CodingKeys: String, CodingKey {
        case rxGoodBytes = "rx_good_bytes"
        case txBytes = "tx_bytes"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rxGoodBytes = container.lenient(FreeboxNumber.self, .rxGoodBytes)
        txBytes = container.lenient(FreeboxNumber.self, .txBytes)
    }
}

/// Règles propres à la Freebox, sans réseau : mot de passe de session et traduction en relevés.
public enum FreeboxLogic {
    /// Mot de passe de session : HMAC-SHA1 du défi, avec le jeton de l'application pour clé, en hexadécimal.
    public static func sessionPassword(appToken: String, challenge: String) -> String {
        let key = SymmetricKey(data: Data(appToken.utf8))
        let code = HMAC<Insecure.SHA1>.authenticationCode(for: Data(challenge.utf8), using: key)
        return code.map { byte in
            let text = String(byte, radix: 16)
            return text.count == 1 ? "0" + text : text
        }.joined()
    }

    public static func bandLabel(_ band: String?) -> String {
        switch band?.lowercased() {
        case "2d4g": return L("Wi-Fi 2,4 GHz")
        case "5g": return L("Wi-Fi 5 GHz")
        case "6g": return L("Wi-Fi 6 GHz")
        case "60g": return L("Wi-Fi 60 GHz")
        default: return "Wi-Fi"
        }
    }

    /// Relevé d'un appareil Wi-Fi. `nil` si la box ne donne pas son adresse MAC.
    public static func reading(station: FreeboxStation, band: String?) -> UsageReading? {
        guard let mac = station.mac?.lowercased(), !mac.isEmpty else { return nil }
        let candidates = [station.host?.primaryName, station.hostname]
        let name = candidates.compactMap { $0 }.first { !$0.isEmpty } ?? mac
        return UsageReading(
            key: "wifi:\(mac)",
            info: UsageDeviceInfo(name: name, address: station.host?.ipv4Address ?? "", link: bandLabel(band)),
            counters: UsageCounters(received: station.txBytes?.value ?? 0, sent: station.rxBytes?.value ?? 0)
        )
    }

    /// Relevé d'un port Ethernet de la box. `nil` si rien n'y est branché.
    ///
    /// Un port derrière lequel la box voit plusieurs appareils est mesuré en bloc : elle ne les départage pas.
    ///
    /// `hosts` : appareils connus de la box, par adresse MAC en minuscules. Il sert à nommer les
    /// appareils du port et à donner leur adresse IP ; sans lui, seuls les noms vus par le port sont repris.
    public static func reading(
        port: FreeboxSwitchPort,
        stats: FreeboxPortStats,
        hosts: [String: FreeboxLanHost] = [:]
    ) -> UsageReading? {
        guard port.link?.lowercased() == "up" else { return nil }
        var names: [String] = []
        var addresses: [String] = []
        for neighbor in port.neighbors ?? [] {
            let host = neighbor.mac.flatMap { hosts[$0.lowercased()] }
            let candidates = [host?.primaryName, neighbor.hostname, neighbor.name, neighbor.mac]
            guard let name = candidates.compactMap({ $0 }).first(where: { !$0.isEmpty }) else { continue }
            names.append(name)
            addresses.append(host?.ipv4Address ?? "")
        }
        var link = "Ethernet"
        if let speed = port.speed?.value, speed > 0 {
            link += speed >= 1_000 ? L(" \(speed / 1_000) Gb/s") : L(" \(speed) Mb/s")
        }
        let name = names.count == 1 ? names[0] : L("Port Ethernet \(port.id)")
        return UsageReading(
            key: "port:\(port.id)",
            info: UsageDeviceInfo(
                name: name,
                address: names.count == 1 ? addresses[0] : "",
                link: link,
                members: names.count > 1 ? names : [],
                memberAddresses: names.count > 1 ? addresses : nil
            ),
            counters: UsageCounters(received: stats.txBytes?.value ?? 0, sent: stats.rxGoodBytes?.value ?? 0)
        )
    }
}
