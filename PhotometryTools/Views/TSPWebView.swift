import SwiftUI
import WebKit

/// Loads bundled TSP HTML and injects the Keychain session the way Android does:
/// localStorage `tsp-auth-token`, `restoreSession(...)`, and optional `?_s=`.
struct TSPWebView: UIViewRepresentable {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var biometric: BiometricSettings
    @EnvironmentObject private var unlock: BiometricUnlockController

    var resourceName: String = "index"
    var subdirectory: String? = "assets"

    func makeCoordinator() -> Coordinator {
        Coordinator(auth: auth, biometric: biometric, unlock: unlock)
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
        context.coordinator.biometric = biometric
        context.coordinator.unlock = unlock
        context.coordinator.syncBiometricFlags(
            enabled: biometric.isEnabled,
            canUse: biometric.canEvaluate
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var auth: AuthService
        var biometric: BiometricSettings
        var unlock: BiometricUnlockController
        weak var webView: WKWebView?

        init(auth: AuthService, biometric: BiometricSettings, unlock: BiometricUnlockController) {
            self.auth = auth
            self.biometric = biometric
            self.unlock = unlock
        }

        func syncBiometricFlags(enabled: Bool, canUse: Bool) {
            let js = """
            window.__TSP_BIOMETRIC_ENABLED__ = \(enabled ? "true" : "false");
            window.__TSP_CAN_BIOMETRIC__ = \(canUse ? "true" : "false");
            """
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }

        func bootstrapScript() -> WKUserScript {
            WKUserScript(
                source: Self.androidBridgeJavaScript(
                    sessionJSON: auth.sessionJSON,
                    anonKey: auth.anonKey ?? "",
                    supabaseURL: AppConfig.supabaseURL.absoluteString,
                    biometricEnabled: biometric.isEnabled,
                    canUseBiometric: biometric.canEvaluate
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
            Task { @MainActor in
                syncBiometricFlags(enabled: biometric.isEnabled, canUse: biometric.canEvaluate)
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

            if isPDFViewerNavigation(url) {
                decisionHandler(.cancel)
                TSPPDFBridge.shared.handlePDFViewerNavigation(url)
                return
            }

            if let scheme = url.scheme, scheme == "http" || scheme == "https" {
                let isMainFrame = navigationAction.targetFrame?.isMainFrame != false
                if isMainFrame && (url.pathExtension.lowercased() == "pdf"
                    || url.path.lowercased().contains(".pdf")) {
                    decisionHandler(.cancel)
                    Task { @MainActor in
                        do {
                            _ = try await TSPPDFBridge.shared.openOrShare(
                                spec: ["url": url.absoluteString, "title": url.lastPathComponent],
                                share: false
                            )
                        } catch {
                            PDFHost.presentAlert(title: "Could not open PDF", message: error.localizedDescription)
                        }
                    }
                    return
                }
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

        private func isPDFViewerNavigation(_ url: URL) -> Bool {
            let name = url.lastPathComponent.lowercased()
            if name.hasPrefix("pdf_viewer.html") { return true }
            return url.path.lowercased().contains("/pdf_viewer.html")
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
            let requestId: String
            let payload: Any
            if let body = message.body as? [String: Any] {
                type = body["type"] as? String ?? ""
                requestId = body["requestId"] as? String ?? ""
                payload = body["payload"] ?? ""
            } else {
                type = ""
                requestId = ""
                payload = ""
            }

            Task { @MainActor in
                await handleBridgeMessage(type: type, payload: payload, requestId: requestId)
            }
        }

        private func handleBridgeMessage(type: String, payload: Any, requestId: String) async {
            let text = stringPayload(payload)
            let spec = dictionaryPayload(payload)

            switch type {
            case "saveSession":
                auth.applyWebSessionJSON(text)
            case "clearSession":
                auth.applyWebClearSession()
            case "showToast":
                auth.lastMessage = text
            case "setBiometricEnabled":
                let enabled = text == "true" || text == "1"
                biometric.setEnabled(enabled)
                syncBiometricFlags(enabled: biometric.isEnabled, canUse: biometric.canEvaluate)
            case "openUrl":
                if let url = URL(string: text) {
                    UIApplication.shared.open(url)
                }
            case "goBack":
                if webView?.canGoBack == true {
                    webView?.goBack()
                }
            case "showLoginPopup":
                // Do not wipe Keychain or sign out (Android cancel could).
                // Offer the password path on the lock screen if biometric is on.
                if auth.isSignedIn && biometric.isEnabled {
                    unlock.requestPasswordFallback()
                }
            case "getManualUrl":
                let path = spec["storage_path"] as? String ?? spec["storagePath"] as? String ?? text
                do {
                    let url = try await TSPPDFBridge.shared.signedManualURL(storagePath: path)
                    reply(requestId: requestId, value: url.absoluteString)
                } catch {
                    reply(requestId: requestId, error: error.localizedDescription)
                }
            case "openManual":
                let path = spec["storage_path"] as? String ?? spec["storagePath"] as? String ?? ""
                let title = spec["title"] as? String ?? "Service Manual"
                let manualID = intValue(spec["manual_id"]) ?? intValue(spec["manualId"])
                await TSPPDFBridge.shared.openManual(storagePath: path, title: title, manualID: manualID)
                reply(requestId: requestId, value: true)
            case "openPdf":
                do {
                    let path = try await TSPPDFBridge.shared.openOrShare(spec: spec.isEmpty ? ["url": text] : spec, share: false)
                    reply(requestId: requestId, value: path)
                } catch {
                    reply(requestId: requestId, error: error.localizedDescription)
                    PDFHost.presentAlert(title: "Could not open PDF", message: error.localizedDescription)
                }
            case "sharePdf":
                do {
                    let path = try await TSPPDFBridge.shared.openOrShare(spec: spec.isEmpty ? ["url": text] : spec, share: true)
                    reply(requestId: requestId, value: path)
                } catch {
                    reply(requestId: requestId, error: error.localizedDescription)
                    PDFHost.presentAlert(title: "Could not share PDF", message: error.localizedDescription)
                }
            case "printReport":
                let html = spec["html"] as? String ?? text
                let jobName = spec["jobName"] as? String ?? spec["title"] as? String ?? "Service Report"
                await TSPPDFBridge.shared.printReport(html: html, jobName: jobName)
                reply(requestId: requestId, value: true)
            default:
                break
            }
        }

        private func reply(requestId: String, value: Any? = nil, error: String? = nil) {
            guard !requestId.isEmpty, let webView else { return }
            var body: [String: Any] = ["id": requestId, "ok": error == nil]
            if let error, !error.isEmpty {
                body["error"] = error
            } else if let value {
                body["value"] = value
            }
            guard let data = try? JSONSerialization.data(withJSONObject: body),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript("window.__tspComplete && window.__tspComplete(\(json));", completionHandler: nil)
        }

        private func stringPayload(_ payload: Any) -> String {
            if let value = payload as? String { return value }
            if let value = payload as? [String: Any],
               let nested = value["value"] as? String {
                return nested
            }
            return ""
        }

        private func dictionaryPayload(_ payload: Any) -> [String: Any] {
            if let dict = payload as? [String: Any] { return dict }
            if let text = payload as? String, let data = text.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return dict
            }
            return [:]
        }

        private func intValue(_ value: Any?) -> Int? {
            switch value {
            case let n as Int: return n
            case let n as NSNumber: return n.intValue
            case let s as String: return Int(s)
            default: return nil
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
              window.__tspPending = window.__tspPending || {};
              window.__tspComplete = function(msg) {
                if (!msg || !msg.id) return;
                var pending = window.__tspPending[msg.id];
                if (!pending) return;
                delete window.__tspPending[msg.id];
                if (msg.ok) pending.resolve(msg.value);
                else pending.reject(new Error(msg.error || 'Native request failed'));
              };
              function post(type, payload, requestId) {
                try {
                  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tsp) {
                    window.webkit.messageHandlers.tsp.postMessage({
                      type: type,
                      payload: payload == null ? '' : payload,
                      requestId: requestId || ''
                    });
                  }
                } catch (e) {}
              }
              function invoke(type, payload) {
                return new Promise(function(resolve, reject) {
                  var id = String(Date.now()) + '-' + Math.random().toString(16).slice(2);
                  window.__tspPending[id] = { resolve: resolve, reject: reject };
                  post(type, payload, id);
                });
              }
              function pdfSpec(urlOrPath, title) {
                if (urlOrPath && typeof urlOrPath === 'object' && !Array.isArray(urlOrPath)) {
                  return urlOrPath;
                }
                return { url: String(urlOrPath || ''), title: title || 'Document' };
              }
              function sendPdf(type, urlOrPath, title) {
                var spec = Object.assign({}, pdfSpec(urlOrPath, title));
                var raw = spec.url || spec.path || spec.file || '';
                if (typeof raw === 'string' && raw.indexOf('blob:') === 0) {
                  return fetch(raw).then(function(r) { return r.arrayBuffer(); }).then(function(buf) {
                    var bytes = new Uint8Array(buf);
                    var binary = '';
                    for (var i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
                    spec.base64 = btoa(binary);
                    delete spec.url;
                    return invoke(type, spec);
                  });
                }
                return invoke(type, spec);
              }
              document.addEventListener('DOMContentLoaded', function() {
                try {
                  var loginChk = document.getElementById('enableBiometric');
                  if (loginChk) loginChk.checked = !!window.__TSP_BIOMETRIC_ENABLED__;
                  var settingsChk = document.getElementById('biometricLogin');
                  if (settingsChk) settingsChk.checked = !!window.__TSP_BIOMETRIC_ENABLED__;
                } catch (e) {}
              });
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
                getManualUrl: function(storagePath) {
                  var path = storagePath;
                  if (storagePath && typeof storagePath === 'object') {
                    path = storagePath.storage_path || storagePath.storagePath || '';
                  }
                  return invoke('getManualUrl', { storage_path: String(path || '') });
                },
                openManual: function(payload) {
                  var spec = payload;
                  if (typeof payload === 'string') {
                    try { spec = JSON.parse(payload); } catch (e) { spec = { storage_path: payload }; }
                  }
                  spec = spec || {};
                  return invoke('openManual', spec);
                },
                openPdf: function(urlOrPath, title) { return sendPdf('openPdf', urlOrPath, title); },
                sharePdf: function(urlOrPath, title) { return sendPdf('sharePdf', urlOrPath, title); },
                printReport: function(html, jobName) {
                  return invoke('printReport', {
                    html: String(html || ''),
                    jobName: String(jobName || 'Service Report')
                  });
                },
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
