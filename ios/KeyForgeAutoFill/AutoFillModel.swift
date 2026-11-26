import Foundation
import Observation

/// L'état de l'extension : ce qu'iOS a demandé, le verrou, les entrées du coffre.
@MainActor
@Observable
final class AutoFillModel {
    enum Request {
        /// Choisir un identifiant ; les identifiants de service du site (domaines ou URL).
        case list([String])
        /// Une entrée précise (son `recordIdentifier`), depuis la barre QuickType.
        case single(String?)
        /// Insérer un secret forgé dans le champ (iOS 18+).
        case insertText
        /// KeyForge vient d'être activé comme fournisseur de remplissage automatique.
        case configuration
    }

    enum Phase: Equatable {
        case locked
        case unlocking
        case ready
        case failed(String)
    }

    private(set) var request: Request = .list([])
    private(set) var phase: Phase = .locked
    private(set) var items: [VaultItem] = []
    var search = ""

    var onSelect: ((VaultItem) -> Void)?
    var onCancel: (() -> Void)?
    var onInsert: ((String) -> Void)?
    var onConfigured: (() -> Void)?

    private let keychain = KeychainStore()

    /// Les entrées du site d'abord, puis les autres ; filtrées par la recherche.
    var sections: (suggested: [VaultItem], others: [VaultItem]) {
        guard case .list(let identifiers) = request else { return ([], items.sortedForDisplay()) }
        let split = AutoFillMatch.split(items, for: identifiers)
        return (split.suggested.filter { $0.matches(search) }, split.others.filter { $0.matches(search) })
    }

    /// Le site demandé, pour le titre (« example.com »).
    var siteName: String? {
        guard case .list(let identifiers) = request else { return nil }
        return identifiers.lazy.map(AutoFillMatch.host(of:)).first { !$0.isEmpty }
    }

    func start(_ request: Request) {
        self.request = request
        switch request {
        case .insertText:
            // Rien du coffre n'est lu : un secret neuf, forgé sur l'appareil.
            phase = .ready
        case .configuration:
            // Seuls les sites et identifiants partent vers iOS, pas les mots de passe.
            if load() { AutoFillIdentities.sync(items) }
            phase = .ready
        case .list, .single:
            Task { await unlock() }
        }
    }

    /// Face ID / Touch ID / le code, puis le coffre. Toujours demandé : l'extension ne
    /// fournit jamais un mot de passe sans que le propriétaire de l'iPhone soit là.
    func unlock() async {
        guard phase != .unlocking else { return }
        phase = .unlocking
        guard await BiometricAuth.authenticate(reason: "Remplir avec un identifiant de votre coffre KeyForge") else {
            phase = .locked
            return
        }
        guard load() else { return }
        if case .single(let record) = request {
            if let item = items.first(where: { $0.id.uuidString == record }) {
                onSelect?(item)
                return
            }
            // L'entrée a disparu du coffre : la liste complète à la place.
            request = .list([])
        }
        phase = .ready
    }

    @discardableResult
    private func load() -> Bool {
        do {
            if let data = try keychain.load() {
                items = try JSONDecoder().decode([VaultItem].self, from: data)
            } else {
                items = []
            }
            return true
        } catch {
            phase = .failed("Le coffre est illisible : \(error.localizedDescription)")
            return false
        }
    }
}
