import CryptoKit
import LocalAuthentication
import XCTest
@testable import KeyForge

/// La clé du coffre gardée par la Secure Enclave : l'enveloppe, puis le coffre entier
/// (trousseau et enclave) quand le banc d'essai les fournit.
final class VaultEnclaveTests: XCTestCase {
    private let items = [
        VaultItem(title: "Banque", username: "moi", website: "https://banque.fr", password: "S3cr3t!"),
        VaultItem(title: "Courriel", password: "aä0ΓD}«¬ç$h", isFavorite: true),
    ]

    // MARK: Enveloppe

    func testWrapRoundTrip() throws {
        let recipient = P256.KeyAgreement.PrivateKey()
        let key = BrocolisHasard.bytes(32)
        let wrapped = try VaultKeyWrap.wrap(key, for: recipient.publicKey)
        XCTAssertEqual(wrapped.count, VaultKeyWrap.length)
        XCTAssertEqual(wrapped.count, 125)
        let opened = try VaultKeyWrap.unwrap(wrapped, recipient: recipient.publicKey) {
            try recipient.sharedSecretFromKeyAgreement(with: $0)
        }
        XCTAssertEqual(opened, key)
    }

    func testEveryWrapIsFresh() throws {
        let recipient = P256.KeyAgreement.PrivateKey()
        let key = BrocolisHasard.bytes(32)
        XCTAssertNotEqual(try VaultKeyWrap.wrap(key, for: recipient.publicKey),
                          try VaultKeyWrap.wrap(key, for: recipient.publicKey))
    }

    func testWrapNeverShowsTheKey() throws {
        let recipient = P256.KeyAgreement.PrivateKey()
        let key = BrocolisHasard.bytes(32)
        let wrapped = try VaultKeyWrap.wrap(key, for: recipient.publicKey)
        XCTAssertNil(wrapped.range(of: Data(key)))
    }

    func testAnotherKeyCannotUnwrap() throws {
        let recipient = P256.KeyAgreement.PrivateKey()
        let thief = P256.KeyAgreement.PrivateKey()
        let wrapped = try VaultKeyWrap.wrap(BrocolisHasard.bytes(32), for: recipient.publicKey)
        XCTAssertThrowsError(try VaultKeyWrap.unwrap(wrapped, recipient: recipient.publicKey) {
            try thief.sharedSecretFromKeyAgreement(with: $0)
        }) { XCTAssertEqual($0 as? VaultEnclaveError, .format) }
    }

    func testTamperedOrTruncatedWrapIsRefused() throws {
        let recipient = P256.KeyAgreement.PrivateKey()
        var wrapped = try VaultKeyWrap.wrap(BrocolisHasard.bytes(32), for: recipient.publicKey)
        wrapped[wrapped.count - 1] ^= 1
        XCTAssertThrowsError(try VaultKeyWrap.unwrap(wrapped, recipient: recipient.publicKey) {
            try recipient.sharedSecretFromKeyAgreement(with: $0)
        })
        XCTAssertThrowsError(try VaultKeyWrap.unwrap(wrapped.dropLast(), recipient: recipient.publicKey) {
            try recipient.sharedSecretFromKeyAgreement(with: $0)
        }) { XCTAssertEqual($0 as? VaultEnclaveError, .format) }
        XCTAssertThrowsError(try VaultKeyWrap.wrap([1, 2, 3], for: recipient.publicKey))
    }

    // MARK: Coffre (trousseau)

    /// Un coffre de test, à part de celui de l'app.
    private func makeVault() throws -> BrocolisVault {
        let id = UUID().uuidString
        let vault = BrocolisVault(
            vault: KeychainStore(service: "com.maxlestage.KeyForge.tests.vault", account: id),
            key: KeychainStore(service: "com.maxlestage.KeyForge.tests.vault-key", account: "brocolis-" + id),
            enclave: KeychainStore(service: "com.maxlestage.KeyForge.tests.vault-key", account: "enclave-" + id),
            enclaveUserPresence: false
        )
        addTeardownBlock { try? vault.erase() }
        do {
            try vault.save([])
        } catch {
            throw XCTSkip("Trousseau indisponible sur ce banc d'essai : \(error.localizedDescription)")
        }
        return vault
    }

    func testVaultWithKeyInTheKeychain() throws {
        let vault = try makeVault()
        XCTAssertTrue(vault.isSealed())
        XCTAssertTrue(vault.hasPlainKey())
        XCTAssertFalse(vault.isEnclaveProtected())
        let key = try vault.save(items)
        let opened = try vault.open(context: nil)
        XCTAssertEqual(opened.items, items)
        XCTAssertEqual(opened.key, key)
        // La clé du coffre ouvert ressert sans relire le trousseau.
        XCTAssertEqual(try vault.save(items + items, key: key), key)
        XCTAssertEqual(try vault.open(context: nil).items.count, 4)
        try vault.erase()
        XCTAssertFalse(vault.isSealed())
        XCTAssertEqual(try vault.open(context: nil).items, [])
    }

    /// Un coffre scellé dont la clé a disparu n'est jamais écrasé par une clé neuve.
    func testSealedVaultWithoutKeyIsNeverOverwritten() throws {
        let vault = try makeVault()
        try vault.save(items)
        try vault.key.delete()
        XCTAssertThrowsError(try vault.save([])) { XCTAssertEqual($0 as? VaultSealError, .missingKey) }
        XCTAssertThrowsError(try vault.open(context: nil)) { XCTAssertEqual($0 as? VaultSealError, .missingKey) }
        XCTAssertTrue(vault.isSealed())
    }

    // MARK: Coffre (Secure Enclave)

    /// Un contexte pour la Secure Enclave du banc d'essai, si elle sait créer une clé.
    private func enclaveContext() throws -> LAContext {
        guard SecureEnclave.isAvailable else { throw XCTSkip("Pas de Secure Enclave sur ce banc d'essai.") }
        let context = LAContext()
        context.interactionNotAllowed = true
        do {
            _ = try VaultEnclave.protect(BrocolisHasard.bytes(32), context: context, userPresence: false)
        } catch VaultEnclaveError.unavailable {
            throw XCTSkip("La Secure Enclave du banc d'essai ne crée pas de clé.")
        }
        return context
    }

    func testVaultWithKeyInTheSecureEnclave() throws {
        let context = try enclaveContext()
        let vault = try makeVault()
        let key = try vault.save(items)

        try vault.protect(context: context)
        XCTAssertTrue(vault.isEnclaveProtected())
        XCTAssertFalse(vault.hasPlainKey(), "la clé telle quelle a quitté le trousseau")
        let record = try XCTUnwrap(vault.enclave.load())
        XCTAssertNil(record.range(of: Data(key)), "la clé n'apparaît pas dans ce qui est rangé")

        // Sans contexte, rien ne sort ; avec, l'enclave rend la clé et le coffre s'ouvre.
        XCTAssertThrowsError(try vault.open(context: nil)) { XCTAssertEqual($0 as? VaultEnclaveError, .refused) }
        let opened = try vault.open(context: context)
        XCTAssertEqual(opened.items, items)
        XCTAssertEqual(opened.key, key)

        // Écrire coffre fermé passe par l'enclave ; le coffre garde la même clé.
        XCTAssertEqual(try vault.save([items[0]], context: context), key)
        XCTAssertEqual(try vault.open(context: context).items, [items[0]])
        // Protéger deux fois ne change rien.
        try vault.protect(context: context)
        XCTAssertTrue(vault.isEnclaveProtected())

        // Retour dans le trousseau : même clé, même coffre.
        try vault.unprotect(context: context)
        XCTAssertFalse(vault.isEnclaveProtected())
        XCTAssertEqual(try vault.key.load(), Data(key))
        XCTAssertNil(try vault.enclave.load())
        XCTAssertEqual(try vault.open(context: nil).items, [items[0]])
    }

    /// Une migration interrompue laisse les deux formes : la clé telle quelle l'emporte,
    /// et protéger à nouveau termine le travail.
    func testInterruptedMigrationKeepsTheVaultReadable() throws {
        let context = try enclaveContext()
        let vault = try makeVault()
        let key = try vault.save(items)
        let record = try VaultEnclave.protect(key, context: context, userPresence: false)
        try vault.enclave.save(JSONEncoder().encode(record))

        XCTAssertFalse(vault.isEnclaveProtected())
        XCTAssertEqual(try vault.open(context: nil).items, items)
        try vault.protect(context: context)
        XCTAssertTrue(vault.isEnclaveProtected())
        XCTAssertEqual(try vault.open(context: context).items, items)
    }

    func testEnclaveRecordRoundTrip() throws {
        let context = try enclaveContext()
        let key = BrocolisHasard.bytes(32)
        let record = try VaultEnclave.protect(key, context: context, userPresence: false)
        let stored = try JSONDecoder().decode(VaultEnclaveRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(try VaultEnclave.reveal(stored, context: context), key)
        var other = stored
        other.wrapped = try VaultKeyWrap.wrap(key, for: P256.KeyAgreement.PrivateKey().publicKey)
        XCTAssertThrowsError(try VaultEnclave.reveal(other, context: context))
    }
}
