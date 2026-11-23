import SwiftUI
import UniformTypeIdentifiers

/// La sauvegarde chiffrée du coffre, au format Brocolis 🥦 : exporter (une phrase,
/// Argon2id, un fichier à garder où l'on veut) ou importer (coller ou ouvrir le
/// fichier, la phrase, et les clés reviennent dans le coffre).
struct BackupView: View {
    enum Mode: String, Identifiable {
        case exporting, importing
        var id: String { rawValue }
    }

    let mode: Mode

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    switch mode {
                    case .exporting: ExportPane()
                    case .importing: ImportPane()
                    }
                    BrocolisBadge()
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(ForgeBackground(intensity: 0.5))
            .navigationTitle(mode == .exporting ? "Exporter le coffre" : "Importer une sauvegarde")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Modèle

/// L'état d'une opération longue (Argon2id), partagé entre l'écran et la tâche de fond.
@MainActor
@Observable
final class BackupTask {
    enum Phase: Equatable {
        case idle
        case working
        case done(String)
        case failed(String)
    }

    var phase: Phase = .idle
    var progress = 0.0

    var isWorking: Bool { phase == .working }

    /// Lance `work` hors du fil principal ; l'animation dure au moins 0,9 s pour
    /// qu'on la voie, même quand Argon2id est plus rapide.
    func run<T: Sendable>(
        _ work: @escaping @Sendable (_ progress: @escaping @Sendable (Double) -> Void) throws -> T
    ) async -> Result<T, Error> {
        phase = .working
        progress = 0
        let report: @Sendable (Double) -> Void = { [weak self] value in
            Task { @MainActor in
                withAnimation(.easeOut(duration: 0.25)) { self?.progress = value }
            }
        }
        let start = ContinuousClock.now
        let result = await Task.detached(priority: .userInitiated) {
            Result { try work(report) }
        }.value
        let elapsed = ContinuousClock.now - start
        if elapsed < .milliseconds(900) {
            try? await Task.sleep(for: .milliseconds(900) - elapsed)
        }
        withAnimation(.easeOut(duration: 0.2)) { progress = 1 }
        return result
    }
}

// MARK: - Exporter

private struct ExportPane: View {
    @Environment(VaultStore.self) private var vault
    @Environment(AppSettings.self) private var settings
    @State private var job = BackupTask()
    @State private var phrase = ""
    @State private var reveal = false
    @State private var generated: (phrase: String, bits: Double)?
    @State private var backup = ""
    @State private var fileURL: URL?
    @State private var count = 0
    @State private var copied = false

    private var bits: Double {
        if let generated, generated.phrase == phrase { return generated.bits }
        return PasswordAnalyzer.analyze(phrase).bits
    }

    private var phraseOK: Bool {
        phrase.unicodeScalars.count >= Brocolis.phraseMinimum
    }

    var body: some View {
        VStack(spacing: 18) {
            if case .done = job.phase {
                result
                    .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .opacity))
            } else if job.isWorking {
                ForgingProgress(progress: job.progress, caption: "Argon2id · \(BrocolisArgon2Params.standard.summary)")
                    .transition(.opacity)
            } else {
                form.transition(.opacity)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: job.phase)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Une phrase pour tout protéger", systemImage: "key.horizontal.fill")
                .font(.headline)
            Text("Votre coffre est chiffré avec une clé aléatoire de 256 bits, elle-même protégée par cette phrase (Argon2id puis AES-256-GCM), dans le format Brocolis v4. Sans la phrase, la sauvegarde est illisible : notez-la en lieu sûr.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)

            PhraseField(phrase: $phrase, reveal: $reveal, placeholder: "Phrase de la sauvegarde")

            Button {
                let options = PassphraseOptions(wordCount: 6, separator: .hyphen, capitalize: true, includeNumber: true)
                let new = Generator.passphrase(options, words: .bundled)
                generated = (new, Generator.passphraseEntropy(options, words: .bundled))
                phrase = new
                reveal = true
                Haptics.tap(.medium)
            } label: {
                Label("Générer une phrase de passe", systemImage: "wand.and.stars")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(PressableStyle())
            .foregroundStyle(Color.gold)

            if !phrase.isEmpty {
                VStack(spacing: 8) {
                    StrengthBar(bits: bits)
                    StrengthLabel(bits: bits)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if case .failed(let message) = job.phase {
                ErrorLine(message: message)
            }

            Button {
                Task { await export() }
            } label: {
                Label("Chiffrer et exporter", systemImage: "lock.doc.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(EmberButtonStyle())
            .disabled(!phraseOK)
            .opacity(phraseOK ? 1 : 0.5)

            if !phraseOK && !phrase.isEmpty {
                Text("Au moins \(Brocolis.phraseMinimum) caractères.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .forgeCard()
        .animation(.snappy, value: phrase.isEmpty)
    }

    private var result: some View {
        VStack(spacing: 16) {
            AnimatedCheck(checked: true, size: 64)
                .padding(.top, 6)
            Text("\(count) clé\(count > 1 ? "s" : "") chiffrée\(count > 1 ? "s" : "")")
                .font(.title3.weight(.bold))
                .contentTransition(.numericText())
            Text("Gardez ce fichier où vous voulez (Fichiers, un autre appareil, une clé USB) : il ne s'ouvre qu'avec votre phrase.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.textSecondary)

            Text(backup)
                .font(.system(.caption2, design: .monospaced))
                .lineLimit(4)
                .truncationMode(.middle)
                .foregroundStyle(Color.gold.opacity(0.9))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.ink.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
                .textSelection(.enabled)

            if let fileURL {
                ShareLink(item: fileURL, preview: SharePreview("Sauvegarde KeyForge", image: Image(systemName: "lock.doc.fill"))) {
                    Label("Partager le fichier", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(EmberButtonStyle())
            }
            HStack(spacing: 12) {
                ShareLink(item: backup) {
                    Label("Texte", systemImage: "text.alignleft")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    UIPasteboard.general.string = backup
                    Haptics.success()
                    withAnimation(.spring) { copied = true }
                } label: {
                    Label(copied ? "Copié" : "Copier", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .tint(.ember)
        }
        .forgeCard()
    }

    private func export() async {
        guard let items = await vault.entriesForExport(requireAuthentication: settings.biometricLock) else {
            job.phase = .failed("Export annulé : le coffre n'a pas été déverrouillé.")
            Haptics.warning()
            return
        }
        let phrase = phrase
        let result = await job.run { progress in
            try VaultBackup.export(items, phrase: phrase, crypto: AppleCrypto.self, progress: progress)
        }
        switch result {
        case .success(let text):
            backup = text
            count = items.count
            fileURL = writeFile(text)
            job.phase = .done(text)
            Haptics.success()
        case .failure(let error):
            job.phase = .failed(error.localizedDescription)
            Haptics.warning()
        }
    }

    private func writeFile(_ text: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(VaultBackup.fileName)
        do {
            try Data(text.utf8).write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - Importer

private struct ImportPane: View {
    @Environment(VaultStore.self) private var vault
    @State private var job = BackupTask()
    @State private var text = ""
    @State private var phrase = ""
    @State private var reveal = false
    @State private var showFiles = false
    @State private var imported = 0
    @State private var found = 0

    private var params: BrocolisArgon2Params? { try? Brocolis.v2Params(in: text) }
    private var looksValid: Bool { VaultBackup.looksLikeBackup(text) }

    var body: some View {
        VStack(spacing: 18) {
            if case .done = job.phase {
                result.transition(.scale(scale: 0.9).combined(with: .opacity))
            } else if job.isWorking {
                ForgingProgress(progress: job.progress, caption: params.map { "Argon2id · \($0.summary)" } ?? "Déchiffrement")
                    .transition(.opacity)
            } else {
                form.transition(.opacity)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: job.phase)
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.plainText, .text, .data]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), let string = String(data: data, encoding: .utf8) {
                withAnimation(.snappy) { text = string }
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("La sauvegarde", systemImage: "doc.text.fill")
                .font(.headline)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.system(.footnote, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
                    .padding(8)
                    .background(Color.ink.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if text.isEmpty {
                    Text("[[BROCOLIS-CLE:v2:…]]\n[[BROCOLIS:v4:…]]")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Color.textSecondary.opacity(0.6))
                        .padding(16)
                        .allowsHitTesting(false)
                }
            }
            HStack(spacing: 12) {
                Button {
                    if let pasted = UIPasteboard.general.string {
                        withAnimation(.snappy) { text = pasted }
                    }
                } label: {
                    Label("Coller", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity)
                }
                Button {
                    showFiles = true
                } label: {
                    Label("Ouvrir un fichier", systemImage: "folder").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .tint(.ember)

            if !text.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: looksValid ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(looksValid ? Color.green : Color.gold)
                        .symbolEffect(.bounce, value: looksValid)
                    Text(looksValid
                         ? "Sauvegarde Brocolis 🥦 détectée" + (params.map { " · \($0.summary)" } ?? "")
                         : "Aucune sauvegarde reconnue dans ce texte.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            PhraseField(phrase: $phrase, reveal: $reveal, placeholder: "Phrase de la sauvegarde")

            if case .failed(let message) = job.phase {
                ErrorLine(message: message)
            }

            Button {
                Task { await importBackup() }
            } label: {
                Label("Déchiffrer et importer", systemImage: "lock.open.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(EmberButtonStyle())
            .disabled(!looksValid || phrase.isEmpty)
            .opacity(looksValid && !phrase.isEmpty ? 1 : 0.5)
        }
        .forgeCard()
        .animation(.snappy, value: text.isEmpty)
    }

    private var result: some View {
        VStack(spacing: 14) {
            AnimatedCheck(checked: true, size: 64)
                .padding(.top, 6)
            Text("\(imported) clé\(imported > 1 ? "s" : "") importée\(imported > 1 ? "s" : "")")
                .font(.title3.weight(.bold))
                .contentTransition(.numericText(value: Double(imported)))
            if found > imported {
                Text("\(found - imported) déjà présente\(found - imported > 1 ? "s" : "") dans le coffre, laissée\(found - imported > 1 ? "s" : "") telle\(found - imported > 1 ? "s" : "") quelle\(found - imported > 1 ? "s" : "").")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .forgeCard()
    }

    private func importBackup() async {
        let text = text
        let phrase = phrase
        let result = await job.run { progress in
            try VaultBackup.open(text, phrase: phrase, crypto: AppleCrypto.self, progress: progress)
        }
        switch result {
        case .success(let items):
            guard let added = vault.importEntries(items) else {
                job.phase = .failed(vault.errorMessage ?? "Le coffre n'a pas pu être lu.")
                Haptics.warning()
                return
            }
            found = items.count
            imported = added
            job.phase = .done("\(added)")
            self.phrase = ""
            Haptics.success()
        case .failure(let error):
            job.phase = .failed(error.localizedDescription)
            Haptics.warning()
        }
    }
}

// MARK: - Éléments

/// Un champ de phrase secrète, masquée ou visible.
private struct PhraseField: View {
    @Binding var phrase: String
    @Binding var reveal: Bool
    let placeholder: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "key.fill")
                .foregroundStyle(Color.ember)
            Group {
                if reveal {
                    TextField(placeholder, text: $phrase)
                        .font(.body.monospaced())
                } else {
                    SecureField(placeholder, text: $phrase)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            Button {
                withAnimation(.snappy) { reveal.toggle() }
            } label: {
                Image(systemName: reveal ? "eye.slash.fill" : "eye.fill")
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(Color.textSecondary)
            }
            .accessibilityLabel(reveal ? "Masquer la phrase" : "Afficher la phrase")
        }
        .padding(14)
        .background(Color.ink.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(phrase.isEmpty ? Color.line : Color.ember.opacity(0.5), lineWidth: 1)
        )
    }
}

private struct ErrorLine: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.octagon.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.forgePink)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// La forge au travail : un anneau qui se remplit, une couronne qui tourne dans le
/// plan, et des étincelles (2D seulement).
private struct ForgingProgress: View {
    let progress: Double
    let caption: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: max(progress, 0.02))
                    .stroke(
                        AngularGradient(colors: [.gold, .ember, .forgePink, .violet, .gold], center: .center),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Circle()
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [3, 9]))
                    .foregroundStyle(Color.ember.opacity(0.6))
                    .padding(-14)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                Image(systemName: "lock.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Color.white)
                    .symbolEffect(.pulse, isActive: !reduceMotion)
                Text("\(Int(progress * 100)) %")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(Color.gold)
                    .contentTransition(.numericText(value: progress))
                    .offset(y: 36)
            }
            .frame(width: 140, height: 140)
            .padding(18)
            Text("Chiffrement en cours…")
                .font(.headline)
            Text(caption)
                .font(.footnote.monospaced())
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .forgeCard(padding: 24)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { spin = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Chiffrement en cours")
        .accessibilityValue("\(Int(progress * 100)) pour cent")
    }
}

/// « Format Brocolis 🥦 ».
private struct BrocolisBadge: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("Format Brocolis 🥦, compatible avec les apps Brocolis")
                .font(.footnote.weight(.semibold))
            Text("Clé protégée [[BROCOLIS-CLE:v2]] (Argon2id 64 Mio, AES-256-GCM) et coffre en message Brocolis v4 [[BROCOLIS:v4]] (clé partagée de 256 bits, résistante aux ordinateurs quantiques). Les anciennes sauvegardes [[BROCOLIS:v1]] restent lisibles. Tout se passe sur cet iPhone : rien n'est envoyé.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, 8)
    }
}
