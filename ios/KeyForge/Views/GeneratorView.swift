import SwiftUI

struct GeneratorView: View {
    @Environment(GeneratorModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(VaultStore.self) private var vault
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Namespace private var modeNamespace
    @State private var spin = 0.0
    @State private var copied = 0
    @State private var saving: VaultItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header.entrance()
                    modePicker.entrance(delay: 0.05)
                    secretCard.entrance(delay: 0.1)
                    actions.entrance(delay: 0.15)
                    options.entrance(delay: 0.2)
                    history.entrance(delay: 0.25)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(ForgeBackground(intensity: 0.8))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Générateur").font(.headline)
                }
            }
            .sheet(item: $saving) { item in
                VaultEditView(item: item, isNew: true) { saved in
                    vault.add(saved)
                    toasts.show("Enregistré dans le coffre", symbol: "lock.shield.fill")
                    Haptics.success()
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            BreathingLogo(size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("Forgez une clé")
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(.white)
                Text("Aléatoire, robuste, sur votre iPhone")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    // MARK: Mode

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(GeneratorMode.allCases) { mode in
                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                        model.mode = mode
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.symbol)
                        Text(mode.title).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(model.mode == mode ? .white : Color.textSecondary)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background {
                        if model.mode == mode {
                            Capsule()
                                .fill(Theme.ember)
                                .matchedGeometryEffect(id: "mode", in: modeNamespace)
                                .shadow(color: .ember.opacity(0.4), radius: 10)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.mode == mode ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.surface))
        .overlay(Capsule().strokeBorder(Color.line))
    }

    // MARK: Secret

    private var secretCard: some View {
        VStack(spacing: 18) {
            SecretText(
                value: model.secret.value,
                font: model.secret.mode == .pin
                    ? .system(size: 40, weight: .bold, design: .monospaced)
                    : .system(.title2, design: .monospaced).weight(.semibold)
            )
            .frame(maxWidth: .infinity, minHeight: 90)
            .padding(.top, 6)
            .overlay { SparkBurst(trigger: copied) }

            StrengthBar(bits: model.secret.entropy)
            StrengthLabel(bits: model.secret.entropy)

            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                Text("Temps de craquage estimé : ")
                    + Text(CrackTime.describe(bits: model.secret.entropy)).bold()
            }
            .font(.footnote)
            .foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentTransition(.interpolate)
            .animation(.snappy, value: model.secret.entropy)
        }
        .forgeCard(padding: 20)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        colors: [.ember, .forgePink, .violet, .gold, .ember],
                        center: .center,
                        angle: .degrees(spin * 2)
                    ),
                    lineWidth: 1.2
                )
                .opacity(0.7)
        )
    }

    // MARK: Actions

    private var actions: some View {
        HStack(alignment: .top) {
            RoundAction(title: "Copier", symbol: copied > 0 ? "checkmark" : "doc.on.doc", tint: .gold, bounce: copied) {
                Clipboard.copy(model.secret.value, expiry: settings.clipboardExpiry)
                copied += 1
                Haptics.success()
                let note = settings.clipboardExpiry == .never ? "" : " · effacé dans \(settings.clipboardExpiry.label)"
                toasts.show("Copié\(note)", symbol: "doc.on.doc.fill")
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = 0
                }
            }
            .frame(maxWidth: .infinity)

            Button {
                Haptics.tap(.medium)
                withAnimation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.6)) {
                    spin += 360
                }
                model.regenerate()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(spin))
                    .frame(width: 84, height: 84)
                    .background(Circle().fill(Theme.ember))
                    .shadow(color: .ember.opacity(0.55), radius: 18, y: 6)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Générer une nouvelle clé")
            .frame(maxWidth: .infinity)

            RoundAction(title: "Enregistrer", symbol: "tray.and.arrow.down.fill", tint: .violet) {
                Haptics.tap()
                saving = VaultItem(title: "", password: model.secret.value)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Options

    @ViewBuilder
    private var options: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(title: "Options", symbol: "slider.horizontal.3")
            switch model.mode {
            case .password:
                LengthSlider(
                    title: "Longueur",
                    value: $model.password.length,
                    range: PasswordOptions.lengthRange,
                    unit: "caractères"
                )
                Divider().overlay(Color.line)
                OptionToggle(title: "Majuscules", detail: "A–Z", isOn: $model.password.uppercase)
                OptionToggle(title: "Minuscules", detail: "a–z", isOn: $model.password.lowercase)
                OptionToggle(title: "Chiffres", detail: "0–9", isOn: $model.password.digits)
                OptionToggle(title: "Symboles", detail: "!@#$%…", isOn: $model.password.symbols)
                OptionToggle(title: "Exclure les caractères ambigus", detail: "0 O o 1 l I |", isOn: $model.password.excludeAmbiguous)
            case .passphrase:
                LengthSlider(
                    title: "Nombre de mots",
                    value: $model.passphrase.wordCount,
                    range: PassphraseOptions.wordRange,
                    unit: "mots"
                )
                Divider().overlay(Color.line)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Séparateur").font(.subheadline.weight(.medium))
                    Picker("Séparateur", selection: $model.passphrase.separator) {
                        ForEach(PassphraseSeparator.allCases) { separator in
                            Text(separator.label).tag(separator)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                OptionToggle(title: "Capitaliser", detail: "Chaque mot commence par une majuscule", isOn: $model.passphrase.capitalize)
                OptionToggle(title: "Ajouter un chiffre", detail: "Un chiffre au hasard dans un mot", isOn: $model.passphrase.includeNumber)
                Label("Liste de \(model.words.words.count) mots français : \(Int(model.words.bitsPerWord)) bits par mot.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
            case .pin:
                LengthSlider(
                    title: "Nombre de chiffres",
                    value: $model.pin.length,
                    range: PinOptions.lengthRange,
                    unit: "chiffres"
                )
                Label("Un code PIN se protège surtout par le nombre d'essais autorisés : réservez-le aux cartes et aux appareils.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .forgeCard()
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: model.mode)
    }

    // MARK: History

    @ViewBuilder
    private var history: some View {
        if !model.history.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Cette session", symbol: "clock")
                ForEach(Array(model.history.prefix(5).enumerated()), id: \.offset) { _, secret in
                    HStack {
                        Text(secret.value)
                            .font(.system(.footnote, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        Circle().fill(secret.strength.color).frame(width: 8, height: 8)
                        Button {
                            Clipboard.copy(secret.value, expiry: settings.clipboardExpiry)
                            Haptics.success()
                            toasts.show("Copié", symbol: "doc.on.doc.fill")
                        } label: {
                            Image(systemName: "doc.on.doc").foregroundStyle(Color.gold)
                        }
                        .accessibilityLabel("Copier")
                    }
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                }
                Text("Effacé dès que l'app passe en arrière-plan.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .forgeCard()
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: model.generation)
        }
    }
}

// MARK: - Controls

struct LengthSlider: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text("\(value)")
                    .font(.title2.monospacedDigit().weight(.heavy))
                    .foregroundStyle(Theme.ember)
                    .contentTransition(.numericText(value: Double(value)))
                    .animation(.snappy, value: value)
                Text(unit).font(.caption).foregroundStyle(Color.textSecondary)
            }
            HStack(spacing: 12) {
                StepButton(symbol: "minus") { if value > range.lowerBound { value -= 1 } }
                Slider(
                    value: Binding(
                        get: { Double(value) },
                        set: { value = Int($0.rounded()) }
                    ),
                    in: Double(range.lowerBound)...Double(range.upperBound),
                    step: 1
                )
                .tint(.ember)
                .accessibilityLabel(title)
                .accessibilityValue("\(value) \(unit)")
                StepButton(symbol: "plus") { if value < range.upperBound { value += 1 } }
            }
        }
        .onChange(of: value) { _, _ in Haptics.selection() }
    }
}

private struct StepButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.surfaceHigh))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(symbol == "plus" ? "Augmenter" : "Diminuer")
    }
}

struct OptionToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(Color.textSecondary)
            }
        }
        .onChange(of: isOn) { _, _ in Haptics.selection() }
        .tint(.ember)
    }
}
