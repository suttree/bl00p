# Releasing bl00p

bl00p uses Sparkle 2 and GitHub Releases for signed application updates.

## Release cadence

Pull requests and pushes to `main` run the full test and installable-app build.
They do not publish updates. Stable updates are published from semantic version
tags such as `v0.2.0`, or from the manual **Release** workflow.

This separation keeps ordinary merges from immediately updating every installed
copy of the app.

## Signing setup

The release job uses the protected GitHub Environment named `release`. That
environment requires approval with administrator bypass disabled, accepts only
the `main` branch and `v*` tags, and holds one environment secret:

- `SPARKLE_PRIVATE_KEY`: the base64 Sparkle Ed25519 private seed.

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
Sparkle's in-app download, install, and relaunch flow. Sparkle's Ed25519
signature protects the update archive independently of Apple code signing, and
`SUVerifyUpdateBeforeExtraction` keeps verification ahead of extraction.
Developer ID signing and notarization can be added later to remove the
first-launch warning; they are usability hardening, not prerequisites for
publishing authenticated Sparkle updates.

## Publish an update

Create and push a semantic version tag from the protected `main` branch. The
`v*` tag ruleset permits only the repository owner to create, move, or delete
release tags:

```sh
git switch main
git pull --ff-only origin main
git tag v0.2.0
git push origin v0.2.0
```

The Release workflow:

1. verifies that both the workflow and release commits are contained in
   `origin/main`;
2. waits for approval through the protected `release` environment;
3. checks that the workflow has no Apple credential or notarization dependency;
4. runs the test suite;
5. ad-hoc signs Sparkle's nested helpers and the app, then verifies the
   signatures again after extracting the final ZIP;
6. signs the archive with Sparkle Ed25519 and verifies that signature against
   the public key embedded in the archived app; and
7. publishes the ad-hoc-signed ZIP and verified `appcast.xml` in a GitHub
   Release.

Manual workflow dispatches must be run from `main` and name an existing,
protected version tag. They cannot select and release an arbitrary branch.

Installed apps read the latest release feed from:

```text
https://github.com/suttree/bl00p/releases/latest/download/appcast.xml
```

The first Sparkle-enabled version must still be installed and approved
manually. Versions after that can be downloaded, installed, and relaunched by
the app.
