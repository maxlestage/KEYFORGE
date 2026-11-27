import Foundation

// Le hasard de Brocolis 🥦 (module `hasard` de brocolis-proto), porté tel quel :
//
// - en production, le CSPRNG du système et rien d'autre (`getrandom` côté Rust,
//   `arc4random_buf` sur iPhone, alimenté par le générateur matériel de la Secure
//   Enclave) : `BrocolisHasard.system()` ;
// - pour les tests seulement, un générateur déterministe : le bloc `i` (32 octets)
//   vaut `SHA-256("Brocolis_vecteurs" ‖ graine ‖ i u64 gros-boutiste)`, `i` partant
//   de 0, les octets servis dans l'ordre sans en jeter. Il rejoue les vecteurs de
//   brocolis-proto et ne doit **jamais** servir en production.
//
// Tout ce que KeyForge tire au hasard (mots de passe, phrases, PIN, charabia, clés et
// nonces Brocolis, clé du coffre) passe par ici.

/// Un générateur aléatoire au sens de Brocolis : une source d'octets.
protocol BrocolisRandom: RandomNumberGenerator {
    mutating func fill(_ buffer: inout [UInt8])
}

extension BrocolisRandom {
    mutating func bytes(_ count: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: count)
        fill(&out)
        return out
    }
}

enum BrocolisHasard {
    /// Le CSPRNG du système, comme `hasard::system()`.
    static func system() -> System { System() }

    /// Des octets du CSPRNG du système, comme `hasard::bytes(&mut system())`.
    static func bytes(_ count: Int) -> [UInt8] {
        var rng = system()
        return rng.bytes(count)
    }

    /// Le CSPRNG du système (`arc4random_buf`), sans état.
    struct System: BrocolisRandom {
        mutating func fill(_ buffer: inout [UInt8]) {
            guard !buffer.isEmpty else { return }
            buffer.withUnsafeMutableBytes { raw in
                if let base = raw.baseAddress { arc4random_buf(base, raw.count) }
            }
        }

        mutating func next() -> UInt64 {
            var value: UInt64 = 0
            withUnsafeMutableBytes(of: &value) { raw in
                if let base = raw.baseAddress { arc4random_buf(base, raw.count) }
            }
            return value
        }
    }

    /// Le générateur déterministe de brocolis-proto : **tests et vecteurs seulement**.
    struct Deterministic: BrocolisRandom {
        private let seed: [UInt8]
        private var counter: UInt64 = 0
        private var block = [UInt8](repeating: 0, count: 32)
        private var used = 32

        init(seed: [UInt8]) { self.seed = seed }
        init(seed: String) { self.init(seed: Array(seed.utf8)) }

        private mutating func refill() {
            var input = Array("Brocolis_vecteurs".utf8)
            input += seed
            input += (0..<8).map { UInt8(truncatingIfNeeded: counter >> (56 - 8 * UInt64($0))) }
            block = PureSHA256.hash(input)
            counter &+= 1
            used = 0
        }

        mutating func fill(_ buffer: inout [UInt8]) {
            for i in buffer.indices {
                if used == 32 { refill() }
                buffer[i] = block[used]
                used += 1
            }
        }

        /// Gros-boutiste, comme `try_next_u64` de brocolis-proto.
        mutating func next() -> UInt64 {
            bytes(8).reduce(0) { $0 << 8 | UInt64($1) }
        }
    }
}
