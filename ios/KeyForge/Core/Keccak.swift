import Foundation

// Keccak-f[1600] et les fonctions de FIPS 202 dont ML-KEM a besoin : SHA3-256 (H),
// SHA3-512 (G), SHAKE128 (XOF) et SHAKE256 (PRF, J). Swift pur, Foundation seulement.

/// L'éponge Keccak, absorbée d'un coup puis pressée à la demande.
struct KeccakSponge {
    private var state = [UInt64](repeating: 0, count: 25)
    private let rate: Int
    private var buffer = [UInt8]()
    private var offset = 0

    private static let roundConstants: [UInt64] = [
        0x0000_0000_0000_0001, 0x0000_0000_0000_8082, 0x8000_0000_0000_808A, 0x8000_0000_8000_8000,
        0x0000_0000_0000_808B, 0x0000_0000_8000_0001, 0x8000_0000_8000_8081, 0x8000_0000_0000_8009,
        0x0000_0000_0000_008A, 0x0000_0000_0000_0088, 0x0000_0000_8000_8009, 0x0000_0000_8000_000A,
        0x0000_0000_8000_808B, 0x8000_0000_0000_008B, 0x8000_0000_0000_8089, 0x8000_0000_0000_8003,
        0x8000_0000_0000_8002, 0x8000_0000_0000_0080, 0x0000_0000_0000_800A, 0x8000_0000_8000_000A,
        0x8000_0000_8000_8081, 0x8000_0000_0000_8080, 0x0000_0000_8000_0001, 0x8000_0000_8000_8008,
    ]
    private static let rotations: [UInt64] = [
        0, 1, 62, 28, 27, 36, 44, 6, 55, 20, 3, 10, 43, 25, 39, 41, 45, 15, 21, 8, 18, 2, 61, 56, 14,
    ]

    /// `rate` en octets ; `suffix` : 0x06 pour SHA3, 0x1F pour SHAKE.
    init(rate: Int, suffix: UInt8, input: [UInt8]) {
        self.rate = rate
        var block = [UInt8](repeating: 0, count: rate)
        var position = 0
        while input.count - position >= rate {
            for i in 0..<rate { block[i] = input[position + i] }
            absorb(block)
            position += rate
        }
        let rest = input.count - position
        for i in 0..<rate { block[i] = i < rest ? input[position + i] : 0 }
        block[rest] ^= suffix
        block[rate - 1] ^= 0x80
        absorb(block)
    }

    private mutating func absorb(_ block: [UInt8]) {
        state.withUnsafeMutableBufferPointer { s in
            block.withUnsafeBufferPointer { b in
                for lane in 0..<(rate / 8) {
                    var v: UInt64 = 0
                    for k in 0..<8 { v |= UInt64(b[lane * 8 + k]) << (8 * UInt64(k)) }
                    s[lane] ^= v
                }
            }
            Self.permute(s)
        }
    }

    /// Les `count` octets suivants de la sortie.
    mutating func squeeze(_ count: Int) -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(count)
        while out.count < count {
            if offset == buffer.count {
                if !buffer.isEmpty {
                    state.withUnsafeMutableBufferPointer { Self.permute($0) }
                }
                buffer = [UInt8](repeating: 0, count: rate)
                for lane in 0..<(rate / 8) {
                    let v = state[lane]
                    for k in 0..<8 { buffer[lane * 8 + k] = UInt8(truncatingIfNeeded: v >> (8 * UInt64(k))) }
                }
                offset = 0
            }
            let take = min(count - out.count, buffer.count - offset)
            out.append(contentsOf: buffer[offset..<(offset + take)])
            offset += take
        }
        return out
    }

    @inline(__always)
    private static func rotl(_ x: UInt64, _ n: UInt64) -> UInt64 {
        n == 0 ? x : (x << n) | (x >> (64 - n))
    }

    private static func permute(_ a: UnsafeMutableBufferPointer<UInt64>) {
        var c = (UInt64(0), UInt64(0), UInt64(0), UInt64(0), UInt64(0))
        var b = [UInt64](repeating: 0, count: 25)
        for round in 0..<24 {
            // θ
            c.0 = a[0] ^ a[5] ^ a[10] ^ a[15] ^ a[20]
            c.1 = a[1] ^ a[6] ^ a[11] ^ a[16] ^ a[21]
            c.2 = a[2] ^ a[7] ^ a[12] ^ a[17] ^ a[22]
            c.3 = a[3] ^ a[8] ^ a[13] ^ a[18] ^ a[23]
            c.4 = a[4] ^ a[9] ^ a[14] ^ a[19] ^ a[24]
            let d0 = c.4 ^ rotl(c.1, 1)
            let d1 = c.0 ^ rotl(c.2, 1)
            let d2 = c.1 ^ rotl(c.3, 1)
            let d3 = c.2 ^ rotl(c.4, 1)
            let d4 = c.3 ^ rotl(c.0, 1)
            for y in stride(from: 0, to: 25, by: 5) {
                a[y] ^= d0
                a[y + 1] ^= d1
                a[y + 2] ^= d2
                a[y + 3] ^= d3
                a[y + 4] ^= d4
            }
            // ρ et π
            for x in 0..<5 {
                for y in 0..<5 {
                    let index = x + 5 * y
                    b[y + 5 * ((2 * x + 3 * y) % 5)] = rotl(a[index], rotations[index])
                }
            }
            // χ
            for y in stride(from: 0, to: 25, by: 5) {
                for x in 0..<5 {
                    a[y + x] = b[y + x] ^ (~b[y + (x + 1) % 5] & b[y + (x + 2) % 5])
                }
            }
            // ι
            a[0] ^= roundConstants[round]
        }
    }
}

enum PureSHA3 {
    static func sha256(_ data: [UInt8]) -> [UInt8] {
        var s = KeccakSponge(rate: 136, suffix: 0x06, input: data)
        return s.squeeze(32)
    }

    static func sha512(_ data: [UInt8]) -> [UInt8] {
        var s = KeccakSponge(rate: 72, suffix: 0x06, input: data)
        return s.squeeze(64)
    }

    static func shake128(_ data: [UInt8]) -> KeccakSponge {
        KeccakSponge(rate: 168, suffix: 0x1F, input: data)
    }

    static func shake256(_ data: [UInt8], count: Int) -> [UInt8] {
        var s = KeccakSponge(rate: 136, suffix: 0x1F, input: data)
        return s.squeeze(count)
    }
}
