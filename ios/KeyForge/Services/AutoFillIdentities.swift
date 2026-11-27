import AuthenticationServices
import Foundation

/// Keeps iOS's list of KeyForge identifiers (user name + site, never the password) in
/// step with the vault, so that the QuickType bar suggests the right entry above the
/// keyboard. Passwords stay in the vault; iOS asks the extension for them, after Face ID.
enum AutoFillIdentities {
    /// One identity per entry that has a website and a password.
    static func identities(for items: [VaultItem]) -> [ASPasswordCredentialIdentity] {
        items.compactMap { item in
            let host = AutoFillMatch.host(of: item.website)
            guard !host.isEmpty, !item.password.isEmpty else { return nil }
            let service = ASCredentialServiceIdentifier(identifier: host, type: .domain)
            return ASPasswordCredentialIdentity(
                serviceIdentifier: service,
                user: AutoFillMatch.user(of: item),
                recordIdentifier: item.id.uuidString
            )
        }
    }

    /// One verification-code identity per entry that has a website and a code generator:
    /// iOS then offers the code above the keyboard in a verification-code field. Only
    /// the site and a label go to iOS, never the secret.
    @available(iOS 18.0, *)
    static func oneTimeCodeIdentities(for items: [VaultItem]) -> [ASOneTimeCodeCredentialIdentity] {
        items.compactMap { item in
            let host = AutoFillMatch.host(of: item.website)
            guard !host.isEmpty, item.oneTimeCode != nil else { return nil }
            let service = ASCredentialServiceIdentifier(identifier: host, type: .domain)
            return ASOneTimeCodeCredentialIdentity(
                serviceIdentifier: service,
                label: AutoFillMatch.user(of: item),
                recordIdentifier: item.id.uuidString
            )
        }
    }

    /// Replaces the identities iOS knows, when KeyForge is enabled as an AutoFill
    /// provider (Réglages → Général → Remplissage automatique et mots de passe).
    static func sync(_ items: [VaultItem]) {
        var identities: [any ASCredentialIdentity] = identities(for: items)
        if #available(iOS 18.0, *) {
            identities += oneTimeCodeIdentities(for: items).map { $0 as any ASCredentialIdentity }
        }
        let store = ASCredentialIdentityStore.shared
        store.getState { state in
            guard state.isEnabled else { return }
            store.replaceCredentialIdentities(identities, completion: nil)
        }
    }

    /// Forgets every identity (the vault was erased).
    static func removeAll() {
        let store = ASCredentialIdentityStore.shared
        store.getState { state in
            guard state.isEnabled else { return }
            store.removeAllCredentialIdentities(nil)
        }
    }

    /// Whether KeyForge is enabled as an AutoFill provider.
    static func isEnabled() async -> Bool {
        await withCheckedContinuation { continuation in
            ASCredentialIdentityStore.shared.getState { state in
                continuation.resume(returning: state.isEnabled)
            }
        }
    }
}
