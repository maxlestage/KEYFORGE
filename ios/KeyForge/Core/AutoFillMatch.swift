import Foundation

/// Which vault entries fit the site or app iOS asks AutoFill for. Pure logic
/// (Foundation only): shared by the AutoFill extension and tested under Linux.
enum AutoFillMatch {
    /// The host of a service identifier or a website field, in lowercase, without
    /// scheme, `www.`, port, path or trailing dot: `https://www.Example.com:8443/a` →
    /// `example.com`. Empty when there is none.
    static func host(of identifier: String) -> String {
        var text = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let scheme = text.range(of: "://") {
            text = String(text[scheme.upperBound...])
        }
        if let end = text.firstIndex(where: { "/?#".contains($0) }) {
            text = String(text[..<end])
        }
        if let at = text.lastIndex(of: "@") {
            text = String(text[text.index(after: at)...])
        }
        if let colon = text.lastIndex(of: ":") {
            text = String(text[..<colon])
        }
        while text.hasSuffix(".") { text.removeLast() }
        if text.hasPrefix("www.") { text = String(text.dropFirst(4)) }
        return text
    }

    /// How well `item` fits the hosts asked for: 2, same host; 1, one host is a
    /// subdomain of the other (`accounts.example.com` and `example.com`); 0, unrelated.
    static func score(_ item: VaultItem, hosts: [String]) -> Int {
        let own = host(of: item.website)
        guard !own.isEmpty else { return 0 }
        var best = 0
        for asked in hosts where !asked.isEmpty {
            if asked == own { return 2 }
            if asked.hasSuffix("." + own) || own.hasSuffix("." + asked) { best = 1 }
        }
        return best
    }

    /// The entries to suggest first (best match, then favorites, then by title) and
    /// all the others, for the list the extension shows.
    static func split(_ items: [VaultItem], for identifiers: [String]) -> (suggested: [VaultItem], others: [VaultItem]) {
        let hosts = identifiers.map(host(of:)).filter { !$0.isEmpty }
        let scored = items.map { ($0, score($0, hosts: hosts)) }
        let suggested = scored.filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                if lhs.0.isFavorite != rhs.0.isFavorite { return lhs.0.isFavorite }
                return lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
            }
            .map(\.0)
        let others = scored.filter { $0.1 == 0 }.map(\.0).sortedForDisplay()
        return (suggested, others)
    }

    /// The user name AutoFill fills in: the identifier, or the title when it is empty.
    static func user(of item: VaultItem) -> String {
        let name = item.username.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? item.title : name
    }
}
