#!/bin/sh
set -eu

openssl_bin=${OPENSSL_BIN:-openssl}
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/bl00p-openssl-check.XXXXXX")

cleanup() {
    rm -rf "$temporary_directory"
}
trap cleanup EXIT HUP INT TERM

if ! "$openssl_bin" version >/dev/null 2>&1; then
    echo "OpenSSL executable is unavailable: $openssl_bin" >&2
    exit 1
fi

printf 'bl00p Ed25519 verification check\n' \
    > "$temporary_directory/message"

if ! "$openssl_bin" genpkey \
        -algorithm ED25519 \
        -out "$temporary_directory/private-key.pem" ||
    ! "$openssl_bin" pkey \
        -in "$temporary_directory/private-key.pem" \
        -pubout \
        -out "$temporary_directory/public-key.pem" ||
    ! "$openssl_bin" pkeyutl \
        -sign \
        -inkey "$temporary_directory/private-key.pem" \
        -rawin \
        -in "$temporary_directory/message" \
        -out "$temporary_directory/signature" ||
    ! "$openssl_bin" pkeyutl \
        -verify \
        -pubin \
        -inkey "$temporary_directory/public-key.pem" \
        -rawin \
        -in "$temporary_directory/message" \
        -sigfile "$temporary_directory/signature"
then
    echo "OpenSSL with Ed25519 pkeyutl -rawin support is required" >&2
    "$openssl_bin" version >&2 || :
    exit 1
fi

echo "Verified OpenSSL Ed25519 support with $openssl_bin"
