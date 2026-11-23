import Foundation
import LocalAuthentication

/// Face ID, Touch ID or, as a fallback, the device passcode.
enum BiometricAuth {
    enum Kind {
        case faceID, touchID, opticID, passcode, none
    }

    static var kind: Kind {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) ? .passcode : .none
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .passcode
        }
    }

    static var label: String {
        switch kind {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        case .passcode: "Code de l'appareil"
        case .none: "Aucun verrouillage disponible"
        }
    }

    static var symbol: String {
        switch kind {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        case .passcode, .none: "lock.fill"
        }
    }

    /// Asks the owner to authenticate. Without any passcode on the device (the
    /// simulator, for instance), the vault opens: there is nothing to check against.
    static func authenticate(reason: String = "Déverrouillez votre coffre KeyForge") async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Annuler"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return true
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
