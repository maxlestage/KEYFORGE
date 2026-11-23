import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(VaultStore.self) private var vault
    @Environment(ToastCenter.self) private var toasts
    @State private var confirmErase = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        BreathingLogo(size: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("KeyForge").font(.title3.weight(.bold))
                            Text("Forgez des clés incassables.")
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.surface)

                Section {
                    Toggle(isOn: $settings.biometricLock) {
                        Label("Verrouillage biométrique", systemImage: BiometricAuth.symbol)
                    }
                    Picker(selection: $settings.clipboardExpiry) {
                        ForEach(ClipboardExpiry.allCases) { expiry in
                            Text(expiry.label).tag(expiry)
                        }
                    } label: {
                        Label("Effacer le presse-papiers", systemImage: "doc.on.clipboard")
                    }
                } header: {
                    Text("Sécurité")
                } footer: {
                    Text("Le coffre demande \(BiometricAuth.label) à chaque ouverture et se verrouille dès que l'app passe en arrière-plan. Les copies restent sur cet appareil (pas de presse-papiers universel).")
                }
                .listRowBackground(Color.surface)

                Section("Générateur") {
                    Picker(selection: $settings.defaultMode) {
                        ForEach(GeneratorMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.symbol).tag(mode)
                        }
                    } label: {
                        Label("Mode par défaut", systemImage: "wand.and.stars")
                    }
                    Toggle(isOn: $settings.haptics) {
                        Label("Retours haptiques", systemImage: "hand.tap.fill")
                    }
                }
                .listRowBackground(Color.surface)

                Section {
                    Button(role: .destructive) {
                        confirmErase = true
                    } label: {
                        Label("Effacer le coffre", systemImage: "trash.fill")
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Coffre")
                } footer: {
                    Text("Supprime toutes les clés enregistrées dans le trousseau de cet iPhone.")
                }
                .listRowBackground(Color.surface)

                Section("À propos") {
                    LabeledContent("Version", value: version)
                    Label("Aucune donnée ne quitte votre iPhone", systemImage: "iphone.and.arrow.forward")
                        .foregroundStyle(.white)
                    Label("Aucun compte, aucun traceur, aucune publicité", systemImage: "eye.slash.fill")
                    if let url = URL(string: "https://github.com/maxlestage/KEYFORGE") {
                        Link(destination: url) {
                            Label("Site web de KeyForge", systemImage: "safari.fill")
                        }
                    }
                    Button {
                        settings.onboardingDone = false
                    } label: {
                        Label("Revoir la présentation", systemImage: "sparkles")
                    }
                }
                .listRowBackground(Color.surface)
            }
            .scrollContentBackground(.hidden)
            .background(ForgeBackground(intensity: 0.4))
            .navigationTitle("Réglages")
            .confirmationDialog("Effacer tout le coffre ?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Tout effacer", role: .destructive) {
                    Task {
                        // The owner confirms with Face ID before everything is erased.
                        if await BiometricAuth.authenticate(reason: "Confirmez l'effacement du coffre") {
                            vault.eraseAll()
                            Haptics.warning()
                            toasts.show("Coffre effacé", symbol: "trash.fill")
                        }
                    }
                }
            } message: {
                Text("Toutes les clés seront supprimées définitivement.")
            }
        }
    }
}
