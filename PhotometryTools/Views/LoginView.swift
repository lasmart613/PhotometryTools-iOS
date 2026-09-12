import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var biometric: BiometricSettings

    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var enableBiometricUnlock = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Sign in with the same Supabase account used on Android / Total Service Pro.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !auth.isConfigured {
                    Section("Setup required") {
                        Text("Copy Secrets.xcconfig.example → Secrets.xcconfig (or Config.example.plist → Config.plist) and add the project anon key. Do not commit those files.")
                        LabeledContent("Project ref", value: AppConfig.supabaseProjectRef)
                    }
                }

                Section("Account") {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }

                if biometric.canEvaluate {
                    Section {
                        Toggle("Enable \(biometric.biometryName) unlock", isOn: $enableBiometricUnlock)
                        Text("Off by default. Turn this on only if you want \(biometric.biometryName) before the signed-in app on the next launch.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        Task {
                            isWorking = true
                            await auth.signIn(email: email.trimmed, password: password)
                            if auth.isSignedIn && enableBiometricUnlock {
                                let result = await biometric.confirmEnrollment()
                                if result == .success {
                                    biometric.setEnabled(true)
                                }
                            }
                            isWorking = false
                        }
                    } label: {
                        if isWorking {
                            ProgressView()
                        } else {
                            Text("Sign In")
                        }
                    }
                    .disabled(isWorking || email.trimmed.isEmpty || password.isEmpty || !auth.isConfigured)

                    Button("Send magic link") {
                        Task {
                            isWorking = true
                            await auth.sendMagicLink(email: email.trimmed)
                            isWorking = false
                        }
                    }
                    .disabled(isWorking || email.trimmed.isEmpty || !auth.isConfigured)

                    Button("Reset password") {
                        Task {
                            isWorking = true
                            await auth.resetPassword(email: email.trimmed)
                            isWorking = false
                        }
                    }
                    .disabled(isWorking || email.trimmed.isEmpty || !auth.isConfigured)
                }

                if let message = auth.lastMessage, !message.isEmpty {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Total Service Pro")
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthService.shared)
        .environmentObject(BiometricSettings.shared)
}
