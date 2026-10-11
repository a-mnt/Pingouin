import Foundation

/// Volumes échangés par un appareil, vus depuis l'appareil : ce qu'il a reçu et ce qu'il a envoyé, en octets.
public struct UsageCounters: Codable, Hashable, Sendable {
    public var received: UInt64
    public var sent: UInt64

    public init(received: UInt64 = 0, sent: UInt64 = 0) {
        self.received = received
        self.sent = sent
    }

    public var total: UInt64 { received &+ sent }

    public static func + (left: UsageCounters, right: UsageCounters) -> UsageCounters {
        UsageCounters(received: left.received &+ right.received, sent: left.sent &+ right.sent)
    }
}

/// Ce que la box sait d'un appareil, ou d'un port derrière lequel se trouvent plusieurs appareils.
public struct UsageDeviceInfo: Codable, Hashable, Sendable {
    public var name: String
    /// Adresse IP, quand la box la donne.
    public var address: String
    /// Liaison lisible : « Wi-Fi 5 GHz », « Ethernet 1 Gb/s »…
    public var link: String
    /// Noms des appareils regroupés, quand la mesure porte sur plusieurs appareils non départagés.
    public var members: [String]
    /// Adresse IP de chaque appareil regroupé, dans l'ordre de `members` ; vide quand elle est inconnue.
    /// Facultatif pour rester lisible dans les fichiers enregistrés avant son ajout.
    public var memberAddresses: [String]?

    public init(name: String, address: String = "", link: String, members: [String] = [], memberAddresses: [String]? = nil) {
        self.name = name
        self.address = address
        self.link = link
        self.members = members
        self.memberAddresses = memberAddresses
    }

    /// Vrai si la mesure regroupe plusieurs appareils que la box ne sait pas départager.
    public var isShared: Bool { members.count > 1 }
}

/// Relevé d'un compteur de la box à un instant donné. Les compteurs sont cumulés par la box :
/// ils repartent de zéro quand l'appareil se reconnecte ou que la box redémarre.
public struct UsageReading: Hashable, Sendable {
    /// Identifiant stable de ce qui est mesuré : « wifi:<adresse MAC> » ou « port:<numéro> ».
    public let key: String
    public let info: UsageDeviceInfo
    public let counters: UsageCounters

    public init(key: String, info: UsageDeviceInfo, counters: UsageCounters) {
        self.key = key
        self.info = info
        self.counters = counters
    }
}

public enum UsageMath {
    /// Octets échangés entre deux relevés d'un même compteur cumulé.
    ///
    /// Sans relevé précédent, rien n'est compté : le premier relevé sert de point de départ.
    /// Un compteur plus petit que le précédent a été remis à zéro : tout ce qu'il affiche est nouveau.
    public static func delta(previous: UInt64?, current: UInt64) -> UInt64 {
        guard let previous else { return 0 }
        return current >= previous ? current - previous : current
    }
}

/// Suivi des relevés pendant que l'application tourne : écarts entre relevés, cumul depuis l'ouverture, débits.
public struct UsageTracker: Sendable {
    /// Au-delà de cet écart entre deux relevés, le débit n'est plus calculé : il ne voudrait rien dire.
    public static let maximumRateInterval: TimeInterval = 300

    private var lastCounters: [String: UsageCounters] = [:]
    private var lastDates: [String: Date] = [:]
    /// Cumul depuis l'ouverture de l'application, par clé.
    public private(set) var sessionTotals: [String: UsageCounters] = [:]
    /// Débit constaté entre les deux derniers relevés, en octets par seconde, par clé.
    public private(set) var rates: [String: UsageCounters] = [:]
    /// Clés présentes dans le dernier relevé.
    public private(set) var presentKeys: Set<String> = []

    public init() {}

    /// Intègre un relevé complet et renvoie, par clé, ce qui a été échangé depuis le relevé précédent.
    public mutating func ingest(_ readings: [UsageReading], at date: Date) -> [String: UsageCounters] {
        var deltas: [String: UsageCounters] = [:]
        var newRates: [String: UsageCounters] = [:]
        for reading in readings {
            let previous = lastCounters[reading.key]
            let delta = UsageCounters(
                received: UsageMath.delta(previous: previous?.received, current: reading.counters.received),
                sent: UsageMath.delta(previous: previous?.sent, current: reading.counters.sent)
            )
            if let lastDate = lastDates[reading.key] {
                let elapsed = date.timeIntervalSince(lastDate)
                if elapsed > 0, elapsed <= Self.maximumRateInterval {
                    newRates[reading.key] = UsageCounters(
                        received: UInt64(Double(delta.received) / elapsed),
                        sent: UInt64(Double(delta.sent) / elapsed)
                    )
                }
            }
            lastCounters[reading.key] = reading.counters
            lastDates[reading.key] = date
            if delta.total > 0 {
                deltas[reading.key] = delta
                sessionTotals[reading.key] = (sessionTotals[reading.key] ?? UsageCounters()) + delta
            } else if sessionTotals[reading.key] == nil {
                // L'appareil apparaît dans la liste dès son premier relevé, même sans trafic.
                sessionTotals[reading.key] = UsageCounters()
            }
        }
        rates = newRates
        presentKeys = Set(readings.map(\.key))
        return deltas
    }
}

/// Registre conservé d'un lancement à l'autre : cumul par jour et par clé, et description des appareils.
public struct UsageLedger: Codable, Sendable, Equatable {
    /// Jour (« 2026-10-10 ») → clé → cumul du jour.
    public private(set) var days: [String: [String: UsageCounters]] = [:]
    public private(set) var devices: [String: UsageDeviceInfo] = [:]

    public init() {}

    public mutating func record(_ deltas: [String: UsageCounters], day: String) {
        guard !deltas.isEmpty else { return }
        var bucket = days[day] ?? [:]
        for (key, delta) in deltas {
            bucket[key] = (bucket[key] ?? UsageCounters()) + delta
        }
        days[day] = bucket
    }

    public mutating func describe(_ readings: [UsageReading]) {
        for reading in readings {
            devices[reading.key] = reading.info
        }
    }

    /// Cumul par clé sur les jours demandés.
    public func totals(days wanted: [String]) -> [String: UsageCounters] {
        var result: [String: UsageCounters] = [:]
        for day in wanted {
            for (key, counters) in days[day] ?? [:] {
                result[key] = (result[key] ?? UsageCounters()) + counters
            }
        }
        return result
    }

    /// Ne garde que les `count` jours les plus récents. Les clés de jour se trient par ordre chronologique.
    public mutating func trim(keepingDays count: Int) {
        let kept = Set(days.keys.sorted().suffix(max(count, 0)))
        days = days.filter { kept.contains($0.key) }
    }
}

/// Écriture d'un volume ou d'un débit, en unités décimales (1 Ko = 1 000 octets, comme macOS).
/// Les unités suivent la langue : « Ko » en français, « kB » ailleurs.
public enum ByteFormat {
    private static var units: [String] { [L("o"), L("Ko"), L("Mo"), L("Go"), L("To")] }

    /// `decimalSeparator` : celui de la région de l'utilisateur, sauf indication contraire.
    public static func volume(_ bytes: UInt64, decimalSeparator: String = Locale.current.decimalSeparator ?? ",") -> String {
        var value = Double(bytes)
        var index = 0
        while value >= 1_000, index < units.count - 1 {
            value /= 1_000
            index += 1
        }
        // Une décimale sous 100 dans les unités composées ; jamais pour les octets.
        if index == 0 || value >= 99.95 {
            return "\(Int(value.rounded())) \(units[index])"
        }
        let tenths = Int((value * 10).rounded())
        return "\(tenths / 10)\(decimalSeparator)\(tenths % 10) \(units[index])"
    }

    public static func rate(_ bytesPerSecond: UInt64, decimalSeparator: String = Locale.current.decimalSeparator ?? ",") -> String {
        volume(bytesPerSecond, decimalSeparator: decimalSeparator) + "/s"
    }
}
