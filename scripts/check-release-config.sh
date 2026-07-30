#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
workflow="$project_root/.github/workflows/release.yml"

ruby -e 'require "yaml"; YAML.parse_file(ARGV.fetch(0))' "$workflow"

for forbidden in \
    'APPLE_' \
    'notarytool' \
    'stapler' \
    'Developer ID' \
    'spctl --assess' \
    'security import'
do
    if grep -Fq "$forbidden" "$workflow"; then
        echo "Release workflow contains forbidden Apple credential or notarization reference: $forbidden" >&2
        exit 1
    fi
done

for required in \
    'CODE_SIGN_IDENTITY: "-"' \
    'SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}' \
    'scripts/verify-adhoc-signatures.sh' \
    'scripts/verify-update-signature.sh'
do
    if ! grep -Fq "$required" "$workflow"; then
        echo "Release workflow is missing required account-free release configuration: $required" >&2
        exit 1
    fi
done

secret_references=$(
    grep -oE 'secrets\.[A-Za-z_][A-Za-z0-9_]*' "$workflow" |
        sort -u
)
if [ "$secret_references" != "secrets.SPARKLE_PRIVATE_KEY" ]; then
    echo "Release workflow may only reference the SPARKLE_PRIVATE_KEY secret" >&2
    printf '%s\n' "$secret_references" >&2
    exit 1
fi

echo "Verified account-free release configuration"
