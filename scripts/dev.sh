#!/bin/bash
set -e

# ---------------------------------------------------------------------------
# dev.sh — single entry point for local development
#
# Usage:
#   ./scripts/dev.sh          # incremental build + launch
#   ./scripts/dev.sh --fresh  # clean rebuild (use when native deps change)
# ---------------------------------------------------------------------------

FRESH=false
if [[ "$1" == "--fresh" ]]; then
  FRESH=true
fi

# Only kill dev instances — match the Debug build path, NOT the production app
pkill -f "Build/Products/Debug/gloam" 2>/dev/null || true
sleep 1

# Load environment variables
DART_DEFINES="--dart-define=IS_DEV=true"
if [ -f ".env" ]; then
  while IFS='=' read -r key value; do
    [ -z "$key" ] && continue
    [[ "$key" =~ ^# ]] && continue
    DART_DEFINES="$DART_DEFINES --dart-define=$key=$value"
  done < .env
fi

# Clean only when explicitly requested (native dep changes, weird cache issues)
if $FRESH; then
  echo "🔄 Fresh build requested — cleaning..."
  fvm flutter clean 2>&1 | tail -1
fi

echo "Building Gloam (dev)..."
fvm flutter build macos --debug $DART_DEFINES 2>&1 | tail -2

# ---------------------------------------------------------------------------
# Native lib bundling — skip if already present (unless --fresh)
# ---------------------------------------------------------------------------
APP="build/macos/Build/Products/Debug/gloam.app"
DEST="$APP/Contents/MacOS"
ENTITLEMENTS="macos/Runner/DebugProfile.entitlements"
SIGN_IDENTITY="Apple Development: Simon Abizmil (57B64F2V6Q)"

mkdir -p "$DEST"

FRAMEWORKS="$APP/Contents/Frameworks"
mkdir -p "$FRAMEWORKS"

NEEDS_BUNDLE=false
if $FRESH || [ ! -f "$DEST/libolm.3.dylib" ] || [ ! -f "$DEST/libcrypto.3.dylib" ]; then
  NEEDS_BUNDLE=true
fi

if $NEEDS_BUNDLE; then
  echo "Bundling native libs..."

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
else
  echo "Native libs already bundled — skipping (use --fresh to force)"
fi

# Copy notification sound files into app bundle Resources
SOUNDS_SRC="macos/Runner/Resources/Sounds"
SOUNDS_DEST="$APP/Contents/Resources"
if [ -d "$SOUNDS_SRC" ]; then
  cp "$SOUNDS_SRC"/*.aiff "$SOUNDS_DEST/" 2>/dev/null || true
fi

# Re-sign the app with developer identity + entitlements
codesign --force --deep --sign "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS" "$APP"

# Verify
echo "Signing identity:"
codesign -dvv "$APP" 2>&1 | grep "Authority" | head -1

echo "Entitlements check:"
codesign -d --entitlements - "$APP" 2>&1 | grep "files.user-selected" && echo "✓ File access entitlements present" || echo "⚠ File access entitlements missing"

# Launch
echo "✓ Launching Gloam (dev)"
open "$APP"
