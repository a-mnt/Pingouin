import Foundation
import Testing
@testable import PingouinCore

@Suite("Supervision : mémoire par heure")
struct MonitorHistoryTests {

    /// Lundi 5 octobre 2026 à 10:00:00 UTC, un début d'heure.
    private let base = Date(timeIntervalSince1970: 1_791_194_400)

    private func sample(_ offset: TimeInterval, success: Bool = true, milliseconds: Double? = 10) -> MonitorSample {
        MonitorSample(date: base.addingTimeInterval(offset), success: success, milliseconds: success ? milliseconds : nil)
    }

    @Test("La date de référence est bien un début d'heure")
    func baseIsHourStart() {
        #expect(MonitorHistory.hourStart(of: base) == base)
        #expect(MonitorHistory.hourStart(of: base.addingTimeInterval(3_599)) == base)
        #expect(MonitorHistory.hourStart(of: base.addingTimeInterval(3_600)) == base.addingTimeInterval(3_600))
    }

    @Test("Les contrôles d'une même heure sont résumés ensemble")
    func sameHour() {
        var history = MonitorHistory()
        history.add(sample(0, milliseconds: 10))
        history.add(sample(60, milliseconds: 30))
        history.add(sample(120, success: false))
        #expect(history.hours.count == 1)
        let bucket = history.hours[0]
        #expect(bucket.hour == base)
        #expect(bucket.count == 3)
        #expect(bucket.successes == 2)
        #expect(bucket.averageMilliseconds == 20)
        #expect(bucket.maximumMilliseconds == 30)
        #expect(history.recent.count == 3)
    }

    @Test("Une nouvelle heure ouvre un nouveau résumé")
    func newHour() {
        var history = MonitorHistory()
        history.add(sample(3_590))
        history.add(sample(3_610, success: false))
        #expect(history.hours.count == 2)
        #expect(history.hours[0].successes == 1)
        #expect(history.hours[1].successes == 0)
        #expect(history.hours[1].averageMilliseconds == nil)
    }

    @Test("Le détail est limité, les résumés gardent tout le compte")
    func recentIsTrimmed() {
        var history = MonitorHistory()
        for index in 0..<200 {
            history.add(sample(Double(index) * 10))
        }
        #expect(history.recent.count == MonitorHistory.recentLimit)
        #expect(history.recent.first?.date == base.addingTimeInterval(800))
        #expect(history.hours.reduce(0) { $0 + $1.count } == 200)
    }

    @Test("Les heures les plus anciennes sont abandonnées au-delà de la limite")
    func hoursAreTrimmed() {
        var history = MonitorHistory()
        for hour in 0..<(MonitorHistory.hourLimit + 5) {
            history.add(sample(Double(hour) * 3_600))
        }
        #expect(history.hours.count == MonitorHistory.hourLimit)
        #expect(history.hours.first?.hour == base.addingTimeInterval(5 * 3_600))
    }

    @Test("La disponibilité par heure additionne les heures de la période")
    func hourlyAvailability() {
        var history = MonitorHistory()
        // Heure 0 : 2 réussites. Heure 1 : 1 réussite, 1 échec. Heure 2 : 2 échecs.
        history.add(sample(0))
        history.add(sample(60))
        history.add(sample(3_600))
        history.add(sample(3_660, success: false))
        history.add(sample(7_200, success: false))
        history.add(sample(7_260, success: false))

        #expect(history.hourlyAvailabilityPercent(since: base) == 50)
        // Depuis le début de l'heure 1 : 1 réussite sur 4.
        #expect(history.hourlyAvailabilityPercent(since: base.addingTimeInterval(3_600)) == 25)
        // Une période qui commence au milieu d'une heure prend cette heure en entier.
        #expect(history.hourlyAvailabilityPercent(since: base.addingTimeInterval(3_700)) == 25)
        #expect(history.hourlyAvailabilityPercent(since: base.addingTimeInterval(20_000)) == nil)
    }

    @Test("La disponibilité récente ne lit que le détail")
    func recentAvailability() {
        var history = MonitorHistory()
        history.add(sample(0, success: false))
        history.add(sample(60))
        history.add(sample(120))
        #expect(history.recentAvailabilityPercent(since: base.addingTimeInterval(30)) == 100)
        #expect(history.recentAvailabilityPercent(since: base.addingTimeInterval(500)) == nil)
    }

    @Test("Une ancienne liste de contrôles est convertie sans changer la disponibilité")
    func conversionFromSamples() {
        let samples = [sample(7_200, success: false), sample(0), sample(3_600), sample(60)]
        let history = MonitorHistory(samples: samples)
        #expect(history.hours.count == 3)
        #expect(history.recent.map(\.date) == samples.map(\.date).sorted())
        #expect(history.hourlyAvailabilityPercent(since: base) == 75)
    }

    @Test("La mémoire se relit après enregistrement")
    func codable() throws {
        var history = MonitorHistory()
        history.add(sample(0))
        history.add(sample(3_600, success: false))
        let data = try JSONEncoder().encode(history)
        let decoded = try JSONDecoder().decode(MonitorHistory.self, from: data)
        #expect(decoded == history)
    }
}
