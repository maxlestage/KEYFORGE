import AuthenticationServices
import Foundation
import UIKit

/// Transfère les identifiants du coffre vers l'app Mots de passe d'Apple (ou un autre
/// gestionnaire) par l'échange d'identifiants d'iOS 26 (Credential Exchange, format CXF
/// de la FIDO Alliance). iOS affiche sa propre feuille : l'utilisateur choisit la
/// destination et confirme. Rien ne passe par un fichier en clair ni par le réseau de
/// KeyForge ; ensuite, l'app Mots de passe les synchronise par le trousseau iCloud.
enum PasswordsExport {
    enum ExportError: LocalizedError {
        case unavailable
        case noWindow

        var errorDescription: String? {
            switch self {
            case .unavailable: "Le transfert vers Mots de passe demande iOS 26 ou plus récent."
            case .noWindow: "Impossible d'afficher la fenêtre de transfert."
            }
        }
    }

    /// Le transfert est-il possible sur cet iPhone ?
    static var isAvailable: Bool {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    /// Transfère `items` après le choix de la destination par l'utilisateur.
    @MainActor
    static func export(_ items: [VaultItem]) async throws {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)
            else { throw ExportError.noWindow }
            let manager = ASCredentialExportManager(presentationAnchor: window)
            let options = try await manager.requestExport(for: nil)
            let account = ASImportableAccount(
                id: Data("keyforge-vault".utf8),
                userName: "",
                email: "",
                fullName: nil,
                collections: [],
                items: items.map(importable)
            )
            let data = ASExportedCredentialData(
                accounts: [account],
                formatVersion: options.formatVersion,
                exporterRelyingPartyIdentifier: "com.maxlestage.KeyForge",
                exporterDisplayName: "KeyForge",
                timestamp: Date()
            )
            try await manager.exportCredentials(data)
            return
        }
        #endif
        throw ExportError.unavailable
    }

    #if compiler(>=6.2)
    /// Une entrée du coffre au format d'échange : identifiant, mot de passe, site.
    @available(iOS 26.0, *)
    private static func importable(_ item: VaultItem) -> ASImportableItem {
        let login = ASImportableCredential.BasicAuthentication(
            userName: ASImportableEditableField(id: nil, fieldType: .string, value: item.username, label: nil),
            password: ASImportableEditableField(id: nil, fieldType: .concealedString, value: item.password, label: nil)
        )
        let scope = siteURL(of: item).map { ASImportableCredentialScope(urls: [$0], androidApps: []) }
        return ASImportableItem(
            id: Data(item.id.uuidString.utf8),
            created: item.createdAt,
            lastModified: item.updatedAt,
            title: item.title,
            subtitle: item.username.isEmpty ? nil : item.username,
            favorite: item.isFavorite,
            scope: scope,
            credentials: [.basicAuthentication(login)],
            tags: []
        )
    }
    #endif

    /// L'adresse du site, avec `https://` quand le champ n'a pas de schéma.
    static func siteURL(of item: VaultItem) -> URL? {
        let text = item.website.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return URL(string: text.contains("://") ? text : "https://" + text)
    }
}
