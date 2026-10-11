import SwiftUI
@preconcurrency import SwiftTerm
import UIKit

/// Relais entre la vue du terminal et la session : SwiftTerm l'appelle sur le fil principal, à chaque
/// frappe et à chaque changement de taille. Les frappes sont remises aussitôt, dans l'ordre.
final class MobileTerminalBridge: NSObject, TerminalViewDelegate {
    var onInput: (@Sendable ([UInt8]) -> Void)?
    var onResize: (@Sendable (Int, Int) -> Void)?

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        onInput?(Array(data))
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        onResize?(newCols, newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func scrolled(source: TerminalView, position: Double) {}

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    func bell(source: TerminalView) {}

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

    /// Le programme distant demande à copier un texte (séquence OSC 52).
    func clipboardCopy(source: TerminalView, content: Data) {
        guard let text = String(data: content, encoding: .utf8) else { return }
        MainActor.assumeIsolated {
            UIPasteboard.general.string = text
        }
    }

    /// Un lien du terminal a été touché : seuls les liens web sont ouverts.
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return
        }
        MainActor.assumeIsolated {
            UIApplication.shared.open(url)
        }
    }
}

/// Terminal d'une session : il détient la vue de SwiftTerm, pour que l'affichage survive quand on
/// quitte l'écran de la session et qu'on y revient.
@MainActor
final class MobileTerminalController {
    let view: TerminalView
    private let bridge = MobileTerminalBridge()

    init() {
        view = TerminalView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        view.terminalDelegate = bridge
    }

    var columns: Int { view.getTerminal().cols }
    var rows: Int { view.getTerminal().rows }

    /// Branche le clavier et la taille du terminal sur une connexion.
    func attach(onInput: @escaping @Sendable ([UInt8]) -> Void, onResize: @escaping @Sendable (Int, Int) -> Void) {
        bridge.onInput = onInput
        bridge.onResize = onResize
    }

    func detach() {
        bridge.onInput = nil
        bridge.onResize = nil
    }

    /// Affiche ce que le serveur a envoyé.
    func feed(_ bytes: [UInt8]) {
        view.feed(byteArray: bytes[...])
    }

    /// Écrit une ligne d'information de Pingouin dans le terminal, hors de la session.
    func note(_ text: String) {
        view.feed(text: "\r\n\u{1B}[2m" + text + "\u{1B}[0m\r\n")
    }

    func apply(theme: TerminalTheme, fontSize: Double) {
        view.nativeBackgroundColor = theme.backgroundColor
        view.nativeForegroundColor = theme.foregroundColor
        view.caretColor = theme.cursorColor
        view.font = UIFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        view.setNeedsDisplay()
    }

    func focus() {
        _ = view.becomeFirstResponder()
    }

    func unfocus() {
        _ = view.resignFirstResponder()
    }
}

/// Emplacement du terminal dans une vue SwiftUI.
struct MobileTerminalHostView: UIViewRepresentable {
    let controller: MobileTerminalController

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        let terminal = controller.view
        guard terminal.superview !== container else { return }
        terminal.removeFromSuperview()
        terminal.frame = container.bounds
        terminal.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(terminal)
    }
}
