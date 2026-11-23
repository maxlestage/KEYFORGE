import Foundation

/// The words of passphrases: one word per line.
struct WordList: Sendable {
    let words: [String]

    init(text: String) {
        var seen = Set<String>()
        words = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    init(words: [String]) {
        self.init(text: words.joined(separator: "\n"))
    }

    /// Bits of entropy of one word drawn from the list.
    var bitsPerWord: Double {
        words.count > 1 ? log2(Double(words.count)) : 0
    }

    /// The 1,024 French words shipped with the app (`wordlist-fr.txt`).
    static let bundled: WordList = {
        if let url = Bundle.main.url(forResource: "wordlist-fr", withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            let list = WordList(text: text)
            if list.words.count >= 2 { return list }
        }
        return fallback
    }()

    /// Used only if the resource is missing (it never should be).
    static let fallback = WordList(words: [
        "abeille", "aurore", "baleine", "cascade", "comete", "dragon", "etoile", "falaise",
        "forge", "galaxie", "glacier", "horizon", "jardin", "lagune", "lumiere", "marbre",
        "mistral", "nuage", "ocean", "orage", "phare", "plume", "quartz", "rivage",
        "saphir", "sommet", "tempete", "tigre", "tresor", "vague", "volcan", "zephyr",
    ])
}
