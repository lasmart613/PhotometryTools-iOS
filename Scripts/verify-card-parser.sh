#!/usr/bin/env bash
# Compile and run the on-device card parser checks (no iOS SDK required).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
swiftc -DCARD_PARSER_SELFTEST -o /tmp/card-parser-selftest \
  "$ROOT/PhotometryTools/Cards/BusinessCardFields.swift" \
  "$ROOT/PhotometryTools/Cards/BusinessCardParser.swift" \
  "$ROOT/PhotometryTools/Cards/CardCustomerPage.swift" \
  "$ROOT/PhotometryTools/Cards/CustomerCardPayload.swift" \
  "$ROOT/PhotometryTools/Cards/CustomerCardDraftStore.swift"
/tmp/card-parser-selftest
