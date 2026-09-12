import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthService

    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false

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

                Section {
                    Button {
                        Task {
                            isWorking = true
                            await auth.signIn(email: email.trimmed, password: password)
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
}
