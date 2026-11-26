import XCTest
@testable import KeyForge

/// Le remplissage automatique : quelles entrées du coffre conviennent au site demandé.
final class AutoFillTests: XCTestCase {
    func testHostNormalisation() {
        XCTAssertEqual(AutoFillMatch.host(of: "https://www.Example.com:8443/a?b#c"), "example.com")
        XCTAssertEqual(AutoFillMatch.host(of: "accounts.google.com"), "accounts.google.com")
        XCTAssertEqual(AutoFillMatch.host(of: "http://user@site.fr/"), "site.fr")
        XCTAssertEqual(AutoFillMatch.host(of: "example.com."), "example.com")
        XCTAssertEqual(AutoFillMatch.host(of: "  "), "")
    }

    func testScores() {
        let google = VaultItem(title: "Google", website: "https://google.com", password: "x")
        let account = VaultItem(title: "Compte", website: "accounts.google.com", password: "y")
        let lookalike = VaultItem(title: "Faux", website: "notgoogle.com", password: "z")
        let note = VaultItem(title: "Note", password: "w")
        XCTAssertEqual(AutoFillMatch.score(google, hosts: ["google.com"]), 2)
        XCTAssertEqual(AutoFillMatch.score(account, hosts: ["google.com"]), 1)
        // Un domaine qui se termine pareil sans être un sous-domaine ne correspond pas.
        XCTAssertEqual(AutoFillMatch.score(lookalike, hosts: ["google.com"]), 0)
        XCTAssertEqual(AutoFillMatch.score(note, hosts: ["google.com"]), 0)
    }

    func testSplitPutsTheSiteFirst() {
        let google = VaultItem(title: "Google", website: "google.com", password: "x")
        let account = VaultItem(title: "Compte", website: "accounts.google.com", password: "y")
        let other = VaultItem(title: "Banque", website: "banque.fr", password: "z")
        let split = AutoFillMatch.split([other, account, google], for: ["https://google.com/login"])
        XCTAssertEqual(split.suggested.map(\.title), ["Google", "Compte"])
        XCTAssertEqual(split.others.map(\.title), ["Banque"])
    }

    func testUserFallsBackToTitle() {
        XCTAssertEqual(AutoFillMatch.user(of: VaultItem(title: "Compte", password: "x")), "Compte")
        XCTAssertEqual(AutoFillMatch.user(of: VaultItem(title: "G", username: "max", password: "x")), "max")
    }

    func testIdentitiesNeverCarryPasswords() {
        let items = [
            VaultItem(title: "Google", username: "max", website: "google.com", password: "secret"),
            VaultItem(title: "Sans site", password: "secret"),
        ]
        let identities = AutoFillIdentities.identities(for: items)
        XCTAssertEqual(identities.count, 1)
        XCTAssertEqual(identities.first?.serviceIdentifier.identifier, "google.com")
        XCTAssertEqual(identities.first?.user, "max")
        XCTAssertEqual(identities.first?.recordIdentifier, items[0].id.uuidString)
    }
}
