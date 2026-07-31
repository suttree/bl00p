#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
linux_entry="$project_root/Sources/Bl00p/main.swift"
source_root="$project_root/Sources/Bl00p"
compat_file="$source_root/Platform/UICompat.swift"

if grep -En 'WindowGroup[[:space:]]*\{' "$linux_entry"; then
    echo "Linux WindowGroup must pass an explicit title; use an empty string for untitled windows" >&2
    exit 1
fi

if ! grep -Fq 'WindowGroup("") {' "$linux_entry"; then
    echo "Linux entry point must keep its explicit empty WindowGroup title" >&2
    exit 1
fi

accessibility_violations=$(
    grep -R -n \
        --include='*.swift' \
        '\.accessibilityElement(children:' \
        "$source_root" |
        grep -Fv "$compat_file:" || true
)
if [ -n "$accessibility_violations" ]; then
    echo "Shared views must use the accessibility helpers in Platform/UICompat.swift:" >&2
    printf '%s\n' "$accessibility_violations" >&2
    exit 1
fi

for helper in \
    'func bl00pAccessibilitySummary(' \
    'func bl00pCombinedAccessibilityLabel('
do
    if ! grep -Fq "$helper" "$compat_file"; then
        echo "Portable UI compatibility helper is missing: $helper" >&2
        exit 1
    fi
done

echo "Verified portable SwiftUI and SwiftOpenUI contracts"
