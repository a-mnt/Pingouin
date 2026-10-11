import SwiftUI
import PingouinCore

/// Transferts d'une session : progression, annulation, et remise d'un fichier téléchargé à la
/// feuille de partage.
struct MobileSFTPTransfersCard: View {
    let browser: MobileSFTPBrowser
    let share: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Transferts"))
                    .font(.headline)
                Spacer()
                if browser.runningTransferCount > 0 {
                    Text(L("\(browser.runningTransferCount) en cours"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Button(L("Effacer la liste")) {
                        browser.clearFinished()
                    }
                    .font(.footnote)
                }
            }
            ForEach(Array(browser.transfers.enumerated()), id: \.element.id) { index, transfer in
                if index > 0 {
                    Divider()
                }
                row(transfer)
            }
            Text(L("Un fichier téléchargé reste dans Pingouin jusqu'à ce qu'il soit partagé (Fichiers, AirDrop…) ; « Effacer la liste » le supprime."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .glassCardPadded(cornerRadius: 22)
    }

    private func row(_ transfer: MobileTransfer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: transfer.direction == .download ? "arrow.down" : "arrow.up")
                    .accessibilityLabel(transfer.direction == .download ? L("Téléchargement") : L("Envoi"))
                Text(transfer.name)
                    .font(.footnote.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if transfer.state == .running, let fraction = transfer.fraction {
                    Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                        .font(.footnote.monospaced())
                }
            }
            switch transfer.state {
            case .running:
                if let fraction = transfer.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
                HStack {
                    Text(progressText(transfer))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Annuler")) {
                        browser.cancel(transfer.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            case .done:
                HStack {
                    StatusLabel(kind: .ok, text: transfer.direction == .download ? L("Téléchargé") : L("Envoyé"))
                        .font(.footnote)
                    Spacer()
                    if let url = transfer.localURL {
                        Button(L("Partager…")) {
                            share(url)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            case .cancelled:
                StatusLabel(kind: .neutral, text: L("Annulé"))
                    .font(.footnote)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func progressText(_ transfer: MobileTransfer) -> String {
        let done = ByteFormat.volume(transfer.doneBytes)
        guard let total = transfer.totalBytes else { return done }
        return L("\(done) sur \(ByteFormat.volume(total))")
    }
}
