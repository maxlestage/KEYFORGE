import Foundation
import LocalAuthentication
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

    /// Le coffre scellé par Brocolis 🥦, déchiffré ici après Face ID.
    private let store = BrocolisVault()

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
            phase = .ready
            Task { await syncIdentities() }
        case .list, .single:
            Task { await unlock() }
        }
    }

    /// Face ID / Touch ID / le code, puis le coffre. Toujours demandé : l'extension ne
    /// fournit jamais un mot de passe sans que le propriétaire de l'iPhone soit là.
    func unlock() async {
        guard phase != .unlocking else { return }
        phase = .unlocking
        // Le contexte authentifié laisse la Secure Enclave libérer la clé du coffre.
        let context = LAContext()
        guard await BiometricAuth.authenticate(
            context: context, reason: "Remplir avec un identifiant de votre coffre KeyForge"
        ) else {
            phase = .locked
            return
        }
        guard load(context) else { return }
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

    /// À l'activation de KeyForge dans les réglages d'iOS : les sites et identifiants du
    /// coffre (jamais les mots de passe) sont proposés au-dessus du clavier. Quand la
    /// Secure Enclave garde la clé du coffre, le propriétaire s'authentifie d'abord.
    private func syncIdentities() async {
        let context = LAContext()
        if store.isEnclaveProtected() {
            guard await BiometricAuth.authenticate(
                context: context, reason: "Proposer vos identifiants KeyForge au-dessus du clavier"
            ) else { return }
        }
        if let opened = try? store.open(context: context) {
            AutoFillIdentities.sync(opened.items)
        }
    }

    @discardableResult
    private func load(_ context: LAContext) -> Bool {
        do {
            items = try store.open(context: context).items
            return true
        } catch {
            phase = .failed("Le coffre est illisible : \(error.localizedDescription)")
            return false
        }
    }
}
