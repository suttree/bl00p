# bl00p

bl00p (“bot loop”) is a native macOS control room for running coding agents through an implementation, review, and publishing loop while keeping a human in control.

The current prototype includes:

- Claude and Codex bot profiles
- Builder, reviewer, and PR-writer roles
- Editable role prompts and working directories
- A Slack-like sidebar with attention badges
- Consistent, legible typography across conversations, settings, and bot creation
- Structured messages, commands, findings, and approval cards
- A real, read-only Codex reviewer powered by `codex app-server`, with a per-bot toggle to auto-approve its commands and file changes instead of asking
- Real, resumable Claude Code builder and PR-writer sessions
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

`AgentRuntime` is intentionally provider-neutral. Codex profiles use the desktop-bundled or plugin-bundled `codex app-server` runtime. Reviewer threads start with a read-only sandbox, user-routed approvals, and resume from their saved thread ID when possible.

Claude profiles use the installed `claude` executable's `stream-json` mode.
They inherit Claude's user and project settings, including configured MCP
servers. The current allowlist supports repository inspection, file edits for
non-reviewer roles, common test commands, and read-only Linear tools. Commit,
push, PR mutation, destructive git, and delete operations remain blocked.

The next integration slices are:

- An in-app approval bridge for individual Claude tool calls
- Git worktree ownership and handoff packages
