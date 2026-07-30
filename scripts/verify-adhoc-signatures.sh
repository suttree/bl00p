#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 APP_OR_ZIP" >&2
    exit 64
fi

input=$1
temporary_directory=

cleanup() {
    if [ -n "$temporary_directory" ]; then
        rm -rf "$temporary_directory"
    fi
}
trap cleanup EXIT HUP INT TERM

if [ -d "$input" ]; then
    app=$input
elif [ -f "$input" ]; then
    unzip -tq "$input"
    temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/bl00p-signature-verification.XXXXXX")
    ditto -x -k "$input" "$temporary_directory"
    app="$temporary_directory/bl00p.app"
else
    echo "Missing app or ZIP: $input" >&2
    exit 1
fi

if [ ! -d "$app" ]; then
    echo "Archive does not contain bl00p.app at its root" >&2
    exit 1
fi

sparkle="$app/Contents/Frameworks/Sparkle.framework"
sparkle_version="$sparkle/Versions/Current"

if [ ! -L "$sparkle_version" ]; then
    echo "Sparkle.framework/Versions/Current is not an archive-preserved symlink" >&2
    exit 1
fi

components="
$sparkle_version/XPCServices/Installer.xpc
$sparkle_version/XPCServices/Downloader.xpc
$sparkle_version/Autoupdate
$sparkle_version/Updater.app
$sparkle
$app
"

codesign --verify --deep --strict --verbose=2 "$app"

printf '%s\n' "$components" |
while IFS= read -r component; do
    if [ -z "$component" ]; then
        continue
    fi
    if [ ! -e "$component" ]; then
        echo "Missing signed component: $component" >&2
        exit 1
    fi

    codesign --verify --strict --verbose=2 "$component"
    details=$(codesign -dv --verbose=4 "$component" 2>&1)
    if ! printf '%s\n' "$details" | grep -q '^Signature=adhoc$'; then
        echo "Component is not ad-hoc signed: $component" >&2
        exit 1
    fi
done

echo "Verified ad-hoc signatures in $input"
