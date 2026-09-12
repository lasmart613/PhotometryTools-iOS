import SwiftUI

/// Opaque cover over the signed-in shell until Face ID / Touch ID (or password)
/// succeeds. Cancel and failed attempts stay here — they do not sign out.
struct BiometricLockView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var biometric: BiometricSettings
    @EnvironmentObject private var unlock: BiometricUnlockController

    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: lockSymbol)
                    .font(.system(size: 48))
                    .foregroundStyle(.white)

                Text("Total Service Pro")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                Text(unlock.prefersPasswordFallback
                     ? "Enter your password to continue. This does not delete your saved session."
                     : "Unlock with \(biometric.biometryName) to open your session.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                if unlock.prefersPasswordFallback {
                    passwordForm
                } else {
                    biometricActions
                }

                if let message = unlock.lastMessage ?? auth.lastMessage, !message.isEmpty {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()

                Button("Sign Out") {
                    Task { await auth.signOut() }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.bottom, 28)
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            if email.isEmpty {
                email = auth.userEmail ?? ""
            }
        }
    }

    private var lockSymbol: String {
        switch biometric.biometryName {
        case "Face ID": return "faceid"
        case "Touch ID": return "touchid"
        default: return "lock.fill"
        }
    }

    private var biometricActions: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    await unlock.promptIfNeeded(
                        isSignedIn: auth.isSignedIn,
                        isEnabled: biometric.isEnabled,
                        force: true
                    )
                }
            } label: {
                Text("Unlock with \(biometric.biometryName)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(unlock.isPrompting)

            Button("Use password") {
                unlock.requestPasswordFallback()
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
    }

    private var passwordForm: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)

            SecureField("Password", text: $password)
                .textContentType(.password)
                .padding(12)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)

            Button {
                Task { await submitPassword() }
            } label: {
                if isWorking {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking || email.trimmed.isEmpty || password.isEmpty)

            Button("Use \(biometric.biometryName)") {
                unlock.cancelPasswordFallback()
                Task {
                    await unlock.promptIfNeeded(
                        isSignedIn: auth.isSignedIn,
                        isEnabled: biometric.isEnabled,
                        force: true
                    )
                }
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .disabled(!biometric.canEvaluate && !biometric.canEvaluateDeviceOwner)
        }
    }

    private func submitPassword() async {
        isWorking = true
        let succeeded = await auth.reauthenticate(email: email.trimmed, password: password)
        isWorking = false
        if succeeded {
            unlock.markUnlocked()
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    BiometricLockView()
        .environmentObject(AuthService.shared)
        .environmentObject(BiometricSettings.shared)
        .environmentObject(BiometricUnlockController.shared)
}
