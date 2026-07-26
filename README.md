# bl00p

bl00p (“bot loop”) is a native macOS control room for running coding agents through an implementation, review, and publishing loop while keeping a human in control.

The current prototype includes:

- Claude and Codex bot profiles
- Builder, reviewer, and PR-writer roles
- Editable role prompts and working directories
- A Slack-like sidebar with attention badges
- Consistent, legible typography across conversations, settings, and bot creation
- Structured messages, commands, findings, and approval cards
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

Claude Code must be installed and authenticated before launching a Claude
profile:

```sh
claude auth login
```

## Runtime boundary

`AgentRuntime` is intentionally provider-neutral. Codex profiles use the desktop-bundled or plugin-bundled `codex app-server` runtime. Threads can write within their selected workspace, route elevated and connected-app actions through bl00p's approval cards, and resume from their saved thread ID when possible.

Claude profiles use the installed `claude` executable's `stream-json` mode.
They inherit Claude's user and project settings, including configured MCP
servers. The current allowlist supports repository inspection, file edits for
non-reviewer roles, common test commands, and read-only Linear tools. Actions
outside that allowlist pause in the conversation, where the user can approve
or decline the exact tool call before Claude continues.

## Roadmap

Planned product work and its acceptance criteria are tracked in
[FEATURES.md](FEATURES.md).
