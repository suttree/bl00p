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
the `main` branch and `v*` tags, and holds these environment secrets:

- `SPARKLE_PRIVATE_KEY`: the base64 Sparkle Ed25519 private seed.
- `APPLE_DEVELOPER_ID_CERTIFICATE`: the Developer ID Application certificate
  and private key exported as a `.p12` file, then base64 encoded.
- `APPLE_CERTIFICATE_PASSWORD`: the password for the `.p12` file.
- `APPLE_NOTARY_KEY_ID`: an App Store Connect API key ID.
- `APPLE_NOTARY_ISSUER_ID`: the App Store Connect API issuer ID.
- `APPLE_NOTARY_PRIVATE_KEY`: the complete contents of the API key `.p8` file.

The app contains the matching public Sparkle Ed25519 key. The release workflow
cryptographically verifies every generated archive signature against that
embedded public key before it can publish.

Never commit or print the private seed. Keep a separate secure backup outside
the repository; the GitHub secret cannot be read back after it is saved.

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
3. runs the test suite;
4. signs Sparkle's nested helpers and the app with Developer ID;
5. notarizes the ZIP with Apple, staples the ticket, and rebuilds the ZIP;
6. signs the archive with Sparkle Ed25519 and verifies that signature against
   the public key embedded in the archived app; and
7. publishes the notarized ZIP and verified `appcast.xml` in a GitHub Release.

Manual workflow dispatches must be run from `main` and name an existing,
protected version tag. They cannot select and release an arbitrary branch.

Installed apps read the latest release feed from:

```text
https://github.com/suttree/bl00p/releases/latest/download/appcast.xml
```

The first Sparkle-enabled version must still be installed manually. Versions
after that can be downloaded, installed, and relaunched by the app.
