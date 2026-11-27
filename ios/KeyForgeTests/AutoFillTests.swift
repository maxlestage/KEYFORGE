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

    // MARK: Enregistrer un identifiant (iOS 26.2)

    private var saved: [VaultItem] {
        [
            VaultItem(title: "Banque", username: "Moi@exemple.fr", website: "https://www.banque.fr/login", password: "ancien"),
            VaultItem(title: "Banque pro", username: "pro", website: "banque.fr", password: "p"),
            VaultItem(title: "Forum", username: "", website: "forum.example", password: "f"),
        ]
    }

    func testSaveUpdatesTheMatchingEntry() throws {
        let items = saved
        XCTAssertEqual(
            VaultSave.plan(service: "banque.fr", user: "moi@exemple.fr", password: "ancien", title: nil, in: items),
            .unchanged
        )
        let plan = VaultSave.plan(service: "https://banque.fr/x", user: " moi@exemple.fr ", password: "neuf", title: nil, in: items)
        guard case .update(let updated) = plan else { return XCTFail("mise à jour attendue") }
        XCTAssertEqual(updated.id, items[0].id)
        XCTAssertEqual(updated.password, "neuf")
        XCTAssertEqual(updated.title, "Banque")
        let applied = VaultSave.apply(plan, to: items)
        XCTAssertEqual(applied.count, 3)
        XCTAssertEqual(applied[0].password, "neuf")
        XCTAssertEqual(applied[1], items[1])
    }

    func testSaveAddsANewEntry() throws {
        let items = saved
        let plan = VaultSave.plan(service: "banque.fr", user: "nouveau", password: "x", title: " Ma banque ", in: items)
        guard case .add(let added) = plan else { return XCTFail("ajout attendu") }
        XCTAssertEqual(added.title, "Ma banque")
        XCTAssertEqual(added.username, "nouveau")
        XCTAssertEqual(added.website, "banque.fr")
        XCTAssertEqual(VaultSave.apply(plan, to: items).count, 4)
        // Un sous-domaine n'est pas le même site : jamais d'écrasement par ressemblance.
        guard case .add = VaultSave.plan(service: "secure.banque.fr", user: "moi@exemple.fr", password: "z", title: nil, in: items)
        else { return XCTFail("ajout attendu pour un autre hôte") }
    }

    func testSaveWithoutUserName() throws {
        let items = saved
        // L'unique entrée du site est mise à jour…
        guard case .update(let updated) = VaultSave.plan(service: "forum.example", user: "", password: "g", title: nil, in: items)
        else { return XCTFail("mise à jour attendue") }
        XCTAssertEqual(updated.id, items[2].id)
        // …mais entre plusieurs entrées, on n'en choisit pas une au hasard.
        guard case .add(let added) = VaultSave.plan(service: "banque.fr", user: "", password: "g", title: nil, in: items)
        else { return XCTFail("ajout attendu") }
        XCTAssertEqual(added.title, "banque.fr")
        XCTAssertEqual(VaultSave.plan(service: "banque.fr", user: "x", password: "", title: nil, in: items), .unchanged)
    }
}
