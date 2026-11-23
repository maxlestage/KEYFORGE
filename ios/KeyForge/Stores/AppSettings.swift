import Foundation
import Observation

/// The user's preferences, kept in `UserDefaults` (never a secret).
@MainActor
@Observable
final class AppSettings {
    enum Keys {
        static let biometricLock = "settings.biometricLock"
        static let clipboardExpiry = "settings.clipboardExpiry"
        static let haptics = "settings.haptics"
        static let defaultMode = "settings.defaultMode"
        static let onboardingDone = "settings.onboardingDone"
        static let passwordOptions = "generator.passwordOptions"
        static let passphraseOptions = "generator.passphraseOptions"
        static let pinOptions = "generator.pinOptions"
    }

    private let defaults: UserDefaults

    var biometricLock: Bool {
        didSet { defaults.set(biometricLock, forKey: Keys.biometricLock) }
    }

    var clipboardExpiry: ClipboardExpiry {
        didSet { defaults.set(clipboardExpiry.rawValue, forKey: Keys.clipboardExpiry) }
    }

    var haptics: Bool {
        didSet { defaults.set(haptics, forKey: Keys.haptics) }
    }

    var defaultMode: GeneratorMode {
        didSet { defaults.set(defaultMode.rawValue, forKey: Keys.defaultMode) }
    }

    var onboardingDone: Bool {
        didSet { defaults.set(onboardingDone, forKey: Keys.onboardingDone) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        biometricLock = defaults.object(forKey: Keys.biometricLock) as? Bool ?? true
        // 30 seconds until the user chooses otherwise ("never" is stored as 0).
        clipboardExpiry = defaults.object(forKey: Keys.clipboardExpiry) == nil
            ? .seconds30
            : ClipboardExpiry(rawValue: defaults.integer(forKey: Keys.clipboardExpiry)) ?? .seconds30
        haptics = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        defaultMode = GeneratorMode(rawValue: defaults.string(forKey: Keys.defaultMode) ?? "") ?? .password
        onboardingDone = defaults.bool(forKey: Keys.onboardingDone)
    }

    /// Generator options are remembered between launches.
    func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func store<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }
}
