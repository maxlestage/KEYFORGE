import SwiftUI

/// The ink background with slowly drifting glows and rising embers (all 2D).
struct ForgeBackground: View {
    var intensity: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.ink
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
                let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                GeometryReader { proxy in
                    let size = proxy.size
                    ZStack {
                        glow(.ember, size: size.width * 1.1)
                            .position(
                                x: size.width * (0.2 + 0.12 * sin(t / 7)),
                                y: size.height * (0.12 + 0.05 * cos(t / 9))
                            )
                        glow(.violet, size: size.width * 1.2)
                            .position(
                                x: size.width * (0.9 + 0.1 * cos(t / 8)),
                                y: size.height * (0.55 + 0.08 * sin(t / 11))
                            )
                        glow(.forgePink, size: size.width * 0.9)
                            .position(
                                x: size.width * (0.35 + 0.15 * sin(t / 10 + 1)),
                                y: size.height * (0.95 + 0.04 * cos(t / 6))
                            )
                    }
                }
            }
            .opacity(0.55 * intensity)
            SparksView(count: 26, intensity: intensity)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func glow(_ color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
            .blur(radius: 30)
    }
}

/// Embers rising from the bottom of the screen, drawn in a `Canvas`.
struct SparksView: View {
    var count = 24
    var intensity: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            Color.clear
        } else {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    for i in 0..<count {
                        let seed = Double(i) * 12.9898
                        let speed = 0.035 + fract(sin(seed) * 437.585) * 0.06
                        let phase = fract(t * speed + fract(sin(seed * 3.1) * 912.3))
                        let baseX = fract(sin(seed * 7.7) * 158.2)
                        let sway = sin(t * (0.6 + baseX) + seed) * 18
                        let x = baseX * size.width + sway
                        let y = size.height * (1.05 - phase * 1.15)
                        let radius = 1.2 + fract(sin(seed * 5.3) * 71.7) * 2.4
                        let alpha = sin(phase * .pi) * 0.85 * intensity
                        let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                        let color: Color = i % 3 == 0 ? .gold : (i % 3 == 1 ? .ember : .forgePink)
                        context.fill(Path(ellipseIn: rect.insetBy(dx: -radius * 1.5, dy: -radius * 1.5)),
                                     with: .color(color.opacity(alpha * 0.18)))
                        context.fill(Path(ellipseIn: rect), with: .color(color.opacity(alpha)))
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func fract(_ x: Double) -> Double { x - floor(x) }
}

/// A short burst of sparks, played when a secret is copied or saved.
struct SparkBurst: View {
    let trigger: Int
    @State private var start: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { timeline in
            Canvas { context, size in
                guard let start else { return }
                let elapsed = timeline.date.timeIntervalSince(start)
                guard elapsed < 0.9 else { return }
                let p = elapsed / 0.9
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for i in 0..<18 {
                    let angle = Double(i) / 18 * 2 * .pi + Double(trigger)
                    let distance = 20 + 70 * (1 - pow(1 - p, 3))
                    let point = CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance + 30 * p * p)
                    let r = 3 * (1 - p)
                    let color: Color = i.isMultiple(of: 2) ? .gold : .ember
                    context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)),
                                 with: .color(color.opacity(1 - p)))
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            guard !reduceMotion else { return }
            start = Date()
            Task {
                try? await Task.sleep(for: .seconds(1))
                start = nil
            }
        }
        .accessibilityHidden(true)
    }
}
