import SwiftUI

@main
struct PhotometryToolsApp: App {
    @StateObject private var auth = AuthService.shared
    @StateObject private var biometric = BiometricSettings.shared
    @StateObject private var unlock = BiometricUnlockController.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(biometric)
                .environmentObject(unlock)
                .task {
                    unlock.prepareForLaunch(
                        isSignedIn: auth.isSignedIn,
                        isEnabled: biometric.isEnabled
                    )
                    await auth.bootstrap()
                    await unlock.promptIfNeeded(
                        isSignedIn: auth.isSignedIn,
                        isEnabled: biometric.isEnabled
                    )
                }
                .onChange(of: scenePhase) { _, phase in
                    unlock.handleScenePhase(
                        phase,
                        isSignedIn: auth.isSignedIn,
                        isEnabled: biometric.isEnabled
                    )
                    if phase == .active {
                        Task {
                            await unlock.promptIfNeeded(
                                isSignedIn: auth.isSignedIn,
                                isEnabled: biometric.isEnabled
                            )
                        }
                    }
                }
                .onChange(of: auth.isSignedIn) { wasSignedIn, isSignedIn in
                    if isSignedIn && !wasSignedIn {
                        unlock.handleSignedInTransition()
                    } else if !isSignedIn {
                        unlock.resetAfterSignOut()
                    }
                }
        }
    }
}
