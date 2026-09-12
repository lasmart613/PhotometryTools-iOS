import SwiftUI
import WebKit

/// Loads bundled TSP HTML and injects the Keychain session the way Android does:
/// localStorage `tsp-auth-token`, `restoreSession(...)`, and optional `?_s=`.
struct TSPWebView: UIViewRepresentable {
    @EnvironmentObject private var auth: AuthService

    var resourceName: String = "index"
    var subdirectory: String? = "assets"

    func makeCoordinator() -> Coordinator {
        Coordinator(auth: auth)
    }

    func makeUIView(context: Context) -> WKWebView {
        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "tsp")
        userContent.addUserScript(context.coordinator.bootstrapScript())

        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences = preferences
        configuration.userContentController = userContent
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        context.coordinator.webView = webView
        context.coordinator.loadBundledPage(
            named: resourceName,
            subdirectory: subdirectory,
            in: webView
        )
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.auth = auth
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var auth: AuthService
        weak var webView: WKWebView?

        init(auth: AuthService) {
            self.auth = auth
        }

        func bootstrapScript() -> WKUserScript {
            WKUserScript(
                source: Self.androidBridgeJavaScript(
                    sessionJSON: auth.sessionJSON,
                    anonKey: auth.anonKey ?? "",
                    supabaseURL: AppConfig.supabaseURL.absoluteString,
                    biometricEnabled: BiometricSettings.isEnabled,
                    canUseBiometric: BiometricSettings.canEvaluate
                ),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        }

        func loadBundledPage(named resourceName: String, subdirectory: String?, in webView: WKWebView) {
            let candidates = [
                (resourceName, subdirectory),
                ("placeholder", subdirectory),
                ("placeholder", "assets")
            ]

            for (name, folder) in candidates {
                if let url = Bundle.main.url(forResource: name, withExtension: "html", subdirectory: folder) {
                    // First load matches Android `file:///android_asset/index.html`
                    // (no `?_s=`). Session is injected via user script + restoreSession.
                    // In-page `navTo()` still appends `?_s=` for subsequent hops.
                    webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
                    return
                }
            }

            webView.loadHTMLString(Self.missingAssetHTML, baseURL: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let json = auth.sessionJSON, !json.isEmpty else { return }
            let escaped = Self.escapeForSingleQuotedJS(json)
            let js = """
            (function(){
              try {
                var raw = '\(escaped)';
                window.__TSP_STORED_SESSION__ = raw;
                try { localStorage.setItem('tsp-auth-token', raw); } catch (e) {}
                if (typeof restoreSession === 'function') { restoreSession(raw); }
              } catch (e) {}
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if let scheme = url.scheme, scheme == "http" || scheme == "https" {
                if url.host?.contains("supabase.co") == true
                    || url.host?.contains("jsdelivr.net") == true
                    || url.host?.contains("googleapis.com") == true
                    || url.host?.contains("gstatic.com") == true
                    || url.host?.contains("cdnjs.cloudflare.com") == true {
                    decisionHandler(.allow)
                    return
                }
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            if let comingSoon = Bundle.main.url(
                forResource: "coming_soon",
                withExtension: "html",
                subdirectory: "assets"
            ) {
                webView.loadFileURL(comingSoon, allowingReadAccessTo: comingSoon.deletingLastPathComponent())
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "tsp" else { return }

            let type: String
            let payload: String
            if let body = message.body as? [String: Any] {
                type = body["type"] as? String ?? ""
                if let value = body["payload"] as? String {
                    payload = value
                } else if let value = body["payload"] {
                    payload = String(describing: value)
                } else {
                    payload = ""
                }
            } else {
                type = ""
                payload = ""
            }

            Task { @MainActor in
                switch type {
                case "saveSession":
                    auth.applyWebSessionJSON(payload)
                case "clearSession":
                    auth.applyWebClearSession()
                case "showToast":
                    auth.lastMessage = payload
                case "setBiometricEnabled":
                    BiometricSettings.isEnabled = payload == "true" || payload == "1"
                case "openUrl":
                    if let url = URL(string: payload) {
                        UIApplication.shared.open(url)
                    }
                case "goBack":
                    if webView?.canGoBack == true {
                        webView?.goBack()
                    }
                case "showLoginPopup":
                    await auth.signOut()
                default:
                    break
                }
            }
        }

        private static func androidBridgeJavaScript(
            sessionJSON: String?,
            anonKey: String,
            supabaseURL: String,
            biometricEnabled: Bool,
            canUseBiometric: Bool
        ) -> String {
            let session = sessionJSON ?? ""
            let localStorageValue = session.isEmpty ? "" : TSPSessionJSON.localStorageValue(from: session)
            return """
            (function() {
              window.TSP_CONFIG = {
                supabaseURL: \(Self.jsonStringLiteral(supabaseURL)),
                supabaseAnonKey: \(Self.jsonStringLiteral(anonKey)),
                platform: 'ios'
              };
              window.__TSP_STORED_SESSION__ = \(Self.jsonStringLiteral(session));
              window.__TSP_BIOMETRIC_ENABLED__ = \(biometricEnabled ? "true" : "false");
              window.__TSP_CAN_BIOMETRIC__ = \(canUseBiometric ? "true" : "false");
              try {
                var stored = \(Self.jsonStringLiteral(localStorageValue));
                if (stored) { localStorage.setItem('tsp-auth-token', stored); }
              } catch (e) {}
              function post(type, payload) {
                try {
                  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tsp) {
                    window.webkit.messageHandlers.tsp.postMessage({
                      type: type,
                      payload: payload == null ? '' : String(payload)
                    });
                  }
                } catch (e) {}
              }
              window.Android = {
                saveSession: function(json) {
                  window.__TSP_STORED_SESSION__ = json;
                  post('saveSession', json);
                },
                clearSession: function() {
                  window.__TSP_STORED_SESSION__ = '';
                  try { localStorage.removeItem('tsp-auth-token'); } catch (e) {}
                  post('clearSession', '');
                },
                getStoredSession: function() { return window.__TSP_STORED_SESSION__ || ''; },
                showToast: function(msg) { post('showToast', msg); },
                setBiometricEnabled: function(enabled) {
                  window.__TSP_BIOMETRIC_ENABLED__ = !!enabled;
                  post('setBiometricEnabled', enabled ? 'true' : 'false');
                },
                isBiometricEnabled: function() { return !!window.__TSP_BIOMETRIC_ENABLED__; },
                canUseBiometric: function() { return !!window.__TSP_CAN_BIOMETRIC__; },
                goBack: function() { post('goBack', ''); },
                openUrl: function(url) { post('openUrl', url); },
                showLoginPopup: function() { post('showLoginPopup', ''); },
                getExitConfirmEnabled: function() { return true; },
                setExitConfirmEnabled: function() {},
                speak: function() {},
                startVoiceRecognition: function() {},
                stopVoiceRecognition: function() {},
                launchBillingFlow: function() {},
                checkSubscription: function() {},
                printReport: function() {},
                getPremiumStatus: function() { return false; },
                setPremiumStatus: function() {}
              };
            })();
            """
        }

        private static func jsonStringLiteral(_ value: String) -> String {
            let data = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)
            return String(data: data ?? Data("\"\"".utf8), encoding: .utf8) ?? "\"\""
        }

        private static func escapeForSingleQuotedJS(_ value: String) -> String {
            value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
        }

        private static let missingAssetHTML = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>TSP shell</title>
        </head>
        <body style="font-family:-apple-system,sans-serif;padding:24px;background:#0f1419;color:#e8eef4;">
          <h1>Assets not found</h1>
          <p>Expected bundled <code>Resources/assets/index.html</code>. Run <code>Scripts/sync-web-assets.sh</code>.</p>
        </body>
        </html>
        """
    }
}
