#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
developer_dir=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
install_dir="$project_root/.build/install"
install_app="$install_dir/bl00p.app"
version=$(
    plutil -extract CFBundleShortVersionString raw \
        "$project_root/Resources/Info.plist"
)
archive="$install_dir/bl00p-$version-macos-arm64.zip"

mkdir -p "$project_root/.build/release-home"
mkdir -p "$project_root/.build/release-cache"
mkdir -p "$project_root/.build/release-clang-module-cache"
mkdir -p "$project_root/.build/release-swiftpm-module-cache"
mkdir -p "$install_dir"

env \
    HOME="$project_root/.build/release-home" \
    XDG_CACHE_HOME="$project_root/.build/release-cache" \
    DEVELOPER_DIR="$developer_dir" \
    CLANG_MODULE_CACHE_PATH="$project_root/.build/release-clang-module-cache" \
    SWIFTPM_MODULECACHE_OVERRIDE="$project_root/.build/release-swiftpm-module-cache" \
    xcrun swift build -c release --disable-sandbox

env DEVELOPER_DIR="$developer_dir" \
    sh "$project_root/scripts/package-app.sh" release

rm -rf "$install_app"
rm -f "$archive"
ditto "$project_root/.build/bl00p.app" "$install_app"

codesign --verify --deep --strict --verbose=2 "$install_app"
ditto -c -k --sequesterRsrc --keepParent "$install_app" "$archive"
unzip -tq "$archive"

echo "$install_app"
echo "$archive"
