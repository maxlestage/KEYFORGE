import SwiftUI

/// Tests a password typed by the user. Nothing is stored nor sent anywhere.
struct AnalyzerView: View {
    @State private var password = ""
    @State private var visible = false
    @FocusState private var focused: Bool

    private var analysis: PasswordAnalysis { PasswordAnalyzer.analyze(password) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    input.entrance()
                    gauge.entrance(delay: 0.06)
                    criteria.entrance(delay: 0.12)
                    tips.entrance(delay: 0.18)
                    Label("Analyse 100 % locale : rien n'est enregistré ni envoyé.", systemImage: "wifi.slash")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .entrance(delay: 0.24)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(ForgeBackground(intensity: 0.6))
            .navigationTitle("Analyse")
            .onTapGesture { focused = false }
            .onDisappear { password = "" }
        }
    }

    private var input: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .foregroundStyle(Theme.ember)
            Group {
                if visible {
                    TextField("Tapez un mot de passe", text: $password)
                } else {
                    SecureField("Tapez un mot de passe", text: $password)
                }
            }
            .font(.system(.body, design: .monospaced))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focused)
            .submitLabel(.done)
            if !password.isEmpty {
                Button {
                    withAnimation(.snappy) { password = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.textSecondary)
                }
                .accessibilityLabel("Effacer")
                .transition(.scale.combined(with: .opacity))
            }
            Button {
                visible.toggle()
            } label: {
                Image(systemName: visible ? "eye.slash.fill" : "eye.fill")
                    .foregroundStyle(Color.gold)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(visible ? "Masquer" : "Afficher")
        }
        .forgeCard(padding: 16)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .strokeBorder(focused ? AnyShapeStyle(Theme.ember) : AnyShapeStyle(Color.clear), lineWidth: 1.5)
        )
        .animation(.snappy, value: focused)
        .animation(.snappy, value: password.isEmpty)
    }

    private var gauge: some View {
        let analysis = self.analysis
        let level = analysis.level
        let progress = password.isEmpty ? 0 : StrengthLevel.progress(bits: analysis.bits)
        return VStack(spacing: 16) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle()
                    .trim(from: 0, to: 0.75 * progress)
                    .stroke(
                        AngularGradient(colors: [.forgePink, .ember, .gold, level.color], center: .center, startAngle: .degrees(0), endAngle: .degrees(270)),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .rotationEffect(.degrees(135))
                    .shadow(color: level.color.opacity(0.5), radius: 10)
                VStack(spacing: 4) {
                    Text("\(Int(analysis.bits.rounded()))")
                        .font(.system(size: 52, weight: .heavy, design: .rounded))
                        .contentTransition(.numericText(value: analysis.bits))
                    Text("bits d'entropie")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .frame(width: 210, height: 210)
            .padding(.top, 8)

            if password.isEmpty {
                Text("Votre mot de passe tient-il le choc ?")
                    .font(.headline)
                    .foregroundStyle(Color.textSecondary)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: level.symbol)
                        .contentTransition(.symbolEffect(.replace))
                    Text(level.title).contentTransition(.interpolate)
                }
                .font(.title3.weight(.bold))
                .foregroundStyle(level.color)
                .modifier(Shake(amount: analysis.isCommon ? 1 : 0))

                VStack(spacing: 2) {
                    Text("Craqué en moyenne en")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text(analysis.crackTime)
                        .font(.headline)
                        .contentTransition(.interpolate)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .forgeCard()
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: analysis.bits)
        .accessibilityElement(children: .combine)
    }

    private var criteria: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Critères", symbol: "checklist")
            ForEach(Criterion.allCases) { criterion in
                let ok = !password.isEmpty && analysis.passed.contains(criterion)
                HStack(spacing: 12) {
                    AnimatedCheck(checked: ok)
                    Text(criterion.title)
                        .font(.subheadline)
                        .foregroundStyle(ok ? .white : Color.textSecondary)
                    Spacer()
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(ok ? "respecté" : "non respecté")
            }
        }
        .forgeCard()
    }

    @ViewBuilder
    private var tips: some View {
        if !password.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Conseils", symbol: "lightbulb.fill")
                ForEach(analysis.suggestions, id: \.self) { tip in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "sparkle").foregroundStyle(Color.gold)
                        Text(tip).font(.subheadline)
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .forgeCard()
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: analysis.suggestions)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}

/// A horizontal shake, for a very common password.
private struct Shake: ViewModifier, Animatable {
    var amount: Double

    var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }

    func body(content: Content) -> some View {
        content.offset(x: sin(amount * .pi * 6) * 8)
    }
}
