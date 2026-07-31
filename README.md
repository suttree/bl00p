# bl00p

bl00p (“bot loop”) is a control room for running coding agents through an implementation, review, and publishing loop while keeping a human in control.

Linux support is built and tested on Kali using the maintained
[SwiftOpenUI fork](https://github.com/FesterCluck/SwiftOpenUI)'s GTK4 backend
in place of AppKit/SwiftUI. The macOS build path remains supported alongside
it; `Package.swift` and the `#if os(macOS)` branches in `Sources/Bl00p` select
the platform automatically.

The current prototype includes:

- Claude and Codex bot profiles
- Seeded Builder, Reviewer, and PR-writer prompts that append the shared easol
  working-guidelines block for new default and custom bots
- Sidebar bot renaming with the name field focused as soon as the alert opens
- Builder, reviewer, and PR-writer roles
- Editable role prompts per bot and per chat, with fallback to bot default, plus a repository selected independently for each chat
- Conversation-header shortcuts for opening the selected repository or active worktree in Finder and Terminal
- Position-labeled conversation tabs with Manager-view-only `⌘1`–`⌘9`
  switching on macOS
- Transcript scrolling that follows streaming replies while preserving deliberate history browsing
- A Slack-like sidebar whose spinner and attention badges follow the bot's
  current chat instead of stale or background chats
- Automatic light and dark appearances that follow the system setting (macOS: live; Linux: read once at launch from `org.gnome.desktop.interface color-scheme`)
- Consistent, legible typography across conversations, settings, and bot creation
- Structured messages, commands, findings, and approval cards
- Interactive structured question cards for Claude `AskUserQuestion` and Codex
  `requestUserInput`, including option descriptions, single-select and
  multi-select answers, and submitted or cancelled states
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
- Automatic macOS releases from every validated `main` merge, with signed
  Sparkle updates discovered hourly or immediately from **Check for Updates…**,
  plus an optional sidebar control to install and relaunch when an update is
  available

## Run the prototype (Linux)

Requires Swift 6.0+ and GTK4 development headers. On Kali/Debian:

```sh
sudo apt install swiftlang libgtk-4-dev
```

```sh
swift run
```

`codex` and `claude` are located on `PATH` or in their usual per-user install
directories (`~/.local/bin`, `~/.npm-global/bin`); see
`Sources/Bl00p/Claude/ClaudeExecutableLocator.swift` and
`Sources/Bl00p/Codex/CodexExecutableLocator.swift`.

**Known issue:** `swift test` currently fails to link on Kali
(`cannot find -l_Testing_Foundation`). Kali's `swiftlang` package (confirmed
via `dpkg -S`) ships `_Testing_Foundation`'s module interface but not its
compiled library, and Swift's cross-import mechanism auto-links it whenever a
file imports both `Testing` and `Foundation` — unavoidable for
`Tests/Bl00pTests/ModelTests.swift`. This is a toolchain packaging gap, not a
bl00p issue; `swift build` is unaffected. Work around it locally by disabling
the cross-import trigger:
`sudo mv /usr/libexec/swift/lib/swift/linux/Testing.swiftcrossimport/Foundation.swiftoverlay{,.disabled}`.

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
`.build/install/`. Both local and GitHub release builds are ad-hoc signed, so
no Apple Developer account is required. Drag the app into `/Applications`,
then approve its first launch through macOS: Control-click the app, choose
**Open**, then confirm **Open**. You can also try opening it normally and use
**Open Anyway** in **System Settings → Privacy & Security**.

Because the app is not Developer ID signed or notarized, macOS will not
identify its developer and the normal double-click first launch is blocked.
Sparkle update archives remain independently protected by Ed25519 signatures;
the release workflow verifies each signature against the public key embedded
in the archived app before publishing. Every reviewed merge to `main`
automatically becomes the latest stable release after tests, packaging, code
signature checks, and appcast verification pass, so incomplete work must not be
merged to `main`.

While bl00p is running, Sparkle looks for a newer build at least once per hour;
**Check for Updates…** starts an immediate check. When Sparkle finds an
authenticated update, an update icon appears at the bottom-left of the sidebar.
Choose it to install the update and relaunch bl00p; if the download is still
being prepared, bl00p waits and completes the request when Sparkle is ready.
Background checks never force an active session to restart, and downloaded
updates can still install when bl00p next quits.

Release cadence, Sparkle signing, and GitHub Actions setup are documented in
[docs/RELEASING.md](docs/RELEASING.md). This applies to the macOS build only —
Sparkle is a macOS-only dependency and is not linked into the Linux build.

### Conversation tabs

Conversation tabs are labeled by their current position rather than by a
generated chat title. On macOS, while the Manager is selected, the first nine
tabs show `⌘1` through `⌘9` and those shortcuts select the matching tab in the
active window, including while the composer has focus. Tabs after the ninth
show their ordinal without a shortcut. Adding or closing a tab immediately
reindexes the labels and shortcuts; the original chat title remains available
as hover and accessibility context.

The tab strip is shown only for the Manager. Selecting a Manager chat switches
the Builder, Reviewer, and Documenter / PR Writer to their corresponding
workflow conversations. Positional shortcuts are disabled while a workflow
participant or any other non-Manager profile is visible, and are restored when
the Manager is selected again.

### Transcript scrolling

Conversation transcripts open at the latest content and continue following a
streaming reply while the viewport is at or near the bottom. If you scroll into
history, new entries and streamed updates leave your position unchanged; use
**Jump to Latest** to return to the newest content and resume automatic
following. Sending a new message also returns the transcript to latest-content
following.

## Claude Code authentication

Claude Code must be installed and authenticated before launching a Claude
profile:

```sh
claude auth login
```

## Optional managed workflows

Every bot can still be used independently. To enable orchestration, add or edit
a bot with the **Manager** role, then assign one existing Builder, Reviewer, and
Documenter / PR Writer in its settings. Choose a repository in the Manager
chat's header before sending the request. The Manager's next request starts a
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

The Manager transcript presents each completed stage as a compact status card
instead of copying the participant's full response. Builder, revision, Reviewer,
and Documenter / PR Writer cards show the role outcome with a bounded summary
and any available branch, test, review, or publishing evidence. The final
**Draft PR created** card highlights the clickable pull-request link. Cards stay
useful when a participant provides no optional summary, and full responses
remain available in the corresponding participant conversation.

Sidebar notifications follow the action required: a successful managed stage
badges only the Manager, while a blocked, failed, approval, or question state
badges only the participant that needs attention. Standalone bot completions
continue to badge their own row. Completion notices for Builder, Reviewer, and
Publisher bots simply report that the agent finished its turn; Manager notices
invite the user to review the Manager's update in bl00p.

Before each Reviewer pass, bl00p requires a clean Builder worktree, the
appropriate committed revision, and passing test evidence. If a Builder turn
ends with blocked Claude actions but those handoff requirements are already
satisfied, the status is shown as **Blocked** and the workflow still advances
to the Reviewer automatically. If the handoff is not ready, the workflow pauses
with the missing requirement so the Builder can retry or finish the commit and
test evidence. For a normally completed but incomplete handoff, bl00p sends the
Builder a targeted repair request automatically, up to two times per build or
revision pass. The retry state is saved before the request is sent, so an app
restart cannot duplicate a repair or create an unbounded loop. After the limit,
the workflow pauses with the exact unmet requirement, latest test evidence, and
attempt count. Revision passes must include fresh passing test evidence recorded
after the review began. Test evidence comes from recognized command invocations
and their structured running/succeeded/failed outcomes; text from a read or
search result that merely mentions tests cannot satisfy the gate. A blocked
test command may advance as **Unverified**, while a blocked commit action still
requires approval. Saved workflows recover these handoff requirements across
app restarts without discarding an already-running Documenter session.

Repository selection belongs to the chat, not the bot profile. New chats start
without a repository, so two chats for the same bot can work in different
repositories. The composer stays locked until a repository is chosen from the
conversation header, then becomes available immediately. Once a chat has
started a runtime thread, created a worktree, or joined a managed workflow, its
repository is locked; create another chat to work elsewhere.

The same conversation header also exposes shortcuts into the selected checkout.
On macOS, the header is integrated into the unified window toolbar; on Linux it
remains inline above the conversation. The toolbar keeps the bot identity,
status, repository/worktree path, repository chooser, terminal, conditional
Stop, and settings controls together. Long paths truncate in the middle so the
toolbar remains usable at small window sizes. The folder button opens the
chat's current repository or worktree in the system file browser, and the
terminal button opens the same directory in a native terminal window. For
managed workflows this means the Builder, Reviewer, and Documenter can jump
directly into the active worktree without copying paths out of the UI.

When you close a chat that owns a managed Git worktree, bl00p's confirmation
explains the cleanup outcome. A worktree that can be removed safely is deleted
from disk, including a dirty worktree after you confirm the warning about its
uncommitted changes; its Git branch remains available for recovery. If bl00p
cannot safely remove the worktree, the chat can still be closed while the
worktree remains on disk, and the branch is retained.

When upgrading, existing chats retain their effective repository. bl00p
migrates the former profile-level repository only when the chat does not
already have repository information from its worktree or pending handoff.

Each workflow snapshots its Manager chat's repository and creates dedicated
Builder, Reviewer, and Documenter chats without changing those bots' selected
standalone chats. The Builder receives an isolated worktree based on that
repository, while the Reviewer and Documenter use the Builder's handed-off
worktree. This lets multiple Manager chats run concurrently against different
repositories with the same configured team.

Questions, failures, blocked Reviewer or Documenter actions, and approval
requests pause the workflow for the user. Builder blocked-action turns are
handoff-gated: ready handoffs continue automatically, while incomplete handoffs
pause with an actionable reason. The Manager's implementation plan approval is
persisted with the workflow, so a relaunch can restore a missing or interrupted
approval card without dispatching the Builder twice. Unrelated runtime
permission approvals remain runtime approvals, and declining the plan leaves
the workflow paused for revision feedback.
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

Provider questions are rendered separately from permission approvals. Claude
`AskUserQuestion` requests and Codex `requestUserInput` events appear as
question cards with the original headings and prompts, vertically stacked
options, and radio-style or checkbox-style selection. The Submit action becomes
available after every question has an answer; once submitted, the card shows
the selected labels and cannot be edited again. Cancelling a turn also marks a
pending question as cancelled. Ordinary command and file permission requests
continue to use their existing Approve and Decline controls.

The persistence rules and restore invariants are documented in
[docs/MANAGED_WORKFLOWS.md](docs/MANAGED_WORKFLOWS.md).

Fresh installs seed the built-in Builder, Reviewer, and Documenter / PR Writer
profiles from `BotProfile.defaults`, and each seeded prompt now appends
`BotProfile.easolWorkingGuidelines`. The Add Bot sheet starts its instructions
editor with that same shared guidelines block so custom bots begin from the
same house rules. Existing saved profiles are not migrated in place; they keep
their persisted instructions until edited manually or replaced.

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
