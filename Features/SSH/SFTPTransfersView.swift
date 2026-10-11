import PingouinCore
import SwiftUI

/// Liste des transferts d'un navigateur de fichiers, avec leur avancement.
struct SFTPTransfersView: View {
    let browser: SFTPBrowser

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("Transferts"))
                    .font(.headline)
                Spacer()
                Button(L("Retirer les transferts terminés")) {
                    browser.clearFinishedTransfers()
                }
                .buttonStyle(.link)
                .disabled(!browser.hasFinishedTransfers)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(browser.transfers) { transfer in
                        transferRow(transfer)
                    }
                }
            }
            .frame(maxHeight: 110)
        }
        .glassCardPadded()
    }

    private func transferRow(_ transfer: SFTPTransfer) -> some View {
        HStack(spacing: 10) {
            Image(systemName: transfer.direction == .upload ? "arrow.up.circle" : "arrow.down.circle")
                .foregroundStyle(.secondary)
                .accessibilityLabel(transfer.direction == .upload ? L("Envoi") : L("Téléchargement"))
            Text(transfer.name)
                .lineLimit(1)
                .frame(maxWidth: 240, alignment: .leading)
            switch transfer.state {
            case .queued:
                Text(L("En attente"))
                    .foregroundStyle(.secondary)
            case .running:
                if let fraction = transfer.fraction {
                    ProgressView(value: fraction)
                        .frame(maxWidth: 180)
                    Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                    Text(transfer.totalBytes.map { L("En cours, \(ByteFormat.volume($0))") } ?? L("En cours"))
                        .foregroundStyle(.secondary)
                }
            case .done:
                StatusLabel(kind: .ok, text: transfer.totalBytes.map { L("Terminé, \(ByteFormat.volume($0))") } ?? L("Terminé"))
            case .cancelled:
                StatusLabel(kind: .neutral, text: L("Interrompu"))
            case .failed(let reason):
                StatusLabel(kind: .failure, text: L("Échec : \(reason)"))
                    .lineLimit(2)
                    .help(reason)
            }
            Spacer(minLength: 0)
            if !transfer.isFinished {
                Button(L("Annuler")) {
                    browser.cancelTransfer(transfer.id)
                }
                .buttonStyle(.link)
            }
        }
    }
}
