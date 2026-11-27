import Foundation

/// An entry of the vault. The whole vault is stored as JSON in the Keychain.
struct VaultItem: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var username: String = ""
    var website: String = ""
    var password: String
    var notes: String = ""
    /// Le générateur de codes de validation (2FA) : un lien `otpauth://totp/…`.
    /// Optionnel : absent des coffres d'avant, qui doivent toujours se lire.
    var totp: String?
    var isFavorite = false
    var createdAt = Date()
    var updatedAt = Date()

    /// The host of the website, for display (`https://www.example.com/a` → `example.com`).
    var displayHost: String {
        var host = website.trimmingCharacters(in: .whitespaces)
        for prefix in ["https://", "http://"] where host.lowercased().hasPrefix(prefix) {
            host = String(host.dropFirst(prefix.count))
        }
        if host.lowercased().hasPrefix("www.") { host = String(host.dropFirst(4)) }
        return host.split(separator: "/").first.map(String.init) ?? host
    }

    /// The first letter shown in the item's badge.
    var initial: String {
        let source = title.isEmpty ? displayHost : title
        return source.first.map { String($0).uppercased() } ?? "•"
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return [title, username, website, notes].contains {
            $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

extension Array where Element == VaultItem {
    /// Favorites first, then by title.
    func sortedForDisplay() -> [VaultItem] {
        sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }
}
