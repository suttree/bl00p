import Foundation

#if os(macOS)
import SwiftUI
#else
import SwiftOpenUI
#endif

/// Resolves the desktop light/dark preference.
///
/// On macOS the system publishes appearance changes and SwiftUI republishes
/// them through the environment. The GTK4 backend has no equivalent signal, so
/// on Linux the preference is read once at launch from the freedesktop
/// `color-scheme` setting and held for the lifetime of the process. Changing
/// the desktop theme therefore requires relaunching bl00p.
enum Bl00pAppearance {
    /// The appearance bl00p paints with. Immutable after launch on Linux.
    nonisolated(unsafe) static let current: ColorScheme = detect()

    private static func detect() -> ColorScheme {
        #if os(macOS)
        return .light
        #else
        if let scheme = gsettingsColorScheme() {
            return scheme
        }

        if let theme = ProcessInfo.processInfo.environment["GTK_THEME"],
            theme.lowercased().contains("dark") {
            return .dark
        }

        return .light
        #endif
    }

    #if !os(macOS)
    /// Reads `org.gnome.desktop.interface color-scheme`, which XFCE and the
    /// other Kali desktops also honour through the XDG settings portal. The
    /// value arrives quoted, for example `'prefer-dark'`.
    private static func gsettingsColorScheme() -> ColorScheme? {
        guard
            let output = runCapturingOutput(
                "gsettings",
                ["get", "org.gnome.desktop.interface", "color-scheme"]
            )
        else { return nil }

        let value = output.trimmingCharacters(
            in: CharacterSet(charactersIn: "' \n\r\t")
        )

        guard !value.isEmpty, value != "default" else { return nil }
        return value.contains("dark") ? .dark : .light
    }

    private static func runCapturingOutput(
        _ executable: String,
        _ arguments: [String]
    ) -> String? {
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

        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
    #endif
}
