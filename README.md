# PhotometryTools (iOS)

SwiftUI + WKWebView shell for the iOS port of **Total Service Pro / PhotometryTools**.

Version **0.5.0** (build **2**), shown in Settings as **0.5.0-beta**. TestFlight is still held. This repo does not include Apple signing credentials.

Signed-in **Home** loads the live site `https://repairplanet.net` (same idea as Android 1.4). Bundled HTML under `Resources/assets/` is the offline and calculator fallback, not the primary UI. Native Calculators, PDFKit manuals, and opt-in biometric unlock stay in the shell.

| Platform | Identifier |
|---|---|
| iOS bundle ID | `com.photometrytools.ios` |
| Android application ID | `com.photometrytools` |

Minimum: **iOS 17**, **Xcode 15+**.

Related inventory (Android screens, Supabase contracts, P0/P1/P2): [Photometry_Tools docs/ios-port-inventory.md](https://github.com/lasmart613/Photometry_Tools/blob/main/docs/ios-port-inventory.md).

## Open in Xcode

1. Clone this repo.
2. Copy secrets (see below) so the app can talk to Supabase.
3. Open `PhotometryTools.xcodeproj` (File → Open, or double-click in Finder).
4. Let Xcode resolve the **supabase-swift** package (`https://github.com/supabase/supabase-swift.git`, 2.55+).
5. Select the **PhotometryTools** shared scheme and an iOS 17+ simulator or device.
6. Run (⌘R). Signing: pick your team in the PhotometryTools target if you run on a device. No certificates or provisioning profiles are stored here.

Signed-out: native email/password login (magic link and password reset send email only).  
Signed-in: three-tab shell.

- **Home** — `WKWebView` of `https://repairplanet.net` with the Android session bridge (`tsp-auth-token`, `Android.getStoredSession`, `__tspRestoreAndroidSession`) and the user-agent token `TSPAndroid/1.4 TSPiOS/0.5.0`. The host allowlist follows Android 1.4 (repairplanet.net, Supabase, Netlify previews, Google/CDN hosts). Stripe Checkout and other non-allowlisted links open in Safari. Offline, or if the live origin cannot connect, Home falls back to bundled `index.html`.
- **Calculators** — native SwiftUI photometry calculators (Fluence, Density, Wavelength, Duty Cycle, Average Power). Formulas match the bundled HTML.
- **Settings** — version/build, sign out, opt-in Face ID / Touch ID unlock, Supabase config status.

## Secrets setup (no keys in git)

Project ref: **`yljztfajyvjzqikxdddf`**  
URL: `https://yljztfajyvjzqikxdddf.supabase.co`

The official [supabase-swift](https://github.com/supabase/supabase-swift) client is constructed as:

`SupabaseClient(supabaseURL: AppConfig.supabaseURL, supabaseKey: key)`

with `KeychainLocalStorage` (not UserDefaults). The Android-compatible session JSON is stored in the Keychain under service `com.photometrytools.ios.session`.

1. Copy `Secrets.xcconfig.example` → `Secrets.xcconfig` **or** `Config.example.plist` → `Config.plist`.
2. Replace `YOUR_SUPABASE_ANON_KEY` with the project **anon** (publishable) key from the Supabase dashboard. Never commit a service-role key.
3. If you use `Config.plist`, add it to the PhotometryTools target’s Copy Bundle Resources (do not commit it).
4. `Debug.xcconfig` / `Release.xcconfig` already `#include? "Secrets.xcconfig"` so a missing secrets file does not break a clean clone.

`Secrets.xcconfig`, `Config.plist`, and signing files are gitignored. **Never commit real anon keys or secrets.**

Without a local key the login screen explains setup and will not call Supabase.

## HTML asset sync (offline fallback)

The primary UI is the live Next.js site. Bundled files are only for offline field use and the HTML calculators.

Android hybrid UI lives in [totalservicepro-web](https://github.com/lasmart613/totalservicepro-web) at `app/src/main/assets/`. Refresh the fallback copy with:

```bash
Scripts/sync-web-assets.sh
# or, if you already cloned the web repo:
Scripts/sync-web-assets.sh /path/to/totalservicepro-web
```

The script:

- Copies the offline shell: home/dashboard, schedule, reports, manuals placeholders, customer directory/profile, calculators, settings, and shared CSS/JS (`tsp.css`, `theme.js`, `web-compat.js`, `org-switcher.js`, `app-version.js`, `service-company-gate.js`).
- Still skips `pdfjs/`, bundled PDFs, `paywall.html`, `marketplace.html`, `ai_assistant.html`, estimates/invoices, `parts_catalog.html`, profile pages, and `old.service_schedule.html`. Those screens load from repairplanet.net when the device is online. `pdf_viewer.html` stays skipped (PDFKit).
- Strips hardcoded Supabase anon JWTs and replaces them with `window.TSP_CONFIG.supabaseAnonKey` (injected by `TSPWebView`).
- Writes `Scripts/asset-sync-manifest.txt`.
- Leaves `placeholder.html` as a safe fallback.

Re-run the script when totalservicepro-web HTML changes. Do not invent pages.

## Session injection into WKWebView

Confirmed against Photometry_Tools `MainActivity` (main + inventory):

1. Native store is Keychain (Android: `SharedPreferences` `TSPPrefs` / `storedSession`).
2. On each page, write `localStorage['tsp-auth-token']` and call `restoreSession(...)`.
3. In-page navigation uses `?_s=` = base64(JSON of `access_token` + `refresh_token`).
4. JS bridge is named `Android` (`saveSession`, `clearSession`, `getStoredSession`, `setBiometricEnabled` / `isBiometricEnabled` / `canUseBiometric`) so existing HTML Settings stay in sync with native.

`WKWebView` injects `TSP_CONFIG` + the `Android` shim at document start, then calls `restoreSession` and `__tspRestoreAndroidSession` (the live site’s `AndroidSessionBridge`) on `didFinish`. A short retry also waits for that function to be installed by the page. `Android.openUrl` loads allowlisted repairplanet.net URLs in the web view and opens Stripe Checkout plus other external http(s) links in Safari. `Android.captureCardImage` / `openCamera` are stubs for a later card-OCR pass and do not open the camera.

## Manuals and report PDFs

Cloud manuals stay in Supabase Storage (`manuals` bucket). This repo does **not** ship `pdfjs/` or large bundled PDFs.

### Open manual (role-gated)

`manual_library.html` and `service_manuals.html` still run `service-company-gate.js` (service company only; owners/suppliers stay blocked). After the HTML allows an open, they navigate to `pdf_viewer.html?storage_path=&title=&manual_id=`.

iOS intercepts that navigation (the Android PDF.js page is not bundled) and:

1. Uses the Keychain / supabase-swift session JWT (refreshed when possible).
2. POSTs `{ "storage_path" }` to `https://yljztfajyvjzqikxdddf.supabase.co/functions/v1/get-manual-url` with `Authorization: Bearer <access_token>` and the local anon key as `apikey`.
3. Downloads the signed URL to a temp file (`tmp/tsp-pdfs/`).
4. Opens it in **PDFKit** (`PDFViewerController`) with a share-sheet button (`UIActivityViewController`).

Folder manuals (`manual_id` + `chapter_metadata` / `entry_file_path`) use the same PostgREST read as Android `pdf_viewer.html`, then a native chapter list. The Edge Function still enforces `user_manuals` ownership — native code does not bypass that.

### Service report PDFs

`reports_list.html` opens `service_report.html` (existing synced flow). Export calls `Android.printReport(html, jobName)` — the same hook Android `MainActivity` implements. iOS renders that HTML with a hidden `WKWebView.createPDF`, writes a temp PDF, and presents PDFKit + share.

### JS bridge additions

The injected `window.Android` shim keeps session methods and adds:

| Method | Behavior |
|---|---|
| `getManualUrl(storagePath)` | Promise → signed URL from `get-manual-url` |
| `openManual({ storage_path, title, manual_id })` | Resolve + open in PDFKit |
| `openPdf(url \| path \| { url, base64, title })` | Download/open in PDFKit. `blob:` is read in JS and sent as base64 |
| `sharePdf(...)` | Same sources, then the iOS share sheet |
| `printReport(html, jobName)` | HTML → PDF → PDFKit (report export) |

Session injection (`tsp-auth-token` / `restoreSession` / `?_s=`) is unchanged.

## Native photometry calculators

The **Calculators** tab is native SwiftUI (not a WebView). Math lives in `PhotometryTools/Calculators/PhotometryMath.swift` and is written to match the bundled HTML:

| Hub item | HTML source | Formula / behavior |
|---|---|---|
| Fluence | `density_calculator.html` (fluence mode) and legacy Android `fluence.html` | `J/cm² = Energy (J) ÷ Area (cm²)` |
| Density | `density_calculator.html` | Same fluence math, plus CW irradiance `W/cm² = Power (W) ÷ Area` and pulsed `E×Hz / Area` or `fluence×Hz` |
| Wavelength | `wavelength.html` | `Δ% = (E₂/HD1₂) ÷ (E₁/HD1₁) × 100`, VBeam table interpolate, then filter correction (nm) |
| Duty Cycle | `duty_cycle.html` | `% = Pulse width ÷ Period × 100`; Period = width + off-time **or** `1000 / PPS` |
| Average Power | `avgpower.html` | `W = Energy (J) × Hz`; reverse `J = W ÷ Hz` (`1 J = 1000 mJ`) |

Spot area uses millimeters ÷ 100 to get cm² (`π × (d÷2)² ÷ 100`, `s² ÷ 100`, `L × W ÷ 100`). Diameter / side pickers are 2–30 mm (HTML defaults: 15 mm circular, 10 mm rectangular).

Validation copy matches the HTML toasts (empty energy, invalid pulse width, Off-Time **or** PPS, pulse wider than `1/PPS`, missing VBeam readings). Results update live when inputs are valid; **Calculate** shows the same error strings. Copy / Share is available on a completed result.

`calculators_menu.html` and the individual HTML pages stay in the bundle for offline fallback. This tab does not replace those pages. When Home is online, calculator links on the live site go to `https://repairplanet.net/calculators`.

Check table + formula samples with `node Scripts/verify-calculator-parity.mjs`.

## Biometric unlock

Face ID / Touch ID is **opt-in only**. The preference defaults to off (`UserDefaults` key `tsp.biometricUnlockEnabled`, same idea as Android `TSPPrefs.biometricEnabled`). A cold launch never shows a biometric prompt unless the user turned the toggle on in native Settings, the HTML Settings page, or the login checkbox.

When the toggle is on and a Keychain session exists:

1. Launch or return from the background covers the signed-in tabs with an opaque lock screen.
2. LocalAuthentication uses `.deviceOwnerAuthentication` so Face ID / Touch ID can fall back to the device passcode.
3. **Cancel or failure does not clear Keychain and does not sign out** (Android cancel could full sign-out — iOS does not).
4. **Use password** re-authenticates against Supabase and leaves the saved session in place until the user taps Sign Out.

`NSFaceIDUsageDescription` is set in `Info.plist`. HTML `Android.setBiometricEnabled` / `isBiometricEnabled` / `canUseBiometric` read and write the same native flag so Settings.html cannot disagree with the Settings tab.

## Soft beta (0.5.0)

1. Live WKWebView shell: `https://repairplanet.net`, host allowlist, Keychain session inject.
2. Supabase auth: password, magic-link send, reset-email send, logout.
3. Estimates, invoices, marketplace, parts, AI, notifications, and profiles come from the live site once the session bridge is signed in.
4. Stripe Checkout opens in Safari. No invented Connect partner URL.
5. Settings shows **0.5.0-beta** and the build number, plus sign out.
6. Native photometry calculators (Fluence, Density, Wavelength, Duty Cycle, Average Power).
7. Opt-in LocalAuthentication unlock (Face ID / Touch ID). Cancel does not sign out.
8. Manuals and report export still use PDFKit.

TestFlight / Apple signing stay held. Still later: card OCR, APNs, StoreKit, AdMob.

## Out of scope

- Peanut Beach Run (not in the Android repo)
- AdMob
- StoreKit / Play Billing
- Apple signing credentials and TestFlight
- Native card OCR (camera bridge is a stub only)
- Invented Stripe Connect partner URLs

## Project layout

```
PhotometryTools.xcodeproj/     Xcode project + shared scheme + supabase-swift SPM
PhotometryTools/
  PhotometryToolsApp.swift     SwiftUI @main
  ContentView.swift            Home / Calculators / Settings tabs
  Views/                       Login, root gate, live Home WKWebView, native calculators, Settings
  Web/LiveWebPolicy.swift      Host allowlist, Stripe → Safari, offline fallback rules
  Calculators/                 Photometry math + VBeam wavelength table (HTML parity)
  Auth/                        Keychain session, supabase-swift sign-in/out, LocalAuthentication gate
  Config/AppConfig.swift       Reads example-backed plist / xcconfig keys
  Supabase/                    SupabaseClient factory (KeychainLocalStorage)
  PDF/                         get-manual-url client, PDFKit viewer, report HTML→PDF
  Resources/assets/            Synced TSP HTML/CSS/JS + placeholder fallback
  Info.plist                   Merged keys (SUPABASE_* from xcconfig, NSFaceIDUsageDescription)
Scripts/sync-web-assets.sh     Refresh assets from totalservicepro-web
Scripts/verify-calculator-parity.mjs   HTML vs native table/formula check
Scripts/secret-scan.sh         Fail if secrets landed in git
Config.example.plist
Secrets.xcconfig.example
```
