import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(VaultStore.self) private var vault
    @Environment(ToastCenter.self) private var toasts
    @State private var confirmErase = false
    @State private var backupMode: BackupView.Mode?
    @State private var composing = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    /// Auteur de KeyForge, affiché dans « À propos » (le même que sur le site).
    static let author = "Maxime Nathan Lestage"

    /// Où en est la clé du coffre, et pourquoi quand la Secure Enclave ne l'a pas prise.
    private var enclaveDetail: String {
        if vault.isEnclaveProtected {
            return "Libérée seulement après \(BiometricAuth.label) ou le code de l'iPhone"
        }
        if let issue = vault.enclaveIssue { return issue }
        if !settings.biometricLock {
            return "Activez le verrouillage biométrique pour la confier à la Secure Enclave"
        }
        return vault.isSealed
            ? "Elle rejoint la Secure Enclave à la prochaine ouverture du coffre"
            : "Elle rejoindra la Secure Enclave dès la première entrée"
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
                    .onChange(of: settings.biometricLock) { _, enabled in
                        Task {
                            // Couper le verrouillage sort la clé de la Secure Enclave :
                            // refusé sans authentification, le réglage reste actif.
                            if !(await vault.setEnclaveProtection(enabled)) { settings.biometricLock = true }
                        }
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
                    Text("Le coffre demande \(BiometricAuth.label) à chaque ouverture et se verrouille dès que l'app passe en arrière-plan. Avec ce verrouillage, la clé du coffre est gardée par la Secure Enclave, la puce de sécurité de l'iPhone, qui ne la libère qu'à vous. Les copies restent sur cet appareil (pas de presse-papiers universel).")
                }
                .listRowBackground(Color.surface)

                AutoFillSection()

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
                    Button {
                        composing = true
                    } label: {
                        HStack(spacing: 12) {
                            Text("🥦").font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Envoyer avec Brocolis").font(.headline).foregroundStyle(.white)
                                Text("Un mot de passe, un code, un secret : chiffré pour un seul destinataire")
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    NavigationLink {
                        IdentityView()
                    } label: {
                        Label("Mon identité Brocolis", systemImage: "atom")
                    }
                    NavigationLink {
                        ReceiveEncryptedView()
                    } label: {
                        Label("Recevoir un message Brocolis", systemImage: "envelope.open.fill")
                    }
                } header: {
                    Text("Brocolis 🥦 · chiffrement post-quantique")
                } footer: {
                    Text("Protocole Brocolis v4 🥦 : X25519 + ML-KEM-768. Un secret envoyé reste protégé tant que l'une des deux protections tient, même face à un ordinateur quantique. Votre identité ne quitte pas cet iPhone.")
                }
                .listRowBackground(Color.surface)

                Section {
                    Button {
                        backupMode = .exporting
                    } label: {
                        Label("Exporter le coffre chiffré", systemImage: "lock.doc.fill")
                    }
                    Button {
                        backupMode = .importing
                    } label: {
                        Label("Importer une sauvegarde", systemImage: "square.and.arrow.down.on.square.fill")
                    }
                } header: {
                    Text("Sauvegarde chiffrée")
                } footer: {
                    Text("Format Brocolis 🥦 v4, compatible avec les apps Brocolis : votre coffre est chiffré sur cet iPhone (Argon2id, puis une clé de 256 bits résistante aux ordinateurs quantiques) avec une phrase que vous seul connaissez. Le fichier se garde où vous voulez.")
                }
                .listRowBackground(Color.surface)

                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vault.isSealed ? "Chiffré par Brocolis 🥦" : "Vide : chiffré par Brocolis 🥦 dès la première entrée")
                                .foregroundStyle(.white)
                            Text("Protocole v4, AES-256-GCM, clé de 256 bits propre au coffre")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    } icon: {
                        Image(systemName: "lock.shield.fill").foregroundStyle(Color.green)
                    }
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vault.isEnclaveProtected ? "Clé gardée par la Secure Enclave" : "Clé dans le trousseau de cet iPhone")
                                .foregroundStyle(.white)
                            Text(enclaveDetail)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    } icon: {
                        Image(systemName: vault.isEnclaveProtected ? "cpu.fill" : "key.fill")
                            .foregroundStyle(vault.isEnclaveProtected ? Color.green : Color.gold)
                    }
                    Button(role: .destructive) {
                        confirmErase = true
                    } label: {
                        Label("Effacer le coffre", systemImage: "trash.fill")
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Coffre")
                } footer: {
                    Text("Sur cet iPhone, le coffre n'est jamais rangé en clair : c'est du charabia au format Brocolis, que seule sa clé déchiffre. Cette clé ne quitte pas l'appareil (ni iCloud, ni sauvegarde) et, gardée par la Secure Enclave, elle n'est libérée qu'après \(BiometricAuth.label) ou le code : lire le trousseau ne suffit pas. Elle dépend du code de l'iPhone : gardez une sauvegarde chiffrée. Effacer le coffre supprime toutes les entrées et cette clé.")
                }
                .listRowBackground(Color.surface)

                Section {
                    LabeledContent("Version", value: version)
                    LabeledContent {
                        Text(Self.author)
                    } label: {
                        Label("Créé par", systemImage: "person.fill")
                    }
                    Label("Aucune donnée ne quitte votre iPhone sans votre accord", systemImage: "iphone.and.arrow.forward")
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
                } header: {
                    Text("À propos")
                } footer: {
                    Text("© 2026 \(Self.author). Tous droits réservés.")
                }
                .listRowBackground(Color.surface)
            }
            .scrollContentBackground(.hidden)
            .background(ForgeBackground(intensity: 0.4))
            .navigationTitle("Réglages")
            .sheet(isPresented: $composing) {
                SendEncryptedView()
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $backupMode) { mode in
                BackupView(mode: mode)
                    .presentationDragIndicator(.visible)
            }
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
