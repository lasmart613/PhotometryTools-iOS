import Foundation

/// Reads Supabase settings from Info.plist (xcconfig-injected) or an optional
/// bundled `Config.plist`. Real anon keys must live only in gitignored files.
enum AppConfig {
    static let supabaseProjectRef = "yljztfajyvjzqikxdddf"

    /// Numeric marketing version lives in the Xcode target (`0.5.0`).
    /// Settings shows this soft-beta label.
    static let marketingLabel = "0.5.0-beta"

    /// Same origin Android 1.4 loads. Bundled HTML is offline fallback only.
    static let productionOrigin = URL(string: "https://repairplanet.net")!

    /// `TSPAndroid/` keeps repairplanet.net on the in-app session bridge
    /// (`isTspAndroidWebView`). `TSPiOS/` identifies this shell.
    static let webViewUserAgentToken = "TSPAndroid/1.4 TSPiOS/0.5.0"

    static let lastWebURLDefaultsKey = "tsp.lastWebURL"

    static let defaultSupabaseURL = URL(string: "https://yljztfajyvjzqikxdddf.supabase.co")!

    static var supabaseURL: URL {
        if let raw = stringValue(for: "SUPABASE_URL"),
           let url = URL(string: raw),
           !isPlaceholder(raw) {
            return url
        }
        return defaultSupabaseURL
    }

    static var supabaseAnonKey: String? {
        guard let key = stringValue(for: "SUPABASE_ANON_KEY"), !isPlaceholder(key) else {
            return nil
        }
        return key
    }

    static var isAnonKeyConfigured: Bool {
        supabaseAnonKey != nil
    }

    private static func stringValue(for key: String) -> String? {
        if let fromInfo = Bundle.main.object(forInfoDictionaryKey: key) as? String,
           !fromInfo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fromInfo
        }

        if let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let value = plist[key] as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }

        return nil
    }

    private static func isPlaceholder(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            || trimmed.contains("YOUR_")
            || trimmed.hasPrefix("$(")
    }
}
