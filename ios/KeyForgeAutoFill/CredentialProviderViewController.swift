import AuthenticationServices
import SwiftUI

/// L'extension de remplissage automatique : iOS l'appelle quand un champ d'identifiant
/// ou de mot de passe demande KeyForge (Safari, les apps, la barre QuickType). Elle lit
/// le coffre partagé avec l'app, toujours après Face ID / Touch ID / le code.
final class CredentialProviderViewController: ASCredentialProviderViewController {
    private let model = AutoFillModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = UIColor(red: 11 / 255, green: 10 / 255, blue: 18 / 255, alpha: 1)

        model.onSelect = { [weak self] item in self?.complete(with: item) }
        model.onCancel = { [weak self] in self?.cancel(.userCanceled) }
        model.onInsert = { [weak self] text in self?.insert(text) }
        model.onConfigured = { [weak self] in
            self?.extensionContext.completeExtensionConfigurationRequest()
        }

        let host = UIHostingController(rootView: AutoFillRootView(model: model))
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    // MARK: Ce qu'iOS demande

    /// La liste des identifiants, ceux du site en tête.
    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        model.start(.list(serviceIdentifiers.map(\.identifier)))
    }

    /// Jamais sans Face ID : iOS ouvre alors l'interface ci-dessous.
    override func provideCredentialWithoutUserInteraction(for credentialRequest: any ASCredentialRequest) {
        cancel(.userInteractionRequired)
    }

    /// Une entrée précise, touchée dans la barre QuickType.
    override func prepareInterfaceToProvideCredential(for credentialRequest: any ASCredentialRequest) {
        let record = (credentialRequest.credentialIdentity as? ASPasswordCredentialIdentity)?.recordIdentifier
        model.start(.single(record))
    }

    /// « Remplissage automatique → Mots de passe » dans n'importe quel champ : insérer un
    /// secret forgé par KeyForge (iOS 18 et plus récent).
    @available(iOS 18.0, *)
    override func prepareInterfaceForUserChoosingTextToInsert() {
        model.start(.insertText)
    }

    /// KeyForge vient d'être activé dans les Réglages : les suggestions sont préparées.
    override func prepareInterfaceForExtensionConfiguration() {
        model.start(.configuration)
    }

    // MARK: Réponses

    private func complete(with item: VaultItem) {
        let credential = ASPasswordCredential(user: AutoFillMatch.user(of: item), password: item.password)
        extensionContext.completeRequest(withSelectedCredential: credential, completionHandler: nil)
    }

    private func insert(_ text: String) {
        if #available(iOS 18.0, *) {
            extensionContext.completeRequest(withTextToInsert: text, completionHandler: nil)
        } else {
            cancel(.userCanceled)
        }
    }

    private func cancel(_ code: ASExtensionError.Code) {
        extensionContext.cancelRequest(withError: NSError(domain: ASExtensionErrorDomain, code: code.rawValue))
    }
}
