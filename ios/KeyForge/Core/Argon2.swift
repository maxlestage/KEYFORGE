import Foundation

/// Argon2id (RFC 9106, version 0x13), en Swift pur : la dérivation de clé des
/// sauvegardes chiffrées au format Brocolis 🥦 (`[[BROCOLIS-CLE:v2:…]]`).
/// Retrouve octet pour octet les vecteurs de `brocolis-proto`.
enum Argon2id {
    static let version: UInt32 = 0x13
    private static let type: UInt64 = 2 // Argon2id
    private static let blockWords = 128 // 1 024 octets
    private static let syncPoints = 4

    /// `Argon2id(password, salt, m Kio, t passes, p voies, length octets)`, sans
    /// secret ni données associées. `progress` reçoit l'avancement (0…1) après
    /// chaque segment.
    static func hash(
        password: [UInt8],
        salt: [UInt8],
        memoryKiB: Int,
        iterations: Int,
        parallelism: Int,
        length: Int = 32,
        progress: ((Double) -> Void)? = nil
    ) -> [UInt8] {
        precondition(parallelism >= 1 && iterations >= 1 && memoryKiB >= 8 * parallelism && length >= 4)
        let lanes = parallelism
        // m' : un multiple de 4p.
        let blockCount = 4 * lanes * (memoryKiB / (4 * lanes))
        let laneLength = blockCount / lanes
        let segmentLength = laneLength / syncPoints

        // H0
        var h = Blake2b(outLength: 64)
        h.update(uint32LE: UInt32(lanes))
        h.update(uint32LE: UInt32(length))
        h.update(uint32LE: UInt32(memoryKiB))
        h.update(uint32LE: UInt32(iterations))
        h.update(uint32LE: version)
        h.update(uint32LE: UInt32(type))
        h.update(uint32LE: UInt32(password.count))
        h.update(password)
        h.update(uint32LE: UInt32(salt.count))
        h.update(salt)
        h.update(uint32LE: 0)
        h.update(uint32LE: 0)
        let h0 = h.finalize()

        let memory = UnsafeMutablePointer<UInt64>.allocate(capacity: blockCount * blockWords)
        memory.initialize(repeating: 0, count: blockCount * blockWords)
        let scratch = UnsafeMutablePointer<UInt64>.allocate(capacity: 5 * blockWords)
        scratch.initialize(repeating: 0, count: 5 * blockWords)
        defer {
            // Les blocs contiennent des dérivés de la phrase : effacés avant de rendre la mémoire.
            memory.update(repeating: 0, count: blockCount * blockWords)
            memory.deallocate()
            scratch.update(repeating: 0, count: 5 * blockWords)
            scratch.deallocate()
        }
        let r = scratch
        let tmp = scratch + blockWords
        let zero = scratch + 2 * blockWords
        let input = scratch + 3 * blockWords
        let address = scratch + 4 * blockWords

        // Les deux premiers blocs de chaque voie.
        for lane in 0..<lanes {
            for column in 0..<2 {
                var seed = h0
                seed += le32(UInt32(column))
                seed += le32(UInt32(lane))
                let bytes = hPrime(seed, length: 1024)
                load(bytes, into: memory + (lane * laneLength + column) * blockWords)
            }
        }

        let totalSegments = Double(iterations * syncPoints * lanes)
        var doneSegments = 0.0
        for pass in 0..<iterations {
            for slice in 0..<syncPoints {
                for lane in 0..<lanes {
                    let independent = pass == 0 && slice < 2
                    var startIndex = 0
                    if independent {
                        for i in 0..<blockWords { input[i] = 0 }
                        input[0] = UInt64(pass)
                        input[1] = UInt64(lane)
                        input[2] = UInt64(slice)
                        input[3] = UInt64(blockCount)
                        input[4] = UInt64(iterations)
                        input[5] = type
                    }
                    if pass == 0 && slice == 0 {
                        startIndex = 2
                        if independent {
                            nextAddresses(input: input, address: address, zero: zero, r: r, tmp: tmp)
                        }
                    }
                    var current = lane * laneLength + slice * segmentLength + startIndex
                    var previous = current % laneLength == 0 ? current + laneLength - 1 : current - 1
                    for index in startIndex..<segmentLength {
                        if current % laneLength == 1 {
                            previous = current - 1
                        }
                        let pseudoRandom: UInt64
                        if independent {
                            if index % blockWords == 0 {
                                nextAddresses(input: input, address: address, zero: zero, r: r, tmp: tmp)
                            }
                            pseudoRandom = address[index % blockWords]
                        } else {
                            pseudoRandom = memory[previous * blockWords]
                        }
                        var refLane = Int((pseudoRandom >> 32) % UInt64(lanes))
                        if pass == 0 && slice == 0 {
                            refLane = lane
                        }
                        let refIndex = indexAlpha(
                            pass: pass, slice: slice, index: index,
                            random: pseudoRandom & 0xffff_ffff,
                            sameLane: refLane == lane,
                            laneLength: laneLength, segmentLength: segmentLength
                        )
                        fillBlock(
                            previous: memory + previous * blockWords,
                            reference: memory + (refLane * laneLength + refIndex) * blockWords,
                            next: memory + current * blockWords,
                            withXor: pass != 0,
                            r: r, tmp: tmp
                        )
                        current += 1
                        previous += 1
                    }
                    doneSegments += 1
                    progress?(doneSegments / totalSegments)
                }
            }
        }

        // C : le XOR des derniers blocs de chaque voie.
        let last = tmp
        for i in 0..<blockWords {
            last[i] = memory[(laneLength - 1) * blockWords + i]
        }
        for lane in 1..<max(lanes, 1) {
            for i in 0..<blockWords {
                last[i] ^= memory[(lane * laneLength + laneLength - 1) * blockWords + i]
            }
        }
        var bytes = [UInt8](repeating: 0, count: 1024)
        for i in 0..<blockWords {
            let word = last[i]
            for j in 0..<8 {
                bytes[i * 8 + j] = UInt8((word >> UInt64(8 * j)) & 0xff)
            }
        }
        defer { for i in bytes.indices { bytes[i] = 0 } }
        return hPrime(bytes, length: length)
    }

    /// H′ : le haché à longueur variable d'Argon2.
    static func hPrime(_ input: [UInt8], length: Int) -> [UInt8] {
        if length <= 64 {
            var b = Blake2b(outLength: length)
            b.update(uint32LE: UInt32(length))
            b.update(input)
            return b.finalize()
        }
        let rounds = (length + 31) / 32 - 2
        var b = Blake2b(outLength: 64)
        b.update(uint32LE: UInt32(length))
        b.update(input)
        var v = b.finalize()
        var out = Array(v[0..<32])
        out.reserveCapacity(length)
        if rounds > 1 {
            for _ in 1..<rounds {
                v = Blake2b.hash(v, outLength: 64)
                out += v[0..<32]
            }
        }
        out += Blake2b.hash(v, outLength: length - 32 * rounds)
        return out
    }

    // MARK: - Interne

    private static func le32(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xff), UInt8((value >> 8) & 0xff), UInt8((value >> 16) & 0xff), UInt8(value >> 24)]
    }

    private static func load(_ bytes: [UInt8], into block: UnsafeMutablePointer<UInt64>) {
        for i in 0..<blockWords {
            var word: UInt64 = 0
            for j in 0..<8 {
                word |= UInt64(bytes[i * 8 + j]) << UInt64(8 * j)
            }
            block[i] = word
        }
    }

    private static func indexAlpha(
        pass: Int, slice: Int, index: Int, random: UInt64, sameLane: Bool,
        laneLength: Int, segmentLength: Int
    ) -> Int {
        let area: Int
        if pass == 0 {
            if slice == 0 {
                area = index - 1
            } else if sameLane {
                area = slice * segmentLength + index - 1
            } else {
                area = slice * segmentLength + (index == 0 ? -1 : 0)
            }
        } else if sameLane {
            area = laneLength - segmentLength + index - 1
        } else {
            area = laneLength - segmentLength + (index == 0 ? -1 : 0)
        }
        var relative = random
        relative = (relative &* relative) >> 32
        relative = UInt64(area) - 1 - ((UInt64(area) &* relative) >> 32)
        let start = pass != 0 && slice != syncPoints - 1 ? (slice + 1) * segmentLength : 0
        return (start + Int(relative)) % laneLength
    }

    private static func nextAddresses(
        input: UnsafeMutablePointer<UInt64>,
        address: UnsafeMutablePointer<UInt64>,
        zero: UnsafeMutablePointer<UInt64>,
        r: UnsafeMutablePointer<UInt64>,
        tmp: UnsafeMutablePointer<UInt64>
    ) {
        input[6] &+= 1
        fillBlock(previous: zero, reference: input, next: address, withXor: false, r: r, tmp: tmp)
        fillBlock(previous: zero, reference: address, next: address, withXor: false, r: r, tmp: tmp)
    }

    /// La fonction de compression G d'Argon2 : `next = P(prev ⊕ ref) ⊕ (prev ⊕ ref)`,
    /// et `⊕ next` à partir de la deuxième passe.
    @inline(__always)
    private static func fillBlock(
        previous: UnsafeMutablePointer<UInt64>,
        reference: UnsafeMutablePointer<UInt64>,
        next: UnsafeMutablePointer<UInt64>,
        withXor: Bool,
        r: UnsafeMutablePointer<UInt64>,
        tmp: UnsafeMutablePointer<UInt64>
    ) {
        for i in 0..<128 {
            let x = previous[i] ^ reference[i]
            r[i] = x
            tmp[i] = withXor ? x ^ next[i] : x
        }
        // Les lignes…
        for i in 0..<8 {
            let o = 16 * i
            round(r, o, o + 1, o + 2, o + 3, o + 4, o + 5, o + 6, o + 7,
                  o + 8, o + 9, o + 10, o + 11, o + 12, o + 13, o + 14, o + 15)
        }
        // … puis les colonnes.
        for i in 0..<8 {
            let o = 2 * i
            round(r, o, o + 1, o + 16, o + 17, o + 32, o + 33, o + 48, o + 49,
                  o + 64, o + 65, o + 80, o + 81, o + 96, o + 97, o + 112, o + 113)
        }
        for i in 0..<128 {
            next[i] = tmp[i] ^ r[i]
        }
    }

    @inline(__always)
    private static func fBlaMka(_ x: UInt64, _ y: UInt64) -> UInt64 {
        let mask: UInt64 = 0xffff_ffff
        return x &+ y &+ 2 &* ((x & mask) &* (y & mask))
    }

    @inline(__always)
    private static func gb(_ v: UnsafeMutablePointer<UInt64>, _ a: Int, _ b: Int, _ c: Int, _ d: Int) {
        var va = v[a], vb = v[b], vc = v[c], vd = v[d]
        va = fBlaMka(va, vb)
        vd = rotr(vd ^ va, 32)
        vc = fBlaMka(vc, vd)
        vb = rotr(vb ^ vc, 24)
        va = fBlaMka(va, vb)
        vd = rotr(vd ^ va, 16)
        vc = fBlaMka(vc, vd)
        vb = rotr(vb ^ vc, 63)
        v[a] = va
        v[b] = vb
        v[c] = vc
        v[d] = vd
    }

    @inline(__always)
    private static func round(
        _ v: UnsafeMutablePointer<UInt64>,
        _ v0: Int, _ v1: Int, _ v2: Int, _ v3: Int, _ v4: Int, _ v5: Int, _ v6: Int, _ v7: Int,
        _ v8: Int, _ v9: Int, _ v10: Int, _ v11: Int, _ v12: Int, _ v13: Int, _ v14: Int, _ v15: Int
    ) {
        gb(v, v0, v4, v8, v12)
        gb(v, v1, v5, v9, v13)
        gb(v, v2, v6, v10, v14)
        gb(v, v3, v7, v11, v15)
        gb(v, v0, v5, v10, v15)
        gb(v, v1, v6, v11, v12)
        gb(v, v2, v7, v8, v13)
        gb(v, v3, v4, v9, v14)
    }
}
