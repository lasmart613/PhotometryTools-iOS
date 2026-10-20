#!/usr/bin/env bash
# Archive PhotometryTools (Release) and export an IPA for App Store Connect.
# Stops after the IPA. Does not upload to TestFlight, App Store Connect, or Apple.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TEAM_ID="${APPLE_TEAM_ID:-}"
if [[ ! "$TEAM_ID" =~ ^[A-Za-z0-9]{10}$ ]]; then
  echo "Set APPLE_TEAM_ID to the 10-character Team ID from developer.apple.com/account." >&2
  echo "Example: APPLE_TEAM_ID=XXXXXXXXXX Scripts/export-testflight.sh" >&2
  echo "This script does not upload the archive." >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is not available. Run this on a Mac with Xcode 15 or newer." >&2
  exit 1
fi

BUILD_DIR="$ROOT/build/testflight"
ARCHIVE="$BUILD_DIR/PhotometryTools.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
PLIST="$BUILD_DIR/ExportOptions.plist"
mkdir -p "$BUILD_DIR"

sed "s/YOUR_APPLE_TEAM_ID/${TEAM_ID}/g" "$ROOT/fastlane/ExportOptions.plist" > "$PLIST"

if grep -q 'YOUR_' "$PLIST"; then
  echo "Generated ExportOptions.plist still contains a placeholder." >&2
  exit 1
fi

if grep -q '<string>upload</string>' "$PLIST"; then
  echo "Refusing to export with destination upload." >&2
  exit 1
fi

echo "Archiving Release (generic iOS device). Team ${TEAM_ID}. No upload."

xcodebuild \
  -project "$ROOT/PhotometryTools.xcodeproj" \
  -scheme PhotometryTools \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE" \
  archive \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$PLIST" \
  -allowProvisioningUpdates

echo "IPA exported under $EXPORT_DIR"
echo "Not uploaded. Use Xcode Organizer or Transporter when you choose to send it."
