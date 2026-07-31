#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
release_workflow="$project_root/.github/workflows/release.yml"
ci_workflow="$project_root/.github/workflows/ci.yml"

for workflow in "$release_workflow" "$ci_workflow"
do
    ruby -e 'require "yaml"; YAML.parse_file(ARGV.fetch(0))' "$workflow"
done

if grep -Eq '^[[:space:]]+tags:' "$release_workflow"; then
    echo "Release workflow must not trigger from tags" >&2
    exit 1
fi

for required in \
    '  push:' \
    '    branches:' \
    '      - main' \
    '  workflow_dispatch:' \
    'GITHUB_RUN_NUMBER' \
    'GITHUB_RUN_ID' \
    'scripts/derive-release-version.rb' \
    'previous_build' \
    'Publish retry-safe latest GitHub Release' \
    'gh release upload' \
    '--clobber' \
    '--verify-tag' \
    '--latest'
do
    if ! grep -Fq -- "$required" "$release_workflow"; then
        echo "Release workflow is missing automatic-release policy: $required" >&2
        exit 1
    fi
done

for forbidden in \
    'APPLE_' \
    'notarytool' \
    'stapler' \
    'Developer ID' \
    'spctl --assess' \
    'security import'
do
    if grep -Fq "$forbidden" "$release_workflow"; then
        echo "Release workflow contains forbidden Apple credential or notarization reference: $forbidden" >&2
        exit 1
    fi
done

for required in \
    'CODE_SIGN_IDENTITY: "-"' \
    'SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}' \
    'brew install openssl@3' \
    'OPENSSL_BIN=$(brew --prefix openssl@3)/bin/openssl' \
    'scripts/check-openssl-ed25519.sh' \
    'scripts/verify-adhoc-signatures.sh' \
    'scripts/verify-update-signature.sh' \
    'EXPECTED_SPARKLE_VERSION' \
    'EXPECTED_DISPLAY_VERSION' \
    'EXPECTED_ASSET_URL'
do
    if ! grep -Fq "$required" "$release_workflow"; then
        echo "Release workflow is missing required account-free release configuration: $required" >&2
        exit 1
    fi
done

secret_references=$(
    grep -oE 'secrets\.[A-Za-z_][A-Za-z0-9_]*' "$release_workflow" |
        sort -u
)
if [ "$secret_references" != "secrets.SPARKLE_PRIVATE_KEY" ]; then
    echo "Release workflow may only reference the SPARKLE_PRIVATE_KEY secret" >&2
    printf '%s\n' "$secret_references" >&2
    exit 1
fi

policy_check_count=$(
    grep -Fc 'scripts/check-release-config.sh' "$ci_workflow"
)
if [ "$policy_check_count" -ne 2 ]; then
    echo "Both CI platforms must run the release-policy check" >&2
    exit 1
fi

portable_ui_check_count=$(
    grep -Fc 'scripts/check-portable-ui.sh' "$ci_workflow"
)
if [ "$portable_ui_check_count" -ne 2 ]; then
    echo "Both CI platforms must run the portable-UI contract check" >&2
    exit 1
fi

openssl_check_count=$(
    grep -Fc 'scripts/check-openssl-ed25519.sh' "$ci_workflow"
)
if [ "$openssl_check_count" -ne 1 ]; then
    echo "macOS CI must verify OpenSSL Ed25519 support" >&2
    exit 1
fi

tests_line=$(grep -n 'name: Run tests' "$release_workflow" | tail -1 | cut -d: -f1)
build_line=$(
    grep -n 'name: Build ad-hoc-signed app' "$release_workflow" |
        cut -d: -f1
)
signature_line=$(
    grep -n 'name: Generate and verify signed appcast' "$release_workflow" |
        cut -d: -f1
)
publish_line=$(
    grep -n 'name: Publish retry-safe latest GitHub Release' "$release_workflow" |
        cut -d: -f1
)
if [ "$tests_line" -ge "$build_line" ] ||
    [ "$build_line" -ge "$signature_line" ] ||
    [ "$signature_line" -ge "$publish_line" ]
then
    echo "Tests, packaging, signing, and publication are ordered incorrectly" >&2
    exit 1
fi

sh "$project_root/scripts/test-release-version.sh"

echo "Verified automatic account-free release configuration"
