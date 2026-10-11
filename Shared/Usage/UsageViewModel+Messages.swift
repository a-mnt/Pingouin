import Foundation
import PingouinCore
import PingouinNetwork

/// Messages d'erreur de la consommation, tels qu'ils sont montrés à l'utilisateur.
extension UsageViewModel {
    static func message(for error: Error) -> String {
        guard let error = error as? FreeboxError else { return error.localizedDescription }
        switch error {
        case .unreachable:
            #if os(macOS)
            return L("La Freebox ne répond pas à l'adresse mafreebox.freebox.fr. Vérifier que ce Mac est bien sur le réseau de la box.")
            #else
            return L("La Freebox ne répond pas à l'adresse mafreebox.freebox.fr. Vérifier que cet appareil est bien sur le réseau Wi-Fi de la box.")
            #endif
        case .notAFreebox:
            return L("L'équipement à l'adresse mafreebox.freebox.fr ne répond pas comme une Freebox.")
        case .authenticationRequired:
            return L("La Freebox demande une nouvelle ouverture de session.")
        case .invalidToken:
            return L("La Freebox n'accepte plus l'accès de Pingouin.")
        case .api(let code, let message):
            if code == "insufficient_rights" {
                return L("La Freebox refuse cette lecture à Pingouin (droits insuffisants) : \(message)")
            }
            return L("La Freebox a répondu par une erreur (\(code)) : \(message)")
        case .badResponse:
            return L("La réponse de la Freebox n'a pas pu être lue.")
        case .untrustedCertificate:
            return L("Le certificat HTTPS de la Freebox n'a pas pu être validé. Pingouin n'a rien envoyé. Si votre box ne sait pas présenter un certificat valide, décocher « Chiffrer les échanges avec la Freebox » dans Réglages > Consommation ; les échanges passeront alors en clair sur le réseau local.")
        }
    }
}
