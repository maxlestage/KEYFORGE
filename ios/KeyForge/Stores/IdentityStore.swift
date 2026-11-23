import Foundation
import Observation

/// Mon identité post-quantique Brocolis v4 : un appareil (X25519, Ed25519, ML-KEM-768)
/// créé une fois et gardé dans le Trousseau de cet iPhone (`ThisDeviceOnly`), son paquet
/// de clés publiques à partager, et les opérations d'envoi et de réception.
@MainActor
@Observable
final class IdentityStore {
    private(set) var device: BrocolisDevice?
    private(set) var bundle: BrocolisKeyBundle?
    var errorMessage: String?

    private let keychain = KeychainStore(service: "com.maxlestage.KeyForge.identity", account: "device")

    init() {
        load()
    }

    private func load() {
        guard let data = try? keychain.load(),
              let stored = try? JSONDecoder().decode(BrocolisDevice.self, from: data)
        else { return }
        device = stored
        bundle = stored.publishedBundle.flatMap { try? BrocolisKeyBundle.parse(bytes: $0, crypto: AppleCrypto.self) }
            ?? (try? stored.bundle(crypto: AppleCrypto.self))
    }

    /// L'identité, créée à la première demande.
    @discardableResult
    func ensure() -> BrocolisDevice? {
        if device == nil { regenerate() }
        return device
    }

    /// Une nouvelle identité : les messages chiffrés pour l'ancienne ne s'ouvriront plus.
    func regenerate() {
        var fresh = BrocolisDevice.generate()
        do {
            let published = try fresh.bundle(crypto: AppleCrypto.self)
            fresh.publishedBundle = published.bytes
            try save(fresh)
            bundle = published
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save(_ updated: BrocolisDevice) throws {
        try keychain.save(JSONEncoder().encode(updated))
        device = updated
    }

    /// Chiffre `text` pour le paquet collé (base64) : `[[BROCOLIS:v4:…]]`.
    func encrypt(_ text: String, forBundle bundleText: String) throws -> (token: String, recipient: BrocolisKeyBundle) {
        guard let me = ensure() else { throw BrocolisV4Error.invalidKey }
        let recipient = try BrocolisKeyBundle.parse(bundleText, crypto: AppleCrypto.self)
        let token = try BrocolisV4.encrypt(text, to: recipient, from: me, crypto: AppleCrypto.self)
        return (token, recipient)
    }

    /// Ouvre un message chiffré pour moi, et retient sa clé éphémère contre le rejeu.
    func open(_ token: String) throws -> BrocolisV4.Received {
        guard var current = ensure() else { throw BrocolisV4Error.notForMe }
        current.purge()
        let received = try BrocolisV4.accept(token, device: &current, crypto: AppleCrypto.self)
        try save(current)
        return received
    }
}
