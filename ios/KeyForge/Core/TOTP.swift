import CryptoKit
import Foundation

/// Un code de validation à usage unique (TOTP, RFC 6238) : le « code à 6 chiffres » de
/// la validation en deux étapes. Calculé sur l'appareil à partir d'un secret partagé
/// avec le site et de l'heure ; rien ne passe par le réseau.
///
/// Le secret arrive par un lien ou un QR code `otpauth://totp/Émetteur:compte?secret=…`
/// (format Key URI de Google Authenticator), ou saisi à la main en base32.
struct TOTP: Equatable, Sendable {
    enum Algorithm: String, CaseIterable, Sendable {
        case sha1 = "SHA1"
        case sha256 = "SHA256"
        case sha512 = "SHA512"
    }

    var secret: [UInt8]
    var algorithm: Algorithm = .sha1
    var digits = 6
    var period = 30
    var issuer = ""
    var account = ""

    // MARK: Lecture

    /// Un lien `otpauth://totp/…` ou, à défaut, un secret en base32 saisi à la main.
    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("otpauth:") {
            self.init(uri: trimmed)
        } else {
            guard let secret = Self.base32Decode(trimmed), secret.count >= 10 else { return nil }
            self.init(secret: secret)
        }
    }

    init(secret: [UInt8]) {
        self.secret = secret
    }

    /// `otpauth://totp/Émetteur:compte?secret=BASE32&issuer=…&algorithm=…&digits=…&period=…`
    init?(uri: String) {
        guard let components = URLComponents(string: uri.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "otpauth",
              components.host?.lowercased() == "totp"
        else { return nil }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            query[item.name.lowercased()] = item.value ?? ""
        }
        guard let secret = Self.base32Decode(query["secret"] ?? ""), !secret.isEmpty else { return nil }
        self.secret = secret

        if let name = query["algorithm"], !name.isEmpty {
            guard let algorithm = Algorithm(rawValue: name.uppercased().replacingOccurrences(of: "-", with: ""))
            else { return nil }
            self.algorithm = algorithm
        }
        if let value = query["digits"], !value.isEmpty {
            guard let digits = Int(value), (6...8).contains(digits) else { return nil }
            self.digits = digits
        }
        if let value = query["period"], !value.isEmpty {
            guard let period = Int(value), (5...300).contains(period) else { return nil }
            self.period = period
        }

        // L'étiquette : « Émetteur:compte » ou « compte ».
        var label = components.path
        if label.hasPrefix("/") { label.removeFirst() }
        if let colon = label.firstIndex(of: ":") {
            issuer = String(label[..<colon]).trimmingCharacters(in: .whitespaces)
            account = String(label[label.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        } else {
            account = label.trimmingCharacters(in: .whitespaces)
        }
        if let named = query["issuer"], !named.isEmpty { issuer = named }
    }

    /// Le lien `otpauth://` complet : ce qui est rangé dans le coffre.
    var uri: String {
        var components = URLComponents()
        components.scheme = "otpauth"
        components.host = "totp"
        let label = issuer.isEmpty ? account : (account.isEmpty ? issuer : "\(issuer):\(account)")
        components.path = "/" + label
        var items = [URLQueryItem(name: "secret", value: Self.base32Encode(secret))]
        if !issuer.isEmpty { items.append(URLQueryItem(name: "issuer", value: issuer)) }
        items.append(URLQueryItem(name: "algorithm", value: algorithm.rawValue))
        items.append(URLQueryItem(name: "digits", value: String(digits)))
        items.append(URLQueryItem(name: "period", value: String(period)))
        components.queryItems = items
        return components.string ?? ""
    }

    // MARK: Code

    /// Le code valable à cette date.
    func code(at date: Date = Date()) -> String {
        let counter = UInt64(max(0, date.timeIntervalSince1970)) / UInt64(period)
        let message = (0..<8).map { UInt8(truncatingIfNeeded: counter >> (56 - 8 * UInt64($0))) }
        let key = SymmetricKey(data: secret)
        let mac: [UInt8]
        switch algorithm {
        case .sha1: mac = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
        case .sha256: mac = Array(HMAC<SHA256>.authenticationCode(for: message, using: key))
        case .sha512: mac = Array(HMAC<SHA512>.authenticationCode(for: message, using: key))
        }
        // Troncature dynamique (RFC 4226) : 31 bits à partir d'un décalage tiré du MAC.
        let offset = Int(mac[mac.count - 1] & 0x0f)
        let binary = UInt32(mac[offset] & 0x7f) << 24
            | UInt32(mac[offset + 1]) << 16
            | UInt32(mac[offset + 2]) << 8
            | UInt32(mac[offset + 3])
        var modulus: UInt32 = 1
        for _ in 0..<digits { modulus *= 10 }
        let value = String(binary % modulus)
        return String(repeating: "0", count: max(0, digits - value.count)) + value
    }

    /// Le code en deux groupes, pour la lecture (« 123 456 »).
    func displayCode(at date: Date = Date()) -> String {
        let value = code(at: date)
        let half = value.count / 2
        return String(value.prefix(half)) + " " + String(value.dropFirst(half))
    }

    /// Les secondes avant le prochain code.
    func secondsRemaining(at date: Date = Date()) -> Int {
        let elapsed = Int(max(0, date.timeIntervalSince1970)) % period
        return period - elapsed
    }

    // MARK: Base32 (RFC 4648)

    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    /// Tolère minuscules, espaces, tirets et remplissage `=`. `nil` : caractère invalide.
    static func base32Decode(_ text: String) -> [UInt8]? {
        var out: [UInt8] = []
        var buffer: UInt32 = 0
        var bits = 0
        for character in text.uppercased() {
            if character == " " || character == "-" || character == "=" || character.isNewline { continue }
            guard let index = alphabet.firstIndex(of: character) else { return nil }
            buffer = (buffer << 5) | UInt32(index)
            bits += 5
            if bits >= 8 {
                bits -= 8
                out.append(UInt8(truncatingIfNeeded: buffer >> UInt32(bits)))
                buffer &= (1 << UInt32(bits)) - 1
            }
        }
        return out
    }

    static func base32Encode(_ bytes: [UInt8]) -> String {
        var out = ""
        var buffer: UInt32 = 0
        var bits = 0
        for byte in bytes {
            buffer = (buffer << 8) | UInt32(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                out.append(alphabet[Int((buffer >> UInt32(bits)) & 0x1f)])
                buffer &= (1 << UInt32(bits)) - 1
            }
        }
        if bits > 0 {
            out.append(alphabet[Int((buffer << UInt32(5 - bits)) & 0x1f)])
        }
        return out
    }
}

extension VaultItem {
    /// Le générateur de codes de validation de cette entrée, s'il y en a un de valide.
    var oneTimeCode: TOTP? {
        guard let totp, !totp.isEmpty else { return nil }
        return TOTP(totp)
    }
}
