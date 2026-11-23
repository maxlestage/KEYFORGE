import CommonCrypto
import CryptoKit
import Foundation

/// AES-256-GCM avec CryptoKit et PBKDF2 avec CommonCrypto : les primitives des
/// formats Brocolis 🥦 dans l'app.
enum AppleCrypto: BrocolisCrypto {
    static func seal(key: [UInt8], nonce: [UInt8], aad: [UInt8], plaintext: [UInt8]) throws -> [UInt8] {
        let box = try AES.GCM.seal(
            plaintext,
            using: SymmetricKey(data: key),
            nonce: AES.GCM.Nonce(data: nonce),
            authenticating: aad
        )
        return [UInt8](box.ciphertext) + [UInt8](box.tag)
    }

    static func open(key: [UInt8], nonce: [UInt8], aad: [UInt8], sealed: [UInt8]) throws -> [UInt8] {
        guard sealed.count >= 16 else { throw BrocolisError.format }
        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonce),
            ciphertext: Array(sealed.dropLast(16)),
            tag: Array(sealed.suffix(16))
        )
        return [UInt8](try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: aad))
    }

    static func pbkdf2SHA256(password: [UInt8], salt: [UInt8], rounds: Int, length: Int) -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: length)
        let status = password.withUnsafeBufferPointer { pw in
            pw.withMemoryRebound(to: Int8.self) { pwChars in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pwChars.baseAddress, password.count,
                    salt, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(rounds),
                    &out, length
                )
            }
        }
        return status == Int32(kCCSuccess) ? out : nil
    }
}

/// X25519 et Ed25519 avec CryptoKit : les courbes du protocole Brocolis v4.
extension AppleCrypto: BrocolisCurves {
    static func x25519Public(secret: [UInt8]) throws -> [UInt8] {
        [UInt8](try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: secret).publicKey.rawRepresentation)
    }

    static func x25519Raw(secret: [UInt8], public: [UInt8]) throws -> [UInt8] {
        let key = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: secret)
        let peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: `public`)
        return try key.sharedSecretFromKeyAgreement(with: peer).withUnsafeBytes { Array($0) }
    }

    static func ed25519Public(seed: [UInt8]) throws -> [UInt8] {
        [UInt8](try Curve25519.Signing.PrivateKey(rawRepresentation: seed).publicKey.rawRepresentation)
    }

    static func ed25519Sign(seed: [UInt8], message: [UInt8]) throws -> [UInt8] {
        [UInt8](try Curve25519.Signing.PrivateKey(rawRepresentation: seed).signature(for: Data(message)))
    }

    static func ed25519Verify(public: [UInt8], message: [UInt8], signature: [UInt8]) -> Bool {
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: `public`) else { return false }
        return key.isValidSignature(Data(signature), for: Data(message))
    }
}
