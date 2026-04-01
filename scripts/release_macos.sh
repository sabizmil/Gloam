#!/bin/bash
set -e

# Build and package a release macOS build with signing and notarization.
#
# Required environment variables:
#   APPLE_SIGN_ID    — Developer ID Application identity (or "-" for ad-hoc)
#   APPLE_ID         — Apple ID email (for notarization)
#   APPLE_TEAM_ID    — Apple team ID
#   APPLE_APP_PASSWORD — App-specific password for notarytool
#
# Usage:
#   bash scripts/release_macos.sh

VERSION=$(grep 'version:' pubspec.yaml | head -1 | awk '{print $2}' | cut -d+ -f1)
echo "Building Gloam v${VERSION} for macOS..."

# Load environment variables
DART_DEFINES=""
if [ -f ".env" ]; then
  while IFS='=' read -r key value; do
    [ -z "$key" ] && continue
    [[ "$key" =~ ^# ]] && continue
    DART_DEFINES="$DART_DEFINES --dart-define=$key=$value"
  done < .env
fi

# Build
fvm flutter build macos --release $DART_DEFINES 2>&1 | tail -3

APP="build/macos/Build/Products/Release/gloam.app"
DEST="$APP/Contents/MacOS"
ENTITLEMENTS="macos/Runner/Release.entitlements"
SIGN_ID="${APPLE_SIGN_ID:-Apple Development: Simon Abizmil (57B64F2V6Q)}"

mkdir -p "$DEST"

# Bundle native libs
LIBOLM="/opt/homebrew/lib/libolm.3.dylib"
if [ -f "$LIBOLM" ]; then
  cp "$LIBOLM" "$DEST/libolm.3.dylib"
  codesign --force --sign "$SIGN_ID" "$DEST/libolm.3.dylib"
fi

LIBCRYPTO="/opt/homebrew/lib/libcrypto.3.dylib"
LIBCRYPTO_REAL=$(readlink -f "$LIBCRYPTO" 2>/dev/null || echo "$LIBCRYPTO")
if [ -f "$LIBCRYPTO_REAL" ]; then
  cp "$LIBCRYPTO_REAL" "$DEST/libcrypto.3.dylib"
  codesign --force --sign "$SIGN_ID" "$DEST/libcrypto.3.dylib"
fi

# Sign the app with hardened runtime (required for notarization)
codesign --force --deep --options runtime \
  --sign "$SIGN_ID" --entitlements "$ENTITLEMENTS" "$APP"

echo "Signed with: $SIGN_ID"

# Create ZIP (Sparkle prefers ZIP over DMG for updates)
OUTPUT_ZIP="build/Gloam-${VERSION}-macos.zip"
cd build/macos/Build/Products/Release
zip -r -y "../../../../${OUTPUT_ZIP}" gloam.app
cd ../../../../..

echo "Created: $OUTPUT_ZIP"

# Notarize (if credentials available)
if [ -n "$APPLE_ID" ] && [ -n "$APPLE_APP_PASSWORD" ]; then
  echo "Notarizing..."
  xcrun notarytool submit "$OUTPUT_ZIP" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --wait

  # Staple the app (re-zip after stapling)
  xcrun stapler staple "$APP"
  cd build/macos/Build/Products/Release
  zip -r -y "../../../../${OUTPUT_ZIP}" gloam.app
  cd ../../../../..
  echo "✓ Notarized and stapled"
else
  echo "⚠ Skipping notarization (no credentials)"
fi

echo "✓ Gloam v${VERSION} macOS build ready: $OUTPUT_ZIP"
ls -lh "$OUTPUT_ZIP"
