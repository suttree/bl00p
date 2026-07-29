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
tabs when a workflow participant is visible. Adding or closing a tab must
recompute both labels and shortcut availability from the current order.

Model coverage should include available and unavailable positions,
reindexing after tab changes, and Manager-scoped selection while viewing a
workflow participant. A focused macOS verification run is:

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
