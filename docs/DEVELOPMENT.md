# Development notes

## Positional conversation tabs

`ConversationTabBar` renders tabs from the session order supplied by
`AppModel`. The visible label is positional: positions one through nine use
`⌘1` through `⌘9`, while later positions show only their ordinal. Session
titles remain persisted and are used for hover and accessibility context; they
must not be used as the visible tab label.

The macOS commands in `Platform/MacEntry.swift` must derive their positions
from the currently visible tab strip and call `selectTab(at:viewing:)`. That
operation resolves the ordered sessions through `tabSessions(for:)` before
delegating to the existing tab-selection path, which preserves Manager-owned
tabs when a workflow participant is visible. The tab strip itself is rendered
only for the Manager; participant views resolve their conversation from the
Manager's selected tab. Adding or closing a tab must recompute both labels and
shortcut availability from the current order.

Model coverage should include available and unavailable positions,
reindexing after tab changes, and Manager-scoped selection while viewing a
workflow participant. Managed-workflow coverage should also verify that
selecting a Manager tab updates every participant conversation. A focused
macOS verification run is:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swiftpm-module-cache" \
XDG_CACHE_HOME="$PWD/.build/cache" \
xcrun swift test --disable-sandbox \
  --filter positionalTabSelectionTracksCurrentSessionOrder
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

## Per-chat prompt overrides

A chat session can override its bot's default `instructions` by setting
`AgentSessionState.instructionsOverride`. When present and non-blank, the
override is sent to the runtime; otherwise, the bot's default is used. This
allows two chats of the same bot to run with different prompts without
detaching them from future bot-default edits.

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
