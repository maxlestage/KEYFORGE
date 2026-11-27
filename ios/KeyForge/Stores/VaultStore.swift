import Foundation
import LocalAuthentication
import Observation

/// The vault: its entries, decrypted in memory only while it is unlocked.
@MainActor
@Observable
final class VaultStore {
    private(set) var items: [VaultItem] = []
    private(set) var isLocked = true
    private(set) var isAuthenticating = false
    var errorMessage: String?

    private let store: BrocolisVault
    /// Vrai quand le coffre rangé est scellé par Brocolis 🥦 (affiché dans les réglages).
    private(set) var isSealed = false
    /// Vrai quand la clé du coffre n'existe plus qu'enveloppée par la Secure Enclave.
    private(set) var isEnclaveProtected = false
    /// Pourquoi la Secure Enclave n'a pas pris la clé au dernier essai (réglages).
    private(set) var enclaveIssue: String?

    /// La clé du coffre ouvert et le contexte authentifié qui l'a libérée : en mémoire
    /// seulement, oubliés au verrouillage.
    private var sessionKey: [UInt8]?
    private var sessionContext: LAContext?
    /// Vrai si le coffre a été ouvert avec le verrouillage biométrique actif : sa clé
    /// doit alors rejoindre la Secure Enclave.
    private var wantsEnclave = false

    init(store: BrocolisVault = BrocolisVault()) {
        self.store = store
        do {
            // Le coffre d'une version précédente rejoint le groupe partagé avec l'extension
            // de remplissage automatique (sans rien perdre si le déplacement échoue)…
            try store.vault.migrateToDefaultGroup()
            // …puis, s'il est encore en JSON clair, il est scellé par Brocolis.
            if !store.isSealed(), try store.vault.load() != nil {
                try store.save(store.open(context: nil).items)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        refreshState()
    }

    var favorites: [VaultItem] { items.filter(\.isFavorite).sortedForDisplay() }
    var others: [VaultItem] { items.filter { !$0.isFavorite }.sortedForDisplay() }

    // MARK: Locking

    /// Opens the vault, asking for Face ID / Touch ID / the passcode when required: always
    /// when the Secure Enclave holds the key, since only the owner can release it.
    func unlock(requireAuthentication: Bool) async {
        guard isLocked, !isAuthenticating else { return }
        let context = LAContext()
        let authenticated = requireAuthentication || store.isEnclaveProtected()
        if authenticated {
            isAuthenticating = true
            let ok = await BiometricAuth.authenticate(context: context)
            isAuthenticating = false
            guard ok else { return }
        }
        // Un coffre illisible reste fermé : rien ne doit pouvoir l'écraser.
        guard let opened = open(context) else { return }
        items = opened.items
        sessionKey = opened.key
        // Seul un contexte authentifié peut servir à la Secure Enclave.
        sessionContext = authenticated ? context : nil
        wantsEnclave = requireAuthentication
        isLocked = false
        harden()
    }

    /// Forgets the decrypted entries and the vault key: they stay only in the Keychain.
    func lock() {
        items = []
        forgetSession()
        isLocked = true
    }

    private func forgetSession() {
        if let count = sessionKey?.count {
            for index in 0..<count { sessionKey?[index] = 0 }
        }
        sessionKey = nil
        sessionContext?.invalidate()
        sessionContext = nil
    }

    // MARK: Entries

    func upsert(_ item: VaultItem) {
        var item = item
        item.updatedAt = Date()
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        persist()
    }

    func delete(_ item: VaultItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func toggleFavorite(_ item: VaultItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isFavorite.toggle()
        persist()
    }

    /// Adds an entry without opening the vault (from the generator). With the key in
    /// the Secure Enclave, the owner authenticates first. `false`: refused or unreadable.
    @discardableResult
    func add(_ item: VaultItem) async -> Bool {
        if !isLocked {
            upsert(item)
            return true
        }
        guard let opened = await openLocked(
            requireAuthentication: false, reason: "Ajoutez cette clé à votre coffre KeyForge"
        ) else { return false }
        // Jamais d'écriture par-dessus un coffre qu'on n'a pas pu lire.
        return write(opened.items + [item], key: opened.key, context: opened.context)
    }

    // MARK: Sauvegarde chiffrée

    /// Les entrées à exporter, après Face ID / Touch ID / le code quand le verrouillage
    /// biométrique est actif. `nil` : refusé ou illisible.
    func entriesForExport(requireAuthentication: Bool) async -> [VaultItem]? {
        let reason = "Autorisez l'export chiffré de votre coffre"
        if !isLocked {
            if requireAuthentication {
                guard await BiometricAuth.authenticate(reason: reason) else { return nil }
            }
            return items
        }
        return await openLocked(requireAuthentication: requireAuthentication, reason: reason)?.items
    }

    /// Ajoute les entrées d'une sauvegarde absentes du coffre (même identifiant :
    /// ignorée). Renvoie le nombre d'entrées ajoutées, `nil` si le coffre est illisible
    /// ou l'authentification refusée.
    func importEntries(_ incoming: [VaultItem]) async -> Int? {
        var opened: (items: [VaultItem], key: [UInt8]?, context: LAContext)?
        let current: [VaultItem]
        if isLocked {
            opened = await openLocked(
                requireAuthentication: false, reason: "Ajoutez la sauvegarde à votre coffre KeyForge"
            )
            // Jamais d'écriture par-dessus un coffre qu'on n'a pas pu lire.
            guard let opened else { return nil }
            current = opened.items
        } else {
            current = items
        }
        let known = Set(current.map(\.id))
        var seen = Set<UUID>()
        let fresh = incoming.filter { !known.contains($0.id) && seen.insert($0.id).inserted }
        guard !fresh.isEmpty else { return 0 }
        if let opened {
            guard write(current + fresh, key: opened.key, context: opened.context) else { return nil }
        } else {
            items = current + fresh
            persist()
        }
        return fresh.count
    }

    func eraseAll() {
        do {
            try store.erase()
            items = []
            forgetSession()
            AutoFillIdentities.removeAll()
        } catch {
            errorMessage = error.localizedDescription
        }
        refreshState()
    }

    // MARK: Secure Enclave

    /// Suit le réglage « Verrouillage biométrique ». Actif : la clé du coffre rejoint la
    /// Secure Enclave (tout de suite si possible, sinon à la prochaine ouverture).
    /// Coupé : après authentification, la clé retourne dans le trousseau.
    /// `false` : le retrait a été refusé, le réglage doit rester actif.
    func setEnclaveProtection(_ enabled: Bool) async -> Bool {
        if enabled {
            wantsEnclave = true
            guard !store.isEnclaveProtected(), store.hasPlainKey(), VaultEnclave.isAvailable else { return true }
            let context = LAContext()
            if await BiometricAuth.authenticate(
                context: context, reason: "Confiez la clé de votre coffre à la Secure Enclave"
            ) {
                if !isLocked { sessionContext = context }
                harden(context)
            }
            return true
        }
        wantsEnclave = false
        guard store.isEnclaveProtected() else { return true }
        let context = LAContext()
        guard await BiometricAuth.authenticate(
            context: context, reason: "Autorisez l'ouverture du coffre sans \(BiometricAuth.label)"
        ) else { return false }
        do {
            try store.unprotect(context: context)
            refreshState()
            return true
        } catch {
            errorMessage = error.localizedDescription
            refreshState()
            return false
        }
    }

    /// Confie la clé à la Secure Enclave si c'est voulu et possible. Un échec ne casse
    /// rien : la clé reste dans le trousseau, la raison est gardée pour les réglages.
    private func harden(_ context: LAContext? = nil) {
        guard wantsEnclave, let context = context ?? sessionContext,
              !store.isEnclaveProtected(), store.hasPlainKey()
        else { return }
        guard VaultEnclave.isAvailable else {
            enclaveIssue = BiometricAuth.kind == .none
                ? "Définissez un code sur l'iPhone pour confier la clé du coffre à la Secure Enclave."
                : VaultEnclaveError.unavailable.localizedDescription
            return
        }
        do {
            try store.protect(context: context)
            enclaveIssue = nil
        } catch {
            enclaveIssue = error.localizedDescription
        }
        refreshState()
    }

    // MARK: Storage

    /// Le coffre déchiffré avec un contexte déjà authentifié (ou sans authentification
    /// quand la clé est dans le trousseau).
    private func open(_ context: LAContext) -> (items: [VaultItem], key: [UInt8]?)? {
        do {
            return try store.open(context: context)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Le coffre fermé, déchiffré le temps d'une opération : authentification si elle
    /// est demandée ou si la Secure Enclave garde la clé.
    private func openLocked(
        requireAuthentication: Bool, reason: String
    ) async -> (items: [VaultItem], key: [UInt8]?, context: LAContext)? {
        let context = LAContext()
        if requireAuthentication || store.isEnclaveProtected() {
            guard await BiometricAuth.authenticate(context: context, reason: reason) else { return nil }
        }
        guard let opened = open(context) else { return nil }
        return (opened.items, opened.key, context)
    }

    private func persist() {
        if write(items, key: sessionKey, context: sessionContext) {
            // La première écriture crée la clé : elle rejoint aussitôt la Secure Enclave.
            harden()
        }
    }

    @discardableResult
    private func write(_ items: [VaultItem], key: [UInt8]?, context: LAContext?) -> Bool {
        do {
            // Scellé par Brocolis : jamais de JSON en clair dans le trousseau.
            let used = try store.save(items, key: key, context: context)
            if !isLocked { sessionKey = used }
            // Les suggestions au-dessus du clavier suivent le coffre (sites et
            // identifiants seulement : les mots de passe restent dans le coffre).
            AutoFillIdentities.sync(items)
            refreshState()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func refreshState() {
        isSealed = store.isSealed()
        isEnclaveProtected = store.isEnclaveProtected()
    }
}
