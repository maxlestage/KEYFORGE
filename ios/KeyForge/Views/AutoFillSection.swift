import AuthenticationServices
import SwiftUI

/// Réglages → « iPhone et Mots de passe » : le remplissage automatique par KeyForge
/// dans Safari et les apps, et le transfert du coffre vers l'app Mots de passe d'Apple.
struct AutoFillSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(VaultStore.self) private var vault
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.scenePhase) private var scenePhase
    @State private var enabled = false
    @State private var exporting = false

    var body: some View {
        Section {
            if enabled {
                Label("KeyForge remplit vos mots de passe", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.white)
            } else {
                Button {
                    Task { try? await ASSettingsHelper.openCredentialProviderAppSettings() }
                } label: {
                    Label("Activer le remplissage automatique", systemImage: "key.viewfinder")
                }
            }
            if PasswordsExport.isAvailable {
                Button {
                    Task { await exportToPasswords() }
                } label: {
                    Label("Transférer vers l'app Mots de passe", systemImage: "key.icloud.fill")
                }
                .disabled(exporting)
            }
        } header: {
            Text("iPhone et Mots de passe")
        } footer: {
            Text(footer)
        }
        .listRowBackground(Color.surface)
        .task(id: scenePhase) {
            // Au retour des Réglages d'iOS, l'état est relu.
            enabled = await AutoFillIdentities.isEnabled()
            if enabled, !vault.isLocked { AutoFillIdentities.sync(vault.items) }
        }
    }

    private var footer: String {
        var text = "Avec le remplissage automatique, vos identifiants KeyForge sont proposés au-dessus du clavier dans Safari et vos apps, sans ouvrir KeyForge ; chaque mot de passe n'est rempli qu'après \(BiometricAuth.label). Dans Réglages → Général → Remplissage automatique et mots de passe, activez KeyForge."
        if PasswordsExport.isAvailable {
            text += " Le transfert copie vos identifiants dans l'app Mots de passe d'Apple, qui les synchronise par le trousseau iCloud (chiffré de bout en bout) : ils restent disponibles même sans KeyForge. Les notes ne sont pas transférées."
        }
        return text
    }

    private func exportToPasswords() async {
        exporting = true
        defer { exporting = false }
        guard let items = await vault.entriesForExport(requireAuthentication: settings.biometricLock) else {
            toasts.show("Transfert annulé", symbol: "xmark.circle.fill")
            return
        }
        guard !items.isEmpty else {
            toasts.show("Le coffre est vide", symbol: "tray")
            return
        }
        do {
            try await PasswordsExport.export(items)
            Haptics.success()
            toasts.show("\(items.count) identifiant\(items.count > 1 ? "s" : "") transféré\(items.count > 1 ? "s" : "")", symbol: "key.icloud.fill")
        } catch {
            // L'utilisateur a refermé la feuille d'iOS, ou le transfert a échoué.
            toasts.show("Transfert non effectué", symbol: "exclamationmark.triangle.fill")
        }
    }
}
