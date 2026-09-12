import SwiftUI

/// Signed-out: native login. Signed-in: tab shell + Home WKWebView.
/// When biometric unlock is opted in, an opaque lock covers the shell until
/// Face ID / Touch ID or password succeeds. Cancel does not sign out.
struct RootView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var biometric: BiometricSettings
    @EnvironmentObject private var unlock: BiometricUnlockController

    var body: some View {
        Group {
            if auth.isSignedIn {
                ZStack {
                    ContentView()
                    if unlock.shouldCoverShell(isSignedIn: true, isEnabled: biometric.isEnabled) {
                        BiometricLockView()
                    }
                }
            } else {
                LoginView()
            }
        }
        .animation(.default, value: auth.isSignedIn)
        .animation(.default, value: unlock.isLocked)
    }
}

#Preview {
    RootView()
        .environmentObject(AuthService.shared)
        .environmentObject(BiometricSettings.shared)
        .environmentObject(BiometricUnlockController.shared)
}
