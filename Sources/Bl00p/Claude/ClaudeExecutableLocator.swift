import Foundation

struct ClaudeExecutableLocator: Sendable {
    private let candidateURLs: [URL]?

    init(candidateURLs: [URL]? = nil) {
        self.candidateURLs = candidateURLs
    }

    func locate() -> URL? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path

        #if os(macOS)
        var candidates = candidateURLs ?? [
            URL(fileURLWithPath: "\(home)/.local/bin/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude")
        ]
        #else
        // The npm global prefix and pipx/uv shims are the usual install sites
        // on a Debian-derived system; Homebrew paths are dropped.
        var candidates = candidateURLs ?? [
            URL(fileURLWithPath: "\(home)/.local/bin/claude"),
            URL(fileURLWithPath: "\(home)/.npm-global/bin/claude"),
            URL(fileURLWithPath: "\(home)/node_modules/.bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
            URL(fileURLWithPath: "/usr/bin/claude")
        ]
        #endif

        if candidateURLs == nil,
            let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(
                contentsOf: path
                    .split(separator: ":")
                    .map {
                        URL(fileURLWithPath: "\($0)/claude")
                    }
            )
        }

        return candidates
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}
