import SwiftUI
import Vision
import VisionKit

// Les codes de validation (2FA) dans l'app : le code du moment sur la fiche d'une
// entrée, le scanner de QR code, et l'accueil d'un lien `otpauth://` ouvert par iOS.

/// Le code du moment et le temps qu'il lui reste.
struct OneTimeCodeCard: View {
    let generator: TOTP
    let copy: (String) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let remaining = generator.secondsRemaining(at: timeline.date)
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Code de validation", systemImage: "clock.badge.checkmark.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                    Text(generator.displayCode(at: timeline.date))
                        .font(.system(.title, design: .monospaced).weight(.bold))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
                Spacer()
                ZStack {
                    Circle().stroke(Color.line, lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: CGFloat(remaining) / CGFloat(generator.period))
                        .stroke(remaining <= 5 ? Color.red : Color.gold, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(remaining)")
                        .font(.caption.monospacedDigit().weight(.bold))
                }
                .frame(width: 38, height: 38)
                .accessibilityLabel("Encore \(remaining) secondes")
                Button {
                    copy(generator.code())
                } label: {
                    Image(systemName: "doc.on.doc").foregroundStyle(Color.gold)
                }
                .accessibilityLabel("Copier le code de validation")
            }
        }
    }
}

// MARK: - Scanner

/// L'appareil photo, à la recherche d'un QR code.
struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onCode: (String) -> Void
        private var done = false

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(
            _ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]
        ) {
            for item in addedItems {
                guard !done, case .barcode(let barcode) = item, let text = barcode.payloadStringValue else { continue }
                done = true
                onCode(text)
            }
        }
    }
}

/// La feuille du scanner : le premier QR code lu est rendu, puis elle se ferme.
struct QRScannerSheet: View {
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported {
                    QRScannerView { text in
                        Haptics.success()
                        onCode(text)
                        dismiss()
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .overlay(alignment: .bottom) {
                        Text("Visez le QR code affiché par le site. Si l'image reste noire, autorisez l'appareil photo dans Réglages → Apps → KeyForge.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .padding(14)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .padding(20)
                    }
                } else {
                    ContentUnavailableView(
                        "Scanner indisponible",
                        systemImage: "qrcode.viewfinder",
                        description: Text("Cet appareil ne peut pas scanner de QR code : collez la clé secrète affichée par le site.")
                    )
                }
            }
            .background(Color.ink)
            .navigationTitle("Scanner le QR code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Lien otpauth://

/// Un code de validation reçu par un lien ou un QR code `otpauth://` ouvert par iOS.
struct IncomingOneTimeCode: Identifiable {
    let id = UUID()
    let generator: TOTP
}

/// Où ranger le code reçu : dans une entrée du coffre, ou dans une nouvelle.
struct OneTimeCodeSetupView: View {
    let generator: TOTP
    @Environment(VaultStore.self) private var vault
    @Environment(AppSettings.self) private var settings
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var creating: VaultItem?
    @State private var search = ""

    /// Les entrées dont le titre ou le site évoque l'émetteur d'abord, puis les autres.
    private var candidates: [VaultItem] {
        let issuer = generator.issuer.trimmingCharacters(in: .whitespaces)
        let all = vault.items.sortedForDisplay().filter { $0.matches(search) }
        guard !issuer.isEmpty else { return all }
        let close = all.filter { $0.matches(issuer) }
        return close + all.filter { item in !close.contains { $0.id == item.id } }
    }

    var body: some View {
        NavigationStack {
            Group {
                if vault.isLocked {
                    VStack(spacing: 18) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 54, weight: .bold))
                            .foregroundStyle(Theme.ember)
                        Text("Déverrouillez le coffre pour y ranger ce code de validation.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.textSecondary)
                        Button {
                            Task { await vault.unlock(requireAuthentication: settings.biometricLock) }
                        } label: {
                            Label("Déverrouiller avec \(BiometricAuth.label)", systemImage: BiometricAuth.symbol)
                        }
                        .buttonStyle(EmberButtonStyle())
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
            }
            .background(Color.ink)
            .navigationTitle("Nouveau code de validation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            .task {
                if vault.isLocked { await vault.unlock(requireAuthentication: settings.biometricLock) }
            }
            .sheet(item: $creating) { item in
                VaultEditView(item: item, isNew: true) { saved in
                    vault.upsert(saved)
                    finish()
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var list: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(generator.issuer.isEmpty ? "Code de validation" : generator.issuer)
                        .font(.headline)
                    if !generator.account.isEmpty {
                        Text(generator.account).font(.subheadline).foregroundStyle(Color.textSecondary)
                    }
                    OneTimeCodeCard(generator: generator) { code in
                        Clipboard.copy(code, expiry: settings.clipboardExpiry)
                        toasts.show("Code copié", symbol: "doc.on.doc.fill")
                    }
                }
                .padding(.vertical, 4)
            } footer: {
                Text("Si le site demande un code pour terminer, copiez celui-ci.")
            }
            .listRowBackground(Color.surface)

            Section {
                Button {
                    creating = VaultItem(
                        title: generator.issuer, username: generator.account, password: "", totp: generator.uri
                    )
                } label: {
                    Label("Nouvelle entrée", systemImage: "plus.circle.fill")
                }
            }
            .listRowBackground(Color.surface)

            if !candidates.isEmpty {
                Section("Ajouter à une entrée du coffre") {
                    ForEach(candidates) { item in
                        Button {
                            var updated = item
                            updated.totp = generator.uri
                            vault.upsert(updated)
                            finish()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title.isEmpty ? item.displayHost : item.title)
                                    .foregroundStyle(.white)
                                Text(item.oneTimeCode == nil
                                    ? (item.username.isEmpty ? item.displayHost : item.username)
                                    : "A déjà un code : il sera remplacé")
                                    .font(.caption)
                                    .foregroundStyle(item.oneTimeCode == nil ? Color.textSecondary : Color.gold)
                            }
                        }
                    }
                }
                .listRowBackground(Color.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .searchable(text: $search, prompt: "Rechercher dans le coffre")
    }

    private func finish() {
        Haptics.success()
        toasts.show("Code de validation rangé dans le coffre", symbol: "clock.badge.checkmark.fill")
        dismiss()
    }
}
