# Releasing bl00p

bl00p uses Sparkle 2 and GitHub Releases for signed application updates.

## Release cadence

Pull requests and pushes to `main` run the full test and installable-app build.
They do not publish updates. Stable updates are published from semantic version
tags such as `v0.2.0`, or from the manual **Release** workflow.

This separation keeps ordinary merges from immediately updating every installed
copy of the app.

## Signing setup

The app contains the public Sparkle Ed25519 key. The matching private seed must
be stored in the repository Actions secret named `SPARKLE_PRIVATE_KEY`.

Never commit or print the private seed. Keep a separate secure backup outside
the repository; the GitHub secret cannot be read back after it is saved.

## Publish an update

Create and push a semantic version tag from the protected `main` branch:

```sh
git switch main
git pull --ff-only origin main
git tag v0.2.0
git push origin v0.2.0
```

The Release workflow:

1. runs the test suite;
2. builds and verifies the installable app;
3. gives the app a monotonically increasing build number;
4. signs the update archive with Sparkle Ed25519;
5. generates `appcast.xml`; and
6. publishes both files in a GitHub Release.

Installed apps read the latest release feed from:

```text
https://github.com/suttree/bl00p/releases/latest/download/appcast.xml
```

The first Sparkle-enabled version must still be installed manually. Versions
after that can be downloaded, installed, and relaunched by the app.
