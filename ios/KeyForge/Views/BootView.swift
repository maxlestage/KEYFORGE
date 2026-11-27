import SwiftUI

/// Une ligne de la séquence de démarrage : ce qui vient d'être vérifié, et son état.
struct BootStep: Identifiable, Equatable {
    let id: Int
    let symbol: String
    let label: String
    let status: String
    var ok = true
}

/// L'écran de démarrage : le logo de l'écran de lancement d'iOS, repris au même endroit,
/// s'allume pendant que KeyForge annonce ce qu'il a amorcé (hasard, liste de mots,
/// coffre, clé), puis laisse la place à l'app. Un toucher l'abrège.
struct BootView: View {
    /// La taille du logo, celle de l'image de lancement (`LaunchLogo`, 120 pt).
    static let logoSize: CGFloat = 120

    let steps: [BootStep]
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = 0
    @State private var lit = false
    @State private var burst = 0
    @State private var finished = false

    var body: some View {
        ZStack {
            Color.ink
            ForgeBackground(intensity: 0.7)
                .opacity(lit ? 1 : 0)
            // Le logo reste au centre exact de l'écran, comme sur l'écran de lancement.
            LogoMark(size: Self.logoSize, animated: lit)
                .scaleEffect(lit ? 1.04 : 1)
                .overlay { SparkBurst(trigger: burst).frame(width: 320, height: 320) }
                .overlay(alignment: .center) {
                    sequence
                        .fixedSize()
                        // Le haut du bloc se place sous le logo, sans le déplacer.
                        .alignmentGuide(VerticalAlignment.center) { $0[.top] - Self.logoSize / 2 - 32 }
                }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: finish)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("KeyForge démarre")
        .accessibilityAddTraits(.isButton)
        .task { await run() }
    }

    private var sequence: some View {
        VStack(spacing: 14) {
            Text("KeyForge")
                .font(.title.weight(.heavy))
                .foregroundStyle(.white)
                .opacity(lit ? 1 : 0)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(steps) { step in
                    HStack(spacing: 8) {
                        Image(systemName: step.symbol)
                            .frame(width: 18)
                            .foregroundStyle(Color.textSecondary)
                        Text(step.label)
                            .foregroundStyle(Color.textSecondary)
                        Text(step.status)
                            .foregroundStyle(step.ok ? Color.mint : Color.gold)
                        Image(systemName: step.ok ? "checkmark" : "exclamationmark.triangle.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(step.ok ? Color.mint : Color.gold)
                    }
                    .font(.system(.footnote, design: .monospaced))
                    .opacity(step.id < revealed ? 1 : 0)
                    .offset(y: step.id < revealed ? 0 : 6)
                }
            }
        }
    }

    /// La séquence : le logo s'allume, les lignes arrivent une à une, puis l'app.
    private func run() async {
        if reduceMotion {
            lit = true
            revealed = steps.count
            try? await Task.sleep(for: .milliseconds(650))
            finish()
            return
        }
        try? await Task.sleep(for: .milliseconds(120))
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { lit = true }
        burst += 1
        for index in steps.indices {
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeOut(duration: 0.2)) { revealed = index + 1 }
        }
        try? await Task.sleep(for: .milliseconds(420))
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinished()
    }
}
