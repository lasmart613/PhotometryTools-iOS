import Network
import SafariServices
import SwiftUI
import WebKit

/// Home shell. Online, this is the live site (`https://repairplanet.net`) with the
/// Android 1.4 session bridge. Bundled HTML is the offline / calculator fallback.
struct TSPWebView: UIViewRepresentable {
    enum Entry: Equatable {
        case liveSite
        case bundled(resource: String, subdirectory: String?)
    }

    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var biometric: BiometricSettings
    @EnvironmentObject private var unlock: BiometricUnlockController

    var entry: Entry = .liveSite

    func makeCoordinator() -> Coordinator {
        Coordinator(auth: auth, biometric: biometric, unlock: unlock, entry: entry)
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
        configuration.applicationNameForUserAgent = AppConfig.webViewUserAgentToken

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        context.coordinator.webView = webView
        context.coordinator.loadInitial(in: webView)
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

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var auth: AuthService
        var biometric: BiometricSettings
        var unlock: BiometricUnlockController
        let entry: TSPWebView.Entry
        let reachability = NetworkReachability()
        weak var webView: WKWebView?
        private var didOfferOfflineFallback = false

        init(
            auth: AuthService,
            biometric: BiometricSettings,
            unlock: BiometricUnlockController,
            entry: TSPWebView.Entry
        ) {
            self.auth = auth
            self.biometric = biometric
            self.unlock = unlock
            self.entry = entry
        }

        func loadInitial(in webView: WKWebView) {
            switch entry {
            case .bundled(let resource, let subdirectory):
                loadBundledPage(named: resource, subdirectory: subdirectory, in: webView)
            case .liveSite:
                let last = UserDefaults.standard
                    .string(forKey: AppConfig.lastWebURLDefaultsKey)
                    .flatMap(URL.init(string:))
                switch LiveWebPolicy.startChoice(lastURL: last, networkAvailable: reachability.isOnline) {
                case .remote(let url):
                    webView.load(URLRequest(url: url))
                case .bundled(let name):
                    loadBundledPage(named: name, subdirectory: "assets", in: webView)
                }
            }
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
            if let url = webView.url, LiveWebPolicy.shouldRemember(url) {
                UserDefaults.standard.set(url.absoluteString, forKey: AppConfig.lastWebURLDefaultsKey)
            }
            Task { @MainActor in
                syncBiometricFlags(enabled: biometric.isEnabled, canUse: biometric.canEvaluate)
                guard let json = auth.sessionJSON, !json.isEmpty else { return }
                let escaped = Self.escapeForSingleQuotedJS(json)
                let stored = Self.escapeForSingleQuotedJS(TSPSessionJSON.localStorageValue(from: json))
                let js = """
                (function(){
                  try {
                    var raw = '\(escaped)';
                    window.__TSP_STORED_SESSION__ = raw;
                    try { localStorage.setItem('tsp-auth-token', '\(stored)'); } catch (e) {}
                    if (typeof restoreSession === 'function') { restoreSession(raw); }
                    if (typeof window.__tspRestoreAndroidSession === 'function') {
                      window.__tspRestoreAndroidSession(raw);
                    }
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
            let isMainFrame = navigationAction.targetFrame?.isMainFrame != false
            let decision = LiveWebPolicy.decide(
                url: url,
                isMainFrame: isMainFrame,
                networkAvailable: reachability.isOnline,
                bundleContains: Self.bundleContains
            )
            perform(decision, original: url, in: webView, fromNavigation: true, decisionHandler: decisionHandler)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard let url = navigationAction.request.url else { return nil }
            let decision = LiveWebPolicy.decide(
                url: url,
                isMainFrame: true,
                networkAvailable: reachability.isOnline,
                bundleContains: Self.bundleContains
            )
            perform(decision, original: url, in: webView, fromNavigation: false, decisionHandler: nil)
            return nil
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping () -> Void
        ) {
            Task { @MainActor in
                guard let host = PDFHost.topViewController() else {
                    completionHandler()
                    return
                }
                let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
                host.present(alert, animated: true)
            }
        }

        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedBy frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            // Camera OCR is Phase 1.5. Deny capture so the site does not prompt.
            decisionHandler(.deny)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
            guard LiveWebPolicy.isConnectivityFailure(error), !didOfferOfflineFallback else { return }
            let failing = (ns.userInfo[NSURLErrorFailingURLErrorKey] as? URL) ?? webView.url
            if let failing, failing.isFileURL { return }
            if let failing, !LiveWebPolicy.isProduction(failing) { return }
            didOfferOfflineFallback = true
            loadBundledPage(named: "index", subdirectory: "assets", in: webView)
        }

        private func perform(
            _ decision: LiveWebPolicy.Navigation,
            original: URL,
            in webView: WKWebView,
            fromNavigation: Bool,
            decisionHandler: ((WKNavigationActionPolicy) -> Void)?
        ) {
            switch decision {
            case .allow:
                if fromNavigation {
                    decisionHandler?(.allow)
                } else if let scheme = original.scheme?.lowercased(),
                          scheme == "about" || scheme == "blob" || scheme == "data" {
                    // `window.open('')` print previews must not replace the live page.
                } else if original.isFileURL {
                    webView.loadFileURL(original, allowingReadAccessTo: original.deletingLastPathComponent())
                } else {
                    webView.load(URLRequest(url: original))
                }
            case .load(let url):
                decisionHandler?(.cancel)
                if url.isFileURL {
                    webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
                } else {
                    webView.load(URLRequest(url: url))
                }
            case .safari(let url):
                decisionHandler?(.cancel)
                Task { @MainActor in SafariPresenter.open(url) }
            case .external(let url):
                decisionHandler?(.cancel)
                Task { @MainActor in UIApplication.shared.open(url) }
            case .pdf(let url):
                decisionHandler?(.cancel)
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
            case .pdfViewer(let url):
                decisionHandler?(.cancel)
                TSPPDFBridge.shared.handlePDFViewerNavigation(url)
            case .bundled(let name):
                decisionHandler?(.cancel)
                loadBundledPage(named: name, subdirectory: "assets", in: webView)
            case .blocked(let message):
                decisionHandler?(.cancel)
                Task { @MainActor in
                    PDFHost.presentAlert(title: "Total Service Pro", message: message)
                }
            }
        }

        private static func bundleContains(_ name: String) -> Bool {
            Bundle.main.url(forResource: name, withExtension: "html", subdirectory: "assets") != nil
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
                guard let url = URL(string: text), let webView else { return }
                let decision = LiveWebPolicy.decide(
                    url: url,
                    isMainFrame: true,
                    networkAvailable: reachability.isOnline,
                    bundleContains: Self.bundleContains
                )
                perform(decision, original: url, in: webView, fromNavigation: false, decisionHandler: nil)
            case "captureCardImage", "openCamera":
                reply(requestId: requestId, error: "Card capture is not available in this beta.")
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
                captureCardImage: function() { return invoke('captureCardImage', {}); },
                openCamera: function() { return invoke('openCamera', {}); },
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
              (function pumpSession() {
                var tries = 0;
                function tick() {
                  tries += 1;
                  var raw = window.__TSP_STORED_SESSION__ || '';
                  if (!raw) return;
                  if (typeof window.__tspRestoreAndroidSession === 'function') {
                    try { window.__tspRestoreAndroidSession(raw); } catch (e) {}
                    return;
                  }
                  if (tries < 100) setTimeout(tick, 50);
                }
                setTimeout(tick, 0);
              })();
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
          <h1>Offline shell</h1>
          <p>Could not load repairplanet.net and the bundled fallback is missing. Reconnect, or run <code>Scripts/sync-web-assets.sh</code>.</p>
        </body>
        </html>
        """
    }
}

/// SFSafariViewController for Stripe Checkout and other links that must not
/// stay inside the live WKWebView. No Connect partner URL is invented here.
@MainActor
enum SafariPresenter {
    static func open(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            UIApplication.shared.open(url)
            return
        }
        guard let host = PDFHost.topViewController() else {
            UIApplication.shared.open(url)
            return
        }
        let safari = SFSafariViewController(url: url)
        safari.dismissButtonStyle = .done
        safari.modalPresentationStyle = .pageSheet
        host.present(safari, animated: true)
    }
}

/// Best-effort reachability. An unresolved path is treated as online so the
/// first paint tries repairplanet.net; a connectivity error still falls back.
final class NetworkReachability: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "tsp.network")
    private let lock = NSLock()
    private var online = true
    private var resolved = false

    var isOnline: Bool {
        lock.lock()
        defer { lock.unlock() }
        return resolved ? online : true
    }

    init() {
        let ready = DispatchSemaphore(value: 0)
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            let first = !self.resolved
            self.online = path.status == .satisfied
            self.resolved = true
            self.lock.unlock()
            if first { ready.signal() }
        }
        monitor.start(queue: queue)
        _ = ready.wait(timeout: .now() + .milliseconds(400))
    }

    deinit {
        monitor.cancel()
    }
}
