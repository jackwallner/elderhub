#!/usr/bin/env bash
# Upload to TestFlight via xcodebuild -exportArchive with AppStoreUploadOptions.plist
# (destination=upload, method=app-store-connect) and -allowProvisioningUpdates,
# so Xcode uses your local App Store Connect / Apple ID session (no password needed).
#
# Prerequisites: Xcode signed in (Xcode → Settings → Accounts) with team YXG4MP6W39.
#
# Usage:
#   ./scripts/upload-testflight.sh [path/to/Aging.xcarchive]
#
# Default archive: ./build/Aging.xcarchive

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="${1:-$ROOT/build/Aging.xcarchive}"
STAGING="$ROOT/build/upload-staging"
PLIST="$ROOT/AppStoreUploadOptions.plist"

if [[ ! -d "$ARCHIVE" ]]; then
  echo "error: archive not found: $ARCHIVE" >&2
  echo "Create one first:" >&2
  echo "  cd aging && bash scripts/testflight.sh" >&2
  exit 1
fi

if [[ ! -f "$PLIST" ]]; then
  echo "error: missing $PLIST" >&2
  exit 1
fi

mkdir -p "$STAGING"
echo "Uploading archive via App Store Connect (local Xcode session)..."
echo "  archive: $ARCHIVE"
echo "  plist:   $PLIST"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$STAGING" \
  -exportOptionsPlist "$PLIST" \
  -allowProvisioningUpdates

echo "If upload succeeded, check App Store Connect → TestFlight for \"Processing\"."
