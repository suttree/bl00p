#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
helper="$project_root/scripts/derive-release-version.rb"
release_sha=1111111111111111111111111111111111111111
other_sha=2222222222222222222222222222222222222222

assert_fails() {
    if ruby "$helper" "$@" >/dev/null 2>&1; then
        echo "Expected release derivation to fail: $*" >&2
        exit 1
    fi
}

derived=$(ruby "$helper" 0.1.0 7 1007 1006 "$release_sha")
expected='version=0.1.7
tag=v0.1.7
build=1007'
if [ "$derived" != "$expected" ]; then
    echo "Unexpected release derivation:" >&2
    printf '%s\n' "$derived" >&2
    exit 1
fi

ruby "$helper" 1.2.3 7 1007 6 "$release_sha" "$release_sha" >/dev/null
ruby "$helper" 1.2.3 7 1007 1007 "$release_sha" "$release_sha" >/dev/null

assert_fails 1.2 7 1007 6 "$release_sha"
assert_fails 1.2.beta 7 1007 6 "$release_sha"
assert_fails 01.2.3 7 1007 6 "$release_sha"
assert_fails 1.2.3 0 1007 6 "$release_sha"
assert_fails 1.2.3 7 6 6 "$release_sha"
assert_fails 1.2.3 7 5 6 "$release_sha"
assert_fails 1.2.3 7 1007 1007 "$release_sha"
assert_fails 1.2.3 7 1007 6 "$release_sha" "$other_sha"

echo "Verified release version derivation"
