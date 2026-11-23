import Foundation

enum Entropy {
    /// Bits of entropy of a secret of `length` symbols drawn uniformly from `poolSize`.
    static func bits(length: Int, poolSize: Int) -> Double {
        guard length > 0, poolSize > 1 else { return 0 }
        return Double(length) * log2(Double(poolSize))
    }
}

/// How hard a secret is to guess, from its entropy in bits.
enum StrengthLevel: Int, CaseIterable, Comparable, Sendable {
    case veryWeak
    case weak
    case fair
    case strong
    case excellent

    init(bits: Double) {
        switch bits {
        case ..<28: self = .veryWeak
        case ..<36: self = .weak
        case ..<60: self = .fair
        case ..<128: self = .strong
        default: self = .excellent
        }
    }

    static func < (lhs: StrengthLevel, rhs: StrengthLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .veryWeak: "Très faible"
        case .weak: "Faible"
        case .fair: "Correcte"
        case .strong: "Forte"
        case .excellent: "Excellente"
        }
    }

    /// Share of the strength bar, from 0.15 to 1.
    var progress: Double {
        switch self {
        case .veryWeak: 0.15
        case .weak: 0.35
        case .fair: 0.6
        case .strong: 0.82
        case .excellent: 1
        }
    }

    /// Progress that keeps growing inside a level, for a smoother bar.
    static func progress(bits: Double) -> Double {
        min(max(bits / 128, 0.04), 1)
    }
}
