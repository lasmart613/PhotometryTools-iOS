#!/usr/bin/env bash
# Static checks for the first TestFlight upload. No Xcode, signing, or network.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

python3 - << 'PY'
import plistlib
import re
import struct
import sys
from pathlib import Path

root = Path(".")
errors = []

def fail(message):
    errors.append(message)

def load_plist(path):
    return plistlib.loads(Path(path).read_bytes())

info = load_plist("PhotometryTools/Info.plist")
camera = info.get("NSCameraUsageDescription", "")
face = info.get("NSFaceIDUsageDescription", "")
if not isinstance(camera, str) or len(camera) < 40 or "camera" not in camera.lower():
    fail("NSCameraUsageDescription is missing or incomplete")
if "business card" not in camera.lower():
    fail("NSCameraUsageDescription does not describe business-card OCR")
if not isinstance(face, str) or len(face) < 20 or "Face ID" not in face:
    fail("NSFaceIDUsageDescription is missing or incomplete")
if info.get("ITSAppUsesNonExemptEncryption") is not False:
    fail("ITSAppUsesNonExemptEncryption must be boolean false")

privacy = load_plist("PhotometryTools/PrivacyInfo.xcprivacy")
if privacy.get("NSPrivacyTracking") is not False:
    fail("NSPrivacyTracking must be false")
if privacy.get("NSPrivacyTrackingDomains") not in ([], None):
    fail("NSPrivacyTrackingDomains must be empty")

collected = {
    item.get("NSPrivacyCollectedDataType")
    for item in privacy.get("NSPrivacyCollectedDataTypes", [])
}
required_types = {
    "NSPrivacyCollectedDataTypeEmailAddress",
    "NSPrivacyCollectedDataTypeName",
    "NSPrivacyCollectedDataTypePhoneNumber",
    "NSPrivacyCollectedDataTypePhysicalAddress",
    "NSPrivacyCollectedDataTypeUserID",
    "NSPrivacyCollectedDataTypeOtherUserContent",
}
missing = required_types - collected
if missing:
    fail(f"privacy manifest missing data types: {sorted(missing)}")
forbidden = {
    "NSPrivacyCollectedDataTypePhotosorVideos",
    "NSPrivacyCollectedDataTypePreciseLocation",
    "NSPrivacyCollectedDataTypeDeviceID",
    "NSPrivacyCollectedDataTypePaymentInfo",
    "NSPrivacyCollectedDataTypeContacts",
    "NSPrivacyCollectedDataTypeAdvertisingData",
}
if collected & forbidden:
    fail(f"privacy manifest declares data the app does not collect: {sorted(collected & forbidden)}")

for item in privacy.get("NSPrivacyCollectedDataTypes", []):
    if item.get("NSPrivacyCollectedDataTypeTracking") is not False:
        fail(f"{item.get('NSPrivacyCollectedDataType')} is marked for tracking")
    if item.get("NSPrivacyCollectedDataTypeLinked") is not True:
        fail(f"{item.get('NSPrivacyCollectedDataType')} should be linked to the account")
    purposes = item.get("NSPrivacyCollectedDataTypePurposes", [])
    if purposes != ["NSPrivacyCollectedDataTypePurposeAppFunctionality"]:
        fail(f"{item.get('NSPrivacyCollectedDataType')} purpose must be app functionality only")

reasons = {
    item.get("NSPrivacyAccessedAPIType"): set(item.get("NSPrivacyAccessedAPITypeReasons", []))
    for item in privacy.get("NSPrivacyAccessedAPITypes", [])
}
if "CA92.1" not in reasons.get("NSPrivacyAccessedAPICategoryUserDefaults", set()):
    fail("UserDefaults reason CA92.1 is required")
if "C617.1" not in reasons.get("NSPrivacyAccessedAPICategoryFileTimestamp", set()):
    fail("File timestamp reason C617.1 is required")

pbx = Path("PhotometryTools.xcodeproj/project.pbxproj").read_text()
if "PrivacyInfo.xcprivacy in Resources" not in pbx:
    fail("PrivacyInfo.xcprivacy is not in Copy Bundle Resources")
if pbx.count("MARKETING_VERSION = 0.5.0;") < 2:
    fail("MARKETING_VERSION must be 0.5.0 on Debug and Release")
if pbx.count("CURRENT_PROJECT_VERSION = 5;") < 2:
    fail("CURRENT_PROJECT_VERSION must be 5 on Debug and Release")
if pbx.count("PRODUCT_BUNDLE_IDENTIFIER = com.photometrytools.ios;") < 2:
    fail("bundle id must stay com.photometrytools.ios")
if 'DEVELOPMENT_TEAM = "$(APPLE_TEAM_ID)"' not in pbx:
    fail("DEVELOPMENT_TEAM must be the APPLE_TEAM_ID placeholder")
if re.search(r'DEVELOPMENT_TEAM = "[A-Z0-9]{10}"', pbx):
    fail("pbxproj contains a real-looking Team ID")
if "CODE_SIGN_STYLE = Automatic;" not in pbx:
    fail("CODE_SIGN_STYLE should stay Automatic")

scheme = Path("PhotometryTools.xcodeproj/xcshareddata/xcschemes/PhotometryTools.xcscheme").read_text()
if 'buildConfiguration = "Release"' not in scheme or "<ArchiveAction" not in scheme:
    fail("Archive action must use the Release configuration")

export = load_plist("fastlane/ExportOptions.plist")
if export.get("method") != "app-store-connect":
    fail("ExportOptions method must be app-store-connect")
if export.get("destination") != "export":
    fail("ExportOptions destination must be export, not upload")
if export.get("signingStyle") != "automatic":
    fail("ExportOptions signingStyle must be automatic")
if export.get("teamID") != "YOUR_APPLE_TEAM_ID":
    fail("ExportOptions teamID must stay the YOUR_APPLE_TEAM_ID placeholder")
if export.get("manageAppVersionAndBuildNumber") is not False:
    fail("ExportOptions must not rewrite the version or build number")

example = Path("Signing.xcconfig.example").read_text()
if "YOUR_APPLE_TEAM_ID" not in example:
    fail("Signing.xcconfig.example must keep the team placeholder")
if not Path(".gitignore").read_text().splitlines().__contains__("Signing.xcconfig"):
    fail("Signing.xcconfig must be gitignored")

icon = Path("PhotometryTools/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
data = icon.read_bytes()
if data[:8] != b"\x89PNG\r\n\x1a\n":
    fail("AppIcon.png is not a PNG")
# IHDR: width, height, bit depth, color type
width, height, depth, color = struct.unpack(">IIBB", data[16:26])
if (width, height) != (1024, 1024):
    fail(f"AppIcon.png must be 1024x1024, got {width}x{height}")
if depth != 8 or color != 2:
    fail(f"AppIcon.png must be 8-bit RGB without alpha (color type 2), got depth {depth} type {color}")
contents = Path("PhotometryTools/Assets.xcassets/AppIcon.appiconset/Contents.json").read_text()
if "AppIcon.png" not in contents or "1024x1024" not in contents:
    fail("AppIcon Contents.json must reference the 1024 image")

script = Path("Scripts/export-testflight.sh").read_text()
fastfile = Path("fastlane/Fastfile").read_text()
for label, text in (("export script", script), ("Fastfile", fastfile)):
    for banned in ("altool", "notarytool", "pilot", "upload_to_testflight", "upload-app"):
        if banned in text:
            fail(f"{label} contains upload command {banned}")

swift = "\n".join(path.read_text(errors="ignore") for path in Path("PhotometryTools").rglob("*.swift"))
for banned in ("import StoreKit", "import GoogleMobileAds"):
    if banned in swift:
        fail(f"soft beta forbids {banned}")

if errors:
    print("\n".join(f"error: {item}" for item in errors), file=sys.stderr)
    sys.exit(1)

print("testflight readiness checks passed")
PY
