import Foundation
import Observation

/// The state of the generator screen: options of each mode and the current secret.
@MainActor
@Observable
final class GeneratorModel {
    var mode: GeneratorMode {
        didSet { if mode != oldValue { regenerate() } }
    }

    var password: PasswordOptions {
        didSet { optionsChanged(password, key: AppSettings.Keys.passwordOptions, mode: .password) }
    }

    var passphrase: PassphraseOptions {
        didSet { optionsChanged(passphrase, key: AppSettings.Keys.passphraseOptions, mode: .passphrase) }
    }

    var pin: PinOptions {
        didSet { optionsChanged(pin, key: AppSettings.Keys.pinOptions, mode: .pin) }
    }

    var gibberish: GibberishOptions {
        didSet { optionsChanged(gibberish, key: AppSettings.Keys.gibberishOptions, mode: .gibberish) }
    }

    private(set) var secret = GeneratedSecret(value: "", mode: .password, entropy: 0)
    /// Increases at every new secret: drives the animations.
    private(set) var generation = 0
    /// The previous secrets of this session (memory only, cleared in the background).
    private(set) var history: [GeneratedSecret] = []

    private let settings: AppSettings
    let words: WordList

    init(settings: AppSettings, words: WordList = .bundled) {
        self.settings = settings
        self.words = words
        mode = settings.defaultMode
        password = settings.load(PasswordOptions.self, key: AppSettings.Keys.passwordOptions) ?? PasswordOptions()
        passphrase = settings.load(PassphraseOptions.self, key: AppSettings.Keys.passphraseOptions)
            ?? PassphraseOptions()
        pin = settings.load(PinOptions.self, key: AppSettings.Keys.pinOptions) ?? PinOptions()
        gibberish = settings.load(GibberishOptions.self, key: AppSettings.Keys.gibberishOptions)
            ?? GibberishOptions()
        regenerate()
    }

    /// Forges a new secret. `record` keeps the previous one in the session history
    /// (not when an option is being adjusted, which regenerates at every step).
    func regenerate(record: Bool = true) {
        if record, !secret.value.isEmpty {
            history.insert(secret, at: 0)
            if history.count > 20 { history.removeLast(history.count - 20) }
        }
        let value: String
        let entropy: Double
        switch mode {
        case .password:
            value = Generator.password(password)
            entropy = Generator.passwordEntropy(password)
        case .passphrase:
            value = Generator.passphrase(passphrase, words: words)
            entropy = Generator.passphraseEntropy(passphrase, words: words)
        case .pin:
            value = Generator.pin(pin)
            entropy = Generator.pinEntropy(pin)
        case .gibberish:
            value = Generator.gibberish(gibberish)
            entropy = Generator.gibberishEntropy(gibberish)
        }
        secret = GeneratedSecret(value: value, mode: mode, entropy: entropy)
        generation += 1
    }

    func clearHistory() {
        history.removeAll()
    }

    private func optionsChanged<T: Encodable & Equatable>(_ value: T, key: String, mode changed: GeneratorMode) {
        settings.store(value, key: key)
        if mode == changed { regenerate(record: false) }
    }
}
