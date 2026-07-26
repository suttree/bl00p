# Planned Features

This file is the source of truth for planned product work. The README describes
what the current prototype already supports.

## Now

- Suppress agent notifications while bl00p is active.
  - Acceptance: status transitions still update sidebar and Dock attention
    state, but bl00p does not display a banner or play a sound while its window
    is active.

## Next

- Add an in-app approval bridge for individual Claude tool calls.
  - Acceptance: Claude actions that need permission pause visibly in the
    conversation, and the user's approval or rejection is returned to the
    running session.
- Add Git worktree ownership and handoff packages.
  - Acceptance: implementation bots can work in isolated worktrees and hand
    off their branch, task context, and test state without overlapping edits.

## Later

- Support the system light and dark appearances throughout the app.
  - Acceptance: every view follows the current macOS appearance with legible
    text, controls, status indicators, and message cards in both modes.
