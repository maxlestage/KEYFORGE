import SwiftUI

// MARK: - Logo

/// The KeyForge mark: a key on an ember gradient, with a breathing glow.
struct LogoMark: View {
    var size: CGFloat = 64
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Theme.ember)
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(.white.opacity(0.25), lineWidth: 1)
            Image(systemName: "key.horizontal.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(-35))
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.18, weight: .bold))
                .foregroundStyle(Color.gold)
                .offset(x: size * 0.24, y: -size * 0.24)
                .symbolEffect(.pulse, options: .repeating, isActive: animated && !reduceMotion)
        }
        .frame(width: size, height: size)
        .phaseAnimator(animated && !reduceMotion ? [false, true] : [false]) { view, glowing in
            view.shadow(color: .ember.opacity(glowing ? 0.65 : 0.3), radius: glowing ? size * 0.32 : size * 0.18)
        } animation: { _ in
            .easeInOut(duration: 1.6)
        }
        .accessibilityHidden(true)
    }
}

/// The glow of the logo keeps breathing as long as it is on screen.
struct BreathingLogo: View {
    var size: CGFloat = 64
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LogoMark(size: size)
            .phaseAnimator(reduceMotion ? [1.0] : [1.0, 1.06]) { view, scale in
                view.scaleEffect(scale)
            } animation: { _ in
                .easeInOut(duration: 1.4)
            }
    }
}

// MARK: - Buttons

/// The main call to action: an ember gradient that shimmers, and squeezes when pressed.
struct EmberButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        EmberButtonBody(configuration: configuration, compact: compact)
    }

    private struct EmberButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let compact: Bool
        @State private var shine = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.vertical, compact ? 10 : 16)
                .padding(.horizontal, compact ? 16 : 22)
                .frame(maxWidth: compact ? nil : .infinity)
                .background {
                    Capsule()
                        .fill(Theme.ember)
                        .overlay {
                            GeometryReader { proxy in
                                LinearGradient(
                                    colors: [.clear, .white.opacity(0.35), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: proxy.size.width * 0.35)
                                .offset(x: shine ? proxy.size.width * 1.2 : -proxy.size.width * 0.5)
                            }
                            .clipShape(Capsule())
                        }
                }
                .shadow(color: .ember.opacity(configuration.isPressed ? 0.2 : 0.45), radius: configuration.isPressed ? 6 : 16, y: 6)
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: false).delay(1)) {
                        shine = true
                    }
                }
        }
    }
}

/// A round secondary action (copy, save…), with a bouncing symbol.
struct RoundAction: View {
    let title: String
    let symbol: String
    var tint: Color = .white
    var bounce = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color.surfaceHigh))
                    .overlay(Circle().strokeBorder(Color.line))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: bounce)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title)
    }
}

/// Shrinks a little while pressed.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Strength

/// A bar that fills and changes colour with the entropy.
struct StrengthBar: View {
    let bits: Double
    var height: CGFloat = 10

    var body: some View {
        let level = StrengthLevel(bits: bits)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [level.color.opacity(0.7), level.color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(height, proxy.size.width * StrengthLevel.progress(bits: bits)))
                    .shadow(color: level.color.opacity(0.6), radius: 6)
                // Ticks at the level thresholds.
                ForEach([28.0, 36, 60], id: \.self) { mark in
                    Rectangle()
                        .fill(Color.ink.opacity(0.7))
                        .frame(width: 2)
                        .offset(x: proxy.size.width * mark / 128)
                }
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.55, dampingFraction: 0.75), value: bits)
        .accessibilityElement()
        .accessibilityLabel("Robustesse")
        .accessibilityValue("\(level.title), \(Int(bits)) bits")
    }
}

/// The level of a secret: an icon, its name and its entropy in bits.
struct StrengthLabel: View {
    let bits: Double

    var body: some View {
        let level = StrengthLevel(bits: bits)
        HStack(spacing: 8) {
            Image(systemName: level.symbol)
                .foregroundStyle(level.color)
                .contentTransition(.symbolEffect(.replace))
            Text(level.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(level.color)
                .contentTransition(.interpolate)
            Spacer()
            Text("\(Int(bits.rounded()))")
                .font(.subheadline.monospacedDigit().weight(.bold))
                .contentTransition(.numericText(value: bits))
            Text("bits")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .animation(.snappy, value: bits)
    }
}

// MARK: - Secrets

/// A secret, character by character: letters in white, digits in gold, symbols in
/// pink. When it changes, it "decodes": random glyphs settle from left to right.
struct SecretText: View {
    let value: String
    var font: Font = .system(.title2, design: .monospaced).weight(.semibold)
    @State private var shown: [Character] = []
    @State private var task: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let glyphs = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789#$%&*+=?@")

    var body: some View {
        shown.reduce(Text("")) { text, character in
            text + Text(String(character)).foregroundColor(color(of: character))
        }
        .font(font)
        .multilineTextAlignment(.center)
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
        .accessibilityLabel(Text(value))
        .onAppear { shown = Array(value) }
        .onChange(of: value) { _, newValue in scramble(to: newValue) }
        .onDisappear { task?.cancel() }
    }

    private func color(of character: Character) -> Color {
        CharacterClass.of(character)?.color ?? .white
    }

    private func scramble(to target: String) {
        task?.cancel()
        let final = Array(target)
        guard !reduceMotion, final.count <= 140 else {
            shown = final
            return
        }
        task = Task { @MainActor in
            let frames = 12
            for frame in 1...frames {
                if Task.isCancelled { return }
                let settled = final.count * frame / frames
                shown = final.enumerated().map { index, character in
                    index < settled || character == " " ? character : Self.glyphs.randomElement()!
                }
                try? await Task.sleep(for: .milliseconds(28))
            }
            shown = final
        }
    }
}

// MARK: - Toast

@MainActor
@Observable
final class ToastCenter {
    struct Toast: Equatable {
        let id = UUID()
        let message: String
        let symbol: String
    }

    private(set) var current: Toast?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    func show(_ message: String, symbol: String = "checkmark.circle.fill") {
        dismissTask?.cancel()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            current = Toast(message: message, symbol: symbol)
        }
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { self?.current = nil }
        }
    }
}

struct ToastView: View {
    let toast: ToastCenter.Toast

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.symbol)
                .foregroundStyle(Color.gold)
                .symbolEffect(.bounce, value: toast.id)
            Text(toast.message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.ember, lineWidth: 1))
        .shadow(color: .ember.opacity(0.35), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Check mark

/// A check mark that draws itself when `checked` becomes true.
struct AnimatedCheck: View {
    let checked: Bool
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(checked ? Color.clear : Color.white.opacity(0.2), lineWidth: 1.5)
            Circle()
                .fill(Color(hex: 0x4ADE80))
                .scaleEffect(checked ? 1 : 0.2)
                .opacity(checked ? 1 : 0)
            CheckShape()
                .trim(from: 0, to: checked ? 1 : 0)
                .stroke(Color.ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                .padding(size * 0.27)
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.4, dampingFraction: 0.65), value: checked)
    }

    private struct CheckShape: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            return path
        }
    }
}

// MARK: - Section title

struct SectionTitle: View {
    let title: String
    var symbol: String?

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol).foregroundStyle(Theme.ember)
            }
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(Color.textSecondary)
            Spacer()
        }
        .accessibilityAddTraits(.isHeader)
    }
}
