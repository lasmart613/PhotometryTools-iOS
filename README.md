# PhotometryTools (iOS)

SwiftUI scaffold for the iOS port of **Total Service Pro / PhotometryTools**.

This repository is a native shell only. It is not feature-complete and does not include Apple signing credentials.

| Platform | Identifier |
|---|---|
| iOS bundle ID | `com.photometrytools.ios` |
| Android application ID | `com.photometrytools` |

Minimum: **iOS 17**, **Xcode 15+**.

Related inventory (Android screens, Supabase contracts, P0/P1/P2): [Photometry_Tools#1](https://github.com/lasmart613/Photometry_Tools/pull/1).

## Open in Xcode

1. Clone this repo.
2. Open `PhotometryTools.xcodeproj` (File → Open, or double-click in Finder).
3. Select the **PhotometryTools** shared scheme and an iOS 17+ simulator or device.
4. Run (⌘R). Signing: pick your team in the PhotometryTools target if you run on a device. No certificates or provisioning profiles are stored here.

You should see a three-tab shell:

- **Home** — `WKWebView` loading bundled `PhotometryTools/Resources/assets/index.html` (“TSP shell — HTML assets sync from totalservicepro-web later”).
- **Calculators** — native SwiftUI stub hub (Density, Wavelength, Duty Cycle, Average Power).
- **Settings** — `CFBundleShortVersionString` and build number (`CFBundleVersion`).

HTML/CSS/JS under `PhotometryTools/Resources/assets/` is a placeholder. Sync real screens from [totalservicepro-web](https://github.com/lasmart613/totalservicepro-web) / the Android assets in a later pass.

## Supabase config (no secrets in git)

Project ref: **`yljztfajyvjzqikxdddf`**  
URL: `https://yljztfajyvjzqikxdddf.supabase.co`

The app includes **supabase-swift client stubs** only (`PhotometryTools/Supabase/SupabaseClientStub.swift`). It does not ship an anon key.

1. Copy `Secrets.xcconfig.example` → `Secrets.xcconfig` **or** `Config.example.plist` → `Config.plist`.
2. Replace `YOUR_SUPABASE_ANON_KEY` with the project anon key from the Supabase dashboard.
3. If you use `Config.plist`, add it to the PhotometryTools target’s Copy Bundle Resources (do not commit it).
4. `Debug.xcconfig` / `Release.xcconfig` already `#include? "Secrets.xcconfig"` so a missing secrets file does not break a clean clone.

`Secrets.xcconfig`, `Config.plist`, and signing files are gitignored. **Never commit real anon keys or secrets.**

When you add the official package ([supabase-swift](https://github.com/supabase/supabase-swift)), construct:

`SupabaseClient(supabaseURL: AppConfig.supabaseURL, supabaseKey: key)`

## P0 parity (not implemented in this scaffold)

Ship a usable field app against the same Supabase project. Full list and contracts: [inventory PR](https://github.com/lasmart613/Photometry_Tools/pull/1).

1. WKWebView (or native) shell: JS bridge, Keychain session, `restoreSession` / `?_s=` equivalent, back + exit confirm.
2. Supabase auth: password, magic link, reset, logout, onboarding gate.
3. Home dashboard + role-aware chrome.
4. Service schedule (CRUD tickets, RPC ticket numbers, notifications list).
5. Service reports list + model-specific form + PDF/share.
6. Customer directory + customer profile (use Android `main`, not the empty snapshot file).
7. Manual library + signed-URL PDF viewer (PDFKit or PDF.js).
8. Photometry calculators (density + wavelength + duty cycle + avg power).
9. Settings About version/build from the Xcode target (this scaffold does #9 only).
10. ATS / HTTPS to Supabase only.

## Out of scope

- Peanut Beach Run (not in the Android repo)
- AdMob
- StoreKit / Play Billing
- Apple signing credentials
- Full feature parity (P1 marketplace, estimates/invoices, AI, profiles, etc.)

## Project layout

```
PhotometryTools.xcodeproj/     Xcode project + shared scheme
PhotometryTools/
  PhotometryToolsApp.swift     SwiftUI @main
  ContentView.swift            Home / Calculators / Settings tabs
  Views/                       Home WKWebView, calculator hub, Settings
  Config/AppConfig.swift       Reads example-backed plist / xcconfig keys
  Supabase/                    supabase-swift client stub
  Resources/assets/            Placeholder HTML/CSS/JS
  Info.plist                   Merged keys (SUPABASE_* from xcconfig)
Config.example.plist
Secrets.xcconfig.example
```
