import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var biometric: BiometricSettings
    @State private var biometricEnabled = false
    @State private var isUpdatingBiometric = false

    private var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    private var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.photometrytools.ios"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("About") {
                    LabeledContent("Version", value: shortVersion)
                    LabeledContent("Build", value: buildNumber)
                    LabeledContent("App", value: "PhotometryTools")
                    LabeledContent("Brand", value: "Total Service Pro")
                }

                Section("Account") {
                    LabeledContent("Signed in", value: auth.userEmail ?? (auth.isSignedIn ? "Session in Keychain" : "No"))
                    Button("Sign Out", role: .destructive) {
                        Task { await auth.signOut() }
                    }
                }

                Section {
                    Toggle(biometric.biometryName + " unlock", isOn: $biometricEnabled)
                        .disabled((!biometric.canEvaluate && !biometric.isEnabled) || isUpdatingBiometric)
                        .onChange(of: biometricEnabled) { _, newValue in
                            Task { await applyBiometricToggle(newValue) }
                        }
                    Text(biometricHelpText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Security")
                } footer: {
                    Text("Opt-in only. A cold launch never prompts unless this is on. Cancel or a failed Face ID / Touch ID attempt does not sign you out.")
                }

                Section("Identifiers") {
                    LabeledContent("iOS bundle ID", value: bundleIdentifier)
                    LabeledContent("Android application ID", value: "com.photometrytools")
                }

                Section("Supabase") {
                    LabeledContent("Project ref", value: AppConfig.supabaseProjectRef)
                    LabeledContent("URL", value: AppConfig.supabaseURL.absoluteString)
                    LabeledContent(
                        "Anon key",
                        value: AppConfig.isAnonKeyConfigured ? "Loaded from local config" : "Not configured"
                    )
                    Text("Copy Config.example.plist or Secrets.xcconfig.example locally. Never commit real keys.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Out of scope") {
                    Text("Peanut Beach Run, AdMob, StoreKit, signing credentials, and full feature parity are not included.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                biometricEnabled = biometric.isEnabled
            }
            .onChange(of: biometric.isEnabled) { _, newValue in
                if biometricEnabled != newValue {
                    biometricEnabled = newValue
                }
            }
        }
    }

    private var biometricHelpText: String {
        if !biometric.canEvaluate {
            return "\(biometric.biometryName) is not available on this device. The preference stays off."
        }
        if biometric.isEnabled {
            return "When you open the app (or return from the background), \(biometric.biometryName) or your device passcode is required before the signed-in tabs appear. You can also use your account password. The Keychain session is kept until you sign out."
        }
        return "Off by default. Turn on to require \(biometric.biometryName) before showing the signed-in app."
    }

    private func applyBiometricToggle(_ enabled: Bool) async {
        guard enabled != biometric.isEnabled else { return }
        isUpdatingBiometric = true
        defer { isUpdatingBiometric = false }

        if enabled {
            let result = await biometric.confirmEnrollment()
            switch result {
            case .success:
                biometric.setEnabled(true)
                biometricEnabled = true
            case .canceled, .failed, .unavailable:
                biometric.setEnabled(false)
                biometricEnabled = false
            }
        } else {
            biometric.setEnabled(false)
            biometricEnabled = false
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthService.shared)
        .environmentObject(BiometricSettings.shared)
}
