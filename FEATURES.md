# Planned Features

This file is the source of truth for planned product work. The README describes
what the current prototype already supports.

## Now

_No items currently queued._

## Later

- Optionally add Apple Developer signing and notarization to improve Gatekeeper
  usability for public releases.
  - This is not a release prerequisite: current releases are ad-hoc signed and
    Sparkle update archives are authenticated independently with Ed25519.
  - Acceptance: after enrolling in the Apple Developer Program, add a separate
    opt-in release path that signs, notarizes, and staples the app while
    retaining Sparkle signature verification.
