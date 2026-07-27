# bl00p

bl00p (“bot loop”) is a control room for running coding agents through an implementation, review, and publishing loop while keeping a human in control.

This fork ([suttree/bl00p](https://github.com/suttree/bl00p) is upstream) targets Linux — built and tested on Kali — using [SwiftOpenUI](https://github.com/codelynx/SwiftOpenUI)'s GTK4 backend in place of AppKit/SwiftUI. The macOS build path is kept working alongside it; `Package.swift` and most `#if os(macOS)` branches in `Sources/Bl00p` select the platform automatically.

The current prototype includes:

- Claude and Codex bot profiles
- Sidebar bot renaming with the name field focused as soon as the alert opens
- Builder, reviewer, and PR-writer roles
- Editable role prompts and working directories
- A Slack-like sidebar with attention badges
- Automatic light and dark appearances that follow the system setting (macOS: live; Linux: read once at launch from `org.gnome.desktop.interface color-scheme`)
- Consistent, legible typography across conversations, settings, and bot creation
- Structured messages, commands, findings, and approval cards
- Optional Manager bots that coordinate a persistent Builder → Reviewer →
  conditional Builder fixes and Reviewer re-check → Documenter / PR Writer
  workflow
- Isolated managed Git worktrees for implementation bots, with structured
  handoff packages that carry branch, task, working-tree, and test context to
  the next bot
- Real Codex sessions powered by `codex app-server`, with workspace-scoped writes and in-app approvals for commands, file changes, extra permissions, and connected-app mutations
- Real, resumable Claude Code builder and PR-writer sessions with in-app tool approvals
- Local JSON persistence
- Persisted workflow handoffs and delivered dispatch payloads so an app restart
  can resume with the original plan, review findings, publishing context, and
  draft PR details intact

## Run the prototype (Linux)

Requires Swift 6.0+ and GTK4 development headers. On Kali/Debian:

```sh
sudo apt install swiftlang libgtk-4-dev
```

```sh
swift run
```

Run tests with `swift test`. `codex` and `claude` are located on `PATH` or in
their usual per-user install directories (`~/.local/bin`, `~/.npm-global/bin`);
see `Sources/Bl00p/Claude/ClaudeExecutableLocator.swift` and
`Sources/Bl00p/Codex/CodexExecutableLocator.swift`.

### Build an installable `.deb`

```sh
sh scripts/build-installable-deb.sh
```

The script writes `bl00p_<version>_<arch>.deb` to `.build/deb/`. Install it
with `sudo apt install ./.build/deb/bl00p_*.deb` (or `sudo dpkg -i` followed by
`sudo apt -f install` for dependency resolution). There is no signed
auto-update feed on Linux — `apt` owns installation, and bl00p's in-app
"Check for Updates" only points you at the latest GitHub release; see
`Sources/Bl00p/UpdateController.swift`.

Directory selection uses `zenity` if present, falling back to `kdialog`;
desktop notifications use `notify-send` (`libnotify-bin`). Both are optional —
bl00p degrades gracefully without them.

## Run the prototype (macOS)

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

### Build an installable release

Build, package, sign, and verify an optimized app bundle with:

```sh
sh scripts/build-installable-app.sh
```

The script writes `bl00p.app` and a bundle-preserving ZIP to
`.build/install/`. The app is ad-hoc signed for local installation: drag the
app into `/Applications`. GitHub releases use Developer ID signing and Apple
notarization before the stapled app is archived for distribution.

Release cadence, Sparkle signing, and GitHub Actions setup are documented in
[docs/RELEASING.md](docs/RELEASING.md). This applies to the macOS build only —
Sparkle is a macOS-only dependency and is not linked into the Linux build.

## Claude Code authentication

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
5. If the Reviewer requests changes (or its structured result is missing), the
   Builder addresses the findings and the Reviewer verifies the updated commit.
   A clean review skips both extra turns.
6. The Documenter updates documentation, commits, pushes, and opens a draft PR.
7. bl00p completes the workflow directly from the recorded branch, test
   evidence, Reviewer result, Documenter summary, and draft PR URL.

Before each Reviewer pass, bl00p requires a clean Builder worktree, the
appropriate committed revision, and passing test evidence. Revision passes
must include fresh passing test evidence recorded after the review began.
Saved workflows recover these handoff requirements across app restarts without
discarding an already-running Documenter session.

Questions, failures, and approval requests pause the workflow for the user.
The Manager's implementation plan approval is persisted with the workflow, so a
relaunch can restore a missing or interrupted approval card without dispatching
the Builder twice. Unrelated runtime permission approvals remain runtime
approvals, and declining the plan leaves the workflow paused for revision
feedback.
Leaving any team assignment unset keeps that Manager in standalone chat mode.
Clean workflows use four agent turns; workflows with one requested-changes
round use six, and workflows with two rounds use eight. If findings remain
after two revision rounds, bl00p pauses the loop for user direction instead of
continuing indefinitely. Reviewer protocol markers are kept out of the
user-visible findings and completion summary.

For an unattended managed workflow, configure its Claude Reviewer with **Auto**
approval mode. A Reviewer in **Ask** mode pauses when it first requests a shell
inspection such as `git diff`, so the workflow waits for a user decision. Auto
mode allows supported read-only repository inspection while preserving the
Reviewer boundary.

The Manager's implementation plan appears once, inside the approval card. The
card renders the plan as readable Markdown and provides the Approve and Decline
actions; the same plan is not repeated as a separate conversation message.

The persistence rules and restore invariants are documented in
[docs/MANAGED_WORKFLOWS.md](docs/MANAGED_WORKFLOWS.md).

If bl00p restarts while a team handoff is being delivered, the saved dispatch
is retried; if the dispatch was already recorded as delivered, the same saved
payload is used when you choose Resume instead of replacing it with a generic
stage prompt.

## Runtime boundary

`AgentRuntime` is intentionally provider-neutral. Codex profiles use the
desktop-bundled or plugin-bundled `codex app-server` runtime. Builder,
Reviewer, and Documenter threads use workspace-scoped execution and route
elevated and connected-app actions through bl00p's approval cards. Manager
threads are non-escalatable and read-only so bl00p alone owns delegation to
the configured team. Threads resume from their saved thread ID when possible.
Successful executable discovery and Claude authentication checks are cached
until a launch, turn, or transport failure invalidates them, so moved provider
executables and expired authentication can be detected again without
restarting bl00p. State writes are coalesced off the main actor, use
last-write-wins revisioning, and are flushed when the app quits (with a short
timeout so a slow write cannot block termination). Performance logs contain
stage durations plus provider, model, role, and cold/warm identifiers only;
prompts, generated content, and filesystem paths are never included.

Claude profiles use the installed `claude` executable's `stream-json` mode.
They inherit Claude's user and project settings, including configured MCP
servers. The current allowlist supports repository inspection, file edits for
Builder and Documenter roles, common test commands, and read-only Linear tools.
Manager actions are always blocked. Reviewers can inspect the repository, but
do not receive pre-approved shell access; built-in file-edit tools and
write-capable shell commands are blocked by the runtime policy. For other
actions, Ask pauses in the conversation so the user can approve or decline the
exact tool call. Auto immediately allows only supported, workspace-scoped
actions and records each decision in the transcript; destructive and
publishing commands, outside-workspace paths, and classified Reviewer writes
remain blocked. Unclassified non-shell tools return to the explicit approval
flow instead of being run automatically.

For Builder and Documenter / PR Writer profiles, build and test permissions
accept both bare and argument-bearing command forms for compatibility with
Claude CLI permission matching. The permission identity also recognizes
supported output filters in commands such as
`swift build 2>&1 | tail -20`, without allowing `tail` to read arbitrary
files. Completed or approved actions are removed from repeated permission
denials, so a retry is not reported as blocked after it has already run
successfully.

Reviewer shell access is intentionally read-only: commands such as
`swift test`, `npm run lint`, and other classified verification commands are
denied rather than offered for approval. Reviewers confirm the reported test
evidence instead. Manager profiles cannot run shell commands in any approval
mode; they coordinate the assigned team through the managed workflow.

For managed workflows, the plan approval is represented by a dedicated
approval entry that replaces the Manager's streamed plan entry at the same
timeline position. The replacement receives its own identifier so subsequent
runtime updates cannot overwrite the approval card. Planning output is scoped
to the current Manager turn, which prevents an older assistant message from
being mistaken for a new implementation plan.

## Roadmap

Planned product work and its acceptance criteria are tracked in
[FEATURES.md](FEATURES.md).
