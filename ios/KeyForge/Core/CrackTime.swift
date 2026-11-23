import Foundation

/// How long an offline attack would take, in plain French.
enum CrackTime {
    /// Guesses per second of a well-equipped offline attacker (GPU farm).
    static let guessesPerSecond = 1e11

    /// Average time to find a secret of `bits` bits: half of the space.
    static func seconds(bits: Double) -> Double {
        guard bits > 0 else { return 0 }
        guard bits < 1000 else { return .infinity }
        return pow(2, bits) / 2 / guessesPerSecond
    }

    static func describe(bits: Double) -> String {
        describe(seconds: seconds(bits: bits))
    }

    static func describe(seconds: Double) -> String {
        let minute = 60.0
        let hour = 60 * minute
        let day = 24 * hour
        let month = 30 * day
        let year = 365 * day
        let century = 100 * year

        if !seconds.isFinite || seconds / century >= 1e6 {
            return "plus d'un million de siècles"
        }
        switch seconds {
        case ..<1: return "instantané"
        case ..<minute: return plural(seconds, "seconde", "secondes")
        case ..<hour: return plural(seconds / minute, "minute", "minutes")
        case ..<day: return plural(seconds / hour, "heure", "heures")
        case ..<month: return plural(seconds / day, "jour", "jours")
        case ..<year: return plural(seconds / month, "mois", "mois")
        case ..<century: return plural(seconds / year, "an", "ans")
        default: return plural(seconds / century, "siècle", "siècles")
        }
    }

    private static func plural(_ value: Double, _ one: String, _ many: String) -> String {
        let n = max(1, Int(value.rounded(.down)))
        return "\(grouped(n)) \(n == 1 ? one : many)"
    }

    /// `1234567` → `1 234 567`, the French way, whatever the device locale.
    static func grouped(_ n: Int) -> String {
        let digits = Array(String(n))
        var out = ""
        for (i, d) in digits.enumerated() {
            if i > 0, (digits.count - i) % 3 == 0 { out.append(" ") }
            out.append(d)
        }
        return out
    }
}
