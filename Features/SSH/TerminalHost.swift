import AppKit
import SwiftUI

#if canImport(SwiftTerm)
@preconcurrency import SwiftTerm
import PingouinCore
#endif

extension TerminalTheme {
    var backgroundColor: NSColor { NSColor(rgb: background) }
    var foregroundColor: NSColor { NSColor(rgb: foreground) }
    var cursorColor: NSColor { NSColor(rgb: cursor) }
}

extension NSColor {
    /// Couleur sRGB à partir d'une valeur 0xRRGGBB.
    convenience init(rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Pilote du terminal intégré : il détient la vue du terminal, pour que la session survive
/// quand on change de module, et lance le processus (`ssh` ou `sftp`) dans un pseudo-terminal.
@MainActor
final class TerminalController {
    #if canImport(SwiftTerm)
    static let isAvailable = true
    private(set) var view: LocalProcessTerminalView?
    private var delegate: ProcessDelegate?
    private var passwordEntry: PasswordEntry?

    /// Terminal qui laisse lire ce que le processus affiche, pour repérer la demande de mot de passe.
    private final class WatchedTerminalView: LocalProcessTerminalView {
        var onOutput: ((String) -> Void)?

        override func dataReceived(slice: ArraySlice<UInt8>) {
            super.dataReceived(slice: slice)
            if let onOutput {
                onOutput(String(decoding: slice, as: UTF8.self))
            }
        }
    }

    /// Saisie automatique du mot de passe enregistré : une seule fois, à la demande d'OpenSSH.
    private struct PasswordEntry {
        /// Fins possibles de la demande d'OpenSSH, en minuscules : « utilisateur@hôte's password: »,
        /// ou « (utilisateur@hôte) Password: » quand le serveur pose la question lui-même.
        static let promptEndings = ["'s password:", ") password:"]
        /// Attente avant la saisie, le temps que `ssh` soit prêt à lire.
        static let delayMilliseconds = 400
        /// Au-delà de ce délai, une demande ne peut plus être celle de l'ouverture de session.
        static let window: TimeInterval = 120

        let password: String
        let started = Date()
        var recentOutput = ""
    }

    /// Relaie la fin du processus vers l'acteur principal.
    private final class ProcessDelegate: NSObject, LocalProcessTerminalViewDelegate {
        let onEnd: @MainActor @Sendable (Int32?) -> Void

        init(onEnd: @escaping @MainActor @Sendable (Int32?) -> Void) {
            self.onEnd = onEnd
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            let handler = onEnd
            Task { @MainActor in
                handler(exitCode)
            }
        }
    }
    #else
    static let isAvailable = false
    #endif

    /// Incrémenté à chaque nouvelle session, pour que la vue SwiftUI sache qu'elle doit changer de terminal.
    private(set) var sessionNumber = 0

    /// Lance un programme dans un nouveau terminal. Renvoie faux si le terminal intégré n'est pas disponible.
    @discardableResult
    func start(
        executable: String,
        arguments: [String],
        theme: TerminalTheme,
        fontSize: CGFloat,
        password: String? = nil,
        onEnd: @escaping @MainActor @Sendable (Int32?) -> Void
    ) -> Bool {
        #if canImport(SwiftTerm)
        stop()
        let terminal = WatchedTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 480))
        passwordEntry = nil
        if let password, !password.isEmpty {
            passwordEntry = PasswordEntry(password: password)
            terminal.onOutput = { [weak self, weak terminal] text in
                guard let self, let terminal else { return }
                self.offerPassword(after: text, to: terminal)
            }
        }
        let delegate = ProcessDelegate(onEnd: onEnd)
        terminal.processDelegate = delegate
        self.delegate = delegate
        self.view = terminal
        apply(theme: theme, fontSize: fontSize)
        sessionNumber += 1
        terminal.startProcess(executable: executable, args: arguments, environment: Self.environment(), execName: nil)
        return true
        #else
        return false
        #endif
    }

    #if canImport(SwiftTerm)
    /// Envoie le mot de passe enregistré quand OpenSSH le demande. Il n'est envoyé qu'une fois :
    /// s'il est refusé, la demande suivante attend une saisie au clavier.
    private func offerPassword(after text: String, to terminal: WatchedTerminalView) {
        guard var entry = passwordEntry else { return }
        guard Date().timeIntervalSince(entry.started) < PasswordEntry.window else {
            passwordEntry = nil
            terminal.onOutput = nil
            return
        }
        entry.recentOutput = String((entry.recentOutput + text).suffix(200))
        let tail = entry.recentOutput.trimmingCharacters(in: .whitespaces).lowercased()
        if PasswordEntry.promptEndings.contains(where: { tail.hasSuffix($0) }) {
            passwordEntry = nil
            terminal.onOutput = nil
            let password = entry.password
            // Court délai avant la saisie : sans lui, le mot de passe a déjà été refusé à tort.
            Task { @MainActor [weak terminal] in
                try? await Task.sleep(for: .milliseconds(PasswordEntry.delayMilliseconds))
                terminal?.send(txt: password + "\r")
            }
        } else {
            passwordEntry = entry
        }
    }
    #endif

    func apply(theme: TerminalTheme, fontSize: CGFloat) {
        #if canImport(SwiftTerm)
        guard let view else { return }
        view.nativeBackgroundColor = theme.backgroundColor
        view.nativeForegroundColor = theme.foregroundColor
        view.caretColor = theme.cursorColor
        view.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        view.needsDisplay = true
        #endif
    }

    /// Met fin au processus en cours, s'il y en a un.
    func stop() {
        #if canImport(SwiftTerm)
        passwordEntry = nil
        if let process = view?.process, process.shellPid > 0 {
            kill(process.shellPid, SIGTERM)
        }
        #endif
    }

    /// Donne le clavier au terminal.
    func focus() {
        #if canImport(SwiftTerm)
        if let view {
            view.window?.makeFirstResponder(view)
        }
        #endif
    }

    #if canImport(SwiftTerm)
    /// Environnement transmis au processus : le strict nécessaire, dont l'accès à l'agent SSH
    /// (c'est par lui que passent les clés gardées dans le Trousseau).
    private static func environment() -> [String] {
        let current = ProcessInfo.processInfo.environment
        var result = ["TERM=xterm-256color", "COLORTERM=truecolor"]
        for key in ["HOME", "USER", "LOGNAME", "PATH", "LANG", "LC_ALL", "LC_CTYPE", "SSH_AUTH_SOCK", "TMPDIR"] {
            if let value = current[key] {
                result.append("\(key)=\(value)")
            }
        }
        if current["LANG"] == nil {
            result.append("LANG=fr_FR.UTF-8")
        }
        return result
    }
    #endif
}

/// Emplacement du terminal dans une vue SwiftUI.
struct TerminalHostView: NSViewRepresentable {
    let controller: TerminalController
    /// Change à chaque nouvelle session : force la mise à jour de la vue.
    let sessionNumber: Int

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.autoresizesSubviews = true
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        #if canImport(SwiftTerm)
        let terminal = controller.view
        if container.subviews.first !== terminal {
            container.subviews.forEach { $0.removeFromSuperview() }
            if let terminal {
                terminal.frame = container.bounds
                terminal.autoresizingMask = [.width, .height]
                container.addSubview(terminal)
                // Au tour suivant de la boucle d'événements, quand la vue est bien dans sa fenêtre.
                Task { @MainActor in
                    terminal.window?.makeFirstResponder(terminal)
                }
            }
        }
        #endif
    }
}
