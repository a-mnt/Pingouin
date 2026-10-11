import Foundation

/// Résumé des contrôles d'une surveillance sur une heure.
public struct MonitorHourBucket: Codable, Hashable, Sendable {
    /// Début de l'heure résumée.
    public var hour: Date
    public var count: Int
    public var successes: Int
    /// Somme des temps de réponse mesurés, et nombre de contrôles qui en ont donné un : leur rapport
    /// est le temps moyen.
    public var totalMilliseconds: Double
    public var timedCount: Int
    public var maximumMilliseconds: Double?

    public init(hour: Date) {
        self.hour = hour
        count = 0
        successes = 0
        totalMilliseconds = 0
        timedCount = 0
        maximumMilliseconds = nil
    }

    public var averageMilliseconds: Double? {
        timedCount > 0 ? totalMilliseconds / Double(timedCount) : nil
    }

    mutating func add(_ sample: MonitorSample) {
        count += 1
        if sample.success {
            successes += 1
        }
        if let time = sample.milliseconds {
            totalMilliseconds += time
            timedCount += 1
            maximumMilliseconds = max(maximumMilliseconds ?? time, time)
        }
    }
}

/// Mémoire d'une surveillance : ses derniers contrôles en détail, et un résumé par heure au-delà.
///
/// Le détail sert aux tuiles et à la disponibilité sur une heure ; les résumés servent aux périodes
/// longues. Rien n'est gardé au-delà de `hourLimit` heures.
public struct MonitorHistory: Codable, Hashable, Sendable {
    /// Nombre de contrôles gardés en détail.
    public static let recentLimit = 120
    /// Nombre d'heures résumées gardées : 30 jours.
    public static let hourLimit = 720

    /// Derniers contrôles, du plus ancien au plus récent.
    public private(set) var recent: [MonitorSample] = []
    /// Résumés par heure, de la plus ancienne à la plus récente.
    public private(set) var hours: [MonitorHourBucket] = []

    public init() {}

    /// Reconstitue une mémoire à partir d'une liste de contrôles, dans l'ordre chronologique.
    public init(samples: [MonitorSample]) {
        for sample in samples.sorted(by: { $0.date < $1.date }) {
            add(sample)
        }
    }

    /// Début de l'heure qui contient cet instant.
    public static func hourStart(of date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 3_600).rounded(.down) * 3_600)
    }

    public mutating func add(_ sample: MonitorSample) {
        recent.append(sample)
        if recent.count > Self.recentLimit {
            recent.removeFirst(recent.count - Self.recentLimit)
        }

        let hour = Self.hourStart(of: sample.date)
        if let last = hours.last, last.hour == hour {
            hours[hours.count - 1].add(sample)
        } else if let index = hours.firstIndex(where: { $0.hour == hour }) {
            // Contrôle arrivé dans le désordre : il rejoint son heure.
            hours[index].add(sample)
        } else {
            var bucket = MonitorHourBucket(hour: hour)
            bucket.add(sample)
            hours.append(bucket)
            hours.sort { $0.hour < $1.hour }
            if hours.count > Self.hourLimit {
                hours.removeFirst(hours.count - Self.hourLimit)
            }
        }
    }

    /// Part des contrôles réussis parmi les contrôles détaillés depuis `start`, de 0 à 100.
    /// Pour les périodes courtes. `nil` s'il n'y a aucun contrôle sur la période.
    public func recentAvailabilityPercent(since start: Date) -> Double? {
        MonitorLogic.availabilityPercent(samples: recent, since: start)
    }

    /// Part des contrôles réussis d'après les résumés par heure, de 0 à 100. Toute heure qui recouvre
    /// la période compte en entier. `nil` s'il n'y a aucun contrôle : une période sans mesure
    /// n'est jamais comptée comme une panne.
    public func hourlyAvailabilityPercent(since start: Date) -> Double? {
        var count = 0
        var successes = 0
        for bucket in hours where bucket.hour.addingTimeInterval(3_600) > start {
            count += bucket.count
            successes += bucket.successes
        }
        guard count > 0 else { return nil }
        return Double(successes) / Double(count) * 100
    }
}
