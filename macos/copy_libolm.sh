#!/bin/bash
# Copy libolm into the app bundle's Frameworks directory
FRAMEWORKS_DIR="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"
cp /opt/homebrew/lib/libolm.3.dylib "$FRAMEWORKS_DIR/"
# Also create the symlink the olm package expects
ln -sf libolm.3.dylib "$FRAMEWORKS_DIR/libolm.dylib"
# Fix the dylib's install name so it can be found in the bundle
install_name_tool -id @rpath/libolm.3.dylib "$FRAMEWORKS_DIR/libolm.3.dylib" 2>/dev/null || true
echo "libolm copied to $FRAMEWORKS_DIR"
