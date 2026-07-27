# Changelog

All notable changes to bl00p are documented in this file.

## Unreleased

### Added

- Add signed automatic update checks, installation, and relaunch through
  Sparkle and GitHub Releases.
- Add automatic light and dark appearances across every app surface.
- Add in-app approval cards for individual Claude tool calls, returning each
  approval or rejection to the active Claude session.
- Add a per-bot approval mode toggle for Claude and Codex bots. Claude Auto
  mode is limited to supported workspace-scoped actions and keeps destructive,
  publishing, and read-only role boundaries enforced. Reviewers can inspect
  repositories without automatic write access, while unclassified actions
  return to explicit approval.
- Add model selection when creating or configuring Claude and Codex bots.
- Add image attachments through drag and drop, with previews in the composer and conversation timeline.
- Add macOS notifications and a Dock badge when a bot finishes, fails, asks a question, or needs approval.
- Add bot renaming from the sidebar.
- Add managed Manager workflows with an explicit user approval gate between
  planning and the Builder handoff.

### Changed

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

### Fixed

- Keep the selected provider when adding a bot, including after switching between Claude and Codex.
- Focus the message composer when the app opens or the user switches bots.
- Keep loading saved profiles and sessions when a bot profile gains new fields, instead of silently discarding all persisted state on decode failure.
- Recover from stale Claude conversation identifiers by continuing in a fresh session without discarding the local transcript.
- Keep Codex lifecycle events connected so idle disconnects are reported correctly.
- Let failed chat messages retry in place with their original text and attachments
  without marking completed messages as failed after idle disconnects.
- Show blocked Claude actions as a readable question that the user can respond to.
- Prevent duplicate sends while a bot is launching or working.
- Migrate legacy bot names, starter cards, permission messages, and Codex review sessions when restoring saved state.
- Stage Claude image attachments in an isolated temporary directory and remove them after each turn.
- Keep Manager sessions plan-only and read-only, prevent hidden delegation,
  and reserve team dispatch for bl00p's visible managed workflow.

### Tests

- Cover active-window notification suppression independently from Dock badge
  updates.
- Expand coverage for notifications, Dock badges, model and prompt isolation, image attachments, session recovery, state migration, composer sizing, automatic reconnects, and long-lived runtime streams.
- Cover the Claude and Codex approval mode toggles, scoped automatic Claude
  decisions, read-only role boundaries, and backward-compatible decoding of
  bot profiles missing newer fields.
- Cover Manager plan approval, visible team dispatch, restart persistence,
  read-only Codex configuration, and role-specific avatar colors.
