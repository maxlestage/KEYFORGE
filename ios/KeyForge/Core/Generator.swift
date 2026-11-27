import Foundation

/// The kinds of secrets KeyForge can forge.
enum GeneratorMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case password
    case passphrase
    case pin
    case gibberish

    var id: String { rawValue }

    var title: String {
        switch self {
        case .password: "Mot de passe"
        case .passphrase: "Phrase de passe"
        case .pin: "Code PIN"
        case .gibberish: "Charabia"
        }
    }

    /// Le libellé court du sélecteur (quatre modes côte à côte).
    var shortTitle: String {
        switch self {
        case .password: "Mot de passe"
        case .passphrase: "Phrase"
        case .pin: "PIN"
        case .gibberish: "Charabia"
        }
    }

    var symbol: String {
        switch self {
        case .password: "key.fill"
        case .passphrase: "text.quote"
        case .pin: "number.square.fill"
        case .gibberish: "scribble.variable"
        }
    }
}

/// The character families a password can be made of.
enum CharacterClass: String, CaseIterable, Sendable {
    case uppercase
    case lowercase
    case digits
    case symbols

    static let ambiguous: Set<Character> = ["0", "O", "o", "1", "l", "I", "|"]

    /// Every character of the family, in a fixed order.
    var characters: [Character] {
        switch self {
        case .uppercase: Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        case .lowercase: Array("abcdefghijklmnopqrstuvwxyz")
        case .digits: Array("0123456789")
        case .symbols: Array("!@#$%^&*()-_=+[]{};:,.?/")
        }
    }

    func characters(excludingAmbiguous: Bool) -> [Character] {
        excludingAmbiguous
            ? characters.filter { !CharacterClass.ambiguous.contains($0) }
            : characters
    }

    /// The family a character belongs to, if any.
    static func of(_ character: Character) -> CharacterClass? {
        allCases.first { $0.characters.contains(character) }
    }
}

struct PasswordOptions: Codable, Equatable, Sendable {
    static let lengthRange = 4...128

    var length: Int = 20
    var uppercase = true
    var lowercase = true
    var digits = true
    var symbols = true
    var excludeAmbiguous = false

    var enabledClasses: [CharacterClass] {
        var classes: [CharacterClass] = []
        if uppercase { classes.append(.uppercase) }
        if lowercase { classes.append(.lowercase) }
        if digits { classes.append(.digits) }
        if symbols { classes.append(.symbols) }
        // A password needs at least one family: lowercase letters by default.
        return classes.isEmpty ? [.lowercase] : classes
    }

    /// Every character the password may contain.
    var pool: [Character] {
        enabledClasses.flatMap { $0.characters(excludingAmbiguous: excludeAmbiguous) }
    }

    var clampedLength: Int {
        min(max(length, Self.lengthRange.lowerBound), Self.lengthRange.upperBound)
    }
}

enum PassphraseSeparator: String, CaseIterable, Codable, Identifiable, Sendable {
    case hyphen = "-"
    case dot = "."
    case underscore = "_"
    case space = " "
    case slash = "/"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .space: "Espace"
        default: rawValue
        }
    }
}

struct PassphraseOptions: Codable, Equatable, Sendable {
    static let wordRange = 3...20

    var wordCount: Int = 5
    var separator: PassphraseSeparator = .hyphen
    var capitalize = false
    var includeNumber = false

    var clampedWordCount: Int {
        min(max(wordCount, Self.wordRange.lowerBound), Self.wordRange.upperBound)
    }
}

struct PinOptions: Codable, Equatable, Sendable {
    static let lengthRange = 4...12

    var length: Int = 6

    var clampedLength: Int {
        min(max(length, Self.lengthRange.lowerBound), Self.lengthRange.upperBound)
    }
}

/// Le charabia : une suite illisible de lettres, chiffres et symboles, avec en option
/// des lettres accentuées, grecques et des symboles typographiques (Unicode).
///
/// Chaque caractère est un seul point de code, déjà en forme normalisée NFC, visible et
/// sans ambiguïté de saisie : ni espace, ni caractère invisible, ni diacritique
/// combinant, ni caractère d'écriture de droite à gauche.
struct GibberishOptions: Codable, Equatable, Sendable {
    static let lengthRange = 8...128

    var length: Int = 24
    var unicode = true

    /// Les 94 caractères ASCII imprimables, espace exclue.
    static let ascii: [Character] = (0x21...0x7E).map { Character(Unicode.Scalar(UInt8($0))) }
    /// Lettres accentuées et grecques, symboles typographiques.
    static let extended: [Character] = Array(
        "àâäáãåçéèêëíìîïñóòôöõøœúùûüýÿßæÀÂÄÁÃÅÇÉÈÊËÍÌÎÏÑÓÒÔÖÕØŒÚÙÛÜÝŸÆ"
        + "αβγδεζηθλμξπσφχψωΓΔΘΛΞΠΣΦΨΩ"
        + "¡¿§¶°±÷¤£€¥¢©®™«»†‡•…‰¬"
    )

    var pool: [Character] { unicode ? Self.ascii + Self.extended : Self.ascii }

    var clampedLength: Int {
        min(max(length, Self.lengthRange.lowerBound), Self.lengthRange.upperBound)
    }
}

/// A generated secret and its strength.
struct GeneratedSecret: Equatable, Sendable {
    let value: String
    let mode: GeneratorMode
    let entropy: Double

    var strength: StrengthLevel { StrengthLevel(bits: entropy) }
}

/// Forges passwords, passphrases, PINs and gibberish from a cryptographically secure source.
///
/// The randomness is Brocolis' (`BrocolisHasard.system()`, the operating system's
/// CSPRNG, as in brocolis-proto), and `Int.random(in:using:)` draws without modulo bias.
enum Generator {
    // MARK: Passwords

    static func password(_ options: PasswordOptions) -> String {
        var rng = BrocolisHasard.system()
        return password(options, using: &rng)
    }

    static func password<R: RandomNumberGenerator>(_ options: PasswordOptions, using rng: inout R) -> String {
        let length = options.clampedLength
        let classes = options.enabledClasses.map {
            $0.characters(excludingAmbiguous: options.excludeAmbiguous)
        }
        let pool = classes.flatMap { $0 }
        var characters: [Character] = []
        characters.reserveCapacity(length)
        // At least one character of every enabled family…
        for family in classes where characters.count < length {
            characters.append(family[Int.random(in: 0..<family.count, using: &rng)])
        }
        // …then the rest from the whole pool, and a shuffle so the guaranteed
        // characters are not always at the start.
        while characters.count < length {
            characters.append(pool[Int.random(in: 0..<pool.count, using: &rng)])
        }
        characters.shuffle(using: &rng)
        return String(characters)
    }

    static func passwordEntropy(_ options: PasswordOptions) -> Double {
        Entropy.bits(length: options.clampedLength, poolSize: options.pool.count)
    }

    // MARK: Passphrases

    static func passphrase(_ options: PassphraseOptions, words: WordList) -> String {
        var rng = BrocolisHasard.system()
        return passphrase(options, words: words, using: &rng)
    }

    static func passphrase<R: RandomNumberGenerator>(
        _ options: PassphraseOptions, words list: WordList, using rng: inout R
    ) -> String {
        var words = (0..<options.clampedWordCount).map { _ in
            list.words[Int.random(in: 0..<list.words.count, using: &rng)]
        }
        if options.capitalize {
            words = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        }
        if options.includeNumber {
            let index = Int.random(in: 0..<words.count, using: &rng)
            words[index] += String(Int.random(in: 0...9, using: &rng))
        }
        return words.joined(separator: options.separator.rawValue)
    }

    static func passphraseEntropy(_ options: PassphraseOptions, words: WordList) -> Double {
        var bits = Double(options.clampedWordCount) * log2(Double(max(words.words.count, 1)))
        if options.includeNumber { bits += log2(10) }
        return bits
    }

    // MARK: PINs

    static func pin(_ options: PinOptions) -> String {
        var rng = BrocolisHasard.system()
        return pin(options, using: &rng)
    }

    static func pin<R: RandomNumberGenerator>(_ options: PinOptions, using rng: inout R) -> String {
        String((0..<options.clampedLength).map { _ in
            Character(String(Int.random(in: 0...9, using: &rng)))
        })
    }

    static func pinEntropy(_ options: PinOptions) -> Double {
        Entropy.bits(length: options.clampedLength, poolSize: 10)
    }

    // MARK: Charabia

    static func gibberish(_ options: GibberishOptions) -> String {
        var rng = BrocolisHasard.system()
        return gibberish(options, using: &rng)
    }

    static func gibberish<R: RandomNumberGenerator>(_ options: GibberishOptions, using rng: inout R) -> String {
        let pool = options.pool
        return String((0..<options.clampedLength).map { _ in pool[Int.random(in: 0..<pool.count, using: &rng)] })
    }

    static func gibberishEntropy(_ options: GibberishOptions) -> Double {
        Entropy.bits(length: options.clampedLength, poolSize: options.pool.count)
    }
}
