#!/bin/bash
set -e

# Build Gloam for macOS with E2EE support (native library bundling)
echo "Building Gloam for macOS..."
fvm flutter build macos --debug

APP="build/macos/Build/Products/Debug/gloam.app"
DEST="$APP/Contents/MacOS"

# Bundle libolm (Matrix E2EE)
LIBOLM="/opt/homebrew/lib/libolm.3.dylib"
if [ -f "$LIBOLM" ]; then
  rm -f "$DEST/libolm.3.dylib"
  cp "$LIBOLM" "$DEST/libolm.3.dylib"
  codesign --force --sign - "$DEST/libolm.3.dylib"
  echo "✓ Bundled libolm"
else
  echo "⚠ libolm not found — install with: brew install libolm"
fi

# Bundle libcrypto (OpenSSL — needed for SSSS key backup operations)
LIBCRYPTO="/opt/homebrew/lib/libcrypto.3.dylib"
if [ -L "$LIBCRYPTO" ]; then
  # Resolve symlink to get the actual file
  LIBCRYPTO_REAL=$(readlink -f "$LIBCRYPTO")
  rm -f "$DEST/libcrypto.3.dylib"
  cp "$LIBCRYPTO_REAL" "$DEST/libcrypto.3.dylib"
  codesign --force --sign - "$DEST/libcrypto.3.dylib"
  echo "✓ Bundled libcrypto"
elif [ -f "$LIBCRYPTO" ]; then
  rm -f "$DEST/libcrypto.3.dylib"
  cp "$LIBCRYPTO" "$DEST/libcrypto.3.dylib"
  codesign --force --sign - "$DEST/libcrypto.3.dylib"
  echo "✓ Bundled libcrypto"
else
  echo "⚠ libcrypto not found — install with: brew install openssl@3"
fi

# Re-sign the entire app bundle
codesign --force --deep --sign - "$APP"
echo "✓ Built and signed $APP"
