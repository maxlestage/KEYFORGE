import Foundation

// Les formats de chiffrement de Brocolis 🥦 (https://github.com/maxlestage/brocolis,
// crate `brocolis-proto`), portés octet pour octet :
//
// - `[[BROCOLIS-CLE:v2:<base64>]]` : une clé de 32 octets protégée par une phrase
//   (83 octets : 0x02 ‖ m u32 BE ‖ t ‖ p ‖ sel 16 ‖ nonce 12 ‖ AES-256-GCM(clé) + tag,
//   l'en-tête de 35 octets en données associées ; clé = Argon2id(phrase, sel, m, t, p)) ;
// - `[[BROCOLIS-CLE:v1:<base64>]]` (lecture) : sel 16 ‖ nonce 12 ‖ AES-256-GCM(clé),
//   PBKDF2-HMAC-SHA256 600 000 tours, données associées `brocolis-cle-v1` ;
// - `[[BROCOLIS:v1:<base64>]]` : nonce 12 ‖ AES-256-GCM(texte) ‖ tag, sans données associées.
//
// Ce fichier n'importe que Foundation : AES-GCM et PBKDF2 viennent d'une
// implémentation de `BrocolisCrypto` (CryptoKit et CommonCrypto dans l'app).

/// Les primitives que les formats utilisent.
protocol BrocolisCrypto {
    /// AES-256-GCM : `chiffré ‖ tag` (16 octets).
    static func seal(key: [UInt8], nonce: [UInt8], aad: [UInt8], plaintext: [UInt8]) throws -> [UInt8]
    /// Ouvre `chiffré ‖ tag` ; lève une erreur si le tag ne correspond pas.
    static func open(key: [UInt8], nonce: [UInt8], aad: [UInt8], sealed: [UInt8]) throws -> [UInt8]
    /// PBKDF2-HMAC-SHA256 (clés protégées v1, en lecture). `nil` : non disponible.
    static func pbkdf2SHA256(password: [UInt8], salt: [UInt8], rounds: Int, length: Int) -> [UInt8]?
}

extension BrocolisCrypto {
    static func pbkdf2SHA256(password: [UInt8], salt: [UInt8], rounds: Int, length: Int) -> [UInt8]? {
        nil
    }
}

enum BrocolisError: LocalizedError, Equatable {
    case phraseTooShort
    case missingToken
    case format
    case base64
    case parameters
    case decryption
    case unsupported

    var errorDescription: String? {
        switch self {
        case .phraseTooShort: "La phrase doit compter au moins \(Brocolis.phraseMinimum) caractères."
        case .missingToken: "Aucune sauvegarde Brocolis 🥦 dans ce texte."
        case .format, .base64: "La sauvegarde est abîmée ou incomplète."
        case .parameters: "Les paramètres Argon2id de cette sauvegarde sont hors limites."
        case .decryption: "Phrase incorrecte, ou sauvegarde abîmée."
        case .unsupported: "Ce format n'est pas pris en charge sur cet appareil."
        }
    }
}

/// Les paramètres Argon2id d'une clé protégée v2.
struct BrocolisArgon2Params: Equatable, Sendable {
    /// m : mémoire, en Kio.
    var memoryKiB: UInt32
    /// t : nombre de passes.
    var iterations: UInt8
    /// p : parallélisme.
    var parallelism: UInt8

    /// Le défaut : 64 Mio, 3 passes, 1 voie.
    static let standard = BrocolisArgon2Params(memoryKiB: 65_536, iterations: 3, parallelism: 1)
    /// Le minimum accepté (OWASP) : 19 Mio, 2 passes.
    static let minimum = BrocolisArgon2Params(memoryKiB: 19_456, iterations: 2, parallelism: 1)
    static let maximumMemoryKiB: UInt32 = 1_048_576
    static let maximumIterations: UInt8 = 16

    /// Les bornes de brocolis-proto : m ∈ [19 456, 1 048 576], 2 ≤ t ≤ 16, p ≥ 1, m ≥ 8p.
    var isValid: Bool {
        memoryKiB >= Self.minimum.memoryKiB
            && memoryKiB <= Self.maximumMemoryKiB
            && iterations >= 2
            && iterations <= Self.maximumIterations
            && parallelism >= 1
            && memoryKiB >= 8 * UInt32(parallelism)
    }

    /// « 64 Mio · 3 passes ».
    var summary: String {
        "\(memoryKiB / 1024) Mio · \(iterations) passes"
    }
}

enum Brocolis {
    static let protectedKeyV1Head = "[[BROCOLIS-CLE:v1:"
    static let protectedKeyV2Head = "[[BROCOLIS-CLE:v2:"
    static let tokenV1Head = "[[BROCOLIS:v1:"
    static let end = "]]"
    static let phraseMinimum = 8
    static let pbkdf2Rounds = 600_000
    private static let adV1 = Array("brocolis-cle-v1".utf8)
    private static let v1Length = 16 + 12 + 32 + 16
    private static let v2Length = 83
    private static let v2Header = 35

    // MARK: Clés protégées

    /// Argon2id(phrase UTF-8, sel, m, t, p) sur 32 octets.
    static func argon2idKey(
        phrase: String, salt: [UInt8], params: BrocolisArgon2Params,
        progress: ((Double) -> Void)? = nil
    ) throws -> [UInt8] {
        guard params.isValid, salt.count == 16 else { throw BrocolisError.parameters }
        return Argon2id.hash(
            password: Array(phrase.utf8), salt: salt,
            memoryKiB: Int(params.memoryKiB), iterations: Int(params.iterations),
            parallelism: Int(params.parallelism), length: 32, progress: progress
        )
    }

    /// `[[BROCOLIS-CLE:v2:…]]` avec un sel et un nonce donnés.
    static func protectKeyV2(
        _ key: [UInt8], phrase: String, params: BrocolisArgon2Params,
        salt: [UInt8], nonce: [UInt8], crypto: BrocolisCrypto.Type,
        progress: ((Double) -> Void)? = nil
    ) throws -> String {
        guard phrase.unicodeScalars.count >= phraseMinimum else { throw BrocolisError.phraseTooShort }
        guard key.count == 32, salt.count == 16, nonce.count == 12 else { throw BrocolisError.format }
        var header: [UInt8] = [0x02]
        header += withUnsafeBytes(of: params.memoryKiB.bigEndian, Array.init)
        header += [params.iterations, params.parallelism]
        header += salt
        header += nonce
        let derived = try argon2idKey(phrase: phrase, salt: salt, params: params, progress: progress)
        let sealed = try crypto.seal(key: derived, nonce: nonce, aad: header, plaintext: key)
        return protectedKeyV2Head + Data(header + sealed).base64EncodedString() + end
    }

    /// Les paramètres d'une clé protégée v2, pour prévenir avant un calcul long.
    static func v2Params(in text: String) throws -> BrocolisArgon2Params {
        guard let body = inner(text, head: protectedKeyV2Head) else { throw BrocolisError.missingToken }
        return try parseV2Params(decode(body, length: v2Length))
    }

    /// Retrouve la clé d'un `[[BROCOLIS-CLE:v2:…]]` (cherché d'abord) ou `v1` dans un texte.
    static func unprotectKey(
        in text: String, phrase: String, crypto: BrocolisCrypto.Type,
        progress: ((Double) -> Void)? = nil
    ) throws -> [UInt8] {
        if let body = inner(text, head: protectedKeyV2Head) {
            let data = try decode(body, length: v2Length)
            let params = try parseV2Params(data)
            let salt = Array(data[7..<23])
            let nonce = Array(data[23..<35])
            let derived = try argon2idKey(phrase: phrase, salt: salt, params: params, progress: progress)
            let key = try open(crypto, key: derived, nonce: nonce, aad: Array(data[0..<v2Header]), sealed: Array(data[v2Header...]))
            guard key.count == 32 else { throw BrocolisError.format }
            return key
        }
        if let body = inner(text, head: protectedKeyV1Head) {
            let data = try decode(body, length: v1Length)
            let salt = Array(data[0..<16])
            let nonce = Array(data[16..<28])
            guard let derived = crypto.pbkdf2SHA256(
                password: Array(phrase.utf8), salt: salt, rounds: pbkdf2Rounds, length: 32
            ) else { throw BrocolisError.unsupported }
            progress?(1)
            let key = try open(crypto, key: derived, nonce: nonce, aad: adV1, sealed: Array(data[28...]))
            guard key.count == 32 else { throw BrocolisError.format }
            return key
        }
        throw BrocolisError.missingToken
    }

    // MARK: Jetons v1

    /// `[[BROCOLIS:v1:…]]` : `text` chiffré sous `key`.
    static func sealTokenV1(_ text: String, key: [UInt8], nonce: [UInt8], crypto: BrocolisCrypto.Type) throws -> String {
        guard key.count == 32, nonce.count == 12 else { throw BrocolisError.format }
        let sealed = try crypto.seal(key: key, nonce: nonce, aad: [], plaintext: Array(text.utf8))
        return tokenV1Head + Data(nonce + sealed).base64EncodedString() + end
    }

    /// Le texte du premier `[[BROCOLIS:v1:…]]` de `text`, ouvert avec `key`.
    static func openTokenV1(in text: String, key: [UInt8], crypto: BrocolisCrypto.Type) throws -> String {
        guard let body = inner(text, head: tokenV1Head) else { throw BrocolisError.missingToken }
        guard let data = Data(base64Encoded: body) else { throw BrocolisError.base64 }
        let combined = [UInt8](data)
        guard combined.count >= 12 + 16 else { throw BrocolisError.format }
        let plain = try open(crypto, key: key, nonce: Array(combined[0..<12]), aad: [], sealed: Array(combined[12...]))
        guard let string = String(bytes: plain, encoding: .utf8) else { throw BrocolisError.format }
        return string
    }

    // MARK: Utilitaires

    /// Des octets du hasard de Brocolis (le CSPRNG du système, `BrocolisHasard`).
    static func randomBytes(_ count: Int) -> [UInt8] {
        BrocolisHasard.bytes(count)
    }

    /// Le contenu entre `head` et `]]`.
    static func inner(_ text: String, head: String) -> String? {
        guard let start = text.range(of: head) else { return nil }
        let rest = text[start.upperBound...]
        guard let stop = rest.range(of: end) else { return nil }
        return String(rest[..<stop.lowerBound])
    }

    private static func decode(_ body: String, length: Int) throws -> [UInt8] {
        // Une clé protégée tient en moins de 120 caractères : rien à décoder au-delà.
        guard body.count <= 4 * ((length + 2) / 3) else { throw BrocolisError.format }
        guard let data = Data(base64Encoded: body) else { throw BrocolisError.base64 }
        guard data.count == length else { throw BrocolisError.format }
        return [UInt8](data)
    }

    private static func parseV2Params(_ data: [UInt8]) throws -> BrocolisArgon2Params {
        guard data.first == 0x02 else { throw BrocolisError.format }
        let memory = UInt32(data[1]) << 24 | UInt32(data[2]) << 16 | UInt32(data[3]) << 8 | UInt32(data[4])
        let params = BrocolisArgon2Params(memoryKiB: memory, iterations: data[5], parallelism: data[6])
        guard params.isValid else { throw BrocolisError.parameters }
        return params
    }

    private static func open(
        _ crypto: BrocolisCrypto.Type, key: [UInt8], nonce: [UInt8], aad: [UInt8], sealed: [UInt8]
    ) throws -> [UInt8] {
        do {
            return try crypto.open(key: key, nonce: nonce, aad: aad, sealed: sealed)
        } catch {
            throw BrocolisError.decryption
        }
    }
}

// MARK: - Sauvegarde du coffre

/// Ce que contient une sauvegarde, une fois ouverte.
struct VaultBackupPayload: Codable, Sendable {
    var format = "keyforge-vault"
    var version = 1
    var exportedAt: Date
    var items: [VaultItem]
}

/// La sauvegarde chiffrée du coffre, au format Brocolis 🥦 : une clé aléatoire K
/// protégée par la phrase (`[[BROCOLIS-CLE:v2:…]]`, Argon2id), puis le coffre en
/// JSON, premier message d'une session **v4 à clé partagée** sous K
/// (`[[BROCOLIS:v4:…]]` : en-tête chiffré, remplissage, clé ML-KEM-768 de cliquet).
/// Les sauvegardes de l'ancien format (`[[BROCOLIS:v1:…]]`) restent lisibles.
enum VaultBackup {
    static let fileName = "keyforge-sauvegarde.brocolis.txt"

    static func export(
        _ items: [VaultItem],
        phrase: String,
        params: BrocolisArgon2Params = .standard,
        crypto: BrocolisV4Crypto.Type,
        date: Date = Date(),
        progress: ((Double) -> Void)? = nil
    ) throws -> String {
        guard phrase.unicodeScalars.count >= Brocolis.phraseMinimum else { throw BrocolisError.phraseTooShort }
        var key = Brocolis.randomBytes(32)
        defer { for i in key.indices { key[i] = 0 } }
        let protected = try Brocolis.protectKeyV2(
            key, phrase: phrase, params: params,
            salt: Brocolis.randomBytes(16), nonce: Brocolis.randomBytes(12),
            crypto: crypto, progress: progress
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let json = try encoder.encode(VaultBackupPayload(exportedAt: date, items: items))
        let token = try BrocolisV4.encryptPSK(String(decoding: json, as: UTF8.self), key: key, crypto: crypto)
        return protected + "\n" + token + "\n"
    }

    /// Les entrées d'une sauvegarde collée ou ouverte (le texte peut contenir autre chose autour).
    static func open(
        _ text: String, phrase: String, crypto: BrocolisV4Crypto.Type,
        progress: ((Double) -> Void)? = nil
    ) throws -> [VaultItem] {
        let isV4 = BrocolisV4.containsToken(text)
        guard isV4 || Brocolis.inner(text, head: Brocolis.tokenV1Head) != nil else { throw BrocolisError.missingToken }
        var key = try Brocolis.unprotectKey(in: text, phrase: phrase, crypto: crypto, progress: progress)
        defer { for i in key.indices { key[i] = 0 } }
        let json: String
        if isV4 {
            do {
                json = try BrocolisV4.acceptPSK(text, key: key, crypto: crypto)
            } catch {
                throw BrocolisError.decryption
            }
        } else {
            json = try Brocolis.openTokenV1(in: text, key: key, crypto: crypto)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = Data(json.utf8)
        if let payload = try? decoder.decode(VaultBackupPayload.self, from: data) {
            return payload.items
        }
        if let items = try? decoder.decode([VaultItem].self, from: data) {
            return items
        }
        throw BrocolisError.format
    }

    /// Vrai si le texte ressemble à une sauvegarde.
    static func looksLikeBackup(_ text: String) -> Bool {
        (text.contains(Brocolis.protectedKeyV2Head) || text.contains(Brocolis.protectedKeyV1Head))
            && (text.contains(Brocolis.tokenV1Head) || BrocolisV4.containsToken(text))
    }
}
