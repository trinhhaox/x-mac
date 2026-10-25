#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="Xmac"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
# Team ID: ký lại bằng Developer ID trên đám mây và notarize qua tài khoản Xcode.
XCODE_NOTARIZE_TEAM="${XCODE_NOTARIZE_TEAM:-}"

if [[ -n "$XCODE_NOTARIZE_TEAM" ]]; then
    if [[ "$CODE_SIGN_IDENTITY" == "-" || -n "$NOTARY_PROFILE" ]]; then
        echo "XCODE_NOTARIZE_TEAM cần CODE_SIGN_IDENTITY không phải ad-hoc và không dùng chung NOTARY_PROFILE." >&2
        exit 1
    fi
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PROJECT_DIR/Resources/Info.plist" 2>/dev/null || echo "1.0.0")"

# Compile exactly what Package.swift compiles, so a new source file can never
# pass `swift test` yet be missing from the release binary.
SWIFT_SOURCES=()
while IFS= read -r -d '' source_file; do
    SWIFT_SOURCES+=("$source_file")
done < <(find "$PROJECT_DIR/Sources" -name '*.swift' -print0 | sort -z)

SWIFT_FLAGS=(
    -O
    -swift-version 5
    -framework Cocoa
    -framework SwiftUI
    -framework ServiceManagement
    -framework UserNotifications
    -framework AudioToolbox
    -framework Carbon
)

echo "=== Building $APP_NAME v$VERSION ==="

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

MODULE_CACHE_DIR="$BUILD_DIR/module-cache"
mkdir -p "$MODULE_CACHE_DIR"
SWIFT_FLAGS+=(
    -module-cache-path "$MODULE_CACHE_DIR"
)

# 1. Biên dịch cho Apple Silicon (arm64)
echo "Compiling for arm64 (Apple Silicon)..."
swiftc "${SWIFT_FLAGS[@]}" -target arm64-apple-macos13.0 \
    -o "$BUILD_DIR/${APP_NAME}_arm64" "${SWIFT_SOURCES[@]}"

# 2. Biên dịch cho Intel (x86_64)
echo "Compiling for x86_64 (Intel)..."
swiftc "${SWIFT_FLAGS[@]}" -target x86_64-apple-macos13.0 \
    -o "$BUILD_DIR/${APP_NAME}_x86_64" "${SWIFT_SOURCES[@]}"

# 3. Tạo Universal Binary (chạy trên mọi máy Mac)
echo "Creating Universal Binary..."
lipo -create \
    "$BUILD_DIR/${APP_NAME}_arm64" \
    "$BUILD_DIR/${APP_NAME}_x86_64" \
    -output "$BUILD_DIR/$APP_NAME"

rm "$BUILD_DIR/${APP_NAME}_arm64" "$BUILD_DIR/${APP_NAME}_x86_64"

echo "Compilation successful!"

# 4. Đóng gói .app bundle
echo "Creating app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/"
if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
fi
for localization_dir in "$PROJECT_DIR"/Sources/LocalizationResources/*.lproj; do
    if [ -d "$localization_dir" ]; then
        cp -R "$localization_dir" "$APP_BUNDLE/Contents/Resources/"
    fi
done

rm "$BUILD_DIR/$APP_NAME"

# 5. Ký mã. Mặc định dùng ad-hoc cho bản local; bản phát hành có thể truyền
# CODE_SIGN_IDENTITY đã tồn tại trong Keychain.
if [[ "$CODE_SIGN_IDENTITY" == "-" ]]; then
    echo "Signing app bundle ad-hoc..."
    codesign --force --deep --sign - "$APP_BUNDLE"
else
    echo "Signing app bundle with configured Developer ID..."
    # Hardened runtime blocks Apple Events (Finder Cut/Paste, NTFS admin
    # prompt) unless the entitlement is declared.
    codesign --force --deep --options runtime --timestamp \
        --entitlements "$PROJECT_DIR/Resources/Xmac.entitlements" \
        --sign "$CODE_SIGN_IDENTITY" "$APP_BUNDLE"
fi

codesign --verify --deep --strict "$APP_BUNDLE"

if [[ -n "$XCODE_NOTARIZE_TEAM" ]]; then
    "$SCRIPT_DIR/notarize-with-xcode.sh" "$APP_BUNDLE" "$XCODE_NOTARIZE_TEAM"
fi

echo "App bundle created at: $APP_BUNDLE"

# 6. Tạo DMG Installer
echo "Creating DMG installer..."
DMG_DIR="$BUILD_DIR/dmg_staging"
DMG_PATH="$BUILD_DIR/Xmac-${VERSION}.dmg"

mkdir -p "$DMG_DIR"
cp -r "$APP_BUNDLE" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

hdiutil create -volname "Xmac" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO \
    "$DMG_PATH" >/dev/null

rm -rf "$DMG_DIR"

# Chứng thư Developer ID trên đám mây không có trong Keychain nên DMG để
# không ký; Gatekeeper kiểm tra app đã staple bên trong.
if [[ "$CODE_SIGN_IDENTITY" != "-" && -z "$XCODE_NOTARIZE_TEAM" ]]; then
    echo "Signing DMG with configured Developer ID..."
    codesign --force --timestamp --sign "$CODE_SIGN_IDENTITY" "$DMG_PATH"
    codesign --verify --strict "$DMG_PATH"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
    if [[ "$CODE_SIGN_IDENTITY" == "-" ]]; then
        echo "NOTARY_PROFILE yêu cầu CODE_SIGN_IDENTITY không phải ad-hoc (-)." >&2
        exit 1
    fi
    echo "Submitting DMG for notarization with configured Keychain profile..."
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
fi

hdiutil verify "$DMG_PATH" >/dev/null

echo ""
echo "=== Build Complete Successfully! ==="
echo "App bundle: $APP_BUNDLE"
echo "DMG File:   $DMG_PATH"
