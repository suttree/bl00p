# bl00p

bl00p (“bot loop”) is a native macOS control room for running coding agents through an implementation, review, and publishing loop while keeping a human in control.

The current prototype includes:

- Claude and Codex bot profiles
- Builder, reviewer, and PR-writer roles
- Editable role prompts and working directories
- A Slack-like sidebar with attention badges
- Automatic light and dark appearances that follow the macOS system setting
- Signed automatic updates through GitHub Releases, with install and relaunch
- Consistent, legible typography across conversations, settings, and bot creation
- Structured messages, commands, findings, and approval cards
- Optional Manager bots that coordinate a persistent Builder → Reviewer →
  Builder fixes → Documenter / PR Writer workflow
- Isolated managed Git worktrees for implementation bots, with handoff packages
  that carry branch, task, working-tree, and test context to the next bot
- Real Codex sessions powered by `codex app-server`, with workspace-scoped writes and in-app approvals for commands, file changes, extra permissions, and connected-app mutations
- Real, resumable Claude Code builder and PR-writer sessions with in-app tool approvals
- Local JSON persistence

## Run the prototype

The installed Xcode toolchain is required because the standalone Command Line Tools installation may not match the current macOS SDK.

```sh
mkdir -p .build/clang-module-cache .build/swiftpm-module-cache .build/cache

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swiftpm-module-cache" \
XDG_CACHE_HOME="$PWD/.build/cache" \
xcrun swift build --disable-sandbox

sh scripts/package-app.sh
open .build/bl00p.app
```

Run tests by replacing `swift build` with `swift test`.

## Build an installable release

Build, package, sign, and verify an optimized app bundle with:

```sh
sh scripts/build-installable-app.sh
```

The script writes `bl00p.app` and a bundle-preserving ZIP to
`.build/install/`. The app is ad-hoc signed for local installation: drag the
app into `/Applications`. GitHub releases use Developer ID signing and Apple
notarization before the stapled app is archived for distribution.

Release cadence, Sparkle signing, and GitHub Actions setup are documented in
[docs/RELEASING.md](docs/RELEASING.md).

Claude Code must be installed and authenticated before launching a Claude
profile:

```sh
claude auth login
```

## Optional managed workflows

Every bot can still be used independently. To enable orchestration, add or edit
a bot with the **Manager** role, then assign one existing Builder, Reviewer, and
Documenter / PR Writer in its settings. The Manager's next request starts a
persisted workflow with this sequence:

1. The Manager prepares the implementation brief.
2. You approve the implementation plan before it is handed to the team.
3. The Builder works in an isolated branch and commits a tested change locally.
4. The Reviewer performs a read-only review.
5. The Builder addresses the findings and commits the fixes.
6. The Documenter receives the revised Builder handoff, runs final verification,
   updates documentation, commits, pushes, and opens a draft PR.
7. The Manager reports the draft PR link and delivery summary.

Questions, failures, and approval requests pause the workflow for the user.
Leaving any team assignment unset keeps that Manager in standalone chat mode.

## Runtime boundary

`AgentRuntime` is intentionally provider-neutral. Codex profiles use the
desktop-bundled or plugin-bundled `codex app-server` runtime. Builder,
Reviewer, and Documenter threads use workspace-scoped execution and route
elevated and connected-app actions through bl00p's approval cards. Manager
threads are non-escalatable and read-only so bl00p alone owns delegation to
the configured team. Threads resume from their saved thread ID when possible.

Claude profiles use the installed `claude` executable's `stream-json` mode.
They inherit Claude's user and project settings, including configured MCP
servers. The current allowlist supports repository inspection, file edits for
Builder and Documenter roles, common test commands, and read-only Linear tools.
Manager and Reviewer roles cannot edit files. Actions outside that allowlist
pause in the conversation, where the user can approve or decline the exact
tool call before Claude continues.

## Roadmap

Planned product work and its acceptance criteria are tracked in
[FEATURES.md](FEATURES.md).
