import Foundation

// Le protocole v4 de Brocolis 🥦 (crate `brocolis-proto`, modules `paquet`, `session4`,
// `jeton_v4`, `kdf`), porté octet pour octet pour des messages « en un coup » :
//
// - un appareil : identité (X25519 + Ed25519), clé pré-signée X25519 (SPK) et clé
//   ML-KEM-768 signée (PQPK), publiées dans un paquet de clés de 1 418 octets ;
// - le premier message d'une session vers un paquet (type 0x01) : établissement hybride
//   X25519 + ML-KEM-768, identité de l'expéditeur cachée dans un préambule chiffré,
//   en-tête de cliquet chiffré, texte remboursé à 160 octets — `[[BROCOLIS:v4:…]]` ;
// - le premier message d'une session à clé partagée (type 0x02), pour la sauvegarde.
//
// Le secret de session mélange trois X25519 et le secret ML-KEM : il reste sûr tant que
// l'un des deux (courbe elliptique ou réseau euclidien) tient, même face à un
// ordinateur quantique. Les primitives de courbe viennent de `BrocolisCurves`
// (CryptoKit dans l'app) ; tout le reste est ici, en Swift pur.

/// X25519 et Ed25519.
protocol BrocolisCurves {
    /// La clé publique X25519 d'un secret brut de 32 octets (réduit par RFC 7748).
    static func x25519Public(secret: [UInt8]) throws -> [UInt8]
    /// X25519(secret, public), sans contrôle (fait par `BrocolisV4.x25519`).
    static func x25519Raw(secret: [UInt8], public: [UInt8]) throws -> [UInt8]
    /// La clé de vérification Ed25519 d'une graine de 32 octets.
    static func ed25519Public(seed: [UInt8]) throws -> [UInt8]
    /// Une signature Ed25519 (64 octets).
    static func ed25519Sign(seed: [UInt8], message: [UInt8]) throws -> [UInt8]
    /// Vérifie une signature Ed25519.
    static func ed25519Verify(public: [UInt8], message: [UInt8], signature: [UInt8]) -> Bool
}

/// Ce dont le protocole v4 a besoin : AES-256-GCM et les courbes.
typealias BrocolisV4Crypto = BrocolisCrypto & BrocolisCurves

enum BrocolisV4Error: LocalizedError, Equatable {
    case missingToken
    case format
    case invalidBundle
    case invalidKey
    case signature
    case notForMe
    case replay
    case decryption
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .missingToken: "Aucun message Brocolis v4 dans ce texte."
        case .format: "Le message est abîmé ou incomplet."
        case .invalidBundle: "Ce n'est pas un paquet de clés Brocolis post-quantique valide."
        case .invalidKey: "Une clé du message est invalide."
        case .signature: "La signature du paquet de clés ne correspond pas : il a peut-être été altéré."
        case .notForMe: "Ce message n'a pas été chiffré pour votre identité."
        case .replay: "Ce message a déjà été ouvert sur cet appareil."
        case .decryption: "Le message n'a pas pu être déchiffré : clé incorrecte ou message altéré."
        case .tooLarge: "Le texte est trop long pour un message."
        }
    }
}

// MARK: - Appareil et paquet de clés

/// Mon identité post-quantique : à garder dans le Trousseau (secrets).
struct BrocolisDevice: Codable, Equatable, Sendable {
    var version = 1
    var identityDH: [UInt8]
    var identitySign: [UInt8]
    var spkID: UInt32
    var spkSecret: [UInt8]
    var pqID: UInt32
    var pqSeed: [UInt8]
    var createdAt: Date
    /// Les clés éphémères des premiers messages déjà ouverts (hex → date), contre le rejeu.
    var seenEphemerals: [String: Date] = [:]
    /// Le paquet publié, gardé tel quel (une signature Ed25519 peut varier d'un calcul à
    /// l'autre : le paquet affiché et partagé reste ainsi le même).
    var publishedBundle: [UInt8]?

    /// Un nouvel appareil. Ordre de tirage de brocolis-proto : secret X25519 (32), graine
    /// Ed25519 (32), id SPK (4), secret SPK (32), id PQPK (4), graine ML-KEM (64).
    static func generate(now: Date = Date(), random: (Int) -> [UInt8] = Brocolis.randomBytes) -> BrocolisDevice {
        let dh = random(32)
        let sign = random(32)
        let spkID = BrocolisV4.firstID(random(4))
        let spk = random(32)
        let pqID = BrocolisV4.firstID(random(4))
        let seed = random(64)
        return BrocolisDevice(
            identityDH: dh, identitySign: sign, spkID: spkID, spkSecret: spk,
            pqID: pqID, pqSeed: seed, createdAt: now
        )
    }

    /// Le paquet de clés publiques, signé.
    func bundle(crypto: BrocolisV4Crypto.Type) throws -> BrocolisKeyBundle {
        let ikDH = try crypto.x25519Public(secret: identityDH)
        let ikSign = try crypto.ed25519Public(seed: identitySign)
        let spk = try crypto.x25519Public(secret: spkSecret)
        let pqKey = MLKEM768.publicKey(seed: pqSeed)
        return BrocolisKeyBundle(
            identityDH: ikDH,
            identitySign: ikSign,
            spkID: spkID,
            spk: spk,
            spkSignature: try crypto.ed25519Sign(
                seed: identitySign, message: BrocolisKeyBundle.spkMessage(ik: ikDH, id: spkID, spk: spk)
            ),
            pqID: pqID,
            pqKey: pqKey,
            pqSignature: try crypto.ed25519Sign(
                seed: identitySign, message: BrocolisKeyBundle.pqMessage(ik: ikDH, id: pqID, key: pqKey)
            )
        )
    }

    /// L'empreinte de ma clé d'échange (celle que voit un destinataire).
    func exchangeFingerprint(crypto: BrocolisV4Crypto.Type) throws -> String {
        BrocolisV4.fingerprint(try crypto.x25519Public(secret: identityDH))
    }

    /// Oublie les clés éphémères vues il y a plus de 30 jours.
    mutating func purge(now: Date = Date()) {
        seenEphemerals = seenEphemerals.filter { now.timeIntervalSince($0.value) < 30 * 86_400 }
    }
}

/// Un paquet de clés publiques (format binaire v1 de brocolis-proto, 1 418 octets).
struct BrocolisKeyBundle: Equatable, Sendable {
    var identityDH: [UInt8]
    var identitySign: [UInt8]
    var spkID: UInt32
    var spk: [UInt8]
    var spkSignature: [UInt8]
    var pqID: UInt32
    var pqKey: [UInt8]
    var pqSignature: [UInt8]

    static let length = 1418
    static let classicLength = 166
    static let spkContext = Array("Brocolis_v3_SPK".utf8)
    static let pqContext = Array("Brocolis_v3_PQPK".utf8)

    static func spkMessage(ik: [UInt8], id: UInt32, spk: [UInt8]) -> [UInt8] {
        spkContext + ik + BrocolisV4.be32(id) + spk
    }

    static func pqMessage(ik: [UInt8], id: UInt32, key: [UInt8]) -> [UInt8] {
        pqContext + ik + BrocolisV4.be32(id) + key
    }

    var bytes: [UInt8] {
        var out: [UInt8] = [0x01]
        out += identityDH + identitySign + BrocolisV4.be32(spkID) + spk + spkSignature
        out += [0x01] + BrocolisV4.be32(pqID) + pqKey + pqSignature
        return out
    }

    var base64: String { Data(bytes).base64EncodedString() }

    /// L'empreinte de l'identité : SHA-256(IK X25519 ‖ IK Ed25519)[0..8].
    var fingerprint: String { BrocolisV4.fingerprint(identityDH + identitySign) }

    /// L'empreinte de la clé d'échange (IK X25519), affichée à la réception.
    var exchangeFingerprint: String { BrocolisV4.fingerprint(identityDH) }

    /// Lit un paquet (base64, espaces tolérés) et vérifie tout : longueur, version, clés,
    /// signatures et clé ML-KEM. Un paquet sans ML-KEM est refusé : KeyForge ne chiffre
    /// qu'en post-quantique.
    static func parse(_ text: String, crypto: BrocolisV4Crypto.Type) throws -> BrocolisKeyBundle {
        let cleaned = text.filter { !$0.isWhitespace }
        guard cleaned.count <= 2 * length, let data = Data(base64Encoded: cleaned) else {
            throw BrocolisV4Error.invalidBundle
        }
        return try parse(bytes: [UInt8](data), crypto: crypto)
    }

    static func parse(bytes d: [UInt8], crypto: BrocolisV4Crypto.Type) throws -> BrocolisKeyBundle {
        guard d.count == length, d[0] == 0x01, d[165] == 0x01 else { throw BrocolisV4Error.invalidBundle }
        let bundle = BrocolisKeyBundle(
            identityDH: Array(d[1..<33]),
            identitySign: Array(d[33..<65]),
            spkID: BrocolisV4.readBE32(d, 65),
            spk: Array(d[69..<101]),
            spkSignature: Array(d[101..<165]),
            pqID: BrocolisV4.readBE32(d, 166),
            pqKey: Array(d[170..<1354]),
            pqSignature: Array(d[1354..<1418])
        )
        try bundle.verify(crypto: crypto)
        return bundle
    }

    func verify(crypto: BrocolisV4Crypto.Type) throws {
        for key in [identityDH, spk] where !BrocolisV4.isCanonical(key) || key.allSatisfy({ $0 == 0 }) {
            throw BrocolisV4Error.invalidKey
        }
        guard crypto.ed25519Verify(
            public: identitySign, message: Self.spkMessage(ik: identityDH, id: spkID, spk: spk), signature: spkSignature
        ) else { throw BrocolisV4Error.signature }
        guard pqID != 0, pqKey.count == MLKEM768.encapsulationKeyLength else { throw BrocolisV4Error.invalidBundle }
        guard crypto.ed25519Verify(
            public: identitySign, message: Self.pqMessage(ik: identityDH, id: pqID, key: pqKey), signature: pqSignature
        ) else { throw BrocolisV4Error.signature }
        guard MLKEM768.isValidEncapsulationKey(pqKey) else { throw BrocolisV4Error.invalidKey }
    }
}

// MARK: - Protocole

enum BrocolisV4 {
    static let head = "[[BROCOLIS:v4:"
    static let end = "]]"
    static let typeInitial: UInt8 = 0x01
    static let typeMessage: UInt8 = 0x02
    static let genreText: UInt8 = 0x00
    static let block = 160
    static let headerLength = 32 + 4 + 4 + 1 + MLKEM768.encapsulationKeyLength
    static let headerLengthWithCiphertext = headerLength + MLKEM768.ciphertextLength
    static let preambleLength = 48
    static let maxPlaintext = 200 * 1024
    static let maxTokenBytes = 256 * 1024
    static let maxSkip: UInt32 = 1000

    private static let zeros32 = [UInt8](repeating: 0, count: 32)
    private static let infoSK = Array("Brocolis_v4_X25519_MLKEM768_SHA-256".utf8)
    private static let infoPSK = Array("Brocolis_v4_PSK_SHA-256".utf8)
    private static let infoPSKRatchet = Array("Brocolis_v4_PSK_Ratchet".utf8)
    private static let infoHeaderKeys = Array("Brocolis_v4_HeaderKeys".utf8)
    private static let infoRatchet = Array("Brocolis_v4_Ratchet".utf8)
    private static let infoRatchetPQ = Array("Brocolis_v4_Ratchet_MLKEM768".utf8)
    private static let infoMessage = Array("Brocolis_v4_MessageKeys".utf8)
    private static let infoPreamble = Array("Brocolis_v4_Preamble".utf8)

    // MARK: Dérivations (kdf.rs)

    static func sk4(dh1: [UInt8], dh2: [UInt8], dh3: [UInt8], ss: [UInt8]) -> [UInt8] {
        PureSHA256.hkdf(salt: zeros32, ikm: [UInt8](repeating: 0xFF, count: 32) + dh1 + dh2 + dh3 + ss, info: infoSK, length: 32)
    }

    static func sk4PSK(_ key: [UInt8]) -> [UInt8] {
        PureSHA256.hkdf(salt: zeros32, ikm: key, info: infoPSK, length: 32)
    }

    static func psk4RatchetSecret(_ sk: [UInt8]) -> [UInt8] {
        PureSHA256.hkdf(salt: zeros32, ikm: sk, info: infoPSKRatchet, length: 32)
    }

    /// `(HK_AB, NHK_BA)`.
    static func headerKeys4(_ sk: [UInt8]) -> (hkAB: [UInt8], nhkBA: [UInt8]) {
        let out = PureSHA256.hkdf(salt: zeros32, ikm: sk, info: infoHeaderKeys, length: 64)
        return (Array(out[0..<32]), Array(out[32..<64]))
    }

    /// `KDF_RK4(rk, dh, ss?)` → `(rk', ck, nhk)`.
    static func kdfRK4(rk: [UInt8], dh: [UInt8], ss: [UInt8]?) -> (rk: [UInt8], ck: [UInt8], nhk: [UInt8]) {
        let out = PureSHA256.hkdf(salt: rk, ikm: dh + (ss ?? []), info: ss == nil ? infoRatchet : infoRatchetPQ, length: 96)
        return (Array(out[0..<32]), Array(out[32..<64]), Array(out[64..<96]))
    }

    /// `KDF_CK(ck)` → `(ck', mk)`.
    static func kdfCK(_ ck: [UInt8]) -> (next: [UInt8], mk: [UInt8]) {
        (PureSHA256.hmac(key: ck, data: [0x02]), PureSHA256.hmac(key: ck, data: [0x01]))
    }

    /// `ENCRYPT4(mk)` → clé AES, nonce du chiffré, nonce de l'en-tête.
    static func messageKeys4(_ mk: [UInt8]) -> (key: [UInt8], nonce: [UInt8], headerNonce: [UInt8]) {
        let out = PureSHA256.hkdf(salt: zeros32, ikm: mk, info: infoMessage, length: 56)
        return (Array(out[0..<32]), Array(out[32..<44]), Array(out[44..<56]))
    }

    static func preambleKey4(dh: [UInt8], ss: [UInt8]) -> (key: [UInt8], nonce: [UInt8]) {
        let out = PureSHA256.hkdf(salt: zeros32, ikm: dh + ss, info: infoPreamble, length: 44)
        return (Array(out[0..<32]), Array(out[32..<44]))
    }

    /// `XXXX-XXXX-XXXX-XXXX` : les 8 premiers octets du SHA-256.
    static func fingerprint(_ data: [UInt8]) -> String {
        let hex = PureSHA256.hash(data).prefix(8).map { String(format: "%02X", $0) }
        return stride(from: 0, to: 8, by: 2).map { hex[$0] + hex[$0 + 1] }.joined(separator: "-")
    }

    // MARK: X25519 avec les contrôles de brocolis-proto

    /// Bit 255 nul et u < 2²⁵⁵ − 19.
    static func isCanonical(_ key: [UInt8]) -> Bool {
        guard key.count == 32, key[31] & 0x80 == 0 else { return false }
        return !(key[31] == 0x7f && key[1..<31].allSatisfy { $0 == 0xff } && key[0] >= 0xed)
    }

    static func x25519(_ secret: [UInt8], _ peer: [UInt8], crypto: BrocolisV4Crypto.Type) throws -> [UInt8] {
        guard isCanonical(peer) else { throw BrocolisV4Error.invalidKey }
        let shared: [UInt8]
        do {
            shared = try crypto.x25519Raw(secret: secret, public: peer)
        } catch {
            throw BrocolisV4Error.invalidKey
        }
        guard shared.count == 32, !shared.allSatisfy({ $0 == 0 }) else { throw BrocolisV4Error.invalidKey }
        return shared
    }

    // MARK: Remplissage (remplissage.rs)

    static func pad(_ data: [UInt8]) -> [UInt8] {
        let length = (data.count / block + 1) * block
        return data + [0x80] + [UInt8](repeating: 0, count: length - data.count - 1)
    }

    static func unpad(_ padded: [UInt8]) throws -> [UInt8] {
        guard !padded.isEmpty, padded.count % block == 0,
              let end = padded.lastIndex(where: { $0 != 0 }), padded[end] == 0x80
        else { throw BrocolisV4Error.format }
        return Array(padded[..<end])
    }

    // MARK: Envoi

    /// Chiffre `text` pour le paquet `bundle` : le premier message d'une session v4
    /// (type 0x01). Ordre de tirage de brocolis-proto : EK (32), cliquet (32), m (32),
    /// graine ML-KEM de cliquet (64).
    static func encrypt(
        _ text: String, to bundle: BrocolisKeyBundle, from device: BrocolisDevice,
        crypto: BrocolisV4Crypto.Type, random: (Int) -> [UInt8] = Brocolis.randomBytes
    ) throws -> String {
        try encrypt(
            text, to: bundle, identitySecret: device.identityDH, crypto: crypto,
            ekSecret: random(32), ratchetSecret: random(32), kemM: random(32), kemSeed: random(64)
        )
    }

    /// `encrypt` avec le hasard donné (les vecteurs).
    static func encrypt(
        _ text: String, to bundle: BrocolisKeyBundle, identitySecret: [UInt8], crypto: BrocolisV4Crypto.Type,
        ekSecret: [UInt8], ratchetSecret: [UInt8], kemM: [UInt8], kemSeed: [UInt8]
    ) throws -> String {
        try bundle.verify(crypto: crypto)
        let ikA = try crypto.x25519Public(secret: identitySecret)
        let dh1 = try x25519(identitySecret, bundle.spk, crypto: crypto)
        let dh2 = try x25519(ekSecret, bundle.identityDH, crypto: crypto)
        let dh3 = try x25519(ekSecret, bundle.spk, crypto: crypto)
        guard let encapsulated = MLKEM768.encapsulate(ek: bundle.pqKey, m: kemM) else { throw BrocolisV4Error.invalidKey }
        let kemCT = encapsulated.ciphertext
        let ss = encapsulated.shared
        let sk = sk4(dh1: dh1, dh2: dh2, dh3: dh3, ss: ss)
        let ephemeral = try crypto.x25519Public(secret: ekSecret)
        let (kPre, nPre) = preambleKey4(dh: dh3, ss: ss)
        let preambleAAD = [typeInitial] + ephemeral + kemCT
        let sealedIdentity = try crypto.seal(key: kPre, nonce: nPre, aad: preambleAAD, plaintext: ikA)
        let body = try sealFirst(
            kind: typeInitial, sk: sk, ad: ikA + bundle.identityDH, ratchetSecret: ratchetSecret,
            remoteRatchet: bundle.spk, kemSeed: kemSeed, text: text, crypto: crypto
        )
        return encode([typeInitial] + ephemeral + kemCT + sealedIdentity + body)
    }

    /// Chiffre `text` sous une clé partagée de 32 octets : le premier message d'une
    /// session v4 à clé partagée (type 0x02). Tirage : EK (32), graine ML-KEM (64).
    static func encryptPSK(
        _ text: String, key: [UInt8], crypto: BrocolisV4Crypto.Type,
        random: (Int) -> [UInt8] = Brocolis.randomBytes
    ) throws -> String {
        try encryptPSK(text, key: key, crypto: crypto, ekSecret: random(32), kemSeed: random(64))
    }

    static func encryptPSK(
        _ text: String, key: [UInt8], crypto: BrocolisV4Crypto.Type, ekSecret: [UInt8], kemSeed: [UInt8]
    ) throws -> String {
        guard key.count == 32 else { throw BrocolisV4Error.invalidKey }
        let sk = sk4PSK(key)
        let r = try crypto.x25519Public(secret: psk4RatchetSecret(sk))
        let ad = try crypto.x25519Public(secret: ekSecret) + r
        let body = try sealFirst(
            kind: typeMessage, sk: sk, ad: ad, ratchetSecret: ekSecret,
            remoteRatchet: r, kemSeed: kemSeed, text: text, crypto: crypto
        )
        return encode([typeMessage] + body)
    }

    /// Le corps du premier message d'un initiateur (`new_initiator` puis `seal`).
    private static func sealFirst(
        kind: UInt8, sk: [UInt8], ad: [UInt8], ratchetSecret: [UInt8], remoteRatchet: [UInt8],
        kemSeed: [UInt8], text: String, crypto: BrocolisV4Crypto.Type
    ) throws -> [UInt8] {
        let data = Array(text.utf8)
        guard data.count <= maxPlaintext else { throw BrocolisV4Error.tooLarge }
        guard kemSeed.count == 64 else { throw BrocolisV4Error.invalidKey }
        let (hkAB, _) = headerKeys4(sk)
        let dh = try x25519(ratchetSecret, remoteRatchet, crypto: crypto)
        let chain = kdfRK4(rk: sk, dh: dh, ss: nil)
        let (_, mk) = kdfCK(chain.ck)
        let (key, nonce, hnonce) = messageKeys4(mk)
        let header = try crypto.x25519Public(secret: ratchetSecret) + be32(0) + be32(0) + [0x00]
            + MLKEM768.publicKey(seed: kemSeed)
        let encHeader = try crypto.seal(key: hkAB, nonce: hnonce, aad: [kind], plaintext: header)
        let aad = ad + [kind] + hnonce + encHeader
        let ciphertext = try crypto.seal(key: key, nonce: nonce, aad: aad, plaintext: pad([genreText] + data))
        return hnonce + be16(UInt16(encHeader.count)) + encHeader + ciphertext
    }

    // MARK: Réception

    struct Received: Equatable, Sendable {
        var text: String
        /// La clé d'échange de l'expéditeur (IK X25519), révélée par le préambule.
        var senderIdentity: [UInt8]
        var senderFingerprint: String { BrocolisV4.fingerprint(senderIdentity) }
    }

    /// Ouvre un premier message (0x01) chiffré pour `device` (`Device::accept4`).
    static func accept(
        _ text: String, device: inout BrocolisDevice, crypto: BrocolisV4Crypto.Type, now: Date = Date()
    ) throws -> Received {
        let token = try decode(text)
        guard case let .initial(ephemeral, kemCT, sealedIdentity, body) = token else { throw BrocolisV4Error.format }
        guard isCanonical(ephemeral) else { throw BrocolisV4Error.invalidKey }
        let seenKey = ephemeral.map { String(format: "%02x", $0) }.joined()
        guard device.seenEphemerals[seenKey] == nil else { throw BrocolisV4Error.replay }
        let dh3 = try x25519(device.spkSecret, ephemeral, crypto: crypto)
        guard let ss = MLKEM768.decapsulate(seed: device.pqSeed, ciphertext: kemCT) else { throw BrocolisV4Error.format }
        let (kPre, nPre) = preambleKey4(dh: dh3, ss: ss)
        guard let ikA = try? crypto.open(key: kPre, nonce: nPre, aad: [typeInitial] + ephemeral + kemCT, sealed: sealedIdentity),
              ikA.count == 32
        else { throw BrocolisV4Error.notForMe }
        let dh1 = try x25519(device.spkSecret, ikA, crypto: crypto)
        let dh2 = try x25519(device.identityDH, ephemeral, crypto: crypto)
        let sk = sk4(dh1: dh1, dh2: dh2, dh3: dh3, ss: ss)
        let ad = ikA + (try crypto.x25519Public(secret: device.identityDH))
        let plain = try openFirst(kind: typeInitial, body: body, sk: sk, ad: ad, ratchetSecret: device.spkSecret, crypto: crypto)
        device.seenEphemerals[seenKey] = now
        return Received(text: plain, senderIdentity: ikA)
    }

    /// Ouvre le premier message (0x02) d'une session à clé partagée (`accept_psk`).
    static func acceptPSK(_ text: String, key: [UInt8], crypto: BrocolisV4Crypto.Type) throws -> String {
        let token = try decode(text)
        guard case let .message(body) = token, key.count == 32 else { throw BrocolisV4Error.format }
        let sk = sk4PSK(key)
        let (hkAB, _) = headerKeys4(sk)
        guard let plainHeader = try? crypto.open(key: hkAB, nonce: body.headerNonce, aad: [typeMessage], sealed: body.header)
        else { throw BrocolisV4Error.decryption }
        let header = try Header.parse(plainHeader)
        guard isCanonical(header.dh) else { throw BrocolisV4Error.invalidKey }
        let rSecret = psk4RatchetSecret(sk)
        let ad = header.dh + (try crypto.x25519Public(secret: rSecret))
        return try openFirst(kind: typeMessage, body: body, sk: sk, ad: ad, ratchetSecret: rSecret, crypto: crypto)
    }

    /// Le déchiffrement d'un répondeur neuf (`new_responder` puis `decrypt`) : l'en-tête
    /// s'ouvre avec HK_AB, le cliquet tourne une fois (sans ML-KEM : la toute première
    /// chaîne de l'initiateur n'en porte pas), puis la clé du message `n`.
    private static func openFirst(
        kind: UInt8, body: Body, sk: [UInt8], ad: [UInt8], ratchetSecret: [UInt8], crypto: BrocolisV4Crypto.Type
    ) throws -> String {
        let (hkAB, _) = headerKeys4(sk)
        guard let plainHeader = try? crypto.open(key: hkAB, nonce: body.headerNonce, aad: [kind], sealed: body.header)
        else { throw BrocolisV4Error.decryption }
        let header = try Header.parse(plainHeader)
        guard header.ct == nil else { throw BrocolisV4Error.format }
        guard header.pn <= maxSkip, header.n <= maxSkip else { throw BrocolisV4Error.format }
        let dh = try x25519(ratchetSecret, header.dh, crypto: crypto)
        var ck = kdfRK4(rk: sk, dh: dh, ss: nil).ck
        for _ in 0..<header.n { ck = kdfCK(ck).next }
        let (key, nonce, hnonce) = messageKeys4(kdfCK(ck).mk)
        guard hnonce == body.headerNonce else { throw BrocolisV4Error.decryption }
        let aad = ad + [kind] + body.headerNonce + body.header
        guard let padded = try? crypto.open(key: key, nonce: nonce, aad: aad, sealed: body.ciphertext) else {
            throw BrocolisV4Error.decryption
        }
        let plain = try unpad(padded)
        guard plain.first == genreText, let string = String(bytes: plain.dropFirst(), encoding: .utf8) else {
            throw BrocolisV4Error.format
        }
        return string
    }

    // MARK: Jeton (jeton_v4.rs)

    struct Body: Equatable {
        var headerNonce: [UInt8]
        var header: [UInt8]
        var ciphertext: [UInt8]
    }

    enum Token: Equatable {
        case initial(ephemeral: [UInt8], kemCiphertext: [UInt8], sealedIdentity: [UInt8], body: Body)
        case message(Body)
    }

    struct Header: Equatable {
        var dh: [UInt8]
        var pn: UInt32
        var n: UInt32
        var ek: [UInt8]
        var ct: [UInt8]?

        static func parse(_ b: [UInt8]) throws -> Header {
            guard b.count == headerLength || b.count == headerLengthWithCiphertext else { throw BrocolisV4Error.format }
            let flags = b[40]
            let ct: [UInt8]?
            switch (flags, b.count) {
            case (0x00, headerLength): ct = nil
            case (0x01, headerLengthWithCiphertext): ct = Array(b[headerLength...])
            default: throw BrocolisV4Error.format
            }
            return Header(
                dh: Array(b[0..<32]), pn: readBE32(b, 32), n: readBE32(b, 36),
                ek: Array(b[41..<headerLength]), ct: ct
            )
        }
    }

    static func encode(_ bytes: [UInt8]) -> String {
        head + Data(bytes).base64EncodedString() + end
    }

    /// Le premier `[[BROCOLIS:v4:…]]` d'un texte collé, décodé strictement.
    static func decode(_ text: String) throws -> Token {
        guard let inner = Brocolis.inner(text, head: head) else { throw BrocolisV4Error.missingToken }
        guard inner.count <= 4 * ((maxTokenBytes + 2) / 3) else { throw BrocolisV4Error.tooLarge }
        guard let data = Data(base64Encoded: inner) else { throw BrocolisV4Error.format }
        return try parse([UInt8](data))
    }

    static func parse(_ d: [UInt8]) throws -> Token {
        guard !d.isEmpty, d.count <= maxTokenBytes else { throw BrocolisV4Error.format }
        var position = 1
        func take(_ n: Int) throws -> [UInt8] {
            guard d.count - position >= n else { throw BrocolisV4Error.format }
            defer { position += n }
            return Array(d[position..<(position + n)])
        }
        func body() throws -> Body {
            let nonce = try take(12)
            let lengthBytes = try take(2)
            let length = Int(lengthBytes[0]) << 8 | Int(lengthBytes[1])
            guard length == headerLength + 16 || length == headerLengthWithCiphertext + 16 else { throw BrocolisV4Error.format }
            let header = try take(length)
            let ciphertext = Array(d[position...])
            guard ciphertext.count >= block + 16, (ciphertext.count - 16) % block == 0 else { throw BrocolisV4Error.format }
            return Body(headerNonce: nonce, header: header, ciphertext: ciphertext)
        }
        switch d[0] {
        case typeInitial:
            let ephemeral = try take(32)
            let kemCT = try take(MLKEM768.ciphertextLength)
            let sealed = try take(preambleLength)
            return .initial(ephemeral: ephemeral, kemCiphertext: kemCT, sealedIdentity: sealed, body: try body())
        case typeMessage:
            return .message(try body())
        default:
            throw BrocolisV4Error.format
        }
    }

    /// Vrai si le texte contient un message v4.
    static func containsToken(_ text: String) -> Bool { text.contains(head) }

    // MARK: Octets

    static func be32(_ v: UInt32) -> [UInt8] {
        [UInt8(v >> 24), UInt8(truncatingIfNeeded: v >> 16), UInt8(truncatingIfNeeded: v >> 8), UInt8(truncatingIfNeeded: v)]
    }

    static func be16(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(truncatingIfNeeded: v)] }

    static func readBE32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) << 24 | UInt32(b[i + 1]) << 16 | UInt32(b[i + 2]) << 8 | UInt32(b[i + 3])
    }

    /// Le premier identifiant de clé pré-signée : `(u32 BE des 4 octets) >> 1`, au moins 1.
    static func firstID(_ bytes: [UInt8]) -> UInt32 {
        max(readBE32(bytes, 0) >> 1, 1)
    }
}
