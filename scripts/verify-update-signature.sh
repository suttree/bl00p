#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 APPCAST ARCHIVE" >&2
    exit 64
fi

appcast=$1
archive=$2
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/bl00p-update-verification.XXXXXX")

cleanup() {
    rm -rf "$temporary_directory"
}
trap cleanup EXIT HUP INT TERM

metadata=$(
    ruby -r rexml/document -e '
        document = REXML::Document.new(File.read(ARGV.fetch(0)))
        item = REXML::XPath.first(document, "//item")
        abort "Appcast has no update item" unless item
        enclosure = REXML::XPath.first(item, "enclosure")
        abort "Appcast update has no enclosure" unless enclosure
        signature = enclosure.attributes.get_attribute_ns(
          "http://www.andymatuschak.org/xml-namespaces/sparkle",
          "edSignature"
        )
        abort "Appcast enclosure has no Ed25519 signature" unless signature
        puts enclosure.attributes.fetch("url")
        puts signature.value
    ' "$appcast"
)
enclosure_url=$(printf '%s\n' "$metadata" | sed -n '1p')
signature=$(printf '%s\n' "$metadata" | sed -n '2p')

if [ "$(basename "$enclosure_url")" != "$(basename "$archive")" ]; then
    echo "Appcast enclosure does not reference the supplied archive" >&2
    exit 1
fi

ditto -x -k "$archive" "$temporary_directory/archive"
app_info="$temporary_directory/archive/bl00p.app/Contents/Info.plist"

if [ ! -f "$app_info" ]; then
    echo "Archive does not contain bl00p.app" >&2
    exit 1
fi

public_key=$(plutil -extract SUPublicEDKey raw "$app_info")
printf '%s' "$public_key" |
    openssl base64 -d -A > "$temporary_directory/public-key.raw"

if [ "$(wc -c < "$temporary_directory/public-key.raw" | tr -d ' ')" -ne 32 ]; then
    echo "The app's Sparkle public key is not a 32-byte Ed25519 key" >&2
    exit 1
fi

# Wrap the raw Ed25519 key in an RFC 8410 SubjectPublicKeyInfo structure.
printf '\060\052\060\005\006\003\053\145\160\003\041\000' \
    > "$temporary_directory/public-key.der"
dd \
    if="$temporary_directory/public-key.raw" \
    of="$temporary_directory/public-key.der" \
    bs=1 \
    seek=12 \
    conv=notrunc \
    2>/dev/null
openssl pkey \
    -pubin \
    -inform DER \
    -in "$temporary_directory/public-key.der" \
    -out "$temporary_directory/public-key.pem"

printf '%s' "$signature" |
    openssl base64 -d -A > "$temporary_directory/signature.bin"

if [ "$(wc -c < "$temporary_directory/signature.bin" | tr -d ' ')" -ne 64 ]; then
    echo "The appcast Ed25519 signature is not 64 bytes" >&2
    exit 1
fi

openssl pkeyutl \
    -verify \
    -pubin \
    -inkey "$temporary_directory/public-key.pem" \
    -rawin \
    -in "$archive" \
    -sigfile "$temporary_directory/signature.bin"
