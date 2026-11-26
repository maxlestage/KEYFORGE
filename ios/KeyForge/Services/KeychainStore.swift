import Foundation
import Security

/// Reads and writes the vault in the iOS Keychain: one generic password item whose
/// data is the JSON of every entry. The item never leaves this device
/// (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`: no iCloud Keychain, no backup
/// restore on another device) and is readable only while the iPhone is unlocked.
///
/// The app and its AutoFill extension share the vault through the keychain access group
/// `com.maxlestage.KeyForge.shared` (entitlement `keychain-access-groups`, listed first:
/// new items go there by default). `migrateToDefaultGroup()` moves a vault written by an
/// earlier version, which lives in the app's own group the extension cannot read.
struct KeychainStore {
    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "code \(status)"
                return "Erreur du trousseau : \(message)"
            }
        }
    }

    var service = "com.maxlestage.KeyForge.vault"
    var account = "vault"
    /// For an item the extension must not read (the post-quantum identity): the app's
    /// own access group, `<équipe>.<suffixe>`, instead of the shared default group.
    var privateGroupSuffix: String?

    /// Where a new item goes: the app's own group for a private item, else the default.
    private var groupForNewItem: String? {
        guard let suffix = privateGroupSuffix,
              let shared = Self.defaultAccessGroup,
              let dot = shared.firstIndex(of: ".")
        else { return nil }
        return String(shared[..<dot]) + "." + suffix
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func load() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainError.unexpectedStatus(status)
        }
    }

    func save(_ data: Data) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery
            query.merge(attributes) { _, new in new }
            if let group = groupForNewItem {
                query[kSecAttrAccessGroup as String] = group
            }
            let added = SecItemAdd(query as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError.unexpectedStatus(added) }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// The access group new items go to: the first of `keychain-access-groups` (the
    /// group shared with the AutoFill extension), or the app's own group when the build
    /// carries no entitlement (the simulator without signing). Found once, with a
    /// throwaway item.
    static let defaultAccessGroup: String? = {
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.maxlestage.KeyForge.probe",
            kSecAttrAccount as String: UUID().uuidString,
        ]
        var add = probe
        add[kSecValueData as String] = Data()
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        add[kSecReturnAttributes as String] = true
        var result: AnyObject?
        guard SecItemAdd(add as CFDictionary, &result) == errSecSuccess else { return nil }
        SecItemDelete(probe as CFDictionary)
        return (result as? [String: Any])?[kSecAttrAccessGroup as String] as? String
    }()

    /// Moves this item to the default access group (shared with the extension) when it
    /// was written elsewhere. The new copy is written and checked before the old one is
    /// removed: an interrupted move never loses the vault. Nothing to do without item,
    /// without entitlement, or when it is already there.
    func migrateToDefaultGroup() throws {
        guard let target = Self.defaultAccessGroup else { return }
        var query = baseQuery
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let found = result as? [[String: Any]] else {
            if status == errSecItemNotFound { return }
            throw KeychainError.unexpectedStatus(status)
        }
        guard !found.contains(where: { $0[kSecAttrAccessGroup as String] as? String == target }),
              let old = found.first,
              let data = old[kSecValueData as String] as? Data,
              let oldGroup = old[kSecAttrAccessGroup as String] as? String
        else { return }
        var add = baseQuery
        add[kSecAttrAccessGroup as String] = target
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainError.unexpectedStatus(added) }
        var check = baseQuery
        check[kSecAttrAccessGroup as String] = target
        check[kSecReturnData as String] = true
        var copy: AnyObject?
        guard SecItemCopyMatching(check as CFDictionary, &copy) == errSecSuccess,
              copy as? Data == data
        else { return }
        var remove = baseQuery
        remove[kSecAttrAccessGroup as String] = oldGroup
        SecItemDelete(remove as CFDictionary)
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
