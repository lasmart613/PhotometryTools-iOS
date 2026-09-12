import Foundation
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

/// Preference + capability stub for P1 LocalAuthentication.
/// Toggle is real; unlock prompt is not finished this slice.
enum BiometricSettings {
    private static let key = "tsp.biometricUnlockEnabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static var canEvaluate: Bool {
        #if canImport(LocalAuthentication)
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        #else
        return false
        #endif
    }

    static var biometryName: String {
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
}
