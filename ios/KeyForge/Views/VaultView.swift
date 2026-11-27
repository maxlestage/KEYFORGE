import SwiftUI

struct VaultView: View {
    @Environment(VaultStore.self) private var vault
    @Environment(AppSettings.self) private var settings
    @Environment(ToastCenter.self) private var toasts

    @State private var search = ""
    @State private var editing: VaultItem?

    var body: some View {
        NavigationStack {
            Group {
                if vault.isLocked {
                    LockedVaultView {
                        Task { await vault.unlock(requireAuthentication: settings.biometricLock) }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else if vault.items.isEmpty {
                    EmptyVaultView { editing = VaultItem(title: "", password: Generator.password(PasswordOptions())) }
                        .transition(.opacity)
                } else {
                    list.transition(.opacity)
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: vault.isLocked)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: vault.items.isEmpty)
            .background(ForgeBackground(intensity: 0.6))
            .navigationTitle("Coffre")
            .toolbar {
                if !vault.isLocked {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            Haptics.tap()
                            vault.lock()
                        } label: {
                            Image(systemName: "lock.fill")
                        }
                        .accessibilityLabel("Verrouiller le coffre")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Haptics.tap()
                            editing = VaultItem(title: "", password: Generator.password(PasswordOptions()))
                        } label: {
                            Image(systemName: "plus.circle.fill").font(.title3)
                        }
                        .accessibilityLabel("Ajouter une clé")
                    }
                }
            }
            .sheet(item: $editing) { item in
                VaultEditView(item: item, isNew: !vault.items.contains { $0.id == item.id }) { saved in
                    vault.upsert(saved)
                    toasts.show("Clé enregistrée", symbol: "lock.shield.fill")
                    Haptics.success()
                }
            }
            .task {
                // Asks for Face ID as soon as the tab appears (not after a manual lock).
                if vault.isLocked {
                    await vault.unlock(requireAuthentication: settings.biometricLock)
                }
            }
            .alert(
                "Erreur",
                isPresented: Binding(get: { vault.errorMessage != nil }, set: { if !$0 { vault.errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vault.errorMessage ?? "")
            }
        }
    }

    private var filteredFavorites: [VaultItem] { vault.favorites.filter { $0.matches(search) } }
    private var filteredOthers: [VaultItem] { vault.others.filter { $0.matches(search) } }

    private var list: some View {
        List {
            if !filteredFavorites.isEmpty {
                Section {
                    ForEach(filteredFavorites) { row($0) }
                } header: {
                    Label("Favoris", systemImage: "star.fill").foregroundStyle(Color.gold)
                }
            }
            if !filteredOthers.isEmpty {
                Section {
                    ForEach(filteredOthers) { row($0) }
                } header: {
                    Text("Toutes les clés")
                }
            }
            if filteredFavorites.isEmpty && filteredOthers.isEmpty {
                ContentUnavailableView.search(text: search)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .searchable(text: $search, prompt: "Rechercher une clé")
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: vault.items)
    }

    private func row(_ item: VaultItem) -> some View {
        NavigationLink {
            VaultDetailView(itemID: item.id)
        } label: {
            VaultRow(item: item)
        }
        .listRowBackground(Color.surface.opacity(0.85))
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Haptics.warning()
                vault.delete(item)
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                Haptics.tap()
                vault.toggleFavorite(item)
            } label: {
                Label(item.isFavorite ? "Retirer" : "Favori", systemImage: item.isFavorite ? "star.slash" : "star.fill")
            }
            .tint(.gold)
        }
        .contextMenu {
            Button {
                Clipboard.copy(item.password, expiry: settings.clipboardExpiry)
                toasts.show("Mot de passe copié", symbol: "doc.on.doc.fill")
            } label: {
                Label("Copier le mot de passe", systemImage: "doc.on.doc")
            }
            if !item.username.isEmpty {
                Button {
                    Clipboard.copy(item.username, expiry: .never)
                    toasts.show("Identifiant copié", symbol: "person.fill")
                } label: {
                    Label("Copier l'identifiant", systemImage: "person")
                }
            }
        }
    }
}

struct VaultRow: View {
    let item: VaultItem

    var body: some View {
        HStack(spacing: 14) {
            Text(item.initial)
                .font(.headline.weight(.heavy))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.ember))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title.isEmpty ? "Sans titre" : item.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if item.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.gold)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                let subtitle = item.username.isEmpty ? item.displayHost : item.username
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Circle()
                .fill(PasswordAnalyzer.analyze(item.password).level.color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Locked and empty states

struct LockedVaultView: View {
    let unlock: () -> Void
    @Environment(VaultStore.self) private var vault
    @State private var wiggle = 0

    var body: some View {
        VStack(spacing: 26) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.ember.opacity(0.12))
                    .frame(width: 190, height: 190)
                    .phaseAnimator([1.0, 1.12]) { view, scale in
                        view.scaleEffect(scale)
                    } animation: { _ in .easeInOut(duration: 1.8) }
                Circle()
                    .strokeBorder(Theme.ember, style: StrokeStyle(lineWidth: 2, dash: [6, 10]))
                    .frame(width: 150, height: 150)
                    .phaseAnimator([0.0, 360.0]) { view, angle in
                        view.rotationEffect(.degrees(angle))
                    } animation: { phase in
                        phase == 0 ? nil : .linear(duration: 12)
                    }
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(Theme.ember)
                    .symbolEffect(.bounce, value: wiggle)
            }
            VStack(spacing: 8) {
                Text("Coffre verrouillé")
                    .font(.title2.weight(.bold))
                Text("Vos clés sont chiffrées par Brocolis 🥦 sur cet iPhone : sans Face ID, ce n'est que du charabia.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            Button {
                wiggle += 1
                Haptics.tap(.medium)
                unlock()
            } label: {
                Label("Déverrouiller avec \(BiometricAuth.label)", systemImage: BiometricAuth.symbol)
            }
            .buttonStyle(EmberButtonStyle())
            .padding(.horizontal, 32)
            .disabled(vault.isAuthenticating)
            Spacer()
        }
    }
}

struct EmptyVaultView: View {
    let add: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "key.viewfinder")
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(Theme.ember)
                .symbolEffect(.pulse, options: .repeating)
                .keyframeAnimator(initialValue: 0.0, repeating: true) { view, offset in
                    view.offset(y: offset)
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(-10, duration: 1.2)
                        CubicKeyframe(0, duration: 1.2)
                    }
                }
            Text("Votre coffre est vide")
                .font(.title2.weight(.bold))
            Text("Forgez une clé et enregistrez-la : elle restera chiffrée sur cet appareil.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Button(action: add) {
                Label("Ajouter une clé", systemImage: "plus")
            }
            .buttonStyle(EmberButtonStyle(compact: true))
            Spacer()
        }
    }
}

// MARK: - Detail

struct VaultDetailView: View {
    let itemID: UUID
    @Environment(VaultStore.self) private var vault
    @Environment(AppSettings.self) private var settings
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var revealed = false
    @State private var editing: VaultItem?
    @State private var confirmDelete = false
    @State private var sending = false

    private var item: VaultItem? { vault.items.first { $0.id == itemID } }

    var body: some View {
        Group {
            if let item {
                ScrollView {
                    VStack(spacing: 18) {
                        VStack(spacing: 10) {
                            Text(item.initial)
                                .font(.largeTitle.weight(.heavy))
                                .foregroundStyle(.white)
                                .frame(width: 84, height: 84)
                                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.ember))
                                .shadow(color: .ember.opacity(0.45), radius: 18)
                            Text(item.title.isEmpty ? "Sans titre" : item.title)
                                .font(.title2.weight(.bold))
                            if !item.displayHost.isEmpty {
                                Text(item.displayHost).foregroundStyle(Color.textSecondary)
                            }
                        }
                        .entrance()

                        VStack(alignment: .leading, spacing: 16) {
                            if !item.username.isEmpty {
                                field("Identifiant", value: item.username, symbol: "person.fill") {
                                    copy(item.username, label: "Identifiant copié", expiry: .never)
                                }
                                Divider().overlay(Color.line)
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Mot de passe", systemImage: "key.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.textSecondary)
                                SecretText(value: revealed ? item.password : String(repeating: "•", count: min(item.password.count, 24)))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                StrengthBar(bits: PasswordAnalyzer.analyze(item.password).bits, height: 6)
                                HStack {
                                    Button {
                                        Haptics.tap()
                                        withAnimation(.snappy) { revealed.toggle() }
                                    } label: {
                                        Label(revealed ? "Masquer" : "Afficher", systemImage: revealed ? "eye.slash" : "eye")
                                            .contentTransition(.symbolEffect(.replace))
                                    }
                                    Spacer()
                                    Button {
                                        copy(item.password, label: "Mot de passe copié", expiry: settings.clipboardExpiry)
                                    } label: {
                                        Label("Copier", systemImage: "doc.on.doc")
                                    }
                                }
                                .font(.subheadline.weight(.semibold))
                            }
                            if !item.website.isEmpty {
                                Divider().overlay(Color.line)
                                field("Site web", value: item.website, symbol: "globe") {
                                    copy(item.website, label: "Adresse copiée", expiry: .never)
                                }
                            }
                            if !item.notes.isEmpty {
                                Divider().overlay(Color.line)
                                VStack(alignment: .leading, spacing: 6) {
                                    Label("Notes", systemImage: "note.text")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.textSecondary)
                                    Text(item.notes)
                                }
                            }
                        }
                        .forgeCard()
                        .entrance(delay: 0.08)

                        Button {
                            Haptics.tap()
                            sending = true
                        } label: {
                            Label("Envoyer avec Brocolis 🥦", systemImage: "paperplane.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(EmberButtonStyle())
                        .accessibilityHint("Chiffre ce mot de passe pour le paquet de clés d'un destinataire")
                        .entrance(delay: 0.12)

                        Text("Modifié le \(item.updatedAt.formatted(date: .long, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(20)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                editing = item
                            } label: {
                                Label("Modifier", systemImage: "pencil")
                            }
                            Button {
                                sending = true
                            } label: {
                                Label("Envoyer avec Brocolis", systemImage: "paperplane")
                            }
                            Button {
                                vault.toggleFavorite(item)
                            } label: {
                                Label(item.isFavorite ? "Retirer des favoris" : "Ajouter aux favoris", systemImage: "star")
                            }
                            Button(role: .destructive) {
                                confirmDelete = true
                            } label: {
                                Label("Supprimer", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                .confirmationDialog("Supprimer cette clé ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Supprimer", role: .destructive) {
                        Haptics.warning()
                        vault.delete(item)
                        dismiss()
                    }
                } message: {
                    Text("Elle sera effacée du trousseau. Cette action est définitive.")
                }
            } else {
                ContentUnavailableView("Clé introuvable", systemImage: "key.slash")
            }
        }
        .background(ForgeBackground(intensity: 0.5))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $sending) {
            if let item {
                SendEncryptedView(secret: item.password, subject: item.title.isEmpty ? nil : item.title)
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $editing) { item in
            VaultEditView(item: item, isNew: false) { saved in
                vault.upsert(saved)
                toasts.show("Modifications enregistrées")
            }
        }
    }

    private func field(_ title: String, value: String, symbol: String, copy: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                Text(value).textSelection(.enabled)
            }
            Spacer()
            Button(action: copy) {
                Image(systemName: "doc.on.doc").foregroundStyle(Color.gold)
            }
            .accessibilityLabel("Copier \(title.lowercased())")
        }
    }

    private func copy(_ value: String, label: String, expiry: ClipboardExpiry) {
        Clipboard.copy(value, expiry: expiry)
        Haptics.success()
        toasts.show(label, symbol: "doc.on.doc.fill")
    }
}

// MARK: - Edit

struct VaultEditView: View {
    @State var item: VaultItem
    let isNew: Bool
    let onSave: (VaultItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showPassword = true
    @State private var spin = 0.0

    var body: some View {
        NavigationStack {
            Form {
                Section("Compte") {
                    TextField("Titre (ex. Banque)", text: $item.title)
                        .textInputAutocapitalization(.sentences)
                    TextField("Identifiant ou e-mail", text: $item.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                    TextField("Site web", text: $item.website)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                Section {
                    HStack {
                        Group {
                            if showPassword {
                                TextField("Mot de passe", text: $item.password)
                            } else {
                                SecureField("Mot de passe", text: $item.password)
                            }
                        }
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(showPassword ? "Masquer" : "Afficher")
                    }
                    StrengthBar(bits: PasswordAnalyzer.analyze(item.password).bits, height: 6)
                    Button {
                        Haptics.tap(.medium)
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) { spin += 360 }
                        item.password = Generator.password(PasswordOptions())
                    } label: {
                        Label {
                            Text("Générer un mot de passe")
                        } icon: {
                            Image(systemName: "arrow.triangle.2.circlepath").rotationEffect(.degrees(spin))
                        }
                    }
                } header: {
                    Text("Mot de passe")
                } footer: {
                    Text("20 caractères, majuscules, minuscules, chiffres et symboles.")
                }
                Section("Notes") {
                    TextField("Notes", text: $item.notes, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    Toggle(isOn: $item.isFavorite) {
                        Label("Favori", systemImage: "star.fill")
                    }
                    .tint(.gold)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ink)
            .navigationTitle(isNew ? "Nouvelle clé" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        var saved = item
                        saved.title = saved.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(saved)
                        dismiss()
                    }
                    .bold()
                    .disabled(item.title.trimmingCharacters(in: .whitespaces).isEmpty || item.password.isEmpty)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}
