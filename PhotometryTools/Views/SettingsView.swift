import SwiftUI

struct SettingsView: View {
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

                Section("Out of scope (this scaffold)") {
                    Text("Peanut Beach Run, AdMob, StoreKit, signing credentials, and full feature parity are not included.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
