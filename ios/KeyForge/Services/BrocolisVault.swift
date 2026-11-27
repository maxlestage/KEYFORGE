import Foundation
import LocalAuthentication

/// Le coffre dans le trousseau, scellé par Brocolis 🥦 (`VaultSeal`) : partagé par l'app
/// et l'extension de remplissage automatique.
///
/// Des éléments du trousseau, dans le groupe partagé, jamais synchronisés ni restaurés
/// sur un autre appareil (`WhenUnlockedThisDeviceOnly`) :
/// - le coffre scellé, `[[BROCOLIS:v4:…]]` ;
/// - sa clé de 256 bits, tirée du hasard de Brocolis à la première écriture, sous l'une
///   de ces deux formes :
///   - **enclave** : enveloppée pour une clé de la Secure Enclave, que la puce ne libère
///     qu'après Face ID, Touch ID ou le code (`VaultEnclave`) ;
///   - **brocolis** : telle quelle, tant que la Secure Enclave n'a pas pris le relais
///     (appareil sans code, verrouillage biométrique coupé, simulateur).
///
/// Le passage de l'une à l'autre écrit et vérifie la nouvelle forme avant d'effacer
/// l'ancienne : une interruption laisse les deux, et la clé telle quelle l'emporte.
struct BrocolisVault {
    var vault = KeychainStore()
    var key = KeychainStore(service: "com.maxlestage.KeyForge.vault-key", account: "brocolis")
    var enclave = KeychainStore(service: "com.maxlestage.KeyForge.vault-key", account: "enclave")
    /// Faux dans les tests seulement : une clé d'enclave utilisable sans authentification.
    var enclaveUserPresence = true

    /// Vrai si le coffre rangé est scellé par Brocolis (faux s'il est vide ou en clair).
    func isSealed() -> Bool {
        guard let data = try? vault.load() else { return false }
        return VaultSeal.isSealed(data)
    }

    /// Vrai si la clé du coffre n'existe plus qu'enveloppée par la Secure Enclave :
    /// l'ouvrir demande alors une authentification.
    func isEnclaveProtected() -> Bool {
        (try? key.load()) == nil && (try? enclave.load()) != nil
    }

    /// Vrai si une clé telle quelle attend d'être confiée à la Secure Enclave.
    func hasPlainKey() -> Bool {
        (try? key.load()) != nil
    }

    /// La clé du coffre : telle quelle si elle existe, sinon rendue par la Secure Enclave
    /// (`context` déjà authentifié), sinon `nil` (pas encore de coffre scellé).
    func storedKey(context: LAContext?) throws -> [UInt8]? {
        if let plain = try key.load() { return [UInt8](plain) }
        guard let data = try enclave.load() else { return nil }
        guard let record = try? JSONDecoder().decode(VaultEnclaveRecord.self, from: data) else {
            throw VaultEnclaveError.format
        }
        guard let context else { throw VaultEnclaveError.refused }
        return try VaultEnclave.reveal(record, context: context)
    }

    /// Les entrées déchiffrées (ou lues en clair pour un coffre d'une version précédente)
    /// et la clé qui les a ouvertes, à garder en mémoire tant que le coffre est ouvert.
    func open(context: LAContext?) throws -> (items: [VaultItem], key: [UInt8]?) {
        guard let data = try vault.load() else { return ([], try? storedKey(context: context)) }
        guard VaultSeal.isSealed(data) else {
            return (try VaultSeal.open(data, key: nil, crypto: AppleCrypto.self), nil)
        }
        let secret = try storedKey(context: context)
        return (try VaultSeal.open(data, key: secret, crypto: AppleCrypto.self), secret)
    }

    /// Scelle et range les entrées avec `known` (la clé du coffre ouvert), sinon la clé
    /// rangée. Une clé neuve n'est créée que s'il n'en existe aucune et que le coffre
    /// rangé n'est pas déjà scellé (sinon, elle le rendrait illisible). Renvoie la clé.
    @discardableResult
    func save(_ items: [VaultItem], key known: [UInt8]? = nil, context: LAContext? = nil) throws -> [UInt8] {
        let secret: [UInt8]
        if let known {
            secret = known
        } else if let stored = try storedKey(context: context) {
            secret = stored
        } else {
            if let data = try vault.load(), VaultSeal.isSealed(data) { throw VaultSealError.missingKey }
            secret = BrocolisHasard.bytes(32)
            try key.save(Data(secret))
        }
        try vault.save(VaultSeal.seal(items, key: secret, crypto: AppleCrypto.self))
        return secret
    }

    // MARK: Secure Enclave

    /// Confie la clé du coffre à la Secure Enclave. La clé telle quelle n'est effacée
    /// qu'après que l'enclave a rendu la bonne clé, relue depuis le trousseau.
    /// `context` : déjà authentifié. Sans clé telle quelle, rien à faire.
    func protect(context: LAContext) throws {
        guard let plain = try key.load() else { return }
        let secret = [UInt8](plain)
        let record = try VaultEnclave.protect(secret, context: context, userPresence: enclaveUserPresence)
        try enclave.save(JSONEncoder().encode(record))
        guard let stored = try enclave.load(),
              let reread = try? JSONDecoder().decode(VaultEnclaveRecord.self, from: stored),
              let revealed = try? VaultEnclave.reveal(reread, context: context),
              revealed == secret
        else {
            try? enclave.delete()
            throw VaultEnclaveError.verification
        }
        try key.delete()
    }

    /// Rend la clé du coffre au trousseau (verrouillage biométrique coupé).
    /// `context` : déjà authentifié. Sans clé dans l'enclave, rien à faire.
    func unprotect(context: LAContext) throws {
        guard let data = try enclave.load() else { return }
        if try key.load() == nil {
            guard let record = try? JSONDecoder().decode(VaultEnclaveRecord.self, from: data) else {
                throw VaultEnclaveError.format
            }
            let secret = try VaultEnclave.reveal(record, context: context)
            try key.save(Data(secret))
            guard try key.load() == Data(secret) else { throw VaultEnclaveError.verification }
        }
        try enclave.delete()
    }

    /// Efface le coffre et sa clé, sous toutes ses formes : le prochain coffre aura une
    /// clé neuve.
    func erase() throws {
        try vault.delete()
        try key.delete()
        try enclave.delete()
    }
}
