import Foundation

/// Navigation rules for the live repairplanet.net shell.
/// Mirrors Android 1.4 `MainActivity` (production origin, host allowlist,
/// bundled HTML only as offline / calculator fallback). Stripe Checkout and
/// other non-allowlisted http(s) links open in Safari instead of WKWebView.
enum LiveWebPolicy {
    static let productionOrigin = "https://repairplanet.net"

    /// Hybrid `*.html` names → live Next.js paths. Same table as Android
    /// `ASSET_TO_PATH`. Calculator pages that are not listed stay in the bundle.
    static let assetPaths: [String: String] = [
        "index": "/",
        "accepted_bids": "/accepted-bids",
        "service_requests": "/service-requests",
        "notifications": "/notifications",
        "service_schedule": "/service-schedule",
        "marketplace": "/marketplace",
        "equipment_listing": "/marketplace",
        "my_lasers": "/my-lasers",
        "customer_directory": "/customers",
        "customer_profile": "/customers",
        "company_profile": "/company",
        "estimates_list": "/estimates",
        "estimate_generator": "/estimates/new",
        "invoices_list": "/invoices",
        "invoice_form": "/invoices/new",
        "reports_list": "/reports",
        "service_report": "/reports/new",
        "manuals": "/manuals",
        "manual_library": "/manuals",
        "service_manuals": "/manuals",
        "pdf_viewer": "/manuals/view",
        "test_equipment": "/test-equipment",
        "calculators_menu": "/calculators",
        "ai_assistant": "/ai-assistant",
        "onboarding": "/onboarding",
        "list_equipment": "/marketplace",
        "list_parts": "/marketplace/parts",
        "settings": "/settings",
        "user_profile": "/profile",
        "parts_catalog": "/parts",
        "service_hub": "/hub",
        "paywall": "/plans",
        "coming_soon": "/",
        "find_a_rep": "/find-a-rep"
    ]

    /// Hosts that may stay inside the WKWebView. Stripe is intentionally absent:
    /// Checkout / Connect pages open in Safari.
    static let inWebViewHostSuffixes = [
        "repairplanet.net",
        "supabase.co",
        "netlify.app",
        "googleapis.com",
        "gstatic.com",
        "google.com",
        "jsdelivr.net",
        "cdnjs.cloudflare.com"
    ]

    static let storeListingMessage = "The mobile apps are coming soon — they are not in the stores yet."

    enum Start: Equatable {
        case remote(URL)
        case bundled(String)
    }

    enum Navigation: Equatable {
        /// Let this navigation proceed in the current web view.
        case allow
        /// Cancel and load a different URL in the web view.
        case load(URL)
        /// Open in SFSafariViewController (Checkout and other web links).
        case safari(URL)
        /// Open with the system handler (tel, mailto, sms).
        case external(URL)
        /// Main-frame PDF → PDFKit.
        case pdf(URL)
        /// Bundled or live `pdf_viewer.html` → existing manual bridge.
        case pdfViewer(URL)
        /// Offline fallback page in the asset bundle.
        case bundled(String)
        /// Swallow the navigation and tell the user why.
        case blocked(String)
    }

    static func startChoice(lastURL: URL?, networkAvailable: Bool) -> Start {
        if networkAvailable {
            if let lastURL, shouldRemember(lastURL) {
                return .remote(lastURL)
            }
            return .remote(productionHomeURL)
        }
        return .bundled("index")
    }

    static func decide(
        url: URL,
        isMainFrame: Bool,
        networkAvailable: Bool,
        bundleContains: (String) -> Bool
    ) -> Navigation {
        let scheme = url.scheme?.lowercased() ?? ""

        if scheme == "about" || scheme == "blob" || scheme == "data" {
            return .allow
        }

        if scheme == "geo" {
            if let maps = mapsSearchURL(fromGeo: url.absoluteString) {
                return .safari(maps)
            }
            return .blocked("Could not open maps")
        }

        if scheme == "mailto" || scheme == "tel" || scheme == "sms" {
            return .external(url)
        }

        if scheme == "totalservicepro" {
            if let callback = productionAuthCallback(fromAppLink: url) {
                return .load(callback)
            }
            return .load(productionHomeURL)
        }

        if scheme == "intent" || scheme == "market" {
            return .blocked(storeListingMessage)
        }

        if isStoreListing(url) {
            return .blocked(storeListingMessage)
        }

        if isPDFViewerNavigation(url) {
            return .pdfViewer(url)
        }

        if scheme == "file" {
            return decideFileURL(url, networkAvailable: networkAvailable, bundleContains: bundleContains)
        }

        if scheme == "http" || scheme == "https" {
            if isMainFrame && looksLikePDF(url) {
                return .pdf(url)
            }
            if isMainFrame && isStripeHost(url) {
                return .safari(url)
            }
            if isAllowedWebURL(url) {
                return .allow
            }
            if isMainFrame {
                return .safari(url)
            }
            return .allow
        }

        return .blocked("Could not open link")
    }

    static func shouldRemember(_ url: URL) -> Bool {
        guard isProduction(url), !looksLikePDF(url), !isStripeHost(url) else { return false }
        return url.scheme?.lowercased() == "https"
    }

    static func isConnectivityFailure(_ error: Error) -> Bool {
        let ns = error as NSError
        guard ns.domain == NSURLErrorDomain else { return false }
        switch ns.code {
        case NSURLErrorNotConnectedToInternet,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorTimedOut,
             NSURLErrorCannotFindHost,
             NSURLErrorCannotConnectToHost,
             NSURLErrorDNSLookupFailed,
             NSURLErrorInternationalRoamingOff,
             NSURLErrorDataNotAllowed:
            return true
        default:
            return false
        }
    }

    static func isProduction(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        return hostMatches(host, suffix: "repairplanet.net")
    }

    static var productionHomeURL: URL {
        URL(string: productionOrigin + "/")!
    }

    // MARK: - Hosts

    static func isAllowedWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        guard let host = url.host else { return false }
        return inWebViewHostSuffixes.contains { hostMatches(host, suffix: $0) }
    }

    static func isStripeHost(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        return hostMatches(host, suffix: "stripe.com")
    }

    static func hostMatches(_ host: String, suffix: String) -> Bool {
        let h = host.lowercased()
        let s = suffix.lowercased()
        return h == s || h.hasSuffix("." + s)
    }

    static func looksLikePDF(_ url: URL) -> Bool {
        let lower = url.absoluteString.lowercased()
        if lower.contains("content-disposition=attachment") { return true }
        let path = url.path.lowercased()
        return path.contains(".pdf")
    }

    static func isPDFViewerNavigation(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        if name.hasPrefix("pdf_viewer.html") { return true }
        return url.path.lowercased().contains("/pdf_viewer.html")
    }

    static func isStoreListing(_ url: URL) -> Bool {
        let lower = url.absoluteString.lowercased()
        return lower.contains("play.google.com/store") || lower.contains("apps.apple.com")
    }

    // MARK: - File and geo

    static func htmlResourceName(fromFileURL url: URL) -> String? {
        let file = url.lastPathComponent
        guard file.lowercased().hasSuffix(".html") else { return nil }
        let base = url.deletingPathExtension().lastPathComponent.lowercased()
        return base.isEmpty ? nil : base
    }

    static func productionURL(forBundledFile url: URL) -> URL? {
        guard let base = htmlResourceName(fromFileURL: url) else { return nil }
        let dest = assetPaths[base] ?? "/" + base.replacingOccurrences(of: "_", with: "-")
        guard var components = URLComponents(string: productionOrigin + dest) else { return nil }
        if dest != "/" {
            let source = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let query = source?.percentEncodedQuery, !query.isEmpty {
                components.percentEncodedQuery = query
            }
        }
        return components.url
    }

    /// `geo:0,0?q=address` → Google Maps search URL (Android `GeoMapsUrl` fallback).
    static func mapsSearchURL(fromGeo raw: String) -> URL? {
        guard let range = raw.lowercased().range(of: "q=") else { return nil }
        let tail = raw[range.upperBound...]
        let encoded = tail.split(separator: "&", maxSplits: 1).first.map(String.init) ?? ""
        let query = encoded.removingPercentEncoding ?? encoded
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents(string: "https://www.google.com/maps/search/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: trimmed)
        ]
        return components?.url
    }

    /// `totalservicepro://auth-callback#...` stays on the live site (Android handoff).
    static func productionAuthCallback(fromAppLink url: URL) -> URL? {
        guard url.scheme?.lowercased() == "totalservicepro" else { return nil }
        let absolute = url.absoluteString
        let fragment: String
        if let hash = absolute.firstIndex(of: "#") {
            fragment = String(absolute[absolute.index(after: hash)...])
        } else {
            fragment = ""
        }
        let raw = fragment.isEmpty ? (url.query ?? "") : fragment
        var next = "/"
        if let parsed = URLComponents(string: "https://repairplanet.net/?" + raw),
           let candidate = parsed.queryItems?.first(where: { $0.name == "next" })?.value,
           candidate.hasPrefix("/"), !candidate.hasPrefix("//") {
            next = candidate
        }
        var dest = productionOrigin + "/auth/callback"
        if next != "/" {
            let encoded = next.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? next
            dest += "?next=" + encoded
        }
        if !fragment.isEmpty {
            dest += "#" + fragment
        }
        return URL(string: dest)
    }

    private static func decideFileURL(
        _ url: URL,
        networkAvailable: Bool,
        bundleContains: (String) -> Bool
    ) -> Navigation {
        guard let name = htmlResourceName(fromFileURL: url) else {
            return .allow
        }
        if networkAvailable, let live = productionURL(forBundledFile: url) {
            if assetPaths[name] != nil || !bundleContains(name) {
                return .load(live)
            }
        }
        if bundleContains(name) {
            return .allow
        }
        return .bundled("coming_soon")
    }
}

#if LIVE_WEB_POLICY_SELFTEST
@main
enum LiveWebPolicySelfTest {
    static func main() {
        let failures = selfCheck()
        if failures.isEmpty {
            print("live-web-policy: ok")
            return
        }
        for failure in failures {
            fputs(failure + "\n", stderr)
        }
        exit(1)
    }

    static func selfCheck() -> [String] {
        let bundle: Set<String> = ["index", "wavelength", "coming_soon", "service_schedule", "calculators_menu"]
        func contains(_ name: String) -> Bool { bundle.contains(name) }
        var failures: [String] = []

        func check(_ name: String, _ urlString: String, main: Bool = true, online: Bool = true, _ expected: LiveWebPolicy.Navigation) {
            guard let url = URL(string: urlString) else {
                failures.append("\(name): bad url \(urlString)")
                return
            }
            let got = LiveWebPolicy.decide(url: url, isMainFrame: main, networkAvailable: online, bundleContains: contains)
            if got != expected {
                failures.append("\(name): got \(got)")
            }
        }

        check("home", "https://repairplanet.net/", .allow)
        check("hub", "https://repairplanet.net/hub", .allow)
        check("estimates", "https://repairplanet.net/estimates", .allow)
        check("invoices", "https://repairplanet.net/invoices/new", .allow)
        check("marketplace", "https://repairplanet.net/marketplace", .allow)
        check("ai", "https://repairplanet.net/ai-assistant", .allow)
        check("notifications", "https://repairplanet.net/notifications", .allow)
        check("preview", "https://deploy-preview.netlify.app/hub", .allow)
        check("supabase", "https://yljztfajyvjzqikxdddf.supabase.co/auth/v1/token", .allow)
        check("stripe-sub", "https://js.stripe.com/v3/stripe.js", main: false, .allow)
        check(
            "checkout",
            "https://checkout.stripe.com/c/pay/cs_test_abc",
            .safari(URL(string: "https://checkout.stripe.com/c/pay/cs_test_abc")!)
        )
        check(
            "connect",
            "https://connect.stripe.com/setup/e/acct_123",
            .safari(URL(string: "https://connect.stripe.com/setup/e/acct_123")!)
        )
        check(
            "external",
            "https://example.com/partner",
            .safari(URL(string: "https://example.com/partner")!)
        )
        check("store", "https://apps.apple.com/app/id000", .blocked(LiveWebPolicy.storeListingMessage))
        check(
            "pdf",
            "https://yljztfajyvjzqikxdddf.supabase.co/storage/v1/object/sign/manuals/a.pdf?token=1",
            .pdf(URL(string: "https://yljztfajyvjzqikxdddf.supabase.co/storage/v1/object/sign/manuals/a.pdf?token=1")!)
        )
        check(
            "pdf-viewer",
            "file:///tmp/assets/pdf_viewer.html?storage_path=manuals/a.pdf",
            .pdfViewer(URL(string: "file:///tmp/assets/pdf_viewer.html?storage_path=manuals/a.pdf")!)
        )
        check(
            "file-estimates-online",
            "file:///tmp/assets/estimates_list.html",
            .load(URL(string: "https://repairplanet.net/estimates")!)
        )
        check(
            "file-calc-online",
            "file:///tmp/assets/wavelength.html",
            .allow
        )
        check(
            "file-missing-offline",
            "file:///tmp/assets/marketplace.html",
            online: false,
            .bundled("coming_soon")
        )
        check(
            "file-schedule-offline",
            "file:///tmp/assets/service_schedule.html",
            online: false,
            .allow
        )
        check("mailto", "mailto:tech@example.com", .external(URL(string: "mailto:tech@example.com")!))
        if let maps = LiveWebPolicy.mapsSearchURL(fromGeo: "geo:0,0?q=Tempe%2C%20AZ") {
            check("geo", "geo:0,0?q=Tempe%2C%20AZ", .safari(maps))
        } else {
            failures.append("geo: maps url nil")
        }

        let remembered = URL(string: "https://repairplanet.net/invoices")!
        let start = LiveWebPolicy.startChoice(lastURL: remembered, networkAvailable: true)
        if start != .remote(remembered) {
            failures.append("start online last: \(start)")
        }
        let offline = LiveWebPolicy.startChoice(lastURL: remembered, networkAvailable: false)
        if offline != .bundled("index") {
            failures.append("start offline: \(offline)")
        }
        let stripeLast = URL(string: "https://checkout.stripe.com/pay")!
        let ignored = LiveWebPolicy.startChoice(lastURL: stripeLast, networkAvailable: true)
        if ignored != .remote(LiveWebPolicy.productionHomeURL) {
            failures.append("start ignores stripe: \(ignored)")
        }

        let callback = LiveWebPolicy.productionAuthCallback(
            fromAppLink: URL(string: "totalservicepro://auth-callback#access_token=abc&next=%2Fhub")!
        )
        if callback?.host != "repairplanet.net" || callback?.path != "/auth/callback" {
            failures.append("callback: \(String(describing: callback))")
        }

        return failures
    }
}
#endif
