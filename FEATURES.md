# Planned Features

This file is the source of truth for planned product work. The README describes
what the current prototype already supports.

## Now

- Add Git worktree ownership and handoff packages.
  - Acceptance: implementation bots can work in isolated worktrees and hand
    off their branch, task context, and test state without overlapping edits.

## Later

- Set up Apple Developer signing and notarization for the first public release.
  - Prerequisite: enroll in the Apple Developer Program.
  - Acceptance: add the Developer ID certificate and App Store Connect
    notarization credentials to the protected `release` environment, then
    confirm the release workflow signs, notarizes, staples, and publishes the
    app successfully.
