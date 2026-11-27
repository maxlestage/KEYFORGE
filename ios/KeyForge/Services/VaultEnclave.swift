import CryptoKit
import Foundation
import LocalAuthentication
import Security

// La clé du coffre gardée par la Secure Enclave.
//
// La clé de 256 bits qui scelle le coffre (format Brocolis 🥦) n'est plus rangée telle
// quelle : elle est enveloppée pour une clé P-256 née dans la Secure Enclave, qui n'en
// sort jamais et que la puce n'utilise qu'après Face ID, Touch ID ou le code de
// l'iPhone (`userPresence`). Lire le trousseau ne suffit donc plus : sans la puce de cet
// iPhone ET son propriétaire, la clé du coffre reste du charabia.
//
// Enveloppe (ECIES) : clé P-256 éphémère, ECDH avec la clé de l'enclave, HKDF-SHA256
// (sel : les deux clés publiques), AES-256-GCM. 125 octets :
// clé publique éphémère X9.63 (65) ‖ nonce (12) ‖ clé chiffrée (32) ‖ tag (16).
// Envelopper ne demande que la clé publique ; ouvrir demande l'enclave.

enum VaultEnclaveError: LocalizedError, Equatable {
    case unavailable
    case format
    case refused
    case verification

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "La Secure Enclave n'est pas disponible sur cet appareil."
        case .format:
            "La clé protégée du coffre est abîmée."
        case .refused:
            "La Secure Enclave n'a pas libéré la clé du coffre : authentifiez-vous avec Face ID, Touch ID ou le code de l'iPhone (un code doit être défini sur l'appareil)."
        case .verification:
            "La Secure Enclave n'a pas rendu la bonne clé : la protection n'a pas été activée."
        }
    }
}

/// L'enveloppe de la clé du coffre pour une clé P-256.
enum VaultKeyWrap {
    static let info = Data("KeyForge_coffre_enclave_v1".utf8)
    static let publicKeyLength = 65
    static let length = publicKeyLength + 12 + 32 + 16

    static func wrap(_ key: [UInt8], for recipient: P256.KeyAgreement.PublicKey) throws -> Data {
        guard key.count == 32 else { throw VaultEnclaveError.format }
        let ephemeral = P256.KeyAgreement.PrivateKey()
        let ephemeralPublic = ephemeral.publicKey.x963Representation
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: recipient)
        let sealed = try AES.GCM.seal(
            Data(key),
            using: wrappingKey(shared, ephemeralPublic: ephemeralPublic, recipient: recipient),
            authenticating: info
        )
        guard let combined = sealed.combined else { throw VaultEnclaveError.format }
        return ephemeralPublic + combined
    }

    /// `agree` fait l'ECDH avec la clé privée du destinataire (dans l'enclave).
    static func unwrap(
        _ wrapped: Data,
        recipient: P256.KeyAgreement.PublicKey,
        agree: (P256.KeyAgreement.PublicKey) throws -> SharedSecret
    ) throws -> [UInt8] {
        guard wrapped.count == length else { throw VaultEnclaveError.format }
        let ephemeralPublic = Data(wrapped.prefix(publicKeyLength))
        guard let peer = try? P256.KeyAgreement.PublicKey(x963Representation: ephemeralPublic),
              let box = try? AES.GCM.SealedBox(combined: Data(wrapped.dropFirst(publicKeyLength)))
        else { throw VaultEnclaveError.format }
        let shared = try agree(peer)
        guard let key = try? AES.GCM.open(
            box,
            using: wrappingKey(shared, ephemeralPublic: ephemeralPublic, recipient: recipient),
            authenticating: info
        ), key.count == 32
        else { throw VaultEnclaveError.format }
        return [UInt8](key)
    }

    private static func wrappingKey(
        _ shared: SharedSecret, ephemeralPublic: Data, recipient: P256.KeyAgreement.PublicKey
    ) -> SymmetricKey {
        shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: ephemeralPublic + recipient.x963Representation,
            sharedInfo: info,
            outputByteCount: 32
        )
    }
}

/// Ce qui est rangé dans le trousseau à la place de la clé du coffre : la clé de
/// l'enclave (un bloc que seule la Secure Enclave de cet iPhone sait utiliser) et la clé
/// du coffre enveloppée pour elle.
struct VaultEnclaveRecord: Codable, Equatable, Sendable {
    var version = 1
    var enclaveKey: Data
    var wrapped: Data
}

enum VaultEnclave {
    /// Vrai si la clé du coffre peut être confiée à la Secure Enclave : la puce existe
    /// et l'iPhone a un code (sans code, rien ne prouve la présence du propriétaire).
    static var isAvailable: Bool {
        SecureEnclave.isAvailable && LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Crée une clé dans la Secure Enclave, enveloppe la clé du coffre pour elle, puis
    /// **vérifie** que l'enclave la rend à l'identique, à partir de ce qui sera rangé.
    /// `context` : déjà authentifié (aucune demande n'est affichée ici).
    static func protect(_ key: [UInt8], context: LAContext, userPresence: Bool = true) throws -> VaultEnclaveRecord {
        guard SecureEnclave.isAvailable else { throw VaultEnclaveError.unavailable }
        var flags: SecAccessControlCreateFlags = [.privateKeyUsage]
        if userPresence { flags.insert(.userPresence) }
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, flags, &error
        ) else {
            _ = error?.takeRetainedValue()
            throw VaultEnclaveError.unavailable
        }
        let enclaveKey: SecureEnclave.P256.KeyAgreement.PrivateKey
        do {
            enclaveKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(
                accessControl: access, authenticationContext: context
            )
        } catch {
            throw VaultEnclaveError.unavailable
        }
        let record = VaultEnclaveRecord(
            enclaveKey: enclaveKey.dataRepresentation,
            wrapped: try VaultKeyWrap.wrap(key, for: enclaveKey.publicKey)
        )
        guard let revealed = try? reveal(record, context: context), revealed == key else {
            throw VaultEnclaveError.verification
        }
        return record
    }

    /// La clé du coffre, rendue par la Secure Enclave. `context` : déjà authentifié.
    static func reveal(_ record: VaultEnclaveRecord, context: LAContext) throws -> [UInt8] {
        let enclaveKey: SecureEnclave.P256.KeyAgreement.PrivateKey
        do {
            enclaveKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(
                dataRepresentation: record.enclaveKey, authenticationContext: context
            )
        } catch {
            throw VaultEnclaveError.refused
        }
        return try VaultKeyWrap.unwrap(record.wrapped, recipient: enclaveKey.publicKey) { peer in
            do {
                return try enclaveKey.sharedSecretFromKeyAgreement(with: peer)
            } catch {
                throw VaultEnclaveError.refused
            }
        }
    }
}
