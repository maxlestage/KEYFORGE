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

    func eraseAll() {
        do {
            try keychain.delete()
            items = []
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func decode(_ data: Data?) throws -> [VaultItem] {
        guard let data else { return [] }
        return try JSONDecoder().decode([VaultItem].self, from: data)
    }
}
