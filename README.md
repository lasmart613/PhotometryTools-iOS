# PhotometryTools (iOS)

SwiftUI + WKWebView shell for the iOS port of **Total Service Pro / PhotometryTools**.

This repository is a native shell plus bundled hybrid HTML. It is not feature-complete and does not include Apple signing credentials.

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

- **Home** — `WKWebView` loading bundled `PhotometryTools/Resources/assets/index.html` (TSP dashboard from totalservicepro-web). Falls back to `placeholder.html` if the entry file is missing.
- **Calculators** — native SwiftUI stub hub (Density, Wavelength, Duty Cycle, Average Power).
- **Settings** — version/build, sign out, biometric-unlock stub, Supabase config status.

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

## HTML asset sync

Android hybrid UI lives in [totalservicepro-web](https://github.com/lasmart613/totalservicepro-web) at `app/src/main/assets/` (same tree Photometry_Tools bundles). The Next.js app under `web/` is **not** a WKWebView target.

Refresh bundled P0 screens:

```bash
Scripts/sync-web-assets.sh
# or, if you already cloned the web repo:
Scripts/sync-web-assets.sh /path/to/totalservicepro-web
```

The script:

- Copies home/dashboard, schedule, reports, manuals placeholders, customer directory/profile, calculators, settings, and shared CSS/JS (`tsp.css`, `theme.js`, `web-compat.js`, `org-switcher.js`, `app-version.js`, `service-company-gate.js`).
- Skips `pdfjs/`, bundled PDFs, paywall, marketplace, AI, estimates/invoices, and `old.service_schedule.html`.
- Strips hardcoded Supabase anon JWTs and replaces them with `window.TSP_CONFIG.supabaseAnonKey` (injected by `TSPWebView`).
- Writes `Scripts/asset-sync-manifest.txt`.
- Leaves `placeholder.html` as a safe fallback.

Re-run the script when totalservicepro-web HTML changes. Do not invent pages.

## Session injection into WKWebView

Confirmed against Photometry_Tools `MainActivity` (main + inventory):

1. Native store is Keychain (Android: `SharedPreferences` `TSPPrefs` / `storedSession`).
2. On each page, write `localStorage['tsp-auth-token']` and call `restoreSession(...)`.
3. In-page navigation uses `?_s=` = base64(JSON of `access_token` + `refresh_token`).
4. JS bridge is named `Android` (`saveSession`, `clearSession`, `getStoredSession`, biometric stubs) so existing HTML keeps working.

`WKWebView` injects `TSP_CONFIG` + the `Android` shim at document start, then calls `restoreSession` on `didFinish`.

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

## P0 parity (this slice)

1. WKWebView shell: JS bridge, Keychain session, `restoreSession` / `?_s=` equivalent.
2. Supabase auth: password, magic-link send, reset-email send, logout.
3. Home dashboard HTML (signed-in only).
4. Settings About version/build + sign out.
5. ATS / HTTPS to Supabase (plus the CDN hosts the HTML already uses).

Still later: schedule/report CRUD polish, native calculators, onboarding gate, StoreKit, full LocalAuthentication prompt.

## Out of scope

- Peanut Beach Run (not in the Android repo)
- AdMob
- StoreKit / Play Billing
- Apple signing credentials
- Full feature parity (P1 marketplace, estimates/invoices, AI, profiles, etc.)

## Project layout

```
PhotometryTools.xcodeproj/     Xcode project + shared scheme + supabase-swift SPM
PhotometryTools/
  PhotometryToolsApp.swift     SwiftUI @main
  ContentView.swift            Home / Calculators / Settings tabs
  Views/                       Login, root gate, Home WKWebView, calculators, Settings
  Auth/                        Keychain session, supabase-swift sign-in/out
  Config/AppConfig.swift       Reads example-backed plist / xcconfig keys
  Supabase/                    SupabaseClient factory (KeychainLocalStorage)
  PDF/                         get-manual-url client, PDFKit viewer, report HTML→PDF
  Resources/assets/            Synced TSP HTML/CSS/JS + placeholder fallback
  Info.plist                   Merged keys (SUPABASE_* from xcconfig)
Scripts/sync-web-assets.sh     Refresh assets from totalservicepro-web
Config.example.plist
Secrets.xcconfig.example
```
