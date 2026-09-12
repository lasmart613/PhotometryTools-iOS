import Foundation

/// Stub stand-in for [supabase-swift](https://github.com/supabase/supabase-swift).
///
/// When the official package is added (`Supabase` product), replace this type
/// with `SupabaseClient(supabaseURL: AppConfig.supabaseURL, supabaseKey: key)`.
///
/// Project: `yljztfajyvjzqikxdddf`
/// Host: `https://yljztfajyvjzqikxdddf.supabase.co`
@MainActor
final class SupabaseClientStub {
    static let shared = SupabaseClientStub()

    let url: URL
    private let anonKey: String?

    var isConfigured: Bool { anonKey != nil }

    init(
        url: URL = AppConfig.supabaseURL,
        anonKey: String? = AppConfig.supabaseAnonKey
    ) {
        self.url = url
        self.anonKey = anonKey
    }

    /// Documents the intended supabase-swift construction without importing the SDK.
    func clientBootstrapDescription() -> String {
        guard isConfigured else {
            return "Supabase client is not configured. Add Secrets.xcconfig or Config.plist from the example files."
        }
        return "Ready for supabase-swift: SupabaseClient(supabaseURL: \(url.absoluteString), supabaseKey: <anon key from local config>)"
    }
}
