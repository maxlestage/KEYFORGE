import Foundation

// ML-KEM-768 (FIPS 203) en Swift pur, Foundation seulement : la moitié post-quantique
// du chiffrement Brocolis v4. Les clés viennent d'une graine `d ‖ z` (64 octets) et
// l'encapsulation d'un message `m` (32 octets) donné, exactement comme
// `mlkem_public`, `mlkem_encapsulate` et `mlkem_decapsulate` de brocolis-proto.
//
// Paramètres : n = 256, q = 3 329, k = 3, η1 = η2 = 2, du = 10, dv = 4.

enum MLKEM768 {
    static let k = 3
    static let q: Int32 = 3329
    /// Clé d'encapsulation : 384·k + 32 = 1 184 octets.
    static let encapsulationKeyLength = 1184
    /// Chiffré : 32·(du·k + dv) = 1 088 octets.
    static let ciphertextLength = 1088
    static let seedLength = 64

    typealias Poly = [Int32]

    // MARK: API

    /// La clé d'encapsulation d'une graine `d ‖ z`.
    static func publicKey(seed: [UInt8]) -> [UInt8] {
        precondition(seed.count == 64)
        return pkeKeyGen(d: Array(seed[0..<32])).ek
    }

    /// Encapsule vers `ek` avec le message `m` : `(chiffré, secret partagé)`.
    /// `nil` si la clé d'encapsulation est mal formée (contrôle de module de FIPS 203).
    static func encapsulate(ek: [UInt8], m: [UInt8]) -> (ciphertext: [UInt8], shared: [UInt8])? {
        guard ek.count == encapsulationKeyLength, m.count == 32, isValidEncapsulationKey(ek) else { return nil }
        let g = PureSHA3.sha512(m + PureSHA3.sha256(ek))
        let shared = Array(g[0..<32])
        let r = Array(g[32..<64])
        return (pkeEncrypt(ek: ek, m: m, r: r), shared)
    }

    /// Décapsule `c` avec la graine `d ‖ z` (rejet implicite : un chiffré altéré donne un
    /// secret pseudo-aléatoire, sans erreur). `nil` si `c` n'a pas la bonne longueur.
    static func decapsulate(seed: [UInt8], ciphertext c: [UInt8]) -> [UInt8]? {
        guard seed.count == 64, c.count == ciphertextLength else { return nil }
        let d = Array(seed[0..<32])
        let z = Array(seed[32..<64])
        let (ek, sHat) = pkeKeyGen(d: d)
        let h = PureSHA3.sha256(ek)
        let mPrime = pkeDecrypt(sHat: sHat, c: c)
        let g = PureSHA3.sha512(mPrime + h)
        let kPrime = Array(g[0..<32])
        let rPrime = Array(g[32..<64])
        let kBar = PureSHA3.shake256(z + c, count: 32)
        let cPrime = pkeEncrypt(ek: ek, m: mPrime, r: rPrime)
        // Comparaison en temps constant, puis sélection sans branche.
        var diff: UInt8 = 0
        for i in 0..<c.count { diff |= c[i] ^ cPrime[i] }
        let mask = UInt8(truncatingIfNeeded: (Int(diff) - 1) >> 8)  // 0xFF si égaux
        return (0..<32).map { (kPrime[$0] & mask) | (kBar[$0] & ~mask) }
    }

    /// Le contrôle de module de FIPS 203 (§7.2) : chaque coefficient < q.
    static func isValidEncapsulationKey(_ ek: [UInt8]) -> Bool {
        guard ek.count == encapsulationKeyLength else { return false }
        for i in 0..<k {
            let poly = byteDecode12(Array(ek[(384 * i)..<(384 * (i + 1))]))
            if poly.contains(where: { $0 >= q }) { return false }
        }
        return true
    }

    // MARK: K-PKE

    /// K-PKE.KeyGen(d) : la clé d'encapsulation et ŝ (pour déchiffrer).
    private static func pkeKeyGen(d: [UInt8]) -> (ek: [UInt8], sHat: [Poly]) {
        let g = PureSHA3.sha512(d + [UInt8(k)])
        let rho = Array(g[0..<32])
        let sigma = Array(g[32..<64])
        let aHat = matrix(rho: rho)
        var n: UInt8 = 0
        var s = [Poly]()
        var e = [Poly]()
        for _ in 0..<k { s.append(cbd2(prf(sigma, n))); n += 1 }
        for _ in 0..<k { e.append(cbd2(prf(sigma, n))); n += 1 }
        let sHat = s.map(ntt)
        let eHat = e.map(ntt)
        var ek = [UInt8]()
        ek.reserveCapacity(encapsulationKeyLength)
        for i in 0..<k {
            var t = [Int32](repeating: 0, count: 256)
            for j in 0..<k { addInPlace(&t, multiplyNTT(aHat[i][j], sHat[j])) }
            addInPlace(&t, eHat[i])
            ek += byteEncode12(t.map(reduce))
        }
        ek += rho
        return (ek, sHat)
    }

    private static func pkeEncrypt(ek: [UInt8], m: [UInt8], r: [UInt8]) -> [UInt8] {
        let tHat = (0..<k).map { byteDecode12(Array(ek[(384 * $0)..<(384 * ($0 + 1))])) }
        let rho = Array(ek[(384 * k)...])
        let aHat = matrix(rho: rho)
        var n: UInt8 = 0
        var y = [Poly]()
        var e1 = [Poly]()
        for _ in 0..<k { y.append(cbd2(prf(r, n))); n += 1 }
        for _ in 0..<k { e1.append(cbd2(prf(r, n))); n += 1 }
        let e2 = cbd2(prf(r, n))
        let yHat = y.map(ntt)
        var c = [UInt8]()
        c.reserveCapacity(ciphertextLength)
        for i in 0..<k {
            var acc = [Int32](repeating: 0, count: 256)
            for j in 0..<k { addInPlace(&acc, multiplyNTT(aHat[j][i], yHat[j])) }
            var u = inverseNTT(acc)
            addInPlace(&u, e1[i])
            c += byteEncode(u.map { compress(reduce($0), bits: 10) }, bits: 10)
        }
        var acc = [Int32](repeating: 0, count: 256)
        for j in 0..<k { addInPlace(&acc, multiplyNTT(tHat[j], yHat[j])) }
        var v = inverseNTT(acc)
        addInPlace(&v, e2)
        let mu = byteDecode(m, bits: 1).map { decompress($0, bits: 1) }
        addInPlace(&v, mu)
        c += byteEncode(v.map { compress(reduce($0), bits: 4) }, bits: 4)
        return c
    }

    private static func pkeDecrypt(sHat: [Poly], c: [UInt8]) -> [UInt8] {
        let uBytes = 32 * 10
        let u = (0..<k).map { i in
            byteDecode(Array(c[(uBytes * i)..<(uBytes * (i + 1))]), bits: 10).map { decompress($0, bits: 10) }
        }
        let v = byteDecode(Array(c[(uBytes * k)...]), bits: 4).map { decompress($0, bits: 4) }
        var acc = [Int32](repeating: 0, count: 256)
        for j in 0..<k { addInPlace(&acc, multiplyNTT(sHat[j], ntt(u[j]))) }
        let product = inverseNTT(acc)
        let w = (0..<256).map { reduce(v[$0] - product[$0]) }
        return byteEncode(w.map { compress($0, bits: 1) }, bits: 1)
    }

    // MARK: Échantillonnage

    /// Â[i][j] = SampleNTT(ρ ‖ j ‖ i).
    private static func matrix(rho: [UInt8]) -> [[Poly]] {
        (0..<k).map { i in (0..<k).map { j in sampleNTT(rho + [UInt8(j), UInt8(i)]) } }
    }

    private static func sampleNTT(_ seed: [UInt8]) -> Poly {
        var xof = PureSHA3.shake128(seed)
        var a = [Int32]()
        a.reserveCapacity(256)
        while a.count < 256 {
            let block = xof.squeeze(168)
            var i = 0
            while i + 3 <= block.count && a.count < 256 {
                let d1 = Int32(block[i]) | (Int32(block[i + 1] & 0x0F) << 8)
                let d2 = Int32(block[i + 1] >> 4) | (Int32(block[i + 2]) << 4)
                if d1 < q { a.append(d1) }
                if d2 < q && a.count < 256 { a.append(d2) }
                i += 3
            }
        }
        return a
    }

    /// PRF_η(s, b) = SHAKE256(s ‖ b, 64·η), η = 2.
    private static func prf(_ s: [UInt8], _ b: UInt8) -> [UInt8] {
        PureSHA3.shake256(s + [b], count: 128)
    }

    /// SamplePolyCBD_2.
    private static func cbd2(_ bytes: [UInt8]) -> Poly {
        var f = [Int32](repeating: 0, count: 256)
        for i in 0..<128 {
            let byte = bytes[i]
            // Deux coefficients par octet : 4 bits chacun.
            for half in 0..<2 {
                let bits = byte >> (4 * UInt8(half))
                let x = Int32(bits & 1) + Int32((bits >> 1) & 1)
                let y = Int32((bits >> 2) & 1) + Int32((bits >> 3) & 1)
                f[2 * i + half] = reduce(x - y)
            }
        }
        return f
    }

    // MARK: NTT

    /// ζ^BitRev7(i) mod q, i = 0…127, avec ζ = 17.
    private static let zetas: [Int32] = (0..<128).map { power(17, bitRev7($0)) }
    /// ζ^(2·BitRev7(i) + 1) mod q, pour la multiplication dans le domaine NTT.
    private static let gammas: [Int32] = (0..<128).map { power(17, 2 * bitRev7($0) + 1) }

    private static func bitRev7(_ x: Int) -> Int {
        var r = 0
        for b in 0..<7 where x & (1 << b) != 0 { r |= 1 << (6 - b) }
        return r
    }

    private static func power(_ base: Int32, _ exponent: Int) -> Int32 {
        var result: Int64 = 1
        var b = Int64(base)
        var e = exponent
        while e > 0 {
            if e & 1 == 1 { result = result * b % Int64(q) }
            b = b * b % Int64(q)
            e >>= 1
        }
        return Int32(result)
    }

    @inline(__always)
    private static func reduce(_ x: Int32) -> Int32 {
        let r = x % q
        return r < 0 ? r + q : r
    }

    @inline(__always)
    private static func mulmod(_ a: Int32, _ b: Int32) -> Int32 {
        Int32((Int64(a) * Int64(b)) % Int64(q))
    }

    private static func ntt(_ input: Poly) -> Poly {
        var f = input
        var i = 1
        var len = 128
        while len >= 2 {
            var start = 0
            while start < 256 {
                let zeta = zetas[i]
                i += 1
                for j in start..<(start + len) {
                    let t = mulmod(zeta, f[j + len])
                    f[j + len] = reduce(f[j] - t)
                    f[j] = reduce(f[j] + t)
                }
                start += 2 * len
            }
            len /= 2
        }
        return f
    }

    private static func inverseNTT(_ input: Poly) -> Poly {
        var f = input.map(reduce)
        var i = 127
        var len = 2
        while len <= 128 {
            var start = 0
            while start < 256 {
                let zeta = zetas[i]
                i -= 1
                for j in start..<(start + len) {
                    let t = f[j]
                    f[j] = reduce(t + f[j + len])
                    f[j + len] = mulmod(zeta, reduce(f[j + len] - t))
                }
                start += 2 * len
            }
            len *= 2
        }
        return f.map { mulmod($0, 3303) }  // 128⁻¹ mod q
    }

    private static func multiplyNTT(_ f: Poly, _ g: Poly) -> Poly {
        var h = [Int32](repeating: 0, count: 256)
        for i in 0..<128 {
            let a0 = f[2 * i], a1 = f[2 * i + 1]
            let b0 = g[2 * i], b1 = g[2 * i + 1]
            h[2 * i] = reduce(mulmod(a0, b0) + mulmod(mulmod(a1, b1), gammas[i]))
            h[2 * i + 1] = reduce(mulmod(a0, b1) + mulmod(a1, b0))
        }
        return h
    }

    @inline(__always)
    private static func addInPlace(_ a: inout Poly, _ b: Poly) {
        for i in 0..<256 { a[i] = reduce(a[i] + b[i]) }
    }

    // MARK: Compression et encodage

    private static func compress(_ x: Int32, bits d: Int) -> Int32 {
        // round(2^d · x / q) mod 2^d, en entiers.
        let numerator = (Int64(x) << d) + Int64(q / 2)
        return Int32((numerator / Int64(q)) & Int64((1 << d) - 1))
    }

    private static func decompress(_ y: Int32, bits d: Int) -> Int32 {
        // round(q · y / 2^d).
        Int32((Int64(q) * Int64(y) + Int64(1 << (d - 1))) >> d)
    }

    private static func byteEncode(_ f: [Int32], bits d: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 32 * d)
        var bitIndex = 0
        for value in f {
            var v = UInt32(value)
            for _ in 0..<d {
                if v & 1 == 1 { out[bitIndex >> 3] |= 1 << UInt8(bitIndex & 7) }
                v >>= 1
                bitIndex += 1
            }
        }
        return out
    }

    private static func byteDecode(_ bytes: [UInt8], bits d: Int) -> [Int32] {
        var f = [Int32](repeating: 0, count: 256)
        var bitIndex = 0
        for i in 0..<256 {
            var v: Int32 = 0
            for b in 0..<d {
                if bytes[bitIndex >> 3] & (1 << UInt8(bitIndex & 7)) != 0 { v |= 1 << Int32(b) }
                bitIndex += 1
            }
            f[i] = v
        }
        return f
    }

    private static func byteEncode12(_ f: [Int32]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 384)
        for i in 0..<128 {
            let a = UInt32(f[2 * i]), b = UInt32(f[2 * i + 1])
            out[3 * i] = UInt8(truncatingIfNeeded: a)
            out[3 * i + 1] = UInt8(truncatingIfNeeded: (a >> 8) | (b << 4))
            out[3 * i + 2] = UInt8(truncatingIfNeeded: b >> 4)
        }
        return out
    }

    /// ByteDecode12 sans réduction (le contrôle de module regarde les valeurs brutes) ;
    /// les valeurs ≥ q sont réduites à l'usage.
    private static func byteDecode12(_ bytes: [UInt8]) -> [Int32] {
        var f = [Int32](repeating: 0, count: 256)
        for i in 0..<128 {
            let b0 = Int32(bytes[3 * i]), b1 = Int32(bytes[3 * i + 1]), b2 = Int32(bytes[3 * i + 2])
            f[2 * i] = b0 | ((b1 & 0x0F) << 8)
            f[2 * i + 1] = (b1 >> 4) | (b2 << 4)
        }
        return f
    }
}
