import Foundation

struct CodexExecutableLocator: Sendable {
    private let candidateURLs: [URL]?

    init(candidateURLs: [URL]? = nil) {
        self.candidateURLs = candidateURLs
    }

    func locate() -> URL? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path
        let candidates = candidateURLs ?? [
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
            URL(fileURLWithPath: "\(home)/.codex/plugins/.plugin-appserver/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex")
        ]

        return candidates
            .first {
                fileManager.isExecutableFile(atPath: $0.path)
                    && isUsable($0, fileManager: fileManager)
            }
    }

    private func isUsable(_ url: URL, fileManager: FileManager) -> Bool {
        // The app-bundled binaries are self-contained. The old Homebrew Node
        // launcher can remain executable even when its optional native package
        // is missing, so prefer self-contained binaries whenever possible.
        if url.path.hasSuffix(".app/Contents/Resources/codex")
            || url.path.contains("/.codex/plugins/.plugin-appserver/") {
            return true
        }

        return url.path != "/opt/homebrew/bin/codex"
            || fileManager.fileExists(
                atPath: "/opt/homebrew/lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/codex/codex"
            )
    }
}
