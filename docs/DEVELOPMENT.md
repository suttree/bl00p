# Development notes

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
