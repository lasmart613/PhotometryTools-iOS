# TestFlight

First upload checklist for Photometry Tools **0.5.0 (5)**. The repo is ready to archive. It does not contain a Team ID, certificate, profile, or API key, and nothing in this repo uploads a build.

Bundle ID: `com.photometrytools.ios`. The shared scheme’s Archive action uses the **Release** configuration.

## Already done

- `PrivacyInfo.xcprivacy` is in the app target. It matches Supabase auth, the on-device Keychain session, on-device business-card OCR, and the `https://repairplanet.net` web view. Tracking is off. There is no AdMob or StoreKit.
- `ITSAppUsesNonExemptEncryption` is `false` (HTTPS and Keychain only).
- `NSCameraUsageDescription` and `NSFaceIDUsageDescription` are set in `Info.plist`.
- `AppIcon` is a 1024×1024 RGB icon. Xcode 14+ generates the smaller sizes from that image.
- Version **0.5.0**, build **5**. Main already used build 4.
- Signing is automatic. `DEVELOPMENT_TEAM` is `$(APPLE_TEAM_ID)` from an optional gitignored `Signing.xcconfig`.
- `Scripts/export-testflight.sh` and `fastlane export_ipa` archive Release and write an IPA. Both stop before upload. `fastlane/ExportOptions.plist` uses `YOUR_APPLE_TEAM_ID`.

## Apple Developer

1. Enroll at [developer.apple.com/programs](https://developer.apple.com/programs) and wait until the membership is active.
2. Copy the 10-character **Team ID** from [Account → Membership details](https://developer.apple.com/account).
3. On the Mac, open Xcode → Settings → Accounts and sign in with that Apple ID. Do not export the distribution certificate into git.
4. Copy `Signing.xcconfig.example` to `Signing.xcconfig` and set `APPLE_TEAM_ID`. Leave the example file unchanged. `Signing.xcconfig` is gitignored.
5. Keep the App ID as `com.photometrytools.ios`. Automatic signing can register it on the first archive. Do not add Push, Sign in with Apple, or App Groups for this beta.

## App Store Connect

1. Create the app: name **Photometry Tools**, bundle ID `com.photometrytools.ios`, SKU of your choice, primary language English. Category is already `public.app-category.business` on the target.
2. There is no StoreKit product. Set the price when App Store Connect asks; the binary does not sell anything.
3. Privacy policy URL: the in-app page still says the policy is coming soon. Add a real URL on the app record before external TestFlight or App Review.
4. App Privacy, matching the manifest. All of these are linked to the account, used for app functionality, and not used for tracking:
   - Contact info: name, email, phone, physical address (sign-in and confirmed business-card fields saved to Supabase).
   - Identifiers: user ID (Supabase user).
   - User content: other user content (records saved in the repairplanet.net web view, plus company, title, and website from a confirmed card).
   - Do not declare photos or videos. The camera is on-device OCR; the photo is not uploaded or stored.
   - Do not declare contacts from the address book, precise location, device ID, payment info, or tracking. Stripe Checkout opens in Safari.
5. The Keychain holds the session on the device. That is not a separate collected data type.
6. Export compliance: the app uses only exempt encryption. `ITSAppUsesNonExemptEncryption` is already false, so processing should not stop on Missing Compliance. If it does, answer that the app does not use non-exempt encryption.

## First upload

Do this on a Mac with Xcode 15 or newer. Put the Supabase **anon** key in gitignored `Secrets.xcconfig` (or `Config.plist`) before archiving so the TestFlight build can sign in. Never use the service-role key.

### Xcode

1. Open `PhotometryTools.xcodeproj`. Let the supabase-swift package resolve.
2. Scheme **PhotometryTools**, run destination **Any iOS Device (arm64)**.
3. Product → Archive. The scheme archives **Release**.
4. In the Organizer, Distribute App → App Store Connect → Upload. Leave the version at 0.5.0 and the build at 5.
5. Wait until the build finishes processing. Internal testers (App Store Connect users on the team) can install it from the TestFlight app. External groups need a beta review.

### Script

The script creates provisioning profiles with the Apple ID already signed into Xcode (`-allowProvisioningUpdates`). It does not upload the IPA.

```bash
APPLE_TEAM_ID=YOUR10CHAR Scripts/export-testflight.sh
```

Or, from the repo root if fastlane is installed: `APPLE_TEAM_ID=YOUR10CHAR fastlane export_ipa`.

The IPA is under `build/testflight/export/`. Upload that file with Xcode Organizer or Transporter when you want it on TestFlight.

The next upload after build 5 must increase `CURRENT_PROJECT_VERSION` in the PhotometryTools target.

## Leave out of git

`Signing.xcconfig`, `Secrets.xcconfig`, `Config.plist`, `*.p12`, `*.cer`, `*.mobileprovision`, `AuthKey_*.p8`, and anything under `build/`.
