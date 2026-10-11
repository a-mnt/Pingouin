import Foundation

public enum PortListError: Error, Equatable, Sendable {
    case empty
    /// L'élément n'est ni un port ni une plage « début-fin ».
    case invalidToken(String)
    /// Un port est hors de l'intervalle 1 à 65535.
    case outOfRange(String)
    /// Plage dont le début dépasse la fin.
    case reversedRange(String)
}

/// Analyse d'une saisie de ports : éléments séparés par des virgules, des points-virgules ou des
/// retours à la ligne, chacun étant un port (« 443 ») ou une plage (« 8000-8100 »).
public enum PortList {
    /// Au-delà de ce nombre de ports, une confirmation explicite est demandée.
    public static let confirmationThreshold = 1_024

    /// Tous les ports TCP, de 1 à 65535.
    public static var all: [UInt16] { Array(1...UInt16.max) }

    /// Ports uniques, triés. Deux nombres séparés par un simple espace (« 22 80 ») sont refusés
    /// plutôt que devinés : l'oubli d'une virgule ne doit pas produire un autre port en silence.
    public static func parse(_ text: String) -> Result<[UInt16], PortListError> {
        let tokens = text
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return .failure(.empty) }

        var ports = Set<UInt16>()
        for token in tokens {
            let parts = token
                .split(separator: "-", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 1 || parts.count == 2 else { return .failure(.invalidToken(token)) }

            var bounds: [Int] = []
            for part in parts {
                guard !part.isEmpty, part.count <= 6,
                      part.allSatisfy({ $0.isASCII && $0.isWholeNumber }),
                      let value = Int(part) else { return .failure(.invalidToken(token)) }
                guard (1...65_535).contains(value) else { return .failure(.outOfRange(token)) }
                bounds.append(value)
            }

            let lower = bounds[0]
            let upper = bounds.count == 2 ? bounds[1] : bounds[0]
            guard lower <= upper else { return .failure(.reversedRange(token)) }

            for value in lower...upper {
                ports.insert(UInt16(value))
            }
        }
        return .success(ports.sorted())
    }

    /// Nom du service habituellement associé au port. Ce n'est qu'une convention :
    /// rien ne garantit que ce service écoute réellement.
    public static func usualService(for port: UInt16) -> String? {
        usualServices[port]
    }

    private static let usualServices: [UInt16: String] = [
        20: L("FTP (données)"), 21: "FTP", 22: "SSH", 23: L("Telnet"), 25: "SMTP", 53: "DNS",
        67: "DHCP", 80: "HTTP", 88: L("Kerberos"), 110: "POP3", 123: "NTP", 135: L("RPC Windows"),
        139: L("NetBIOS"), 143: "IMAP", 161: "SNMP", 389: "LDAP", 443: "HTTPS", 445: L("Partage de fichiers SMB"),
        465: L("SMTP sécurisé"), 514: L("Syslog"), 515: L("Impression LPD"), 548: L("Partage de fichiers AFP"),
        554: "RTSP", 587: L("SMTP (soumission)"), 631: L("Impression IPP"), 636: L("LDAP sécurisé"),
        993: L("IMAP sécurisé"), 995: L("POP3 sécurisé"), 1433: L("SQL Server"), 1521: L("Oracle"),
        1883: "MQTT", 3306: L("MySQL"), 3389: L("Bureau à distance RDP"), 5000: L("UPnP ou service web"),
        5432: L("PostgreSQL"), 5900: L("Partage d'écran VNC"), 6379: L("Redis"), 8000: L("HTTP alternatif"),
        8080: L("HTTP alternatif"), 8443: L("HTTPS alternatif"), 9100: L("Impression directe"), 27017: L("MongoDB")
    ]
}

/// Contrôle minimal d'un nom d'hôte ou d'une adresse saisis par l'utilisateur.
public enum HostInput {
    /// Vrai si la saisie peut être un nom d'hôte ou une adresse : non vide, 253 caractères au plus,
    /// sans espace ni caractère de chemin ou d'URL. La résolution réelle reste à la charge du réseau.
    public static func isPlausible(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= 253 else { return false }
        return !text.contains { $0.isWhitespace || $0 == "/" || $0 == "?" || $0 == "#" || $0 == "@" }
    }
}

/// Ce que le test de connexion a observé sur un port.
public enum PortProbeDetail: Hashable, Sendable {
    /// La connexion TCP a abouti.
    case accepted(milliseconds: Double)
    /// L'hôte a refusé la connexion.
    case refused
    /// Aucune réponse avant le délai.
    case timedOut
    /// Erreur réseau avant toute réponse (code système, 0 si inconnu).
    case networkError(code: Int32)
}

public enum PortState: Hashable, Sendable {
    case open
    case closed
    /// Le test ne permet pas de conclure : pas de réponse, ou erreur réseau.
    case undetermined
}

public struct PortScanResult: Hashable, Sendable, Identifiable {
    public let port: UInt16
    public let detail: PortProbeDetail

    public init(port: UInt16, detail: PortProbeDetail) {
        self.port = port
        self.detail = detail
    }

    public var id: UInt16 { port }

    public var state: PortState {
        switch detail {
        case .accepted: .open
        case .refused: .closed
        case .timedOut, .networkError: .undetermined
        }
    }
}
