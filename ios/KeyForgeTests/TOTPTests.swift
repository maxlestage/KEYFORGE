import AuthenticationServices
import XCTest
@testable import KeyForge

/// Les codes de validation (TOTP) : vecteurs de la RFC 6238, liens `otpauth://`, base32,
/// et ce qu'iOS reçoit pour les proposer au-dessus du clavier.
final class TOTPTests: XCTestCase {
    private func generator(_ algorithm: TOTP.Algorithm) -> TOTP {
        let seed = "1234567890123456789012345678901234567890123456789012345678901234"
        let length: Int
        switch algorithm {
        case .sha1: length = 20
        case .sha256: length = 32
        case .sha512: length = 64
        }
        var totp = TOTP(secret: Array(seed.utf8.prefix(length)))
        totp.algorithm = algorithm
        totp.digits = 8
        return totp
    }

    /// RFC 6238, annexe B.
    func testRFC6238Vectors() {
        let vectors: [(TimeInterval, String, String, String)] = [
            (59, "94287082", "46119246", "90693936"),
            (1_111_111_109, "07081804", "68084774", "25091201"),
            (1_111_111_111, "14050471", "67062674", "99943326"),
            (1_234_567_890, "89005924", "91819424", "93441116"),
            (2_000_000_000, "69279037", "90698825", "38618901"),
            (20_000_000_000, "65353130", "77737706", "47863826"),
        ]
        for (time, sha1, sha256, sha512) in vectors {
            let date = Date(timeIntervalSince1970: time)
            XCTAssertEqual(generator(.sha1).code(at: date), sha1, "SHA-1 à \(time)")
            XCTAssertEqual(generator(.sha256).code(at: date), sha256, "SHA-256 à \(time)")
            XCTAssertEqual(generator(.sha512).code(at: date), sha512, "SHA-512 à \(time)")
        }
    }

    func testSixDigitsAndCountdown() throws {
        var totp = generator(.sha1)
        totp.digits = 6
        XCTAssertEqual(totp.code(at: Date(timeIntervalSince1970: 59)), "287082")
        XCTAssertEqual(totp.displayCode(at: Date(timeIntervalSince1970: 59)), "287 082")
        XCTAssertEqual(totp.secondsRemaining(at: Date(timeIntervalSince1970: 59)), 1)
        XCTAssertEqual(totp.secondsRemaining(at: Date(timeIntervalSince1970: 60)), 30)
        // Le code change à la période suivante.
        XCTAssertNotEqual(totp.code(at: Date(timeIntervalSince1970: 59)), totp.code(at: Date(timeIntervalSince1970: 60)))
    }

    func testBase32() {
        XCTAssertEqual(TOTP.base32Encode(Array("foobar".utf8)), "MZXW6YTBOI")
        XCTAssertEqual(TOTP.base32Decode("mzxw 6ytb-oi======"), Array("foobar".utf8))
        XCTAssertNil(TOTP.base32Decode("MZXW6YTB0I"), "0 n'est pas en base32")
        for count in 0..<40 {
            let bytes = (0..<count).map { UInt8(truncatingIfNeeded: $0 &* 37 &+ 11) }
            XCTAssertEqual(TOTP.base32Decode(TOTP.base32Encode(bytes)), bytes)
        }
    }

    func testOtpauthLink() throws {
        let link = "otpauth://totp/ACME%20Co:john.doe@email.com?secret=HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ&issuer=ACME%20Co&algorithm=SHA256&digits=8&period=60"
        let totp = try XCTUnwrap(TOTP(link))
        XCTAssertEqual(totp.issuer, "ACME Co")
        XCTAssertEqual(totp.account, "john.doe@email.com")
        XCTAssertEqual(totp.algorithm, .sha256)
        XCTAssertEqual(totp.digits, 8)
        XCTAssertEqual(totp.period, 60)
        XCTAssertEqual(totp.secret.count, 20)
        // Le lien rangé dans le coffre se relit à l'identique.
        XCTAssertEqual(TOTP(totp.uri), totp)
    }

    func testDefaultsAndBareSecret() throws {
        let link = try XCTUnwrap(TOTP("otpauth://totp/moi@exemple.fr?secret=JBSWY3DPEHPK3PXP"))
        XCTAssertEqual(link.algorithm, .sha1)
        XCTAssertEqual(link.digits, 6)
        XCTAssertEqual(link.period, 30)
        XCTAssertEqual(link.issuer, "")
        XCTAssertEqual(link.account, "moi@exemple.fr")
        // La clé saisie à la main, comme les sites l'affichent.
        let bare = try XCTUnwrap(TOTP("jbsw y3dp ehpk 3pxp"))
        XCTAssertEqual(bare.secret, link.secret)
        XCTAssertEqual(bare.code(at: Date(timeIntervalSince1970: 59)), link.code(at: Date(timeIntervalSince1970: 59)))
    }

    func testRefusedInputs() {
        XCTAssertNil(TOTP(""))
        XCTAssertNil(TOTP("bonjour"))
        XCTAssertNil(TOTP("otpauth://hotp/x?secret=JBSWY3DPEHPK3PXP"), "les compteurs HOTP ne sont pas gérés")
        XCTAssertNil(TOTP("otpauth://totp/x"))
        XCTAssertNil(TOTP("otpauth://totp/x?secret=JBSWY3DPEHPK3PXP&digits=12"))
        XCTAssertNil(TOTP("otpauth://totp/x?secret=JBSWY3DPEHPK3PXP&period=0"))
        XCTAssertNil(TOTP("otpauth://totp/x?secret=JBSWY3DPEHPK3PXP&algorithm=MD5"))
    }

    // MARK: Coffre

    /// Un coffre d'avant les codes de validation (sans champ `totp`) se lit toujours.
    func testVaultWithoutCodesStillDecodes() throws {
        let json = #"[{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","title":"a","username":"","website":"","password":"p","notes":"","isFavorite":false,"createdAt":0,"updatedAt":0}]"#
        let items = try JSONDecoder().decode([VaultItem].self, from: Data(json.utf8))
        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items[0].totp)
        XCTAssertNil(items[0].oneTimeCode)
    }

    func testVaultItemKeepsItsCode() throws {
        var item = VaultItem(title: "Banque", website: "banque.fr", password: "x")
        item.totp = "otpauth://totp/Banque:moi?secret=JBSWY3DPEHPK3PXP"
        let decoded = try JSONDecoder().decode(VaultItem.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(decoded, item)
        XCTAssertEqual(decoded.oneTimeCode?.issuer, "Banque")
        item.totp = "n'importe quoi"
        XCTAssertNil(item.oneTimeCode)
    }

    // MARK: iOS

    /// iOS ne reçoit que le site et un libellé : jamais le secret ni un code.
    func testOneTimeCodeIdentities() throws {
        guard #available(iOS 18.0, *) else { throw XCTSkip("Codes de validation : iOS 18 et plus récent.") }
        let secret = "JBSWY3DPEHPK3PXP"
        var withCode = VaultItem(title: "Banque", username: "moi", website: "https://www.banque.fr/login", password: "x")
        withCode.totp = "otpauth://totp/Banque:moi?secret=\(secret)"
        var codeOnly = VaultItem(title: "Forum", website: "forum.example", password: "")
        codeOnly.totp = secret
        var noSite = VaultItem(title: "Sans site", password: "x")
        noSite.totp = secret
        let plain = VaultItem(title: "Simple", website: "simple.fr", password: "x")

        let codes = AutoFillIdentities.oneTimeCodeIdentities(for: [withCode, codeOnly, noSite, plain])
        XCTAssertEqual(codes.map(\.serviceIdentifier.identifier), ["banque.fr", "forum.example"])
        XCTAssertEqual(codes.map(\.label), ["moi", "Forum"])
        XCTAssertEqual(codes.map(\.recordIdentifier), [withCode.id.uuidString, codeOnly.id.uuidString])
        for identity in codes {
            XCTAssertFalse(identity.label.contains(secret))
        }
        // Une entrée sans mot de passe n'est pas proposée comme identifiant.
        let passwords = AutoFillIdentities.identities(for: [withCode, codeOnly, noSite, plain])
        XCTAssertEqual(passwords.map(\.serviceIdentifier.identifier), ["banque.fr", "simple.fr"])
    }
}
