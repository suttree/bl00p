import Foundation

#if os(macOS)
import AppKit
#endif

/// Presents a native folder picker.
///
/// SwiftOpenUI has no file-dialog abstraction, so the Linux path shells out to
/// the desktop's own chooser. `zenity` (GTK) is tried first to match the GTK4
/// window, then `kdialog` for Plasma sessions.
enum DirectoryChooser {
    @MainActor
    static func chooseDirectory(
        title: String,
        message: String
    ) -> String? {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK else { return nil }
        return panel.url?.path
        #else
        let candidates: [(String, [String])] = [
            (
                "zenity",
                [
                    "--file-selection",
                    "--directory",
                    "--title=\(title)"
                ]
            ),
            (
                "kdialog",
                [
                    "--getexistingdirectory",
                    FileManager.default.homeDirectoryForCurrentUser.path,
                    "--title", title
                ]
            )
        ]

        for (executable, arguments) in candidates {
            guard let path = run(executable, arguments) else { continue }
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return trimmed
        }

        return nil
        #endif
    }

    #if !os(macOS)
    /// Returns nil when the tool is absent or the dialog was cancelled, so the
    /// caller falls through to the next candidate.
    private static func run(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        // Exit code 1 is a user cancel; 127 means the tool is not installed.
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
    #endif
}
