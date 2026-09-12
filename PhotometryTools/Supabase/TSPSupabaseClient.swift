import Foundation
import Supabase

/// Real [supabase-swift](https://github.com/supabase/supabase-swift) client.
/// Anon key comes from gitignored Secrets.xcconfig / Config.plist only.
/// Session persistence uses the SDK default `KeychainLocalStorage`.
enum TSPSupabaseClient {
    static func make(anonKey: String) -> SupabaseClient {
        SupabaseClient(
            supabaseURL: AppConfig.supabaseURL,
            supabaseKey: anonKey,
            options: SupabaseClientOptions(
                auth: .init(
                    storage: KeychainLocalStorage(),
                    storageKey: "tsp-auth-token",
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }
}
