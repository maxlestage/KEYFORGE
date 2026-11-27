import Foundation

/// Le coffre tel qu'il est rangé sur l'iPhone : du charabia au format Brocolis 🥦.
///
/// Les entrées (JSON) forment le premier message d'une session **v4 à clé partagée**
/// sous une clé de 256 bits propre au coffre : `[[BROCOLIS:v4:…]]` (en-tête chiffré,
/// AES-256-GCM, remplissage par blocs de 160 octets, clé ML-KEM-768 de cliquet), le
/// même format que la sauvegarde chiffrée et que les apps Brocolis. Un nouveau sceau,
/// avec une clé éphémère neuve, à chaque écriture.
///
/// Un coffre d'une version précédente (JSON en clair dans le trousseau) se lit toujours ;
/// il est scellé à la première écriture.
enum VaultSeal {
    /// Vrai si les octets rangés sont un coffre scellé (et pas l'ancien JSON en clair).
    static func isSealed(_ data: Data) -> Bool {
        data.starts(with: Data(BrocolisV4.head.utf8))
    }

    static func seal(_ items: [VaultItem], key: [UInt8], crypto: BrocolisV4Crypto.Type) throws -> Data {
        let json = try JSONEncoder().encode(items)
        let token = try BrocolisV4.encryptPSK(String(decoding: json, as: UTF8.self), key: key, crypto: crypto)
        return Data(token.utf8)
    }

    /// Les entrées d'un coffre scellé (avec sa clé) ou en clair (ancien format).
    static func open(_ data: Data, key: [UInt8]?, crypto: BrocolisV4Crypto.Type) throws -> [VaultItem] {
        guard isSealed(data) else {
            return try JSONDecoder().decode([VaultItem].self, from: data)
        }
        guard let key else { throw VaultSealError.missingKey }
        let json: String
        do {
            json = try BrocolisV4.acceptPSK(String(decoding: data, as: UTF8.self), key: key, crypto: crypto)
        } catch {
            throw VaultSealError.unreadable
        }
        return try JSONDecoder().decode([VaultItem].self, from: Data(json.utf8))
    }
}

enum VaultSealError: LocalizedError, Equatable {
    case missingKey
    case unreadable

    var errorDescription: String? {
        switch self {
        case .missingKey:
            "La clé Brocolis du coffre est introuvable sur cet iPhone : le coffre ne peut pas être déchiffré."
        case .unreadable:
            "Le coffre chiffré par Brocolis n'a pas pu être déchiffré : clé incorrecte ou données altérées."
        }
    }
}
