#!/usr/bin/env bash
# Fail if common secrets landed in the working tree.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail=0

if git ls-files | grep -E '(^|/)(Secrets\.xcconfig|Config\.plist)$'; then
  echo "error: gitignored secret files are tracked" >&2
  fail=1
fi

if git grep -nE 'eyJ[A-Za-z0-9_\-]{20,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}' -- ':!*.md' ':!Scripts/secret-scan.sh'; then
  echo "error: JWT-like token found in tracked files" >&2
  fail=1
fi

if git grep -nEi 'service_role|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY' -- ':!*.md' ':!Scripts/secret-scan.sh'; then
  echo "error: private key / service_role material found" >&2
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi

echo "secret scan clean"
