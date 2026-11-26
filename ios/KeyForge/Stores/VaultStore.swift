import Foundation
import Observation

/// The vault: its entries, decrypted in memory only while it is unlocked.
@MainActor
@Observable
final class VaultStore {
    private(set) var items: [VaultItem] = []
    private(set) var isLocked = true
    private(set) var isAuthenticating = false
    var errorMessage: String?

    private let keychain: KeychainStore

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
        // Le coffre d'une version précédente rejoint le groupe partagé avec l'extension
        // de remplissage automatique (sans rien perdre si le déplacement échoue).
        do {
            try keychain.migrateToDefaultGroup()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var favorites: [VaultItem] { items.filter(\.isFavorite).sortedForDisplay() }
    var others: [VaultItem] { items.filter { !$0.isFavorite }.sortedForDisplay() }

    // MARK: Locking

    /// Opens the vault, asking for Face ID / Touch ID / the passcode when required.
    func unlock(requireAuthentication: Bool) async {
        guard isLocked, !isAuthenticating else { return }
        if requireAuthentication {
            isAuthenticating = true
            let ok = await BiometricAuth.authenticate()
            isAuthenticating = false
            guard ok else { return }
        }
        load()
        isLocked = false
    }

    /// Forgets the decrypted entries: they stay only in the Keychain.
    func lock() {
        items = []
        isLocked = true
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

    /// Adds an entry without opening the vault (from the generator).
    func add(_ item: VaultItem) {
        if isLocked {
            var stored = (try? decode(keychain.load())) ?? []
            stored.append(item)
            write(stored)
        } else {
            upsert(item)
        }
    }

    // MARK: Sauvegarde chiffrée

    /// Les entrées à exporter, après Face ID / Touch ID / le code quand le verrouillage
    /// biométrique est actif. `nil` : refusé ou illisible.
    func entriesForExport(requireAuthentication: Bool) async -> [VaultItem]? {
        if requireAuthentication {
            guard await BiometricAuth.authenticate(reason: "Autorisez l'export chiffré de votre coffre") else {
                return nil
            }
        }
        if !isLocked { return items }
        do {
            return try decode(keychain.load())
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Ajoute les entrées d'une sauvegarde absentes du coffre (même identifiant :
    /// ignorée). Renvoie le nombre d'entrées ajoutées, `nil` si le coffre est illisible.
    func importEntries(_ incoming: [VaultItem]) -> Int? {
        let current: [VaultItem]
        if isLocked {
            do {
                current = try decode(keychain.load())
            } catch {
                // Jamais d'écriture par-dessus un coffre qu'on n'a pas pu lire.
                errorMessage = error.localizedDescription
                return nil
            }
        } else {
            current = items
        }
        let known = Set(current.map(\.id))
        var seen = Set<UUID>()
        let fresh = incoming.filter { !known.contains($0.id) && seen.insert($0.id).inserted }
        guard !fresh.isEmpty else { return 0 }
        if isLocked {
            write(current + fresh)
        } else {
            items = current + fresh
            persist()
        }
        return fresh.count
    }

    func eraseAll() {
        do {
            try keychain.delete()
            items = []
            AutoFillIdentities.removeAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Storage

    private func load() {
        do {
            items = try decode(keychain.load())
        } catch {
            errorMessage = error.localizedDescription
            items = []
        }
    }

    private func persist() {
        write(items)
    }

    private func write(_ items: [VaultItem]) {
        do {
            try keychain.save(JSONEncoder().encode(items))
            // Les suggestions au-dessus du clavier suivent le coffre (sites et
            // identifiants seulement : les mots de passe restent dans le coffre).
            AutoFillIdentities.sync(items)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func decode(_ data: Data?) throws -> [VaultItem] {
        guard let data else { return [] }
        return try JSONDecoder().decode([VaultItem].self, from: data)
    }
}
