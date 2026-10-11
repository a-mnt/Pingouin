import Foundation
import Testing
@testable import PingouinCore

@Suite("Fichiers de données versionnés")
struct VersionedFileTests {

    private struct Note: Codable, Equatable {
        var title: String
        var stars: Int
    }

    @Test("Un fichier sans enveloppe est lu comme la version 0")
    func legacyFile() throws {
        let data = Data(#"[{"title":"a","stars":1}]"#.utf8)
        let opened = try VersionedFile.open(data)
        #expect(opened.version == 0)
        #expect(opened.payload == data)
    }

    @Test("L'enveloppe écrite est relue avec sa version et son contenu")
    func roundTrip() throws {
        let written = try JSONEncoder().encode(VersionedEnvelope(version: 3, data: [Note(title: "a", stars: 2)]))
        let opened = try VersionedFile.open(written)
        #expect(opened.version == 3)
        let notes = try JSONDecoder().decode([Note].self, from: opened.payload)
        #expect(notes == [Note(title: "a", stars: 2)])
    }

    @Test("Un objet qui a seulement un champ « version » n'est pas pris pour une enveloppe")
    func lookalike() throws {
        let data = Data(#"{"version":2,"data":[1,2]}"#.utf8)
        let opened = try VersionedFile.open(data)
        #expect(opened.version == 0)
    }

    @Test("Un fichier qui n'est pas du JSON est refusé")
    func notJSON() {
        #expect(throws: VersionedFile.Failure.notJSON) {
            _ = try VersionedFile.open(Data("{ ceci n'est pas du JSON".utf8))
        }
    }

    @Test("Les migrations s'enchaînent dans l'ordre, et une étape absente ne change rien")
    func migrationChain() throws {
        // Version 0 : { "name" } ; version 1 : inchangée ; version 2 : « name » devient « title » et « stars » apparaît.
        let rename: VersionedFile.Migration = { data in
            let object = try JSONSerialization.jsonObject(with: data)
            guard var note = object as? [String: Any] else { throw VersionedFile.Failure.notJSON }
            note["title"] = note.removeValue(forKey: "name")
            note["stars"] = 0
            return try JSONSerialization.data(withJSONObject: note)
        }
        let old = Data(#"{"name":"ancienne"}"#.utf8)
        let migrated = try VersionedFile.migrate(old, from: 0, to: 2, using: [1: rename])
        let note = try JSONDecoder().decode(Note.self, from: migrated)
        #expect(note == Note(title: "ancienne", stars: 0))

        let untouched = try VersionedFile.migrate(old, from: 2, to: 2, using: [1: rename])
        #expect(untouched == old)
    }

    @Test("Un fichier d'une version plus récente est refusé, pas interprété")
    func newerVersion() {
        #expect(throws: VersionedFile.Failure.newerVersion(found: 5, supported: 2)) {
            _ = try VersionedFile.migrate(Data("{}".utf8), from: 5, to: 2, using: [:])
        }
    }

    @Test("Une migration qui échoue est signalée avec sa version de départ")
    func failingMigration() {
        let failing: VersionedFile.Migration = { _ in throw VersionedFile.Failure.notJSON }
        #expect(throws: VersionedFile.Failure.migrationFailed(from: 1)) {
            _ = try VersionedFile.migrate(Data("{}".utf8), from: 0, to: 2, using: [1: failing])
        }
    }
}
