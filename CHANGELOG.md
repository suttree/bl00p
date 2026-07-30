# Changelog

All notable changes to bl00p are documented in this file.

## Unreleased

### Added

- Add positional conversation-tab labels and `⌘1`–`⌘9` shortcuts on macOS,
  available only in the Manager view, with shortcuts and labels reindexing as
  tabs are added or closed.
- Add repository selection to individual chats, including a **Choose
  Repository…** action in the conversation header for new chats.
- Add signed automatic update checks, installation, and relaunch through
  Sparkle and GitHub Releases.
- Add automatic light and dark appearances across every app surface.
- Add in-app approval cards for individual Claude tool calls, returning each
  approval or rejection to the active Claude session.
- Add a per-bot approval mode toggle for Claude and Codex bots. Claude Auto
  mode is limited to supported workspace-scoped actions and keeps destructive,
  publishing, and role boundaries enforced. Reviewers can inspect repositories
  without pre-approved shell access; built-in edits and write-capable shell
  commands remain blocked. Configure Claude Reviewers in Auto mode for
  unattended managed workflows; Ask mode pauses on the first shell inspection.
- Add model selection when creating or configuring Claude and Codex bots.
- Add image attachments through drag and drop, with previews in the composer and conversation timeline.
- Add macOS notifications and a Dock badge when a bot finishes, fails, asks a question, or needs approval.
- Add bot renaming from the sidebar.
- Add managed Manager workflows with an explicit user approval gate between
  planning and the Builder handoff.
- Add interactive structured question cards for Claude `AskUserQuestion` and
  Codex `requestUserInput`, with option descriptions, single-select and
  multi-select controls, and submitted or cancelled states.
- Add a Linux build backed by SwiftOpenUI and GTK4, including Debian
  packaging, desktop notifications, directory selection, and Linux CI.

### Changed

- Publish macOS updates with account-free ad-hoc code signing while retaining
  Sparkle Ed25519 archive verification; Apple Developer signing and
  notarization are now optional Gatekeeper usability hardening.
- Keep repository ownership with chat sessions instead of bot profiles. Chats
  lock their repository after launch, worktree creation, or workflow
  participation, while each managed workflow receives dedicated Builder,
  Reviewer, and Documenter / PR Writer chats so workflows can run concurrently.
- Speed up managed workflows by skipping unnecessary fix/re-check turns after
  a clean review, composing the completion entry locally, and moving state
  encoding and writes onto a coalescing persistence queue.
- Add workflow-stage, runtime-launch, turn, handoff, and persistence timing
  metrics without recording prompts, generated content, or filesystem paths.
- Suppress notification banners and sounds while a bl00p window is active,
  while preserving sidebar and Dock attention state.
- Increase the typography throughout the Add Bot sheet and its role-prompt editor for readability.
- Make Codex bots general-purpose agents instead of starting every conversation in review mode.
- Start or reconnect a stopped bot automatically when its next message is sent, while preserving its transcript.
- Keep bot profiles separate by applying each bot's model, prompt, and working directory to its own runtime session.
- Simplify bot creation and settings around provider, model, instructions, and working directory.
- Refresh the conversation, composer, sidebar, avatars, typography, and app icon.
- Present tool activity in compact, expandable cards and use clearer status text throughout the app.
- Increase the app build number from 2 to 6.
- Use hot pink avatars for Manager bots across the sidebar, conversation,
  settings, and bot-creation surfaces.
- Let Claude Managers run the test suite and read-only inspection commands to
  ground their plans, with the same Ask/Auto approval mode picker available to
  Reviewers. Managers remain unable to edit files, commit, push, or publish in
  either mode. Codex Managers are unchanged and stay in a read-only sandbox.

### Fixed

- Clarify the close-chat warning so managed worktree deletion, retained Git
  branches, uncommitted changes, and unsafe worktrees left on disk are each
  described accurately.
- Keep chat transcripts pinned to current streaming content without restoring
  stale entry anchors, while preserving deliberate history browsing behind a
  **Jump to Latest** control.
- Scope sidebar bot spinners and attention dots to the currently visible chat,
  so stale or background chats no longer light up an idle sidebar avatar.
- Disable the message composer for new chats until a repository is selected,
  while preserving editable drafts during running agent turns.
- Migrate saved profile-level repositories into their existing chats, preferring
  repository information from owned worktrees and pending handoffs, and restore
  workflow participants without cross-repository state changes.
- Focus the bot name field when the sidebar rename alert opens without
  replacing text entered during presentation.
- Hand the Builder the exact implementation plan approved by the user, while
  preserving the original request as separate context and pausing on an
  inconsistent or missing plan.
- Bound managed review revisions to two rounds, then pause with the remaining
  findings for user direction instead of looping indefinitely.
- Preserve multi-entry reviewer findings while parsing the structured review
  disposition, and remove the internal disposition marker from user-visible
  handoffs and completion summaries.
- Invalidate cached Claude authentication and provider executable discovery
  after runtime failures; reset cold-start tracking when a runtime stops.
- Restore managed workflow stage timing from persisted timestamps, complete
  legacy reporting workflows that already have a draft PR URL, validate the
  publisher before entering the publishing stage, and allow quit to continue
  after a three-second persistence-flush deadline.
- Preserve resumable Documenter sessions across restart, restore revision
  validation for older saved workflows, and avoid treating generic tool output
  as test evidence.
- Show each managed implementation plan only once in its approval card,
  preserving Markdown formatting and preventing later runtime updates from
  replacing the approval state.
- Keep the selected provider when adding a bot, including after switching between Claude and Codex.
- Focus the message composer when the app opens or the user switches bots.
- Keep loading saved profiles and sessions when a bot profile gains new fields, instead of silently discarding all persisted state on decode failure.
- Recover from stale Claude conversation identifiers by continuing in a fresh session without discarding the local transcript.
- Keep Codex lifecycle events connected so idle disconnects are reported correctly.
- Let failed chat messages retry in place with their original text and attachments
  without marking completed messages as failed after idle disconnects.
- Show blocked Claude actions as a readable question that the user can respond to.
- Keep provider question requests separate from permission approvals, preserve
  Claude's original question payload when returning answers, and cancel
  unanswered question cards when their runtime turn ends.
- Prevent duplicate sends while a bot is launching or working.
- Migrate legacy bot names, starter cards, permission messages, and Codex review sessions when restoring saved state.
- Stage Claude image attachments in an isolated temporary directory and remove them after each turn.
- Keep Manager sessions non-delegating and write-blocked, reserve team
  dispatch for bl00p's visible managed workflow, and confine Manager tool use
  to planning-time test and inspection commands.
- Keep Claude permission matching compatible with exact and argument-bearing
  command forms, including common build/test pipelines such as
  `swift build 2>&1 | tail -20`, while keeping the `tail` filter allowlist
  narrow.
- Deduplicate Claude permission denials against actions that already completed
  or received approval, so successful retries do not remain blocked by stale
  denial reports.
- Restore interrupted Manager plan approvals from valid saved evidence without
  turning unrelated runtime permission approvals into plan approvals or
  dispatching a Builder twice.
- Keep Claude Reviewers read-only by denying built-in edits, write-capable shell
  commands, and test-running commands in every approval mode.
- Quarantine unreadable saved state instead of letting the next autosave
  overwrite it with defaults, and rotate a `state.json.bak` backup on every
  save so one bad write can't destroy the only copy of prior state.
- Preserve managed workflow dispatch payloads through runtime delivery and
  restart recovery, including implementation plans, review findings, and
  publishing and reporting details.
- Make the Builder to Reviewer/QA handoff robust to blocked turns: a single
  shared readiness gate, symmetric between the initial build and the revision
  pass, now advances a blocked-but-committed Builder handoff with unverified
  test evidence to the Reviewer carrying a visible caveat instead of pausing,
  but only when the recorded denial actually matches a known test command —
  an unrelated blocked action (e.g. `rm -rf build`) still hard-blocks an
  untested pass on either side. Names the specific blocked action (e.g. a
  denied `git commit`) in the pause reason when the handoff genuinely isn't
  ready and that denial plausibly explains the failure, without
  misattributing an unrelated denial as the cause; scoped to denials recorded
  since the current turn started so a stale denial from an earlier, already-
  resolved turn can't be reused; and automatically re-runs the gate and
  advances the workflow the next time the Builder reaches a terminal status,
  instead of leaving a not-ready pause as a dead end.

### Tests

- Stabilize Claude unmatched-command approval-flow coverage with an injected
  client stub, while retaining subprocess coverage for the CLI permission
  transport.
- Cover sidebar indicator scoping for standalone chats and selected Manager
  workflows.
- Cover bounded review revisions, multi-block review output, protocol-marker
  stripping, restored workflows, cache invalidation, cold-start tracking, and
  coalesced persistence without timing-based assertions.
- Cover active-window notification suppression independently from Dock badge
  updates.
- Expand coverage for notifications, Dock badges, model and prompt isolation, image attachments, session recovery, state migration, composer sizing, automatic reconnects, and long-lived runtime streams.
- Cover the Claude and Codex approval mode toggles, scoped automatic Claude
  decisions, read-only role boundaries, and backward-compatible decoding of
  bot profiles missing newer fields.
- Cover Manager plan approval, visible team dispatch, restart persistence,
  delivered dispatch payload recovery, read-only Codex configuration, and
  role-specific avatar colors.
- Cover the approved-plan Builder handoff, including revised plans and missing
  or inconsistent plan safeguards.
- Run the application and model test suite on Ubuntu in CI alongside macOS.
- Cover idempotent plan-approval restoration, stale or duplicate approval-card
  cleanup, and relaunch behavior for unrelated runtime approvals.
- Cover structured Claude and Codex questions, response encoding, multiple and
  multi-select answers, cancellation, persistence round-trips, and unchanged
  approval flows.
- Cover the Builder handoff readiness gate advancing a blocked turn with
  unverified tests under a caveat, rejecting the caveat when the blocked
  action is unrelated to running tests, ignoring a stale blocked-action entry
  from an earlier turn rather than misusing it for a later turn's caveat or
  diagnosis, still pausing on genuinely failing tests, naming a blocked
  action in the pause reason only when it explains the specific failure, and
  self-healing a paused handoff once the Builder next reaches a terminal
  status.
