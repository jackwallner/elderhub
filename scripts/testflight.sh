#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$DIR/.."

SCHEME="Aging"
ARCHIVE_PATH="$PROJECT_DIR/build/Aging.xcarchive"

cd "$PROJECT_DIR"

# Before anything else, and before the build number moves: does the schema the
# client sends still exist on the server? plan84 §1.1 shipped because nothing
# ever asked. One round trip, and it is the difference between a working app
# and a silent one.
echo "==> Checking for schema drift..."
"$DIR/check-schema-drift.py"


# TestFlight release for Aging. The shared fleet script does the work: bump the
# build in project.yml, xcodegen, archive Release signed with the App Store
# Connect API key, upload, then commit and push the bump once Apple accepts it.
# Flags (--upload-only, --no-bump, --clean, --post-archive) and credentials are
# documented in ~/ios/release/testflight.sh.
exec "$HOME/ios/release/testflight.sh" --project Aging.xcodeproj --scheme Aging --clean "$@"
