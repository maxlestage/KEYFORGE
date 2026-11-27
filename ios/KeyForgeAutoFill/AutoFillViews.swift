import SwiftUI

/// L'écran de l'extension, aux couleurs de la forge.
struct AutoFillRootView: View {
    @Bindable var model: AutoFillModel

    var body: some View {
        NavigationStack {
            content
                .background(Color.ink.ignoresSafeArea())
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") { model.onCancel?() }
                            .tint(.white)
                    }
                }
                .toolbarBackground(Color.ink, for: .navigationBar)
        }
        .tint(.ember)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        switch model.request {
        case .insertText:
            ForgeInsertView { model.onInsert?($0) }
                .navigationTitle("Forger un secret")
                .navigationBarTitleDisplayMode(.inline)
        case .configuration:
            ConfiguredView { model.onConfigured?() }
        case .list, .single, .codes, .singleCode:
            switch model.phase {
            case .ready:
                CredentialListView(model: model)
                    .navigationTitle(model.siteName ?? (model.wantsCode ? "Codes de validation" : "KeyForge"))
                    .navigationBarTitleDisplayMode(.inline)
            case .failed(let message):
                MessageView(symbol: "exclamationmark.triangle.fill", title: "Coffre indisponible", message: message)
            case .locked, .unlocking:
                LockedView(isUnlocking: model.phase == .unlocking) {
                    Task { await model.unlock() }
                }
            }
        }
    }
}

// MARK: Verrouillé

private struct LockedView: View {
    let isUnlocking: Bool
    let unlock: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: BiometricAuth.symbol)
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(Theme.ember)
                .symbolEffect(.pulse, isActive: isUnlocking)
            Text("Coffre KeyForge verrouillé")
                .font(.title3.bold())
            Text("Déverrouillez-le pour remplir ce champ.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Button(action: unlock) {
                Label("Déverrouiller avec \(BiometricAuth.label)", systemImage: BiometricAuth.symbol)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.ember, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
            }
            .disabled(isUnlocking)
            .padding(.horizontal, 32)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Liste

private struct CredentialListView: View {
    @Bindable var model: AutoFillModel

    var body: some View {
        let sections = model.sections
        List {
            if !sections.suggested.isEmpty {
                Section("Pour ce site") {
                    ForEach(sections.suggested) { row($0) }
                }
            }
            if !sections.others.isEmpty {
                Section(sections.suggested.isEmpty
                    ? (model.wantsCode ? "Vos codes de validation" : "Votre coffre")
                    : (model.wantsCode ? "Autres codes" : "Autres identifiants")) {
                    ForEach(sections.others) { row($0) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .searchable(text: $model.search, prompt: "Rechercher dans le coffre")
        .overlay {
            if sections.suggested.isEmpty && sections.others.isEmpty {
                if model.wantsCode && model.search.isEmpty {
                    MessageView(
                        symbol: "clock.badge.checkmark",
                        title: "Aucun code de validation",
                        message: "Ajoutez un code de validation à une entrée dans l'app KeyForge : il apparaîtra ici."
                    )
                } else {
                    MessageView(
                        symbol: model.items.isEmpty ? "tray" : "magnifyingglass",
                        title: model.items.isEmpty ? "Coffre vide" : "Aucun résultat",
                        message: model.items.isEmpty
                            ? "Enregistrez vos identifiants dans l'app KeyForge : ils apparaîtront ici."
                            : "Aucune entrée ne correspond à « \(model.search) »."
                    )
                }
            }
        }
    }

    private func row(_ item: VaultItem) -> some View {
        Button {
            model.choose(item)
        } label: {
            HStack(spacing: 14) {
                Text(item.initial)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.ember, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.title.isEmpty ? item.displayHost : item.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                        if item.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.gold)
                        }
                    }
                    Text(item.username.isEmpty ? item.displayHost : item.username)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
                .lineLimit(1)
                Spacer()
                if model.wantsCode, let generator = item.oneTimeCode {
                    // Le code du moment, rafraîchi chaque seconde.
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        Text(generator.displayCode(at: timeline.date))
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .foregroundStyle(Color.gold)
                            .contentTransition(.numericText())
                    }
                } else {
                    Image(systemName: "key.fill")
                        .foregroundStyle(Color.ember)
                }
            }
            .contentShape(Rectangle())
        }
        .listRowBackground(Color.surface)
        .accessibilityLabel("\(item.title), \(item.username)")
        .accessibilityHint(model.wantsCode ? "Remplit le code de validation" : "Remplit cet identifiant et son mot de passe")
    }
}

// MARK: Forger et insérer

private struct ForgeInsertView: View {
    let insert: (String) -> Void
    @State private var mode: GeneratorMode = .password
    @State private var secret = ""
    @State private var bits = 0.0

    var body: some View {
        VStack(spacing: 20) {
            Picker("Type", selection: $mode) {
                ForEach(GeneratorMode.allCases) { Text($0.shortTitle).tag($0) }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 12) {
                Text(secret)
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.numericText())
                let level = StrengthLevel(bits: bits)
                Label("\(level.title) · \(Int(bits.rounded())) bits", systemImage: level.symbol)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(level.color)
            }
            .forgeCard()

            HStack(spacing: 12) {
                Button {
                    forge()
                } label: {
                    Label("Reforger", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.surfaceHigh, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Button {
                    insert(secret)
                } label: {
                    Label("Insérer", systemImage: "text.insert")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.ember, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .foregroundStyle(.white)

            Text("Pensez à enregistrer ce nouveau mot de passe dans votre coffre KeyForge.")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(20)
        .onAppear(perform: forge)
        .onChange(of: mode) { forge() }
    }

    /// Le même moteur que l'app, avec ses réglages par défaut.
    private func forge() {
        switch mode {
        case .password:
            let options = PasswordOptions()
            secret = Generator.password(options)
            bits = Generator.passwordEntropy(options)
        case .passphrase:
            let options = PassphraseOptions()
            secret = Generator.passphrase(options, words: .bundled)
            bits = Generator.passphraseEntropy(options, words: .bundled)
        case .pin:
            let options = PinOptions()
            secret = Generator.pin(options)
            bits = Generator.pinEntropy(options)
        case .gibberish:
            let options = GibberishOptions()
            secret = Generator.gibberish(options)
            bits = Generator.gibberishEntropy(options)
        }
    }
}

// MARK: Configuration et messages

private struct ConfiguredView: View {
    let done: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(Theme.ember)
            Text("KeyForge remplit vos mots de passe")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text("Vos identifiants KeyForge sont proposés au-dessus du clavier, dans Safari et dans vos apps. Chaque mot de passe reste dans le coffre et n'en sort qu'après \(BiometricAuth.label).")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Button(action: done) {
                Text("Terminé")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.ember, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
            }
            .padding(.top, 8)
            Spacer()
        }
        .padding(28)
    }
}

private struct MessageView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 40))
                .foregroundStyle(Color.textSecondary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
