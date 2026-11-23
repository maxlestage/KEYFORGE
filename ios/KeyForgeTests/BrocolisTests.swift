import XCTest
@testable import KeyForge

/// Les vecteurs de brocolis-proto (`proto/vectors.json` de
/// https://github.com/maxlestage/brocolis) : KeyForge doit les retrouver octet pour octet.
final class BrocolisTests: XCTestCase {
    private let key = (0..<32).map(UInt8.init)
    private let phrase = "brocoli vert 2026"
    private let wrongPhrase = "brocoli vert 2025"

    private func bytes(_ hex: String) -> [UInt8] {
        var out = [UInt8]()
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            out.append(UInt8(hex[i..<j], radix: 16)!)
            i = j
        }
        return out
    }

    func testArgon2idVectors() throws {
        let salt = [UInt8](repeating: 0x33, count: 16)
        XCTAssertEqual(
            try Brocolis.argon2idKey(phrase: phrase, salt: salt, params: .minimum),
            bytes("f75a95bffa2db21d6f6702883d7ede9c585dcb6bbe58c05b50cb22a81acd6bd8")
        )
        XCTAssertEqual(
            try Brocolis.argon2idKey(phrase: phrase, salt: salt, params: .standard),
            bytes("929b1bafcfa4cdbbc93e2f8e4d3c319d15d96a058befb4749dafc5db98de24ad")
        )
    }

    func testProtectedKeyV2Vectors() throws {
        let cases: [(BrocolisArgon2Params, String)] = [
            (.minimum, "[[BROCOLIS-CLE:v2:AgAATAACATMzMzMzMzMzMzMzMzMzMzNERERERERERERERERAUxWgTZ6ZBUGbuMWWk5gln1V7GZgwoYOu0FWCX4KZU25GrK9aOSl+ZjCHSgr6Glk=]]"),
            (.standard, "[[BROCOLIS-CLE:v2:AgABAAADATMzMzMzMzMzMzMzMzMzMzNERERERERERERERERm6Sk2e917/gD3dxBLq4+2XXGrDTY2sG4gyt758Zc4dbDv6x7ZUhTk+dIUdGuu1UI=]]"),
        ]
        for (params, expected) in cases {
            let token = try Brocolis.protectKeyV2(
                key, phrase: phrase, params: params,
                salt: [UInt8](repeating: 0x33, count: 16), nonce: [UInt8](repeating: 0x44, count: 12),
                crypto: AppleCrypto.self
            )
            XCTAssertEqual(token, expected)
            XCTAssertEqual(try Brocolis.v2Params(in: expected), params)
            XCTAssertEqual(try Brocolis.unprotectKey(in: "Voici : \(expected) !", phrase: phrase, crypto: AppleCrypto.self), key)
            XCTAssertThrowsError(try Brocolis.unprotectKey(in: expected, phrase: wrongPhrase, crypto: AppleCrypto.self)) {
                XCTAssertEqual($0 as? BrocolisError, .decryption)
            }
        }
    }

    func testProtectedKeyV1Vector() throws {
        let token = "[[BROCOLIS-CLE:v1:ERERERERERERERERERERESIiIiIiIiIiIiIiIsq57j18BXkqq/4VdIw82nQqzrax9Cfn2mfUJjWH8l327NAf2rWaSYCJh3BfGH4eWA==]]"
        XCTAssertEqual(try Brocolis.unprotectKey(in: token, phrase: phrase, crypto: AppleCrypto.self), key)
        XCTAssertThrowsError(try Brocolis.unprotectKey(in: token, phrase: wrongPhrase, crypto: AppleCrypto.self))
    }

    func testRejectedParameters() {
        for (m, t, p) in [(19_455, 2, 1), (19_456, 1, 1), (1_048_577, 3, 1), (65_536, 3, 0), (65_536, 17, 1)] {
            XCTAssertFalse(BrocolisArgon2Params(memoryKiB: UInt32(m), iterations: UInt8(t), parallelism: UInt8(p)).isValid)
        }
        XCTAssertTrue(BrocolisArgon2Params.standard.isValid)
        XCTAssertThrowsError(try Brocolis.protectKeyV2(
            key, phrase: "court", params: .minimum,
            salt: [UInt8](repeating: 0, count: 16), nonce: [UInt8](repeating: 0, count: 12), crypto: AppleCrypto.self
        )) {
            XCTAssertEqual($0 as? BrocolisError, .phraseTooShort)
        }
    }

    func testLegacyTokenV1Vector() throws {
        let token = "[[BROCOLIS:v1:rJ0bFC0ezvGOT/o9DTvx9YeDWhXv9HSWqp3ARMc9XcQLB7zbzVI=]]"
        let first = bytes("42dacfb18bcfa86c9337ed322d188270dfe2d3e06334cdfd15960645332c1ee1")
        XCTAssertEqual(try Brocolis.openTokenV1(in: token, key: first, crypto: AppleCrypto.self), "Salut 🥦")
        let nonce = Array([UInt8](Data(base64Encoded: "rJ0bFC0ezvGOT/o9DTvx9YeDWhXv9HSWqp3ARMc9XcQLB7zbzVI=")!).prefix(12))
        XCTAssertEqual(try Brocolis.sealTokenV1("Salut 🥦", key: first, nonce: nonce, crypto: AppleCrypto.self), token)
        let second = bytes("f8cb01f6fe489a81bb2bfa11efd267913b9a820c27984e576f1b4dcab5445ac3")
        XCTAssertThrowsError(try Brocolis.openTokenV1(in: token, key: second, crypto: AppleCrypto.self))
    }

    func testVaultBackupRoundTrip() throws {
        let items = [
            VaultItem(title: "GitHub", username: "max", website: "github.com", password: "Tg7#qP!m2Lz@Wv9$", notes: "🥦"),
            VaultItem(title: "Banque", password: "Galet-Phare7-Sorbet-Lynx-Opale", isFavorite: true),
        ]
        let text = try VaultBackup.export(items, phrase: "Galet-Phare7-Sorbet", params: .minimum, crypto: AppleCrypto.self)
        XCTAssertTrue(VaultBackup.looksLikeBackup(text))
        XCTAssertTrue(text.hasPrefix(Brocolis.protectedKeyV2Head))
        let restored = try VaultBackup.open("Ma sauvegarde :\n\(text)", phrase: "Galet-Phare7-Sorbet", crypto: AppleCrypto.self)
        XCTAssertEqual(restored.map(\.id), items.map(\.id))
        XCTAssertEqual(restored.map(\.password), items.map(\.password))
        XCTAssertEqual(restored.last?.isFavorite, true)
        XCTAssertThrowsError(try VaultBackup.open(text, phrase: "mauvaise phrase", crypto: AppleCrypto.self)) {
            XCTAssertEqual($0 as? BrocolisError, .decryption)
        }
        XCTAssertThrowsError(try VaultBackup.export(items, phrase: "court", crypto: AppleCrypto.self))
    }

    func testDefaultExportUsesStandardParameters() throws {
        let text = try VaultBackup.export([], phrase: "une phrase assez longue", crypto: AppleCrypto.self)
        XCTAssertEqual(try Brocolis.v2Params(in: text), .standard)
    }
}
