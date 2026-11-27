import Foundation
import LocalAuthentication
import Observation

/// Un identifiant qu'iOS demande d'enregistrer dans KeyForge (iOS 26.2 et plus récent).
struct SaveDraft: Equatable {
    var service: String
    var user: String
    var password: String
    var title: String?
}

/// L'état de l'extension : ce qu'iOS a demandé, le verrou, les entrées du coffre.
@MainActor
@Observable
final class AutoFillModel {
    enum Request {
        /// Choisir un identifiant ; les identifiants de service du site (domaines ou URL).
        case list([String])
        /// Une entrée précise (son `recordIdentifier`), depuis la barre QuickType.
        case single(String?)
        /// Choisir un code de validation (2FA) ; les identifiants de service du site.
        case codes([String])
        /// Le code d'une entrée précise, depuis la barre QuickType.
        case singleCode(String?)
        /// Enregistrer un identifiant saisi dans Safari ou une app (iOS 26.2+).
        case save(SaveDraft)
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
    var onSelectCode: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var onInsert: ((String) -> Void)?
    var onConfigured: (() -> Void)?
    var onSaved: (() -> Void)?

    /// Ce que l'enregistrement demandé changera dans le coffre.
    private(set) var savePlan: VaultSave.Plan = .unchanged
    /// La clé et le contexte qui ont ouvert le coffre, pour le sceller à nouveau.
    private var openedKey: [UInt8]?
    private var openedContext: LAContext?

    /// Le coffre scellé par Brocolis 🥦, déchiffré ici après Face ID.
    private let store = BrocolisVault()

    /// Vrai quand iOS demande un code de validation plutôt qu'un identifiant.
    var wantsCode: Bool {
        switch request {
        case .codes, .singleCode: true
        default: false
        }
    }

    /// Les identifiants de service du site demandé.
    private var identifiers: [String]? {
        switch request {
        case .list(let identifiers), .codes(let identifiers): identifiers
        default: nil
        }
    }

    /// Les entrées du site d'abord, puis les autres ; filtrées par la recherche. Pour un
    /// code de validation, seules les entrées qui en génèrent un.
    var sections: (suggested: [VaultItem], others: [VaultItem]) {
        let pool = wantsCode ? items.filter { $0.oneTimeCode != nil } : items.filter { !$0.password.isEmpty }
        guard let identifiers else { return ([], pool.sortedForDisplay().filter { $0.matches(search) }) }
        let split = AutoFillMatch.split(pool, for: identifiers)
        return (split.suggested.filter { $0.matches(search) }, split.others.filter { $0.matches(search) })
    }

    /// Le site demandé, pour le titre (« example.com »).
    var siteName: String? {
        identifiers?.lazy.map(AutoFillMatch.host(of:)).first { !$0.isEmpty }
    }

    /// Remplit le champ avec l'entrée choisie : son code de validation ou son identifiant.
    func choose(_ item: VaultItem) {
        if wantsCode {
            if let code = item.oneTimeCode?.code() { onSelectCode?(code) }
        } else {
            onSelect?(item)
        }
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
        case .list, .single, .codes, .singleCode, .save:
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
        if case .singleCode(let record) = request {
            if let code = items.first(where: { $0.id.uuidString == record })?.oneTimeCode?.code() {
                onSelectCode?(code)
                return
            }
            // L'entrée n'a plus de code : la liste des codes à la place.
            request = .codes([])
        }
        if case .save(let draft) = request {
            savePlan = plan(for: draft, in: items)
            if savePlan == .unchanged {
                // Déjà dans le coffre avec ce mot de passe : rien à confirmer.
                onSaved?()
                return
            }
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

    // MARK: Enregistrer

    private func plan(for draft: SaveDraft, in items: [VaultItem]) -> VaultSave.Plan {
        VaultSave.plan(
            service: draft.service, user: draft.user, password: draft.password, title: draft.title, in: items
        )
    }

    /// Enregistre sans rien afficher quand c'est possible : la clé du coffre est dans le
    /// trousseau (verrouillage biométrique coupé) et il n'y a pas de mot de passe à
    /// remplacer sans l'accord du propriétaire. `false` : l'interface est nécessaire.
    func saveSilently(_ draft: SaveDraft, mayOverwrite: Bool) -> Bool {
        guard !store.isEnclaveProtected(), let opened = try? store.open(context: nil) else { return false }
        let plan = plan(for: draft, in: opened.items)
        if plan == .unchanged { return true }
        if case .update = plan, !mayOverwrite { return false }
        return write(plan, to: opened.items, key: opened.key, context: nil)
    }

    /// Le propriétaire a confirmé : le coffre est scellé à nouveau avec l'identifiant.
    func confirmSave() {
        if write(savePlan, to: items, key: openedKey, context: openedContext) {
            onSaved?()
        }
    }

    private func write(_ plan: VaultSave.Plan, to items: [VaultItem], key: [UInt8]?, context: LAContext?) -> Bool {
        let updated = VaultSave.apply(plan, to: items)
        do {
            try store.save(updated, key: key, context: context)
            // iOS proposera aussitôt ce nouvel identifiant au-dessus du clavier.
            AutoFillIdentities.sync(updated)
            return true
        } catch {
            phase = .failed("L'identifiant n'a pas pu être enregistré : \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    private func load(_ context: LAContext) -> Bool {
        do {
            let opened = try store.open(context: context)
            items = opened.items
            openedKey = opened.key
            openedContext = context
            return true
        } catch {
            phase = .failed("Le coffre est illisible : \(error.localizedDescription)")
            return false
        }
    }
}
