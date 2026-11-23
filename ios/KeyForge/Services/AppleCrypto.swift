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
