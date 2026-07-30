import Foundation

/// Opens a session's worktree (or repository) directory in a native terminal
/// window.
///
/// Mirrors `DirectoryChooser`'s per-platform shell-out pattern: macOS uses
/// `open -a Terminal`, Linux probes desktop terminals in turn since there is
/// no single cross-desktop launch command.
enum WorktreeTerminalLauncher {
    /// Resolves the directory a terminal should open at: the worktree when
    /// one exists, else the repository path, else `nil` when no repository
    /// has been chosen yet.
    static func terminalTargetPath(
        worktreePath: String?,
        repositoryPath: String
    ) -> String? {
        if let worktreePath, !worktreePath.isEmpty {
            return worktreePath
        }
        return repositoryPath.isEmpty ? nil : repositoryPath
    }

    static func open(_ directory: String) {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", directory]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        #else
        let candidates: [(String, [String])] = [
            ("gnome-terminal", ["--working-directory=\(directory)"]),
            ("konsole", ["--workdir", directory]),
            ("xterm", [])
        ]

        for (executable, arguments) in candidates {
            if run(executable, arguments, workingDirectory: directory) {
                return
            }
        }
        #endif
    }

    #if !os(macOS)
    /// Resolves `name` against `PATH` rather than shelling out through
    /// `/usr/bin/env`: terminals like `xterm` stay in the foreground rather
    /// than forking, so this cannot wait on an exit code to detect "not
    /// installed" the way `DirectoryChooser` does for its short-lived
    /// dialogs. Resolving first lets `Process.run()` fail synchronously and
    /// non-blockingly when the executable is absent.
    private static func resolveExecutable(_ name: String) -> URL? {
        guard let pathVariable = ProcessInfo.processInfo.environment["PATH"]
        else { return nil }

        for directory in pathVariable.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory))
                .appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Returns `true` once the process has been launched; `false` when the
    /// executable is not on `PATH` or fails to spawn, so the caller falls
    /// through to the next candidate.
    private static func run(
        _ executable: String,
        _ arguments: [String],
        workingDirectory: String
    ) -> Bool {
        guard let executableURL = resolveExecutable(executable) else { return false }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        return (try? process.run()) != nil
    }
    #endif
}
