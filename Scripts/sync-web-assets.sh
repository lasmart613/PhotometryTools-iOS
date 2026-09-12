#!/usr/bin/env bash
# Sync P0 TSP hybrid HTML from totalservicepro-web (same files Android
# ships under app/src/main/assets/) into the iOS bundle.
#
# Usage:
#   Scripts/sync-web-assets.sh
#   Scripts/sync-web-assets.sh /path/to/totalservicepro-web
#   WEB_REPO_URL=https://github.com/lasmart613/totalservicepro-web Scripts/sync-web-assets.sh
#
# The Next.js app lives in totalservicepro-web/web and is not a WKWebView
# target. Android (and this script) use the hybrid HTML at
# app/src/main/assets/. If those paths ever diverge, the script copies the
# best matching public files and writes a note into the manifest.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/PhotometryTools/Resources/assets"
MANIFEST="$ROOT/Scripts/asset-sync-manifest.txt"
WEB_REPO_URL="${WEB_REPO_URL:-https://github.com/lasmart613/totalservicepro-web}"
WEB_REF="${WEB_REF:-main}"
ASSET_SUBDIR="app/src/main/assets"
FALLBACK_PLACEHOLDER="$DEST/placeholder.html"

# P0 shell + shared CSS/JS auth helpers. Do not invent pages.
# Skip pdfjs/, manuals PDFs, paywall, marketplace, AI, estimates/invoices,
# old.service_schedule.html — those are P1 or oversized viewer chrome.
# pdf_viewer.html is also skipped: iOS intercepts that URL and opens PDFKit
# after calling the get-manual-url Edge Function (see README).
P0_FILES=(
  index.html
  service_hub.html
  service_schedule.html
  reports_list.html
  service_report.html
  coming_soon.html
  manual_library.html
  service_manuals.html
  onboarding.html
  customer_directory.html
  customer_profile.html
  calculators_menu.html
  settings.html
  density_calculator.html
  wavelength.html
  duty_cycle.html
  avgpower.html
  tsp.css
  theme.js
  web-compat.js
  org-switcher.js
  app-version.js
  service-company-gate.js
)

SOURCE_ROOT="${1:-}"
CLEANUP_DIR=""

if [[ -n "$SOURCE_ROOT" ]]; then
  if [[ ! -d "$SOURCE_ROOT" ]]; then
    echo "error: source path is not a directory: $SOURCE_ROOT" >&2
    exit 1
  fi
else
  CLEANUP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tsp-web-sync.XXXXXX")"
  echo "Cloning $WEB_REPO_URL ($WEB_REF)..."
  git clone --depth 1 --branch "$WEB_REF" "$WEB_REPO_URL" "$CLEANUP_DIR/repo"
  SOURCE_ROOT="$CLEANUP_DIR/repo"
fi

ASSET_SRC="$SOURCE_ROOT/$ASSET_SUBDIR"
if [[ ! -d "$ASSET_SRC" ]]; then
  echo "error: expected Android-style assets at $ASSET_SRC" >&2
  echo "totalservicepro-web/web is Next.js and is not copied." >&2
  exit 1
fi

mkdir -p "$DEST"

# Keep the scaffold placeholder as a safe WKWebView fallback.
if [[ -f "$DEST/index.html" ]] && ! grep -q "Total Service Pro" "$FALLBACK_PLACEHOLDER" 2>/dev/null; then
  if grep -q "TSP shell — HTML assets sync" "$DEST/index.html"; then
    cp "$DEST/index.html" "$FALLBACK_PLACEHOLDER"
  fi
fi

copied=()
missing=()
for name in "${P0_FILES[@]}"; do
  if [[ -f "$ASSET_SRC/$name" ]]; then
    cp "$ASSET_SRC/$name" "$DEST/$name"
    copied+=("$name")
  else
    missing+=("$name")
  fi
done

python3 - "$DEST" <<'PY'
import pathlib
import re
import sys

dest = pathlib.Path(sys.argv[1])
# Public anon JWT hardcoded in Android HTML. Replace so git stays clean;
# iOS injects the key from Secrets.xcconfig / Config.plist at WebView load.
jwt = re.compile(
    r"""(['"])eyJ[A-Za-z0-9_\-]+=*\.[A-Za-z0-9_\-]+=*\.[A-Za-z0-9_\-]+=*\1"""
)
replacement = r"((window.TSP_CONFIG && window.TSP_CONFIG.supabaseAnonKey) || '')"

changed = []
for path in sorted(dest.iterdir()):
    if path.suffix.lower() not in {".html", ".js", ".css"}:
        continue
    text = path.read_text(encoding="utf-8")
    new, n = jwt.subn(replacement, text)
    if n:
        path.write_text(new, encoding="utf-8")
        changed.append(f"{path.name} ({n})")

print("stripped anon JWTs from: " + (", ".join(changed) if changed else "none"))
PY

{
  echo "TSP iOS web-asset sync"
  echo "source: $WEB_REPO_URL"
  echo "ref: $WEB_REF"
  echo "asset root: $ASSET_SUBDIR"
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ -d "$SOURCE_ROOT/.git" ]]; then
    echo "commit: $(git -C "$SOURCE_ROOT" rev-parse HEAD)"
  fi
  echo
  echo "copied:"
  for name in "${copied[@]}"; do
    bytes="$(wc -c < "$DEST/$name" | tr -d ' ')"
    echo "  - $name ($bytes bytes)"
  done
  if ((${#missing[@]})); then
    echo
    echo "missing (not present in source):"
    for name in "${missing[@]}"; do
      echo "  - $name"
    done
  fi
  echo
  echo "skipped: pdfjs/, manuals/, paywall.html, marketplace.html,"
  echo "ai_assistant.html, estimates/invoices, old.service_schedule.html"
  echo
  echo "Hardcoded Supabase anon JWTs were stripped and replaced with"
  echo "window.TSP_CONFIG.supabaseAnonKey (injected by TSPWebView)."
} > "$MANIFEST"

echo "Wrote ${#copied[@]} files to $DEST"
echo "Manifest: $MANIFEST"

if [[ -n "$CLEANUP_DIR" ]]; then
  rm -rf "$CLEANUP_DIR"
fi
