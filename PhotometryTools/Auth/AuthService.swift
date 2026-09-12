import Foundation
import Supabase
import SwiftUI

/// Email/password auth plus Keychain session used by the WKWebView bridge.
@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published private(set) var isSignedIn = false
    @Published private(set) var isConfigured = false
    @Published private(set) var sessionJSON: String?
    @Published private(set) var userEmail: String?
    @Published var lastMessage: String?

    private var client: SupabaseClient?

    var supabase: SupabaseClient? { client }

    var anonKey: String? { AppConfig.supabaseAnonKey }

    init() {
        isConfigured = AppConfig.isAnonKeyConfigured
        sessionJSON = SessionKeychain.load()
        isSignedIn = TSPSessionJSON.tokens(from: sessionJSON ?? "") != nil
    }

    func bootstrap() async {
        isConfigured = AppConfig.isAnonKeyConfigured
        guard let key = AppConfig.supabaseAnonKey else {
            lastMessage = "Add Secrets.xcconfig or Config.plist from the example files."
            return
        }

        let client = TSPSupabaseClient.make(anonKey: key)
        self.client = client

        if let session = try? await client.auth.session {
            persist(session: session)
            return
        }

        if let stored = SessionKeychain.load(),
           let tokens = TSPSessionJSON.tokens(from: stored),
           !tokens.refreshToken.isEmpty {
            do {
                let session = try await client.auth.setSession(
                    accessToken: tokens.accessToken,
                    refreshToken: tokens.refreshToken
                )
                persist(session: session)
            } catch {
                clearLocalSession()
                lastMessage = error.localizedDescription
            }
        }
    }

    func signIn(email: String, password: String) async {
        lastMessage = nil
        guard let client else {
            lastMessage = "Supabase is not configured. Copy Secrets.xcconfig.example locally."
            return
        }

        do {
            let response = try await client.auth.signIn(email: email, password: password)
            persist(session: response)
        } catch {
            lastMessage = error.localizedDescription
        }
    }

    func signOut() async {
        lastMessage = nil
        do {
            try await client?.auth.signOut()
        } catch {
            lastMessage = error.localizedDescription
        }
        clearLocalSession()
        BiometricSettings.isEnabled = false
    }

    /// Magic-link stub — sends OTP email; deep-link completion is P1.
    func sendMagicLink(email: String) async {
        lastMessage = nil
        guard let client else {
            lastMessage = "Supabase is not configured."
            return
        }
        do {
            try await client.auth.signInWithOTP(email: email)
            lastMessage = "Magic link sent. Check your email (return-to-app is a later slice)."
        } catch {
            lastMessage = error.localizedDescription
        }
    }

    /// Password-reset stub — sends reset email.
    func resetPassword(email: String) async {
        lastMessage = nil
        guard let client else {
            lastMessage = "Supabase is not configured."
            return
        }
        do {
            try await client.auth.resetPasswordForEmail(email)
            lastMessage = "Password reset email sent."
        } catch {
            lastMessage = error.localizedDescription
        }
    }

    /// Called from the Android-compatible JS bridge (`Android.saveSession`).
    func applyWebSessionJSON(_ json: String) {
        guard TSPSessionJSON.tokens(from: json) != nil else { return }
        do {
            try SessionKeychain.save(json)
            sessionJSON = json
            isSignedIn = true
        } catch {
            lastMessage = error.localizedDescription
        }
    }

    /// Called from `Android.clearSession`.
    func applyWebClearSession() {
        clearLocalSession()
        BiometricSettings.isEnabled = false
        Task { try? await client?.auth.signOut() }
    }

    private func persist(session: Session) {
        guard let json = TSPSessionJSON.encode(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            expiresAt: session.expiresAt
        ) else {
            lastMessage = "Could not encode session."
            return
        }

        do {
            try SessionKeychain.save(json)
            sessionJSON = json
            userEmail = session.user.email
            isSignedIn = true
        } catch {
            lastMessage = error.localizedDescription
        }
    }

    private func clearLocalSession() {
        try? SessionKeychain.delete()
        sessionJSON = nil
        userEmail = nil
        isSignedIn = false
    }
}
