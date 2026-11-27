import Foundation

/// Le coffre dans le trousseau, scellé par Brocolis 🥦 (`VaultSeal`) : partagé par l'app
/// et l'extension de remplissage automatique.
///
/// Deux éléments du trousseau, dans le groupe partagé, jamais synchronisés ni restaurés
/// sur un autre appareil (`WhenUnlockedThisDeviceOnly`) :
/// - le coffre scellé, `[[BROCOLIS:v4:…]]` ;
/// - sa clé de 256 bits, tirée du hasard de Brocolis à la première écriture.
struct BrocolisVault {
    var vault = KeychainStore()
    var key = KeychainStore(service: "com.maxlestage.KeyForge.vault-key", account: "brocolis")

    /// Vrai si le coffre rangé est scellé par Brocolis (faux s'il est vide ou en clair).
    func isSealed() -> Bool {
        guard let data = try? vault.load() else { return false }
        return VaultSeal.isSealed(data)
    }

    /// Les entrées, déchiffrées (ou lues en clair pour un coffre d'une version précédente).
    func load() throws -> [VaultItem] {
        guard let data = try vault.load() else { return [] }
        let stored = try key.load().map { [UInt8]($0) }
        return try VaultSeal.open(data, key: stored, crypto: AppleCrypto.self)
    }

    /// Scelle et range les entrées. La clé n'est créée que s'il n'en existe aucune et que
    /// le coffre rangé n'est pas déjà scellé (sinon, une clé neuve le rendrait illisible).
    func save(_ items: [VaultItem]) throws {
        let secret: [UInt8]
        if let stored = try key.load() {
            secret = [UInt8](stored)
        } else {
            if let data = try vault.load(), VaultSeal.isSealed(data) { throw VaultSealError.missingKey }
            secret = BrocolisHasard.bytes(32)
            try key.save(Data(secret))
        }
        try vault.save(VaultSeal.seal(items, key: secret, crypto: AppleCrypto.self))
    }

    /// Efface le coffre et sa clé : le prochain coffre aura une clé neuve.
    func erase() throws {
        try vault.delete()
        try key.delete()
    }
}
