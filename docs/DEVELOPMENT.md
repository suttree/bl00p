# Development notes

## Transcript scrolling

`TranscriptView` uses one `TranscriptScrollCoordinator` per visible
conversation. The coordinator owns the session identity, latest-content
following state, near-bottom tolerance, and one coalesced scroll request. The
view scrolls only to its session-specific bottom sentinel; it must not retain a
per-entry scroll-position binding alongside imperative `scrollTo` calls.
The `ScrollViewReader` subtree also has session-specific identity so SwiftUI
recreates the native scroll container rather than carrying an outgoing chat's
offset or lazy-layout state into the incoming chat.

Content changes include both a new timeline entry and in-place mutation of the
final entry, which is required for streamed assistant text. While following,
the coordinator schedules one deferred scroll so streaming, card updates,
multiline growth, and layout changes do not create competing animation queues.
When a user deliberately moves beyond the 80-point near-bottom tolerance,
following is suspended and **Jump to Latest** is shown. Explicitly jumping to
latest, sending a message, or returning within the tolerance resumes following.
Changing sessions resets the coordinator and invalidates pending requests so a
previous chat cannot affect the new chat. The reset deliberately does not
schedule its initial scroll until the replacement transcript reports that it
has mounted. Viewport reports and scroll completions include their session
identity and are ignored after that session is no longer current.

macOS observes scroll geometry through `TranscriptScrollObserver`. Linux and
SwiftOpenUI do not expose equivalent geometry, so the transcript uses a
completed drag beyond the same tolerance as its history-browsing signal. Keep
that fallback threshold aligned with `TranscriptScrollCoordinator.nearBottomTolerance`.

The UI-independent state machine has focused coverage for initial positioning,
appends, streamed mutations, layout growth, near-bottom behavior, history
browsing, explicit return to latest, message sends, small Linux drag gestures,
session resets, rapid switching, and stale lifecycle callbacks. Run the focused
tests with:

```sh
swift test --disable-sandbox --filter TranscriptScrollCoordinatorTests
```

On macOS, use the repository's Xcode environment variables shown in the test
commands below. On Linux, run the equivalent command without
`--disable-sandbox`; the Linux toolchain's known `_Testing_Foundation` linking
issue is documented in the README.

## Positional conversation tabs

`ConversationTabBar` renders tabs from the session order supplied by
`AppModel`. The visible label is positional: positions one through nine use
`⌘1` through `⌘9`, while later positions show only their ordinal. Session
titles remain persisted and are used for hover and accessibility context; they
must not be used as the visible tab label.

The macOS commands in `Platform/MacEntry.swift` must derive their positions
from the currently visible tab strip and use
`canSelectTab(at:viewing:)` for command availability.
`selectTab(at:viewing:)` repeats that guard before changing selection so stale
command state cannot act after the selected profile changes. The shared check
requires an existing Manager profile and a position in its current tab order;
all positions are unavailable for workflow participants and other non-Manager
profiles. The tab strip itself is rendered only for the Manager; participant
views continue to resolve their conversation from the Manager's selected tab.
Adding or closing a tab must recompute both labels and shortcut availability
from the current order.

Model coverage should include available and unavailable positions,
reindexing after tab changes, refusal without selection changes while viewing
workflow participants and standalone non-Managers, and restored availability
after returning to the Manager. Managed-workflow coverage should also verify
that selecting a Manager tab updates every participant conversation. A focused
macOS verification run is:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swiftpm-module-cache" \
XDG_CACHE_HOME="$PWD/.build/cache" \
xcrun swift test --disable-sandbox \
  --filter positionalTabSelection
```

## Sidebar rename focus

The sidebar rename action uses a native alert. Its name input is backed by a
small `NSViewRepresentable` bridge in `SidebarView.swift` rather than a global
window search or a fixed presentation delay.

The AppKit control observes its alert window becoming key and focuses itself
only when it is not already editing. After focus is transferred, the caret is
placed at the end of the current value so text entered while the alert was
presenting is preserved. Keep this behavior in sync with the user-facing
description in the README and changelog.

The model test suite does not drive AppKit alerts. When changing this flow,
run the full test suite and manually verify that choosing **Rename…** from a
sidebar context menu opens the alert with the existing name ready to edit.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swiftpm-module-cache" \
XDG_CACHE_HOME="$PWD/.build/cache" \
xcrun swift test --disable-sandbox
```

## Sidebar indicators

`BotRow` receives an explicit `SidebarIndicatorState` from
`AppModel.sidebarIndicatorState(for:)`. Keep that state scoped to the
conversation currently visible for the row. Standalone bots derive completion,
attention, and running state from their selected chat. Managed participants
show only their own running or actionable state; their successful completion
is routed to the selected workflow's Manager unread state. The Manager spinner
can reflect active participants, but its badge comes only from its own
attention or unread workflow updates.

When a managed participant becomes blocked, fails, asks a question, or requires
approval, clear any stale Manager completion unread and badge only that
participant. A completed participant session must not also retain its own
completion unread. This keeps the Dock count at one for a single routed event.
Viewing the Manager chat clears its unread state through the normal
`markSessionViewed` path.

Model coverage should verify standalone background chats, selected-chat
switching, Manager workflow scoping, attention routing, and single-count Dock
badges. A focused verification run is:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swiftpm-module-cache" \
XDG_CACHE_HOME="$PWD/.build/cache" \
xcrun swift test --disable-sandbox \
  --filter sidebarIndicator
```

## Managed workflow update cards

Manager-only stage summaries are stored in `TimelineEntry.workflowUpdate`.
The optional payload is backward-compatible with entries persisted before the
field existed and carries the role, outcome, headline, bounded summary, and
structured branch, test, review, and pull-request data. Builder, revision,
Reviewer, and Documenter / PR Writer completions each append one card; the
publishing card includes the draft PR URL when one is available. Missing
optional summaries must not produce placeholder text. `TimelineEntryView` uses
the payload to render a normal-sized success or attention card; the full
participant transcript remains in its private workflow chat.

Use `WorkflowUpdateSummarizer` only on final assistant response text. It
deterministically removes protocol markers, fenced code, labelled command
output, and repeated paragraphs before enforcing the length bound, adding an
ellipsis when content is omitted. Do not feed streamed reasoning or command
timeline entries into the summary. Keep the payload's optional fields optional
so sessions saved before workflow cards were introduced continue decoding.

## macOS update affordance

`UpdateController` is the single Sparkle delegate owned by `Bl00pApp`. It
publishes the availability of a validated update and whether the user has
requested installation. `SidebarView` observes that controller and renders
the optional bottom-left update button only while an update is available.

The button may be activated before Sparkle supplies its immediate-install
handler; the controller retains that request and invokes the handler once it
arrives. Installation clears the affordance before calling Sparkle so repeated
clicks cannot trigger multiple installations. Sparkle's normal termination
path remains responsible for flushing persisted state before relaunch.

Keep the macOS controller and sidebar wiring behind `#if os(macOS)` so Linux
continues to use its package-manager handoff. State-transition coverage can be
run without starting Sparkle with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swiftpm-module-cache" \
XDG_CACHE_HOME="$PWD/.build/cache" \
xcrun swift test --disable-sandbox --filter UpdateControllerTests
```

Manual macOS checks should use an older packaged build and a newer signed
appcast: verify the icon's bottom-left placement and accessibility text,
activate it while preparation is in progress and when ready, and confirm that
the app relaunches with persisted data intact. Background discovery must not
restart an active session without the user's action.

## Structured user questions

Claude `AskUserQuestion` control requests and Codex
`item/tool/requestUserInput` events use the same question model and UI flow.
`StructuredQuestion` preserves each question's identifier, optional heading,
prompt, option labels and descriptions, and `multiSelect` flag. A
`TimelineEntry` stores the questions and a `QuestionResolution`, so submitted
and cancelled cards remain readable in the persisted transcript. The optional
fields keep older saved sessions decodable.

The provider runtimes retain the original request while the card is pending and
emit `.needsAnswer`, rather than treating a question as a permission approval.
The shared `resolveQuestion` path validates that every question has an answer,
prevents duplicate resolution, and emits a terminal submitted or cancelled
state. Claude responses must preserve the original `questions` payload and add
an `answers` object keyed by the exact question text; Codex responses map each
selection back to its request question identifier. Pending question state is
cleared when a turn is cancelled, completed, disconnected, or fails.

`ConversationView` renders option descriptions in vertically stacked rows. Use
radio-style rows for single-select questions and checkbox-style rows for
multi-select questions. Keep question cards distinct from ordinary approval
cards: permission requests still render their existing Approve and Decline
actions, while question cards never expose raw provider JSON.

When changing this flow, update the model/runtime tests for the provider
payload, response encoding, multiple questions, multi-select answers,
cancellation, persistence, and unchanged approval behavior. Manual checks
should also cover selecting and submitting a fixture-backed question, resumed
provider execution, a resolved card that cannot be edited twice, and readable
option wrapping at a narrow conversation width.

## Claude approval-flow test doubles

The model test `unmatchedClaudeCommandReachesTheApprovalCardFlow` uses the
injected `ApprovalStubClaudeClient` to exercise the complete approval-card
round trip deterministically. The stub captures the runtime invocation
arguments and can emit permission denials, so the test covers the pending
`uname -a` approval, approved resolution, denial reconciliation, and completed
turn without depending on Python, a temporary executable, or process timing.

Keep `claudeCLIClientCompletesThePermissionRoundTrip` as the separate
subprocess-level transport test. When changing Claude permission arguments or
approval reconciliation, run the focused flow test and the transport test
independently:

```sh
swift test --disable-sandbox \
  --filter unmatchedClaudeCommandReachesTheApprovalCardFlow
swift test --disable-sandbox \
  --filter claudeCLIClientCompletesThePermissionRoundTrip
```

The approval-flow test should continue to assert `--permission-mode default`,
structured permission transport, and the narrow Builder shell-command
allowlist. Keep those assertions in the stub-backed test; they validate the
runtime wiring without turning the model test into another process-level
transport test.

## Per-chat prompt overrides

A chat session can override its bot's default `instructions` by setting
`AgentSessionState.instructionsOverride`. When present and non-blank, the
override is sent to the runtime; otherwise, the bot's default is used. This
allows two chats of the same bot to run with different prompts without
detaching them from future bot-default edits.

The built-in Builder, Reviewer, and Documenter / PR Writer prompts are seeded
from `BotProfile.defaults`. Those defaults keep their role-specific prose and
append the shared `BotProfile.easolWorkingGuidelines` block, which also
prefills `NewBotDraft.instructions` on the Add Bot sheet. Keep that guidelines
text centralized in `BotProfile` so prompt updates stay consistent across
seeded profiles, new custom bots, and the associated tests.

This remains seed-time behavior only. `AppModel` uses `BotProfile.defaults`
when bootstrapping a fresh state store, but existing persisted profiles are not
retroactively rewritten when the default prompt text changes. Document any
future migration separately if prompt updates must backfill saved installs.

The resolution logic lives in a pure, testable helper:
`AgentSessionState.effectiveInstructions(profile:session:)`. It returns the
override (trimmed and non-blank) when present, otherwise the profile default.
Blank overrides are normalized to `nil` so the UI and runtime never disagree
about whether an override is in use.

The runtime wiring is one-off: `AppModel.runtimeProfile(for:sessionID:)` sets
`runtimeProfile.instructions` after resolving the effective prompt. This single
seam feeds both Claude (via `ClaudeInvocation.systemPrompt`) and Codex (via
`CodexAppServerRuntime.parameters`), and covers standalone chats, manager
workflow dispatches, and all provider delegation paths.

UI binding in `ProfileInspectorView` distinguishes bot-level and chat-level
editing with a segmented picker (when a chat is selected). The editor reads the
effective prompt as starting text; edits write to whichever scope is being
edited (the override when in chat mode, the profile default when in bot mode).
A "Reset to bot default" button clears the override. The persisted
`instructionsOverride` field is optional, so legacy chats without it decode
correctly and inherit the bot default.

Model coverage should verify: effective-prompt resolution with and without
overrides, blank-override normalization to `nil`, Codable round-trip and
backward-compatibility (legacy payloads lacking the field), and runtime
wiring for both providers. UI coverage should test segmented picker scope
switching, editor read/write behavior, reset action, persistence across
relaunch, and manager-workflow override propagation.

Claude approval-mode behavior is role-sensitive and should stay aligned across
runtime policy, prompt copy, and UI copy. Builders and Publishers can use the
workspace-scoped auto-approval path for supported actions. Reviewers stay
inspection-only in both Ask and Auto modes: they may inspect repositories but
cannot run test commands or edit through built-in tools. Managers sit between
those tiers during managed-workflow planning: they may run supported test and
inspection commands to ground an implementation plan, but built-in file edits,
write-capable shell commands, commits, push, and publishing remain blocked in
every mode. `ClaudeToolApprovalPolicy.allowedTools(for:)` should continue to
omit preapproved shell access for Reviewers and Managers so shell requests
still flow through the runtime policy.

## Repository-gated composer

`AgentSessionState.repositoryPath` is the UI source of truth for whether a chat
can accept a new message. `ConversationView` passes that state to
`ComposerView` separately from the existing send-readiness flag because agent
status still disables sending while intentionally leaving the draft editor
typeable.

Keep that separation intact. A missing repository must disable the text editor,
send button, and command-return submission, and the composer footer should
direct users to choose a repository. Once a repository is set, the editor should
remain editable during launching or working states while the send button
continues to follow the normal status, plan-approval, and structured-answer
gates.

The conversation header uses the same session state to expose best-effort local
navigation actions. The folder button continues to follow the repository lock
rules, while the terminal button should resolve its target through
`WorktreeTerminalLauncher.terminalTargetPath(worktreePath:repositoryPath:)` so
every chat opens its owned worktree when present and otherwise falls back to the
base repository. Keep the path-resolution logic pure and covered by focused
tests; the platform-specific process launch remains intentionally untested and
is verified by a manual smoke check.
