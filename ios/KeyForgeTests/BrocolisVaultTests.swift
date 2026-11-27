import XCTest
@testable import KeyForge

/// Le hasard de Brocolis, le mode Charabia et le coffre scellé par Brocolis.
final class BrocolisVaultTests: XCTestCase {
    private let crypto = AppleCrypto.self

    private func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }

    // MARK: Hasard

    /// Le générateur déterministe de brocolis-proto (`hasard::Deterministic`) :
    /// bloc i = SHA-256("Brocolis_vecteurs" ‖ graine ‖ i u64 BE).
    func testDeterministicMatchesBrocolisProto() {
        var rng = BrocolisHasard.Deterministic(seed: "x")
        let out = rng.bytes(40)
        XCTAssertEqual(hex(Array(out[0..<32])), "9db6055f3e40759eb1983af1e48b8da56ddb6c2b4bd9e056c6c19496c8b42bf0")
        XCTAssertEqual(hex(Array(out[32..<40])), "23076d56106e7a2c")
    }

    func testDeterministicIsContinuous() {
        var a = BrocolisHasard.Deterministic(seed: "x")
        var b = BrocolisHasard.Deterministic(seed: "x")
        XCTAssertEqual(a.bytes(40), b.bytes(7) + b.bytes(33))
    }

    func testSystemRandomness() {
        XCTAssertNotEqual(BrocolisHasard.bytes(32), BrocolisHasard.bytes(32))
        XCTAssertEqual(Brocolis.randomBytes(16).count, 16)
    }

    // MARK: Charabia

    func testGibberishLengthAndPool() {
        var options = GibberishOptions()
        let value = Generator.gibberish(options)
        XCTAssertEqual(value.count, 24)
        XCTAssertTrue(value.allSatisfy { options.pool.contains($0) })

        options.unicode = false
        options.length = 500
        let ascii = Generator.gibberish(options)
        XCTAssertEqual(ascii.count, GibberishOptions.lengthRange.upperBound)
        XCTAssertTrue(ascii.allSatisfy { $0.isASCII && !$0.isWhitespace })
    }

    func testGibberishPoolIsClean() {
        let pool = GibberishOptions().pool
        XCTAssertEqual(Set(pool).count, pool.count, "aucun caractère en double")
        for character in pool {
            XCTAssertEqual(character.unicodeScalars.count, 1)
            XCTAssertEqual(String(character).precomposedStringWithCanonicalMapping, String(character))
            XCTAssertFalse(character.isWhitespace)
        }
    }

    func testGibberishEntropyAndDeterminism() {
        let options = GibberishOptions()
        XCTAssertEqual(Generator.gibberishEntropy(options), 24 * log2(Double(options.pool.count)), accuracy: 1e-9)
        XCTAssertGreaterThan(Generator.gibberishEntropy(options), 180)
        var a = BrocolisHasard.Deterministic(seed: "charabia")
        var b = BrocolisHasard.Deterministic(seed: "charabia")
        XCTAssertEqual(Generator.gibberish(options, using: &a), Generator.gibberish(options, using: &b))
    }

    // MARK: Coffre scellé

    private let items = [
        VaultItem(title: "Banque", username: "moi", website: "https://banque.fr", password: "S3cr3t!"),
        VaultItem(title: "Courriel", password: "aä0ΓD}«¬ç$h", isFavorite: true),
    ]

    func testSealRoundTrip() throws {
        let key = BrocolisHasard.bytes(32)
        let sealed = try VaultSeal.seal(items, key: key, crypto: crypto)
        XCTAssertTrue(VaultSeal.isSealed(sealed))
        let text = String(decoding: sealed, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("[[BROCOLIS:v4:"))
        XCTAssertFalse(text.contains("S3cr3t"), "jamais de mot de passe en clair")
        XCTAssertFalse(text.contains("Banque"))
        XCTAssertEqual(try VaultSeal.open(sealed, key: key, crypto: crypto), items)
    }

    func testEverySealIsFresh() throws {
        let key = BrocolisHasard.bytes(32)
        XCTAssertNotEqual(try VaultSeal.seal(items, key: key, crypto: crypto),
                          try VaultSeal.seal(items, key: key, crypto: crypto))
    }

    func testWrongOrMissingKey() throws {
        let sealed = try VaultSeal.seal(items, key: BrocolisHasard.bytes(32), crypto: crypto)
        XCTAssertThrowsError(try VaultSeal.open(sealed, key: BrocolisHasard.bytes(32), crypto: crypto)) {
            XCTAssertEqual($0 as? VaultSealError, .unreadable)
        }
        XCTAssertThrowsError(try VaultSeal.open(sealed, key: nil, crypto: crypto)) {
            XCTAssertEqual($0 as? VaultSealError, .missingKey)
        }
    }

    /// Un coffre d'une version précédente (JSON en clair) se lit toujours, sans clé.
    func testLegacyPlainVaultStillOpens() throws {
        let plain = try JSONEncoder().encode(items)
        XCTAssertFalse(VaultSeal.isSealed(plain))
        XCTAssertEqual(try VaultSeal.open(plain, key: nil, crypto: crypto), items)
    }

    /// Le coffre scellé est un message v4 à clé partagée standard : la sauvegarde et les
    /// apps Brocolis l'ouvrent avec la même clé.
    func testSealIsAStandardBrocolisMessage() throws {
        let key = BrocolisHasard.bytes(32)
        let sealed = try VaultSeal.seal(items, key: key, crypto: crypto)
        let json = try BrocolisV4.acceptPSK(String(decoding: sealed, as: UTF8.self), key: key, crypto: crypto)
        XCTAssertEqual(try JSONDecoder().decode([VaultItem].self, from: Data(json.utf8)), items)
    }
}
