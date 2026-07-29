#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
configuration=${1:-debug}
binary_path="$project_root/.build/$configuration/bl00p"
arch=$(dpkg --print-architecture 2>/dev/null || echo amd64)
version=${APP_VERSION:-0.1.0}
stage_dir="$project_root/.build/deb/bl00p_${version}_${arch}"
deb_path="$project_root/.build/deb/bl00p_${version}_${arch}.deb"

if [ ! -x "$binary_path" ]; then
    echo "Missing $binary_path. Run swift build first." >&2
    exit 1
fi

rm -rf "$stage_dir"
mkdir -p \
    "$stage_dir/DEBIAN" \
    "$stage_dir/usr/bin" \
    "$stage_dir/usr/share/applications" \
    "$stage_dir/usr/share/icons/hicolor/1024x1024/apps"

cp "$binary_path" "$stage_dir/usr/bin/bl00p"
chmod 755 "$stage_dir/usr/bin/bl00p"

cp "$project_root/packaging/linux/dev.bl00p.app.desktop" \
    "$stage_dir/usr/share/applications/dev.bl00p.app.desktop"

cp "$project_root/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" \
    "$stage_dir/usr/share/icons/hicolor/1024x1024/apps/dev.bl00p.app.png"

sed \
    -e "s/__VERSION__/$version/" \
    -e "s/__ARCH__/$arch/" \
    "$project_root/packaging/linux/control.template" \
    > "$stage_dir/DEBIAN/control"

mkdir -p "$project_root/.build/deb"
dpkg-deb --build --root-owner-group "$stage_dir" "$deb_path"

echo "$deb_path"
