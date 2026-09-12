import SwiftUI

@main
struct PhotometryToolsApp: App {
    @StateObject private var auth = AuthService.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .task {
                    await auth.bootstrap()
                }
        }
    }
}
