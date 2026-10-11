import Foundation
import Testing
@testable import PingouinCore

@Suite("Consommation par appareil")
struct UsageTests {

    private func reading(_ key: String, received: UInt64, sent: UInt64) -> UsageReading {
        UsageReading(
            key: key,
            info: UsageDeviceInfo(name: key, link: "Wi-Fi"),
            counters: UsageCounters(received: received, sent: sent)
        )
    }

    @Test("Le premier relevé sert de point de départ : rien n'est compté")
    func firstReadingCountsNothing() {
        #expect(UsageMath.delta(previous: nil, current: 5_000) == 0)
    }

    @Test("Un compteur qui grandit donne l'écart")
    func growingCounter() {
        #expect(UsageMath.delta(previous: 1_000, current: 1_750) == 750)
    }

    @Test("Un compteur remis à zéro compte tout ce qu'il affiche")
    func resetCounter() {
        #expect(UsageMath.delta(previous: 9_000, current: 300) == 300)
    }

    @Test("Le suivi cumule les écarts et calcule le débit")
    func trackerAccumulates() {
        var tracker = UsageTracker()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let first = tracker.ingest([reading("wifi:a", received: 10_000, sent: 1_000)], at: start)
        #expect(first.isEmpty)
        #expect(tracker.sessionTotals["wifi:a"] == UsageCounters())

        let second = tracker.ingest([reading("wifi:a", received: 40_000, sent: 4_000)], at: start.addingTimeInterval(30))
        #expect(second["wifi:a"] == UsageCounters(received: 30_000, sent: 3_000))
        #expect(tracker.sessionTotals["wifi:a"] == UsageCounters(received: 30_000, sent: 3_000))
        #expect(tracker.rates["wifi:a"] == UsageCounters(received: 1_000, sent: 100))

        // Reconnexion : le compteur de la box repart de zéro.
        let third = tracker.ingest([reading("wifi:a", received: 2_000, sent: 500)], at: start.addingTimeInterval(60))
        #expect(third["wifi:a"] == UsageCounters(received: 2_000, sent: 500))
        #expect(tracker.sessionTotals["wifi:a"] == UsageCounters(received: 32_000, sent: 3_500))
        #expect(tracker.presentKeys == ["wifi:a"])
    }

    @Test("Aucun débit n'est calculé après une longue interruption")
    func noRateAfterLongGap() {
        var tracker = UsageTracker()
        let start = Date(timeIntervalSince1970: 1_000_000)
        _ = tracker.ingest([reading("wifi:a", received: 0, sent: 0)], at: start)
        _ = tracker.ingest([reading("wifi:a", received: 9_000, sent: 0)], at: start.addingTimeInterval(3_600))
        #expect(tracker.rates["wifi:a"] == nil)
        #expect(tracker.sessionTotals["wifi:a"]?.received == 9_000)
    }

    @Test("Le registre cumule par jour et additionne les jours demandés")
    func ledgerTotals() {
        var ledger = UsageLedger()
        ledger.record(["wifi:a": UsageCounters(received: 100, sent: 10)], day: "2026-10-09")
        ledger.record(["wifi:a": UsageCounters(received: 50, sent: 5)], day: "2026-10-10")
        ledger.record(["wifi:a": UsageCounters(received: 25, sent: 0), "port:2": UsageCounters(received: 7, sent: 3)], day: "2026-10-10")

        let today = ledger.totals(days: ["2026-10-10"])
        #expect(today["wifi:a"] == UsageCounters(received: 75, sent: 5))
        #expect(today["port:2"] == UsageCounters(received: 7, sent: 3))

        let both = ledger.totals(days: ["2026-10-09", "2026-10-10"])
        #expect(both["wifi:a"] == UsageCounters(received: 175, sent: 15))

        ledger.trim(keepingDays: 1)
        #expect(ledger.days.keys.sorted() == ["2026-10-10"])
    }

    @Test("Les volumes sont écrits en unités décimales, avec une virgule")
    func byteFormat() {
        #expect(ByteFormat.volume(0) == "0 o")
        #expect(ByteFormat.volume(999) == "999 o")
        #expect(ByteFormat.volume(1_500, decimalSeparator: ",") == "1,5 Ko")
        #expect(ByteFormat.volume(12_000_000, decimalSeparator: ",") == "12,0 Mo")
        #expect(ByteFormat.volume(18_400_000_000, decimalSeparator: ",") == "18,4 Go")
        #expect(ByteFormat.volume(250_000_000) == "250 Mo")
        #expect(ByteFormat.rate(4_600_000, decimalSeparator: ",") == "4,6 Mo/s")
    }

    @Test("Le mot de passe de session Freebox est un HMAC-SHA1 en hexadécimal")
    func freeboxPassword() {
        // Vecteur d'essai classique de HMAC-SHA1.
        let password = FreeboxLogic.sessionPassword(appToken: "key", challenge: "The quick brown fox jumps over the lazy dog")
        #expect(password == "de7c9b85b8b78aa6bc8a7a36f70a90701c9db4d9")
    }

    @Test("Le chemin de base de l'API vient de la version annoncée par la box")
    func freeboxBasePath() throws {
        let json = Data(#"{"api_base_url":"/api/","api_version":"8.0","device_name":"Freebox Server"}"#.utf8)
        let version = try JSONDecoder().decode(FreeboxAPIVersion.self, from: json)
        #expect(version.basePath == "/api/v8/")
    }

    @Test("Une station Wi-Fi devient un relevé vu depuis l'appareil")
    func freeboxStation() throws {
        let json = Data(#"""
        {"success":true,"result":[{"mac":"AA:BB:CC:00:11:22","hostname":"tv","rx_bytes":210,"tx_bytes":9800,
        "host":{"primary_name":"tv-salon","l3connectivities":[{"addr":"fe80::1","af":"ipv6","active":true},
        {"addr":"192.168.1.31","af":"ipv4","active":true}]}}]}
        """#.utf8)
        let envelope = try JSONDecoder().decode(FreeboxEnvelope<[FreeboxStation]>.self, from: json)
        let stations = envelope.result ?? []
        #expect(stations.count == 1)
        let station = try #require(stations.first)
        let reading = try #require(FreeboxLogic.reading(station: station, band: "5g"))
        #expect(reading.key == "wifi:aa:bb:cc:00:11:22")
        #expect(reading.info.name == "tv-salon")
        #expect(reading.info.address == "192.168.1.31")
        #expect(reading.info.link == "Wi-Fi 5 GHz")
        // Ce que la box envoie, l'appareil le reçoit.
        #expect(reading.counters == UsageCounters(received: 9_800, sent: 210))
    }

    @Test("Un port Ethernet avec plusieurs appareils est mesuré en bloc")
    func freeboxSharedPort() throws {
        let portJSON = Data(#"{"id":2,"link":"up","speed":"1000","mac_list":[{"mac":"AA:AA:AA:AA:AA:01","hostname":"nas"},{"mac":"AA:AA:AA:AA:AA:02","hostname":"imprimante"}]}"#.utf8)
        let statsJSON = Data(#"{"rx_good_bytes":640,"tx_bytes":2900}"#.utf8)
        let port = try JSONDecoder().decode(FreeboxSwitchPort.self, from: portJSON)
        let stats = try JSONDecoder().decode(FreeboxPortStats.self, from: statsJSON)
        let reading = try #require(FreeboxLogic.reading(port: port, stats: stats))
        #expect(reading.key == "port:2")
        #expect(reading.info.name == "Port Ethernet 2")
        #expect(reading.info.link == "Ethernet 1 Gb/s")
        #expect(reading.info.isShared)
        #expect(reading.info.members == ["nas", "imprimante"])
        #expect(reading.counters == UsageCounters(received: 2_900, sent: 640))
    }

    @Test("Les appareils d'un port partagé prennent le nom et l'adresse connus de la box")
    func freeboxSharedPortWithHosts() throws {
        let portJSON = Data(#"{"id":1,"link":"up","speed":"100","mac_list":[{"mac":"AA:AA:AA:AA:AA:01","hostname":"nas"},{"mac":"AA:AA:AA:AA:AA:02","hostname":"inconnu"}]}"#.utf8)
        let hostJSON = Data(#"{"primary_name":"NAS du bureau","l2ident":[{"id":"AA:AA:AA:AA:AA:01","type":"mac_address"}],"l3connectivities":[{"addr":"192.168.1.20","af":"ipv4","active":true}]}"#.utf8)
        let port = try JSONDecoder().decode(FreeboxSwitchPort.self, from: portJSON)
        let stats = try JSONDecoder().decode(FreeboxPortStats.self, from: Data("{}".utf8))
        let host = try JSONDecoder().decode(FreeboxLanHost.self, from: hostJSON)
        #expect(host.macAddresses == ["aa:aa:aa:aa:aa:01"])
        let reading = try #require(FreeboxLogic.reading(port: port, stats: stats, hosts: ["aa:aa:aa:aa:aa:01": host]))
        #expect(reading.info.link == "Ethernet 100 Mb/s")
        #expect(reading.info.members == ["NAS du bureau", "inconnu"])
        #expect(reading.info.memberAddresses == ["192.168.1.20", ""])
    }

    @Test("Un registre enregistré avant l'ajout des adresses reste lisible")
    func ledgerWithoutMemberAddresses() throws {
        let json = Data(#"{"name":"Port Ethernet 1","address":"","link":"Ethernet","members":["a","b"]}"#.utf8)
        let info = try JSONDecoder().decode(UsageDeviceInfo.self, from: json)
        #expect(info.isShared)
        #expect(info.memberAddresses == nil)
    }

    @Test("Un port sans lien ne donne pas de relevé")
    func freeboxDownPort() throws {
        let port = try JSONDecoder().decode(FreeboxSwitchPort.self, from: Data(#"{"id":3,"link":"down"}"#.utf8))
        let stats = try JSONDecoder().decode(FreeboxPortStats.self, from: Data("{}".utf8))
        #expect(FreeboxLogic.reading(port: port, stats: stats) == nil)
    }

    @Test("Un champ secondaire au format inattendu ne fait pas perdre l'appareil")
    func freeboxLenientFields() throws {
        // « host » est un texte au lieu d'un objet, « rx_bytes » est un texte, et un élément est illisible.
        let json = Data(#"""
        {"success":true,"result":[{"mac":"AA:BB:CC:00:11:33","hostname":"tablette","rx_bytes":"120","tx_bytes":4500,"host":"inconnu"},
        "element illisible",{"id":"3","name":{"x":1}}]}
        """#.utf8)
        let envelope = try JSONDecoder().decode(FreeboxEnvelope<[FreeboxLossy<FreeboxStation>]>.self, from: json)
        let elements = envelope.result ?? []
        #expect(elements.count == 3)
        #expect(elements[1].value == nil)
        let station = try #require(elements[0].value)
        let reading = try #require(FreeboxLogic.reading(station: station, band: nil))
        #expect(reading.info.name == "tablette")
        #expect(reading.info.link == "Wi-Fi")
        #expect(reading.counters == UsageCounters(received: 4_500, sent: 120))
    }

    @Test("Un identifiant écrit comme un texte est accepté")
    func freeboxTextIdentifier() throws {
        let port = try JSONDecoder().decode(FreeboxSwitchPort.self, from: Data(#"{"id":"4","link":"up","speed":1000,"mac_list":"aucun"}"#.utf8))
        #expect(port.id == 4)
        #expect(port.neighbors == nil)
        let accessPoint = try JSONDecoder().decode(FreeboxAccessPoint.self, from: Data(#"{"id":1,"name":{"x":1},"config":{"band":"6g"}}"#.utf8))
        #expect(accessPoint.id == 1)
        #expect(accessPoint.name == nil)
        #expect(accessPoint.config?.band == "6g")
    }

    @Test("Une erreur dont le contenu a une autre forme reste lisible")
    func freeboxErrorWithOtherResult() throws {
        // La box joint un défi de connexion à l'erreur, là où le succès aurait porté une liste.
        let json = Data(#"{"success":false,"msg":"Vous devez vous connecter","error_code":"auth_required","result":{"challenge":"abc","password_salt":"xyz"}}"#.utf8)
        let status = try JSONDecoder().decode(FreeboxStatus.self, from: json)
        #expect(status.success == false)
        #expect(status.errorCode == "auth_required")
    }

    @Test("Une réponse d'erreur garde son code")
    func freeboxError() throws {
        let json = Data(#"{"success":false,"msg":"Authentification requise","error_code":"auth_required"}"#.utf8)
        let envelope = try JSONDecoder().decode(FreeboxEnvelope<FreeboxSession>.self, from: json)
        #expect(envelope.success == false)
        #expect(envelope.errorCode == "auth_required")
        #expect(envelope.result == nil)
    }
}
