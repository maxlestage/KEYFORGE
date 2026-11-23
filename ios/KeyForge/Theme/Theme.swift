import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// The forge palette.
    static let ink = Color(hex: 0x0B0A12)
    static let surface = Color(hex: 0x15131F)
    static let surfaceHigh = Color(hex: 0x1E1B2B)
    static let line = Color.white.opacity(0.08)
    static let ember = Color(hex: 0xFF6B2C)
    static let gold = Color(hex: 0xFFB547)
    static let violet = Color(hex: 0x7C5CFF)
    static let forgePink = Color(hex: 0xFF2E7E)
    static let textSecondary = Color.white.opacity(0.62)
}

enum Theme {
    /// Ember → pink → violet: buttons, logo, highlights.
    static let ember = LinearGradient(
        colors: [.ember, .forgePink, .violet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let fire = LinearGradient(
        colors: [.gold, .ember, .forgePink],
        startPoint: .top,
        endPoint: .bottom
    )

    static let corner: CGFloat = 22
}

extension StrengthLevel {
    var color: Color {
        switch self {
        case .veryWeak: Color(hex: 0xFF4D4D)
        case .weak: Color(hex: 0xFF9A3C)
        case .fair: Color(hex: 0xFFD447)
        case .strong: Color(hex: 0x4ADE80)
        case .excellent: Color(hex: 0x2DD4BF)
        }
    }

    var symbol: String {
        switch self {
        case .veryWeak: "exclamationmark.octagon.fill"
        case .weak: "exclamationmark.triangle.fill"
        case .fair: "checkmark.circle.fill"
        case .strong: "checkmark.shield.fill"
        case .excellent: "crown.fill"
        }
    }
}

extension CharacterClass {
    /// Colour of a character in a displayed secret.
    var color: Color {
        switch self {
        case .uppercase, .lowercase: .white
        case .digits: .gold
        case .symbols: Color(hex: 0xFF7AA8)
        }
    }
}

/// A rounded, slightly glowing surface.
struct ForgeCard: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Color.surface.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(Color.line, lineWidth: 1)
            )
    }
}

extension View {
    func forgeCard(padding: CGFloat = 18) -> some View {
        modifier(ForgeCard(padding: padding))
    }

    /// Appears with a fade and a slide, `delay` seconds after the view shows up.
    func entrance(delay: Double = 0) -> some View {
        modifier(Entrance(delay: delay))
    }
}

private struct Entrance: ViewModifier {
    let delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 18)
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.82).delay(delay)) {
                    shown = true
                }
            }
    }
}
