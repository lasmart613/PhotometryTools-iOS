#!/usr/bin/env bash
# Compile and run LiveWebPolicy self-checks (no iOS SDK required).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
swiftc -DLIVE_WEB_POLICY_SELFTEST -o /tmp/live-web-policy-selftest \
  "$ROOT/PhotometryTools/Web/LiveWebPolicy.swift"
/tmp/live-web-policy-selftest
