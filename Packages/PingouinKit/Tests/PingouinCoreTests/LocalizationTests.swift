import Foundation
import Testing
@testable import PingouinCore

@Suite("Traduction : clés et insertion des valeurs")
struct LocalizationTests {

    @Test("La clé remplace chaque valeur par « %@ » et double le signe « % »")
    func keys() {
        let plain: LocalizedText = "Lancer la découverte"
        #expect(plain.key == "Lancer la découverte")
        #expect(plain.arguments.isEmpty)

        let port = 22
        let host = "nas.local"
        let mixed: LocalizedText = "Port \(port) ouvert sur \(host), perte 5 %"
        #expect(mixed.key == "Port %@ ouvert sur %@, perte 5 %%")
        #expect(mixed.arguments == ["22", "nas.local"])

        let percent: LocalizedText = "moins de 1 %"
        #expect(percent.key == "moins de 1 %%")
    }

    @Test("Les valeurs sont insérées dans l'ordre, ou par position")
    func fill() {
        #expect(Localization.fill("Port %@ ouvert sur %@", with: ["22", "nas"]) == "Port 22 ouvert sur nas")
        #expect(Localization.fill("%2$@ von %1$@ Knoten", with: ["3", "5"]) == "5 von 3 Knoten")
        #expect(Localization.fill("perte %@ %%", with: ["5"]) == "perte 5 %")
        #expect(Localization.fill("sans valeur", with: ["inutile"]) == "sans valeur")
    }

    @Test("Une traduction mal formée ne fait rien lire qui n'existe pas")
    func malformed() {
        #expect(Localization.fill("%@ et %@", with: ["un"]) == "un et ")
        #expect(Localization.fill("%9$@ ici", with: ["un"]) == " ici")
        #expect(Localization.fill("100 % sûr", with: []) == "100 % sûr")
        #expect(Localization.fill("fin %", with: []) == "fin %")
        #expect(Localization.fill("%d éléments", with: ["3"]) == "%d éléments")
    }

    @Test("Sans catalogue, le texte reste le français du code")
    func fallback() {
        let count = 3
        #expect(L("\(count) hôtes trouvés.") == "3 hôtes trouvés.")
        #expect(L("moins de 1 %") == "moins de 1 %")
        #expect(L(count: 1, one: "\(1) étape", other: "\(1) étapes") == "1 étape")
        #expect(L(count: 4, one: "\(4) étape", other: "\(4) étapes") == "4 étapes")
    }
}
