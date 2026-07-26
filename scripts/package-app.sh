#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
configuration=${1:-debug}
binary_path="$project_root/.build/$configuration/bl00p"
app_path="$project_root/.build/bl00p.app"
icon_info_path="$project_root/.build/AppIconInfo.plist"
developer_dir=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
sparkle_framework="$project_root/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
embedded_sparkle="$app_path/Contents/Frameworks/Sparkle.framework"

if [ ! -x "$binary_path" ]; then
    echo "Missing $binary_path. Run swift build first." >&2
    exit 1
fi

if [ ! -d "$sparkle_framework" ]; then
    echo "Missing Sparkle framework. Run swift package resolve first." >&2
    exit 1
fi

mkdir -p "$app_path/Contents/MacOS"
mkdir -p "$app_path/Contents/Resources"
mkdir -p "$app_path/Contents/Frameworks"
cp "$binary_path" "$app_path/Contents/MacOS/bl00p"
cp "$project_root/Resources/Info.plist" "$app_path/Contents/Info.plist"
cp "$project_root/Resources/BrandIcon.png" "$app_path/Contents/Resources/BrandIcon.png"
rm -rf "$embedded_sparkle"
ditto "$sparkle_framework" "$embedded_sparkle"

if [ -n "${APP_VERSION:-}" ]; then
    plutil -replace CFBundleShortVersionString \
        -string "$APP_VERSION" \
        "$app_path/Contents/Info.plist"
fi

if [ -n "${BUILD_NUMBER:-}" ]; then
    plutil -replace CFBundleVersion \
        -string "$BUILD_NUMBER" \
        "$app_path/Contents/Info.plist"
fi

env DEVELOPER_DIR="$developer_dir" xcrun actool \
    "$project_root/Resources/IconComposer/AppIcon.icon" \
    --compile "$app_path/Contents/Resources" \
    --output-format human-readable-text \
    --notices \
    --warnings \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --target-device mac \
    --app-icon AppIcon \
    --include-all-app-icons \
    --compress-pngs \
    --enable-on-demand-resources NO \
    --development-region en \
    --bundle-identifier dev.bl00p.app \
    --output-partial-info-plist "$icon_info_path"
codesign \
    --force \
    --deep \
    --sign - \
    --timestamp=none \
    "$embedded_sparkle"
codesign \
    --force \
    --sign - \
    --timestamp=none \
    "$app_path"

echo "$app_path"
