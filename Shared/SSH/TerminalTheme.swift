import Foundation
import PingouinCore

/// Thème de couleurs du terminal.
struct TerminalTheme: Identifiable, Hashable {
    let id: String
    let name: String
    /// Couleurs au format 0xRRGGBB.
    let background: UInt32
    let foreground: UInt32
    let cursor: UInt32

    static let all: [TerminalTheme] = [
        TerminalTheme(id: "nuit-polaire", name: L("Nuit polaire"), background: 0x121A23, foreground: 0xE6EBF1, cursor: 0xF08A3C),
        TerminalTheme(id: "banquise", name: L("Banquise"), background: 0xF4F6F8, foreground: 0x17212B, cursor: 0xC2560A),
        TerminalTheme(id: "encre", name: L("Encre"), background: 0x000000, foreground: 0xF2F2F2, cursor: 0xFFFFFF),
        TerminalTheme(id: "papier", name: L("Papier"), background: 0xFBF7EF, foreground: 0x3B2F2F, cursor: 0x8F3D05),
        TerminalTheme(id: "ocean", name: L("Océan"), background: 0x0B2A3D, foreground: 0xCDE7F5, cursor: 0x5CC8FF),
        TerminalTheme(id: "foret", name: L("Forêt"), background: 0x0F1F14, foreground: 0xCFE8D3, cursor: 0x6FD08C),
        TerminalTheme(id: "phosphore", name: L("Phosphore vert"), background: 0x06120A, foreground: 0x5CF28A, cursor: 0x5CF28A),
        TerminalTheme(id: "ambre", name: L("Ambre"), background: 0x1A1206, foreground: 0xFFB454, cursor: 0xFFB454)
    ]

    static let fallback = all[0]

    static func named(_ id: String?) -> TerminalTheme {
        all.first { $0.id == id } ?? fallback
    }
}
