import XCTest
@testable import KeyForge

final class GeneratorTests: XCTestCase {
    func testPasswordHasTheRequestedLength() {
        for length in [4, 12, 20, 64, 128] {
            var options = PasswordOptions()
            options.length = length
            XCTAssertEqual(Generator.password(options).count, length)
        }
    }

    func testPasswordLengthIsClamped() {
        var options = PasswordOptions()
        options.length = 1
        XCTAssertEqual(Generator.password(options).count, 4)
        options.length = 500
        XCTAssertEqual(Generator.password(options).count, 128)
    }

    func testPasswordContainsEveryEnabledClass() {
        let options = PasswordOptions(length: 4)
        for _ in 0..<300 {
            let password = Generator.password(options)
            for family in CharacterClass.allCases {
                XCTAssertTrue(password.contains { family.characters.contains($0) }, "\(family) missing in \(password)")
            }
        }
    }

    func testPasswordOnlyUsesEnabledClasses() {
        let options = PasswordOptions(length: 64, uppercase: false, lowercase: false, digits: true, symbols: false)
        let password = Generator.password(options)
        XCTAssertTrue(password.allSatisfy(\.isNumber))
    }

    func testNoClassFallsBackToLowercase() {
        let options = PasswordOptions(length: 30, uppercase: false, lowercase: false, digits: false, symbols: false)
        XCTAssertTrue(Generator.password(options).allSatisfy { $0.isLowercase })
    }

    func testAmbiguousCharactersAreExcluded() {
        let options = PasswordOptions(length: 128, excludeAmbiguous: true)
        for _ in 0..<50 {
            let password = Generator.password(options)
            XCTAssertFalse(password.contains { CharacterClass.ambiguous.contains($0) })
        }
    }

    func testPassphraseWordCountAndSeparator() {
        let words = WordList(words: ["alpha", "bravo", "charlie", "delta"])
        for separator in PassphraseSeparator.allCases {
            let options = PassphraseOptions(wordCount: 7, separator: separator)
            let phrase = Generator.passphrase(options, words: words)
            let parts = phrase.components(separatedBy: separator.rawValue)
            XCTAssertEqual(parts.count, 7)
            XCTAssertTrue(parts.allSatisfy { words.words.contains($0) })
        }
    }

    func testPassphraseCapitalizeAndNumber() {
        let words = WordList(words: ["alpha", "bravo"])
        let options = PassphraseOptions(wordCount: 4, separator: .dot, capitalize: true, includeNumber: true)
        let parts = Generator.passphrase(options, words: words).components(separatedBy: ".")
        XCTAssertTrue(parts.allSatisfy { $0.first?.isUppercase == true })
        XCTAssertEqual(parts.filter { $0.last?.isNumber == true }.count, 1)
    }

    func testPassphraseReachesExcellent() {
        // 20 mots : assez pour le niveau « Excellente » (128 bits et plus).
        var options = PassphraseOptions()
        options.wordCount = 20
        XCTAssertEqual(options.clampedWordCount, 20)
        let bits = Generator.passphraseEntropy(options, words: .bundled)
        XCTAssertGreaterThanOrEqual(bits, 128)
        XCTAssertEqual(StrengthLevel(bits: bits), .excellent)
        options.wordCount = 99
        XCTAssertEqual(options.clampedWordCount, 20)
    }

    func testPinIsDigitsOnly() {
        for length in PinOptions.lengthRange {
            let pin = Generator.pin(PinOptions(length: length))
            XCTAssertEqual(pin.count, length)
            XCTAssertTrue(pin.allSatisfy(\.isNumber))
        }
    }

    func testBundledWordList() throws {
        #if os(Linux)
        throw XCTSkip("The word list is a resource of the iOS app bundle.")
        #endif
        let list = WordList.bundled
        XCTAssertEqual(list.words.count, 1024)
        XCTAssertEqual(list.bitsPerWord, 10, accuracy: 0.0001)
    }
}

final class EntropyTests: XCTestCase {
    func testEntropyFormulas() {
        XCTAssertEqual(Entropy.bits(length: 10, poolSize: 10), 10 * log2(10), accuracy: 0.0001)
        XCTAssertEqual(Generator.pinEntropy(PinOptions(length: 6)), 6 * log2(10), accuracy: 0.0001)
        let all = PasswordOptions(length: 20)
        XCTAssertEqual(all.pool.count, 26 + 26 + 10 + 24)
        XCTAssertEqual(Generator.passwordEntropy(all), 20 * log2(86), accuracy: 0.0001)
        let words = WordList(words: (0..<1024).map { "w\($0)" })
        XCTAssertEqual(Generator.passphraseEntropy(PassphraseOptions(wordCount: 5), words: words), 50, accuracy: 0.0001)
        XCTAssertEqual(
            Generator.passphraseEntropy(PassphraseOptions(wordCount: 5, includeNumber: true), words: words),
            50 + log2(10), accuracy: 0.0001
        )
    }

    func testLevels() {
        XCTAssertEqual(StrengthLevel(bits: 0), .veryWeak)
        XCTAssertEqual(StrengthLevel(bits: 27.9), .veryWeak)
        XCTAssertEqual(StrengthLevel(bits: 28), .weak)
        XCTAssertEqual(StrengthLevel(bits: 36), .fair)
        XCTAssertEqual(StrengthLevel(bits: 60), .strong)
        XCTAssertEqual(StrengthLevel(bits: 128), .excellent)
        XCTAssertLessThan(StrengthLevel.weak, StrengthLevel.strong)
    }
}

final class AnalyzerTests: XCTestCase {
    func testCommonPasswordsAreNearZero() {
        for password in ["password", "azerty", "123456", "Password123!", "motdepasse"] {
            let analysis = PasswordAnalyzer.analyze(password)
            XCTAssertTrue(analysis.isCommon, password)
            XCTAssertLessThanOrEqual(analysis.bits, 4, password)
            XCTAssertEqual(analysis.level, .veryWeak)
            XCTAssertFalse(analysis.passed.contains(.notCommon))
        }
    }

    func testPatternsArePenalised() {
        let sequence = PasswordAnalyzer.analyze("abcdefghijkl")
        let random = PasswordAnalyzer.analyze("qmzvhtrwpkxc")
        XCTAssertTrue(sequence.hasPatterns)
        XCTAssertLessThan(sequence.bits, random.bits)
        XCTAssertTrue(PasswordAnalyzer.analyze("abcabcabcabc").hasPatterns)
        XCTAssertTrue(PasswordAnalyzer.analyze("aaaaaaaaaaaa").hasPatterns)
    }

    func testStrongPasswordPassesEverything() {
        let analysis = PasswordAnalyzer.analyze("T7#qLm!x2Vr9@Kp")
        XCTAssertEqual(analysis.passed, Set(Criterion.allCases))
        XCTAssertGreaterThanOrEqual(analysis.level, .strong)
    }

    func testEmpty() {
        XCTAssertEqual(PasswordAnalyzer.analyze(""), .empty)
    }
}

final class CrackTimeTests: XCTestCase {
    func testDescriptions() {
        XCTAssertEqual(CrackTime.describe(seconds: 0.2), "instantané")
        XCTAssertEqual(CrackTime.describe(seconds: 1), "1 seconde")
        XCTAssertEqual(CrackTime.describe(seconds: 42), "42 secondes")
        XCTAssertEqual(CrackTime.describe(seconds: 3 * 3600 + 5), "3 heures")
        XCTAssertEqual(CrackTime.describe(seconds: 2 * 86400), "2 jours")
        XCTAssertEqual(CrackTime.describe(seconds: 65 * 86400), "2 mois")
        XCTAssertEqual(CrackTime.describe(seconds: 365 * 86400), "1 an")
        XCTAssertEqual(CrackTime.describe(seconds: 12 * 100 * 365 * 86400), "12 siècles")
        XCTAssertEqual(CrackTime.describe(seconds: .infinity), "plus d'un million de siècles")
    }

    func testGrouping() {
        XCTAssertEqual(CrackTime.grouped(7), "7")
        XCTAssertEqual(CrackTime.grouped(1234), "1 234")
        XCTAssertEqual(CrackTime.grouped(1234567), "1 234 567")
    }

    func testSecondsGrowWithBits() {
        XCTAssertLessThan(CrackTime.seconds(bits: 40), CrackTime.seconds(bits: 41))
        XCTAssertEqual(CrackTime.seconds(bits: 0), 0)
        XCTAssertEqual(CrackTime.describe(bits: 128), "plus d'un million de siècles")
    }
}

final class VaultItemTests: XCTestCase {
    func testDisplayHostAndSearch() {
        let item = VaultItem(title: "Banque", username: "moi", website: "https://www.exemple.fr/connexion", password: "x")
        XCTAssertEqual(item.displayHost, "exemple.fr")
        XCTAssertEqual(item.initial, "B")
        XCTAssertTrue(item.matches("exem"))
        XCTAssertTrue(item.matches("banque"))
        XCTAssertFalse(item.matches("zzz"))
    }

    func testCodableRoundTripAndSorting() throws {
        let items = [
            VaultItem(title: "Zeta", password: "a"),
            VaultItem(title: "alpha", password: "b"),
            VaultItem(title: "Mu", password: "c", isFavorite: true),
        ]
        let decoded = try JSONDecoder().decode([VaultItem].self, from: JSONEncoder().encode(items))
        XCTAssertEqual(decoded, items)
        XCTAssertEqual(items.sortedForDisplay().map(\.title), ["Mu", "alpha", "Zeta"])
    }
}
