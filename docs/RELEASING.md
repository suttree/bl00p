# Releasing bl00p

bl00p uses Sparkle 2 and GitHub Releases for authenticated macOS updates.

## Release contract

Every reviewed push or merge to protected `main` is release-ready. The
**Release** workflow validates that commit and publishes it automatically as
the latest stable GitHub Release. Incomplete, experimental, or otherwise
unreleasable work must not be merged to `main`.

The repository version in `Resources/Info.plist` defines the release series.
For a base version `major.minor.patch`, a workflow with
`github.run_number = N` publishes:

```text
display version: major.minor.(patch + N)
tag:             vmajor.minor.(patch + N)
bundle build:    github.run_id
```

The run number and run ID do not change when GitHub retries the same workflow
run. The run ID is a strictly increasing numeric `CFBundleVersion`, which is
the value Sparkle uses to order builds. Before packaging, the workflow checks
it against the repository baseline and the newest published appcast. It also
rejects a malformed base version or a release tag owned by another commit.

The workflow has no tag trigger, so the tag it creates cannot recursively
start another release.

## Signing and GitHub setup

The release job uses the protected GitHub Environment named `release`. Configure
that environment to:

- allow deployments from protected `main`;
- have no required deployment reviewers, so a successful `main` build can
  publish without a manual gate; and
- hold one environment secret, `SPARKLE_PRIVATE_KEY`, containing the base64
  Sparkle Ed25519 private seed.

The app contains the matching public Sparkle Ed25519 key. The release workflow
cryptographically verifies every generated archive signature against that
embedded public key before it can publish. The app, Sparkle framework, XPC
services, updater, and autoupdate helper are signed inside-out with an ad-hoc
identity. `scripts/verify-adhoc-signatures.sh` extracts the final ZIP and checks
that every component is structurally intact, validly signed, and reports
`Signature=adhoc`.

Never commit or print the private seed. Keep a separate secure backup outside
the repository; the GitHub secret cannot be read back after it is saved.

## Gatekeeper tradeoff

This release path does not use an Apple Developer account, Developer ID
certificate, or Apple notarization. macOS therefore does not identify or
notarize bl00p, and Gatekeeper blocks the normal first double-click after a
download.

For the first installation, drag `bl00p.app` into `/Applications`,
Control-click it, choose **Open**, then confirm **Open**. Alternatively, try
opening it once and choose **Open Anyway** in **System Settings → Privacy &
Security**. Only do this for an archive downloaded from the project's GitHub
Releases page.

This manual approval affects the first installation. Later updates still use
Sparkle's in-app flow. Sparkle's Ed25519 signature protects the update archive
independently of Apple code signing, and `SUVerifyUpdateBeforeExtraction` keeps
verification ahead of extraction. Developer ID signing and notarization can be
added later to remove the first-launch warning; they are usability hardening,
not prerequisites for authenticated updates.

## What happens after a merge

The Release workflow:

1. verifies that the workflow commit is contained in `origin/main`;
2. derives a unique tag, display version, and monotonic bundle build;
3. checks that any existing release tag belongs to the same commit;
4. validates both Actions workflows and the account-free release policy;
5. runs the complete macOS test suite;
6. builds the installable ZIP, ad-hoc signs Sparkle's nested helpers and the
   app, and verifies the signatures after extracting the final archive;
7. generates the appcast with the Sparkle private key and verifies its asset
   URL, bundle build, display version, and Ed25519 signature; and
8. only then creates the tag and publishes the ZIP and `appcast.xml`, explicitly
   marking the non-draft, non-prerelease GitHub Release as latest.

A failure in steps 1–7 creates no tag or release. Publication is safe to retry:
an existing tag must resolve to the same commit, and assets are replaced only
on that exact release. A native retry reuses the original run number and run
ID.

Installed apps read:

```text
https://github.com/suttree/bl00p/releases/latest/download/appcast.xml
```

Sparkle checks that feed while the app is running at a one-hour interval, its
supported minimum. **Check for Updates…** performs an immediate manual check.
With automatic updates enabled, Sparkle may download the authenticated update
in the background and install it when the app quits or is relaunched; the app
does not force-restart an active session.

## First controlled automatic release

After merging this release automation:

1. confirm the workflow finishes and exactly one release is marked latest;
2. confirm that release contains the ZIP and `appcast.xml`;
3. open the latest appcast URL and verify it resolves to that release;
4. install the preceding build, use **Check for Updates…**, and complete an
   end-to-end update; and
5. confirm the updated app reports the new display version and bundle build.
