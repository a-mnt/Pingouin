import Foundation
import Testing
@testable import PingouinCore

@Suite("Navigateur SFTP : lecture des listes et chemins")
struct SFTPListingTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .gmt
        return calendar
    }

    /// 11 octobre 2026 à midi, heure de Paris.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 12)) ?? Date()
    }

    @Test("Une ligne de fichier est lue en entier")
    func fileLine() throws {
        let line = "-rw-r--r--    1 1000     1000         2048 Oct  9 10:12 notes.txt"
        let entry = try #require(SFTPListing.parseLine(line, now: now, calendar: calendar))
        #expect(entry.name == "notes.txt")
        #expect(entry.kind == .file)
        #expect(entry.size == 2_048)
        #expect(entry.permissions == "-rw-r--r--")
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: try #require(entry.modified))
        #expect(parts.year == 2026)
        #expect(parts.month == 10)
        #expect(parts.day == 9)
        #expect(parts.hour == 10)
        #expect(parts.minute == 12)
    }

    @Test("Un nom avec des espaces est conservé tel quel")
    func nameWithSpaces() throws {
        let line = "drwxr-xr-x    2 0        0            4096 Jan  3  2024 Mes  documents"
        let entry = try #require(SFTPListing.parseLine(line, now: now, calendar: calendar))
        #expect(entry.name == "Mes  documents")
        #expect(entry.kind == .directory)
        let parts = calendar.dateComponents([.year, .month, .day], from: try #require(entry.modified))
        #expect(parts.year == 2024)
        #expect(parts.month == 1)
        #expect(parts.day == 3)
    }

    @Test("Une date récente située dans le futur est de l'année passée")
    func recentDateFromLastYear() throws {
        let line = "-rw-------    1 501      20             12 Dec 24 08:30 cadeau"
        let entry = try #require(SFTPListing.parseLine(line, now: now, calendar: calendar))
        let parts = calendar.dateComponents([.year, .month, .day], from: try #require(entry.modified))
        #expect(parts.year == 2025)
        #expect(parts.month == 12)
        #expect(parts.day == 24)
    }

    @Test("Un nom précédé de son chemin est ramené au nom seul")
    func nameWithPathPrefix() throws {
        let line = "drwxr-xr-x    5 1000     1000         4096 Mar 28  2025 /home/utilisateur/venv"
        let entry = try #require(SFTPListing.parseLine(line, now: now, calendar: calendar))
        #expect(entry.name == "venv")
        #expect(entry.kind == .directory)
    }

    @Test("Les échos de commande et les messages ne sont pas des éléments")
    func otherLinesAreIgnored() {
        #expect(SFTPListing.parseLine("sftp> ls -lan \"/home/utilisateur\"") == nil)
        #expect(SFTPListing.parseLine("Remote working directory: /home/utilisateur") == nil)
        #expect(SFTPListing.parseLine("") == nil)
    }

    @Test("La liste écarte « . » et « .. » et place les dossiers en premier")
    func listing() {
        let output = """
        sftp> ls -lan "/srv"
        drwxr-xr-x    4 0        0            4096 Oct  1 09:00 .
        drwxr-xr-x   20 0        0            4096 Sep 12 18:40 ..
        -rw-r--r--    1 0        0             120 Oct  2 11:00 alpha.conf
        lrwxrwxrwx    1 0        0              11 Oct  2 11:00 courant
        drwxr-xr-x    2 0        0            4096 Oct  3 11:00 zeta
        -rw-r--r--    1 0        0              10 Oct  2 11:00 fichier10
        -rw-r--r--    1 0        0              10 Oct  2 11:00 fichier9
        """
        let entries = SFTPListing.parse(output, now: now, calendar: calendar)
        #expect(entries.map(\.name) == ["zeta", "alpha.conf", "courant", "fichier9", "fichier10"])
        #expect(entries[2].kind == .link)
    }

    @Test("Le dossier courant est lu dans la réponse à pwd")
    func workingDirectory() {
        #expect(SFTPListing.workingDirectory(in: "sftp> pwd\nRemote working directory: /home/utilisateur\n") == "/home/utilisateur")
        #expect(SFTPListing.workingDirectory(in: "sftp> pwd\n") == nil)
    }

    @Test("Un chemin n'est mis entre guillemets que s'il est sans caractère interprété")
    func quoting() {
        #expect(SFTPPath.quoted("/home/utilisateur/Mes documents") == "\"/home/utilisateur/Mes documents\"")
        #expect(SFTPPath.quoted("/home/utilisateur/l'été.txt") == "\"/home/utilisateur/l'été.txt\"")
        #expect(SFTPPath.quoted("/tmp/a\"b") == nil)
        #expect(SFTPPath.quoted("/tmp/*.log") == nil)
        #expect(SFTPPath.quoted("/tmp/a?") == nil)
        #expect(SFTPPath.quoted("/tmp/[x]") == nil)
        #expect(SFTPPath.quoted("/tmp/a\\b") == nil)
        #expect(SFTPPath.quoted("/tmp/a\nrm b") == nil)
        #expect(SFTPPath.quoted("") == nil)
    }

    @Test("Un nom de fichier ne contient pas de barre et n'est ni « . » ni « .. »")
    func names() {
        #expect(SFTPPath.isValidName("rapport final.pdf"))
        #expect(!SFTPPath.isValidName("a/b"))
        #expect(!SFTPPath.isValidName(".."))
        #expect(!SFTPPath.isValidName("."))
        #expect(!SFTPPath.isValidName(""))
        #expect(!SFTPPath.isValidName("*"))
    }

    @Test("Assemblage, dossier parent et chemin saisi")
    func paths() {
        #expect(SFTPPath.join("/", "etc") == "/etc")
        #expect(SFTPPath.join("/home/utilisateur", "notes") == "/home/utilisateur/notes")
        #expect(SFTPPath.parent(of: "/home/utilisateur") == "/home")
        #expect(SFTPPath.parent(of: "/home") == "/")
        #expect(SFTPPath.parent(of: "/") == "/")
        #expect(SFTPPath.normalized(" /var//log/ ") == "/var/log")
        #expect(SFTPPath.normalized("/") == "/")
        #expect(SFTPPath.normalized("var/log") == nil)
        #expect(SFTPPath.normalized("/var/*") == nil)
    }
}
