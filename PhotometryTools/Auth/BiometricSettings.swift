import Combine
import Foundation
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

/// Opt-in Face ID / Touch ID preference. Default is **off** so a cold launch
/// never prompts unless the user enabled the Settings (or HTML) toggle.
/// The flag is not a secret — UserDefaults matches Android `TSPPrefs.biometricEnabled`.
/// The session itself stays in Keychain.
@MainActor
final class BiometricSettings: ObservableObject {
    static let shared = BiometricSettings()

    static let preferenceKey = "tsp.biometricUnlockEnabled"

    @Published private(set) var isEnabled: Bool

    static var isEnabled: Bool {
        get { shared.isEnabled }
        set { shared.setEnabled(newValue) }
    }

    static var canEvaluate: Bool { shared.canEvaluate }

    static var biometryName: String { shared.biometryName }

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.preferenceKey)
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.preferenceKey)
    }

    /// Biometrics enrolled and available (Face ID / Touch ID / Optic ID).
    var canEvaluate: Bool {
        #if canImport(LocalAuthentication)
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        #else
        return false
        #endif
    }

    /// Device passcode and/or biometrics — used as unlock fallback.
    var canEvaluateDeviceOwner: Bool {
        #if canImport(LocalAuthentication)
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        #else
        return false
        #endif
    }

    var biometryName: String {
        #if canImport(LocalAuthentication)
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Biometrics"
        }
        #else
        return "Biometrics"
        #endif
    }

    /// Confirm biometrics when turning the toggle on. Cancel / failure does not
    /// change the stored session.
    func confirmEnrollment() async -> BiometricAuthResult {
        await authenticate(
            reason: "Enable \(biometryName) to unlock your Total Service Pro session.",
            allowPasscodeFallback: false
        )
    }

    /// Unlock prompt. Passcode fallback is allowed so cancel/failure is not a
    /// dead end; the Keychain session is never deleted here.
    func promptUnlock() async -> BiometricAuthResult {
        await authenticate(
            reason: "Unlock your Total Service Pro session.",
            allowPasscodeFallback: true
        )
    }

    func authenticate(reason: String, allowPasscodeFallback: Bool) async -> BiometricAuthResult {
        #if canImport(LocalAuthentication)
        let policy: LAPolicy = allowPasscodeFallback
            ? .deviceOwnerAuthentication
            : .deviceOwnerAuthenticationWithBiometrics
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        if allowPasscodeFallback {
            context.localizedFallbackTitle = "Use Passcode"
        } else {
            context.localizedFallbackTitle = ""
        }

        var error: NSError?
        guard context.canEvaluatePolicy(policy, error: &error) else {
            if let error {
                return Self.result(from: error)
            }
            return .unavailable
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: reason) { success, evaluateError in
                if success {
                    continuation.resume(returning: .success)
                    return
                }
                if let evaluateError {
                    continuation.resume(returning: Self.result(from: evaluateError))
                } else {
                    continuation.resume(returning: .failed("Authentication did not succeed."))
                }
            }
        }
        #else
        return .unavailable
        #endif
    }

    #if canImport(LocalAuthentication)
    private static func result(from error: Error) -> BiometricAuthResult {
        let code = (error as NSError).code
        switch code {
        case LAError.userCancel.rawValue,
             LAError.appCancel.rawValue,
             LAError.systemCancel.rawValue,
             LAError.userFallback.rawValue:
            return .canceled
        case LAError.biometryNotAvailable.rawValue,
             LAError.biometryNotEnrolled.rawValue,
             LAError.passcodeNotSet.rawValue,
             LAError.biometryLockout.rawValue:
            return .unavailable
        default:
            return .failed(error.localizedDescription)
        }
    }
    #endif
}

enum BiometricAuthResult: Equatable {
    case success
    case canceled
    case failed(String)
    case unavailable

    var message: String? {
        switch self {
        case .success, .canceled:
            return nil
        case .failed(let text):
            return text
        case .unavailable:
            return "Biometric unlock is not available. Use your password."
        }
    }
}
