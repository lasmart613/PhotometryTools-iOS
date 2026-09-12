import SwiftUI

/// Gates the signed-in shell behind an opt-in LocalAuthentication prompt.
///
/// Lessons from Android:
/// - Never prompt on cold launch unless the user opted in.
/// - Cancel / failure must not clear Keychain or sign the user out.
/// - Device passcode (LA policy) and a password re-auth path are fallbacks.
@MainActor
final class BiometricUnlockController: ObservableObject {
    static let shared = BiometricUnlockController()

    @Published private(set) var isLocked = false
    @Published private(set) var isPrompting = false
    @Published var prefersPasswordFallback = false
    @Published var lastMessage: String?

    private var didPrepareLaunch = false
    private var skipAutoPrompt = false

    /// Call once at launch. Locks only when a Keychain session exists **and**
    /// the user enabled biometric unlock.
    func prepareForLaunch(isSignedIn: Bool, isEnabled: Bool) {
        guard !didPrepareLaunch else { return }
        didPrepareLaunch = true
        if isSignedIn && isEnabled {
            isLocked = true
        } else {
            isLocked = false
        }
    }

    func shouldCoverShell(isSignedIn: Bool, isEnabled: Bool) -> Bool {
        isSignedIn && isEnabled && isLocked
    }

    func markUnlocked() {
        isLocked = false
        isPrompting = false
        prefersPasswordFallback = false
        skipAutoPrompt = false
        lastMessage = nil
    }

    func resetAfterSignOut() {
        isLocked = false
        isPrompting = false
        prefersPasswordFallback = false
        skipAutoPrompt = false
        lastMessage = nil
    }

    /// Fresh password sign-in already proved identity — do not lock.
    func handleSignedInTransition() {
        markUnlocked()
    }

    func requestPasswordFallback() {
        if !isLocked {
            isLocked = true
        }
        prefersPasswordFallback = true
        lastMessage = nil
    }

    func cancelPasswordFallback() {
        prefersPasswordFallback = false
        lastMessage = nil
    }

    func handleScenePhase(_ phase: ScenePhase, isSignedIn: Bool, isEnabled: Bool) {
        switch phase {
        case .background:
            if isSignedIn && isEnabled {
                isLocked = true
                prefersPasswordFallback = false
                skipAutoPrompt = false
            }
        case .active:
            break
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    /// Shows Face ID / Touch ID (with device passcode fallback). Cancel leaves
    /// the lock screen up and keeps the Keychain session.
    func promptIfNeeded(isSignedIn: Bool, isEnabled: Bool, force: Bool = false) async {
        guard isSignedIn, isEnabled, isLocked, !isPrompting, !prefersPasswordFallback else {
            return
        }
        if skipAutoPrompt && !force {
            return
        }
        if force {
            skipAutoPrompt = false
        }

        isPrompting = true
        lastMessage = nil
        let result = await BiometricSettings.shared.promptUnlock()
        isPrompting = false

        switch result {
        case .success:
            markUnlocked()
        case .canceled:
            // Android cancel could full sign-out — do not repeat that.
            isLocked = true
            skipAutoPrompt = true
            lastMessage = "Unlock canceled. Session is still saved."
        case .failed(let text):
            isLocked = true
            skipAutoPrompt = true
            lastMessage = text
        case .unavailable:
            isLocked = true
            lastMessage = result.message
            prefersPasswordFallback = true
        }
    }
}
