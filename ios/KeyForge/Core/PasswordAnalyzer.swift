import Foundation

/// A rule the analyzer checks.
enum Criterion: String, CaseIterable, Identifiable, Sendable {
    case length
    case lowercase
    case uppercase
    case digits
    case symbols
    case notCommon
    case noPatterns

    var id: String { rawValue }

    var title: String {
        switch self {
        case .length: "Au moins 12 caractères"
        case .lowercase: "Des minuscules"
        case .uppercase: "Des majuscules"
        case .digits: "Des chiffres"
        case .symbols: "Des symboles"
        case .notCommon: "Absent des mots de passe courants"
        case .noPatterns: "Sans répétition ni suite évidente"
        }
    }
}

struct PasswordAnalysis: Equatable, Sendable {
    let bits: Double
    let isCommon: Bool
    let hasPatterns: Bool
    let passed: Set<Criterion>
    let suggestions: [String]

    var level: StrengthLevel { StrengthLevel(bits: bits) }
    var crackSeconds: Double { CrackTime.seconds(bits: bits) }
    var crackTime: String { CrackTime.describe(seconds: crackSeconds) }

    static let empty = PasswordAnalysis(
        bits: 0, isCommon: false, hasPatterns: false, passed: [], suggestions: []
    )
}

/// Estimates the strength of a password typed by the user, entirely on the device.
///
/// The estimate starts from the size of the character pool and the length, then
/// discounts what attackers try first: very common passwords, repeated characters,
/// sequences (`abc`, `123`) and keyboard walks (`qwerty`, `azerty`).
enum PasswordAnalyzer {
    static let common: Set<String> = [
        "123456", "123456789", "12345678", "12345", "1234567", "1234567890", "1234",
        "111111", "000000", "123123", "654321", "666666", "121212", "112233", "123321",
        "password", "password1", "passw0rd", "motdepasse", "azerty", "azertyuiop",
        "qwerty", "qwertyuiop", "qwerty123", "azerty123", "abc123", "abcdef", "iloveyou",
        "jetaime", "soleil", "doudou", "chouchou", "loulou", "marseille", "football",
        "dragon", "monkey", "letmein", "admin", "welcome", "bonjour", "princess",
        "sunshine", "master", "shadow", "superman", "batman", "trustno1", "starwars",
        "nicolas", "camille", "qazwsx", "zaq12wsx", "aaaaaa", "1q2w3e4r", "1qaz2wsx",
    ]

    /// Keyboard rows (French and English layouts) and the digit row.
    static let rows = [
        "azertyuiop", "qsdfghjklm", "wxcvbn",
        "qwertyuiop", "asdfghjkl", "zxcvbnm",
        "1234567890", "0123456789",
    ]

    static func analyze(_ password: String) -> PasswordAnalysis {
        let characters = Array(password)
        guard !characters.isEmpty else { return .empty }

        // Size of the pool, from the families present.
        let hasLower = characters.contains { $0.isLowercase && $0.isASCII }
        let hasUpper = characters.contains { $0.isUppercase && $0.isASCII }
        let hasDigit = characters.contains { $0.isASCII && $0.isNumber }
        let hasSymbol = characters.contains { $0.isASCII && !$0.isLetter && !$0.isNumber }
        let hasOther = characters.contains { !$0.isASCII }
        var pool = 0
        if hasLower { pool += 26 }
        if hasUpper { pool += 26 }
        if hasDigit { pool += 10 }
        if hasSymbol { pool += 33 }
        if hasOther { pool += 100 }
        pool = max(pool, 2)

        // Characters that follow a pattern only count for a quarter.
        let lowered = characters.map { Character($0.lowercased()) }
        var patterned = 0
        for i in characters.indices.dropFirst() {
            if follows(lowered[i - 1], lowered[i]) { patterned += 1 }
        }
        // A string made of one block repeated (`abcabcabc`) is as strong as its block.
        let block = repeatedBlockLength(lowered)
        var effectiveLength = Double(characters.count - patterned) + Double(patterned) * 0.25
        if block < characters.count {
            effectiveLength = min(effectiveLength, Double(block) + 1)
        }
        var bits = effectiveLength * log2(Double(pool))

        let normalized = password.lowercased()
        // `Password123!` is still `password` to an attacker.
        let stripped = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "0123456789!?.*"))
        let isCommon = common.contains(normalized) || (!stripped.isEmpty && common.contains(stripped))
        if isCommon { bits = min(bits, 4) }
        let hasPatterns = patterned * 3 >= characters.count || block < characters.count

        var passed = Set<Criterion>()
        if characters.count >= 12 { passed.insert(.length) }
        if hasLower { passed.insert(.lowercase) }
        if hasUpper { passed.insert(.uppercase) }
        if hasDigit { passed.insert(.digits) }
        if hasSymbol || hasOther { passed.insert(.symbols) }
        if !isCommon { passed.insert(.notCommon) }
        if !hasPatterns { passed.insert(.noPatterns) }

        var suggestions: [String] = []
        if isCommon {
            suggestions.append("Ce mot de passe figure parmi les plus utilisés : changez-le sans attendre.")
        }
        if characters.count < 12 {
            suggestions.append("Allongez-le : chaque caractère multiplie le travail d'un attaquant.")
        }
        if !hasUpper || !hasLower {
            suggestions.append("Mélangez majuscules et minuscules.")
        }
        if !hasDigit || !(hasSymbol || hasOther) {
            suggestions.append("Ajoutez des chiffres et des symboles.")
        }
        if hasPatterns {
            suggestions.append("Évitez les répétitions, les suites (abc, 123) et les rangées du clavier.")
        }
        if suggestions.isEmpty {
            suggestions.append("Excellent travail. Gardez-le unique : un mot de passe par compte.")
        }
        return PasswordAnalysis(
            bits: bits, isCommon: isCommon, hasPatterns: hasPatterns,
            passed: passed, suggestions: suggestions
        )
    }

    /// Whether `next` repeats `previous`, continues an alphabetical or numerical
    /// sequence, or is its neighbour on a keyboard row.
    static func follows(_ previous: Character, _ next: Character) -> Bool {
        if previous == next { return true }
        if let a = previous.unicodeScalars.first?.value, let b = next.unicodeScalars.first?.value,
           previous.isASCII, next.isASCII, previous.isLetter || previous.isNumber,
           next.isLetter || next.isNumber, a.distance(to: b) == 1 || b.distance(to: a) == 1 {
            return true
        }
        let pair = String([previous, next])
        return rows.contains { $0.contains(pair) }
    }

    /// The length of the shortest block that, repeated, makes the whole string.
    static func repeatedBlockLength(_ characters: [Character]) -> Int {
        let n = characters.count
        guard n >= 4 else { return n }
        for size in 1...(n / 2) where n % size == 0 {
            let block = characters[0..<size]
            if stride(from: size, to: n, by: size).allSatisfy({ characters[$0..<($0 + size)] == block }) {
                return size
            }
        }
        return n
    }
}
