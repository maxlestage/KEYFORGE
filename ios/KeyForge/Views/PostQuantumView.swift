import CoreImage.CIFilterBuiltins
import SwiftUI

// Le chiffrement post-quantique de KeyForge, par le protocole Brocolis v4 🥦 :
// mon identité (paquet de clés à partager), envoyer un secret chiffré pour quelqu'un,
// et recevoir un secret chiffré pour moi. X25519 + ML-KEM-768 : le secret reste protégé
// tant que l'un des deux tient, même face à un ordinateur quantique.

// MARK: - Éléments communs

/// « Post-quantique · X25519 + ML-KEM-768 », avec une bordure en dégradé qui tourne.
struct PQBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle = 0.0

    var body: some View {
        Label("Post-quantique · X25519 + ML-KEM-768", systemImage: "atom")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.surfaceHigh))
            .overlay(
                Capsule().strokeBorder(
                    AngularGradient(colors: [.ember, .forgePink, .violet, .gold, .ember], center: .center, angle: .degrees(angle)),
                    lineWidth: 1.5
                )
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { angle = 360 }
            }
            .accessibilityLabel("Chiffrement post-quantique, X25519 et ML-KEM-768")
    }
}

/// Un réseau de points qui ondule : l'image des réseaux euclidiens sur lesquels repose
/// ML-KEM (2D, Canvas).
struct LatticeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                let columns = 14, rows = 6
                let dx = size.width / CGFloat(columns - 1)
                let dy = size.height / CGFloat(rows - 1)
                for row in 0..<rows {
                    for column in 0..<columns {
                        let phase = Double(column) * 0.45 + Double(row) * 0.7
                        let wave = sin(t * 1.6 + phase)
                        let x = CGFloat(column) * dx + CGFloat(sin(t + Double(row))) * 3
                        let y = CGFloat(row) * dy + CGFloat(wave) * 4
                        let radius = 2.2 + CGFloat(wave + 1) * 1.4
                        let color: Color = (column + row) % 5 == 0 ? .gold : ((column * row) % 3 == 0 ? .forgePink : .ember)
                        canvas.fill(
                            Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius)),
                            with: .color(color.opacity(0.35 + 0.3 * (wave + 1) / 2))
                        )
                    }
                }
            }
        }
        .frame(height: 70)
        .accessibilityHidden(true)
    }
}

/// Un QR code (niveau de correction L : le paquet post-quantique fait 1 892 caractères).
struct QRCodeImage: View {
    let text: String

    var body: some View {
        if let image = Self.render(text) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("QR code du paquet de clés")
        } else {
            Image(systemName: "qrcode")
                .font(.system(size: 80))
                .foregroundStyle(Color.textSecondary)
        }
    }

    static func render(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "L"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 6, y: 6))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

private struct FingerprintRow: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack {
            Label(title, systemImage: symbol)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                .foregroundStyle(Color.gold)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.octagon.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.forgePink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Un éditeur de texte monospace avec un texte indicatif.
private struct TokenEditor: View {
    @Binding var text: String
    let placeholder: String
    var minHeight: CGFloat = 110

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.system(.footnote, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: minHeight)
                .padding(8)
                .background(Color.ink.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Color.textSecondary.opacity(0.6))
                    .padding(16)
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Mon identité

struct IdentityView: View {
    @Environment(IdentityStore.self) private var identity
    @Environment(ToastCenter.self) private var toasts
    @State private var confirmRegenerate = false
    @State private var copied = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 12) {
                    LatticeView()
                    PQBadge()
                    Text("Partagez ce paquet de clés : on pourra vous envoyer des secrets que vous seul ouvrirez, sur cet iPhone.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.textSecondary)
                }
                .entrance()

                if let bundle = identity.bundle {
                    VStack(spacing: 16) {
                        QRCodeImage(text: bundle.base64)
                            .frame(maxWidth: 260)
                            .padding(12)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                        FingerprintRow(title: "Empreinte", value: bundle.fingerprint, symbol: "touchid")
                        FingerprintRow(title: "Clé d'échange", value: bundle.exchangeFingerprint, symbol: "key.horizontal.fill")
                        Text(bundle.base64)
                            .font(.system(.caption2, design: .monospaced))
                            .lineLimit(3)
                            .truncationMode(.middle)
                            .foregroundStyle(Color.gold.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.ink.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
                        HStack(spacing: 12) {
                            ShareLink(item: bundle.base64) {
                                Label("Partager", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                            }
                            Button {
                                Clipboard.copy(bundle.base64, expiry: .never)
                                Haptics.success()
                                copied += 1
                                toasts.show("Paquet de clés copié", symbol: "doc.on.doc.fill")
                            } label: {
                                Label("Copier", systemImage: "doc.on.doc")
                                    .symbolEffect(.bounce, value: copied)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.ember)
                    }
                    .forgeCard()
                    .entrance(delay: 0.08)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Comment ça marche", systemImage: "info.circle.fill")
                        .font(.headline)
                    Text("Votre identité tient dans le Trousseau de cet iPhone et ne le quitte jamais. Le paquet ne contient que des clés publiques, signées : une clé X25519 et une clé ML-KEM-768. Comparez l'empreinte de vive voix avec la personne qui vous écrit.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                    Text("Compatible avec Brocolis 🥦 (protocole v4) : le site de KeyForge et les apps Brocolis lisent les mêmes paquets et les mêmes messages.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
                .forgeCard()
                .entrance(delay: 0.14)

                Button(role: .destructive) {
                    confirmRegenerate = true
                } label: {
                    Label("Nouvelle identité", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .tint(.forgePink)
            }
            .padding(20)
        }
        .background(ForgeBackground(intensity: 0.45))
        .navigationTitle("Identité post-quantique")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { identity.ensure() }
        .confirmationDialog("Créer une nouvelle identité ?", isPresented: $confirmRegenerate, titleVisibility: .visible) {
            Button("Remplacer mon identité", role: .destructive) {
                withAnimation(.spring) { identity.regenerate() }
                Haptics.warning()
                toasts.show("Nouvelle identité créée", symbol: "atom")
            }
        } message: {
            Text("Les messages chiffrés pour l'ancienne identité ne pourront plus être ouverts. Partagez ensuite votre nouveau paquet.")
        }
    }
}

// MARK: - Envoyer

/// Chiffre un secret pour le paquet de clés d'un destinataire.
struct SendEncryptedView: View {
    var secret: String = ""
    var subject: String?
    @Environment(IdentityStore.self) private var identity
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var recipient = ""
    @State private var result: (token: String, fingerprint: String)?
    @State private var error: String?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    PQBadge().entrance()
                    if let result {
                        output(result)
                    } else {
                        form
                    }
                }
                .padding(20)
                .animation(.spring(response: 0.5, dampingFraction: 0.82), value: result?.token)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(ForgeBackground(intensity: 0.5))
            .navigationTitle(subject.map { "Envoyer « \($0) »" } ?? "Envoyer avec Brocolis 🥦")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .onAppear { if message.isEmpty { message = secret } }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Le secret", systemImage: "key.fill").font(.headline)
            TokenEditor(text: $message, placeholder: "Un mot de passe, un code, une note…", minHeight: 80)
            Label("Le paquet de clés du destinataire", systemImage: "person.badge.key.fill").font(.headline)
            TokenEditor(text: $recipient, placeholder: "Collez le paquet (base64) que le destinataire vous a partagé")
            HStack(spacing: 12) {
                Button {
                    if let pasted = UIPasteboard.general.string {
                        withAnimation(.snappy) { recipient = pasted }
                    }
                } label: {
                    Label("Coller", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity)
                }
                Button {
                    identity.ensure()
                    if let mine = identity.bundle {
                        withAnimation(.snappy) { recipient = mine.base64 }
                    }
                } label: {
                    Label("Pour moi (test)", systemImage: "person.fill").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .tint(.ember)
            if let error { ErrorBanner(message: error) }
            Button {
                encrypt()
            } label: {
                Label("Chiffrer en post-quantique", systemImage: "lock.shield.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(EmberButtonStyle())
            .disabled(message.isEmpty || recipient.isEmpty)
            Text("X25519 + ML-KEM-768, puis AES-256-GCM. Votre identité reste cachée dans le message : seul le destinataire la découvre.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .forgeCard()
        .entrance(delay: 0.06)
    }

    private func output(_ result: (token: String, fingerprint: String)) -> some View {
        VStack(spacing: 16) {
            AnimatedCheck(checked: true, size: 64)
            Text("Chiffré pour la clé d'échange")
                .font(.headline)
            Text(result.fingerprint)
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .foregroundStyle(Color.gold)
            Text("Vérifiez cette empreinte avec le destinataire, puis envoyez-lui le message par n'importe quel canal : seul son iPhone pourra l'ouvrir.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.textSecondary)
            Text(result.token)
                .font(.system(.caption2, design: .monospaced))
                .lineLimit(4)
                .truncationMode(.middle)
                .foregroundStyle(Color.gold.opacity(0.9))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.ink.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
                .textSelection(.enabled)
            ShareLink(item: result.token) {
                Label("Partager le message", systemImage: "paperplane.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(EmberButtonStyle())
            Button {
                Clipboard.copy(result.token, expiry: .never)
                Haptics.success()
                withAnimation(.spring) { copied = true }
            } label: {
                Label(copied ? "Copié" : "Copier", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.ember)
        }
        .forgeCard()
        .transition(.scale(scale: 0.92).combined(with: .opacity))
    }

    private func encrypt() {
        do {
            let sealed = try identity.encrypt(message, forBundle: recipient)
            Haptics.success()
            withAnimation(.spring) {
                error = nil
                result = (sealed.token, sealed.recipient.exchangeFingerprint)
            }
            toasts.show("Chiffré en post-quantique", symbol: "lock.shield.fill")
        } catch {
            Haptics.warning()
            withAnimation(.snappy) { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Recevoir

/// Ouvre un message `[[BROCOLIS:v4:…]]` chiffré pour mon identité.
struct ReceiveEncryptedView: View {
    @Environment(IdentityStore.self) private var identity
    @Environment(VaultStore.self) private var vault
    @Environment(AppSettings.self) private var settings
    @Environment(ToastCenter.self) private var toasts
    @State private var token = ""
    @State private var received: BrocolisV4.Received?
    @State private var error: String?
    @State private var saved = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                PQBadge().entrance()
                if let received {
                    result(received)
                } else {
                    form
                }
            }
            .padding(20)
            .animation(.spring(response: 0.5, dampingFraction: 0.82), value: received)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(ForgeBackground(intensity: 0.45))
        .navigationTitle("Recevoir")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Le message chiffré", systemImage: "envelope.badge.shield.half.filled").font(.headline)
            TokenEditor(text: $token, placeholder: "[[BROCOLIS:v4:…]]")
            Button {
                if let pasted = UIPasteboard.general.string {
                    withAnimation(.snappy) { token = pasted }
                }
            } label: {
                Label("Coller", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.ember)
            if let error { ErrorBanner(message: error) }
            Button {
                open()
            } label: {
                Label("Ouvrir avec mon identité", systemImage: "lock.open.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(EmberButtonStyle())
            .disabled(!BrocolisV4.containsToken(token))
        }
        .forgeCard()
        .entrance(delay: 0.06)
    }

    private func result(_ received: BrocolisV4.Received) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                AnimatedCheck(checked: true, size: 44)
                VStack(alignment: .leading) {
                    Text("Message ouvert").font(.headline)
                    Text("Expéditeur · \(received.senderFingerprint)")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Color.gold)
                }
            }
            SecretText(value: received.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Comparez l'empreinte de l'expéditeur avec sa clé d'échange avant de faire confiance au message.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            HStack(spacing: 12) {
                Button {
                    Clipboard.copy(received.text, expiry: settings.clipboardExpiry)
                    Haptics.success()
                    toasts.show("Copié", symbol: "doc.on.doc.fill")
                } label: {
                    Label("Copier", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.ember)
                Button {
                    vault.add(VaultItem(
                        title: "Reçu · \(received.senderFingerprint.prefix(9))",
                        password: received.text,
                        notes: "Reçu chiffré en post-quantique (Brocolis v4) de la clé \(received.senderFingerprint)."
                    ))
                    Haptics.success()
                    withAnimation(.spring) { saved = true }
                    toasts.show("Rangé dans le coffre", symbol: "tray.and.arrow.down.fill")
                } label: {
                    Label(saved ? "Rangé" : "Ranger dans le coffre", systemImage: saved ? "checkmark" : "tray.and.arrow.down.fill")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(EmberButtonStyle())
                .disabled(saved)
            }
            Button("Ouvrir un autre message") {
                withAnimation(.spring) {
                    self.received = nil
                    token = ""
                    saved = false
                }
            }
            .frame(maxWidth: .infinity)
        }
        .forgeCard()
        .transition(.scale(scale: 0.92).combined(with: .opacity))
    }

    private func open() {
        do {
            let opened = try identity.open(token)
            Haptics.success()
            withAnimation(.spring) {
                error = nil
                received = opened
            }
        } catch {
            Haptics.warning()
            withAnimation(.snappy) { self.error = error.localizedDescription }
        }
    }
}
