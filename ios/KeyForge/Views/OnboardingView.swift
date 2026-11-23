import SwiftUI

/// Three pages on the first launch: Forgez, Protégez, Vérifiez.
struct OnboardingView: View {
    let onFinish: () -> Void

    private struct PageInfo: Identifiable {
        let id: Int
        let symbol: String
        let title: String
        let text: String
        let colors: [Color]
    }

    private let pages = [
        PageInfo(
            id: 0, symbol: "wand.and.stars", title: "Forgez",
            text: "Des mots de passe, phrases de passe et codes PIN tirés d'un générateur cryptographique, en un geste.",
            colors: [.gold, .ember]
        ),
        PageInfo(
            id: 1, symbol: "lock.shield.fill", title: "Protégez",
            text: "Rangez vos clés dans un coffre ouvert par Face ID, et partagez-les chiffrées en post-quantique (Brocolis 🥦, X25519 + ML-KEM-768).",
            colors: [.ember, .forgePink]
        ),
        PageInfo(
            id: 2, symbol: "gauge.with.needle.fill", title: "Vérifiez",
            text: "Testez la robustesse d'un mot de passe, sans réseau : entropie, temps de craquage et conseils.",
            colors: [.forgePink, .violet]
        ),
    ]

    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForgeBackground(intensity: 1.2)
            VStack(spacing: 0) {
                HStack {
                    LogoMark(size: 36)
                    Text("KeyForge").font(.headline).foregroundStyle(.white)
                    Spacer()
                    if page < pages.count - 1 {
                        Button("Passer", action: onFinish)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                TabView(selection: $page) {
                    ForEach(pages) { info in
                        OnboardingPage(
                            symbol: info.symbol, title: info.title, text: info.text,
                            colors: info.colors, isCurrent: page == info.id
                        )
                        .tag(info.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 8) {
                    ForEach(pages) { info in
                        Capsule()
                            .fill(page == info.id ? AnyShapeStyle(Theme.ember) : AnyShapeStyle(Color.white.opacity(0.2)))
                            .frame(width: page == info.id ? 28 : 8, height: 8)
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: page)
                .padding(.bottom, 24)
                .accessibilityHidden(true)

                Button {
                    Haptics.tap(.medium)
                    if page < pages.count - 1 {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { page += 1 }
                    } else {
                        onFinish()
                    }
                } label: {
                    HStack {
                        Text(page < pages.count - 1 ? "Continuer" : "Commencer")
                            .contentTransition(.interpolate)
                        Image(systemName: page < pages.count - 1 ? "arrow.right" : "sparkles")
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .buttonStyle(EmberButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .animation(.snappy, value: page)
            }
        }
    }
}

private struct OnboardingPage: View {
    let symbol: String
    let title: String
    let text: String
    let colors: [Color]
    let isCurrent: Bool
    @State private var ring = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                // Rings that spread out like heat waves.
                ForEach(0..<3) { index in
                    Circle()
                        .stroke(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom), lineWidth: 2)
                        .frame(width: 150, height: 150)
                        .scaleEffect(ring ? 1.9 : 1)
                        .opacity(ring ? 0 : 0.7)
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: 2.6).repeatForever(autoreverses: false).delay(Double(index) * 0.85),
                            value: ring
                        )
                }
                Circle()
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 150, height: 150)
                    .shadow(color: colors[0].opacity(0.6), radius: 30)
                Image(systemName: symbol)
                    .font(.system(size: 62, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: isCurrent)
                    .keyframeAnimator(initialValue: 0.0, trigger: isCurrent) { view, angle in
                        view.rotationEffect(.degrees(angle))
                    } keyframes: { _ in
                        KeyframeTrack {
                            SpringKeyframe(-12, duration: 0.25)
                            SpringKeyframe(10, duration: 0.25)
                            SpringKeyframe(0, duration: 0.4)
                        }
                    }
            }
            .frame(height: 300)
            .scaleEffect(isCurrent ? 1 : 0.8)
            .opacity(isCurrent ? 1 : 0.4)
            .animation(.spring(response: 0.6, dampingFraction: 0.7), value: isCurrent)

            VStack(spacing: 14) {
                Text(title)
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [Color.white] + colors, startPoint: .leading, endPoint: .trailing))
                Text(text)
                    .font(.body)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .offset(y: isCurrent || reduceMotion ? 0 : 30)
            .opacity(isCurrent ? 1 : 0)
            .animation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.1), value: isCurrent)
            Spacer()
        }
        .onAppear { ring = true }
        .accessibilityElement(children: .combine)
    }
}
