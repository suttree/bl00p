import Foundation

enum ClaudeAuthenticationStatus: Sendable {
    case loggedIn
    case loggedOut
    case unavailable(String)
}

actor ProviderPreflightCache {
    private var executableURL: URL?
    private var authenticatedExecutables: Set<URL> = []

    func executable(
        using probe: @Sendable () -> URL?
    ) -> URL? {
        if let executableURL {
            return executableURL
        }
        let located = probe()
        if let located {
            executableURL = located
        }
        return located
    }

    func claudeAuthentication(
        for executableURL: URL,
        using probe: @Sendable (URL) -> ClaudeAuthenticationStatus
    ) -> ClaudeAuthenticationStatus {
        if authenticatedExecutables.contains(executableURL) {
            return .loggedIn
        }
        let status = probe(executableURL)
        if case .loggedIn = status {
            authenticatedExecutables.insert(executableURL)
        }
        return status
    }

    func invalidateClaudeAuthentication(for executableURL: URL) {
        authenticatedExecutables.remove(executableURL)
    }

    func invalidateExecutable(_ staleURL: URL) {
        guard executableURL == staleURL else { return }
        executableURL = nil
        authenticatedExecutables.remove(staleURL)
    }
}
