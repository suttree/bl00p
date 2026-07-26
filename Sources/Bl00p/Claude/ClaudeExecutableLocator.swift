import Foundation

struct ClaudeExecutableLocator: Sendable {
    private let candidateURLs: [URL]?

    init(candidateURLs: [URL]? = nil) {
        self.candidateURLs = candidateURLs
    }

    func locate() -> URL? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path
        var candidates = candidateURLs ?? [
            URL(fileURLWithPath: "\(home)/.local/bin/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude")
        ]

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
