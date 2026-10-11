import Foundation

/// Statistiques d'une série de pings, calculées sur les temps aller-retour en millisecondes.
public struct PingStatistics: Equatable, Sendable {
    public let sent: Int
    public let received: Int
    public let minimum: Double?
    public let average: Double?
    public let maximum: Double?
    /// Écart-type des temps de réponse : mesure de leur régularité.
    public let standardDeviation: Double?

    /// - Parameters:
    ///   - sent: nombre de requêtes envoyées (réponses reçues et délais dépassés confondus).
    ///   - roundTrips: temps des réponses reçues.
    public init(sent: Int, roundTrips: [Double]) {
        self.sent = max(sent, roundTrips.count)
        self.received = roundTrips.count
        guard !roundTrips.isEmpty else {
            minimum = nil
            average = nil
            maximum = nil
            standardDeviation = nil
            return
        }
        let mean = roundTrips.reduce(0, +) / Double(roundTrips.count)
        let variance = roundTrips.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(roundTrips.count)
        minimum = roundTrips.min()
        average = mean
        maximum = roundTrips.max()
        standardDeviation = variance.squareRoot()
    }

    public var lost: Int { sent - received }

    /// Part des requêtes restées sans réponse, de 0 à 100.
    public var lossPercent: Double {
        sent == 0 ? 0 : Double(lost) / Double(sent) * 100
    }
}
