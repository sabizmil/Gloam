#!/bin/bash
set -e

# Kill any running Gloam instance (SIGTERM to allow DB flush, then SIGKILL fallback)
pkill -f "gloam" 2>/dev/null || true
sleep 2
pkill -9 -f "gloam" 2>/dev/null || true

# Load environment variables
DART_DEFINES=""
if [ -f ".env" ]; then
  while IFS='=' read -r key value; do
    [ -z "$key" ] && continue
    [[ "$key" =~ ^# ]] && continue
    DART_DEFINES="$DART_DEFINES --dart-define=$key=$value"
  done < .env
fi

# Clean build to avoid stale Dart cache
echo "Cleaning..."
fvm flutter clean 2>&1 | tail -1

echo "Building Gloam..."
fvm flutter build macos --debug $DART_DEFINES 2>&1 | tail -2

# Bundle native libs
APP="build/macos/Build/Products/Debug/gloam.app"
DEST="$APP/Contents/MacOS"
ENTITLEMENTS="macos/Runner/DebugProfile.entitlements"
SIGN_IDENTITY="Apple Development: Simon Abizmil (57B64F2V6Q)"

mkdir -p "$DEST"

FRAMEWORKS="$APP/Contents/Frameworks"
mkdir -p "$FRAMEWORKS"

LIBOLM="/opt/homebrew/lib/libolm.3.dylib"
if [ -f "$LIBOLM" ]; then
  rm -f "$DEST/libolm.3.dylib" "$FRAMEWORKS/libolm.3.dylib"
  cp "$LIBOLM" "$DEST/libolm.3.dylib"
  cp "$LIBOLM" "$FRAMEWORKS/libolm.3.dylib"
  install_name_tool -id "@rpath/libolm.3.dylib" "$DEST/libolm.3.dylib"
  install_name_tool -id "@rpath/libolm.3.dylib" "$FRAMEWORKS/libolm.3.dylib"
  codesign --force --sign "$SIGN_IDENTITY" "$DEST/libolm.3.dylib"
  codesign --force --sign "$SIGN_IDENTITY" "$FRAMEWORKS/libolm.3.dylib"
fi

LIBCRYPTO="/opt/homebrew/lib/libcrypto.3.dylib"
LIBCRYPTO_REAL=$(readlink -f "$LIBCRYPTO" 2>/dev/null || echo "$LIBCRYPTO")
if [ -f "$LIBCRYPTO_REAL" ]; then
  rm -f "$DEST/libcrypto.3.dylib"
  cp "$LIBCRYPTO_REAL" "$DEST/libcrypto.3.dylib"
  codesign --force --sign "$SIGN_IDENTITY" "$DEST/libcrypto.3.dylib"
fi

# Re-sign the app with developer identity + entitlements
codesign --force --deep --sign "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS" "$APP"

# Verify
echo "Signing identity:"
codesign -dvv "$APP" 2>&1 | grep "Authority" | head -1

echo "Entitlements check:"
codesign -d --entitlements - "$APP" 2>&1 | grep "files.user-selected" && echo "✓ File access entitlements present" || echo "⚠ File access entitlements missing"

# Launch
echo "✓ Launching Gloam"
open "$APP"
