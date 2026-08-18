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

# Auto-increment build number so TestFlight never rejects a duplicate
echo "==> Bumping build number..."
CURRENT_BUILD=$(grep 'CURRENT_PROJECT_VERSION:' project.yml | sed 's/.*: *"\(.*\)".*/\1/')
NEXT_BUILD=$((CURRENT_BUILD + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION: \"$CURRENT_BUILD\"/CURRENT_PROJECT_VERSION: \"$NEXT_BUILD\"/" project.yml
echo "    $CURRENT_BUILD -> $NEXT_BUILD"

echo "==> Regenerating Xcode project..."
if command -v xcodegen &> /dev/null; then
  xcodegen generate
else
  echo "warning: xcodegen not found. Using existing Aging.xcodeproj."
fi

echo "==> Cleaning..."
xcodebuild -project Aging.xcodeproj -scheme "$SCHEME" clean

echo "==> Archiving..."
xcodebuild -project Aging.xcodeproj -scheme "$SCHEME" -configuration Release archive -archivePath "$ARCHIVE_PATH" -destination "generic/platform=iOS" -allowProvisioningUpdates

echo "==> Exporting & Uploading..."
exec "$DIR/upload-testflight.sh" "$ARCHIVE_PATH"
