import Foundation

#if os(macOS)
import Combine
import Sparkle
import SwiftUI
#else
import SwiftOpenUI
// URLSession/URLRequest live in a separate module on Linux; Foundation alone
// doesn't re-export them the way Darwin's does.
import FoundationNetworking
#endif

#if os(macOS)

@MainActor
final class UpdateController {
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var updater: SPUUpdater {
        controller.updater
    }
}

@MainActor
private final class CheckForUpdatesViewModel: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}

#else

/// The Linux build is delivered as a `.deb`, so the package manager owns
/// installation and Sparkle's in-app download-and-relaunch flow does not
/// apply. This controller only answers "is there a newer release?" and hands
/// the user off to the release page; `apt` performs the actual upgrade.
final class UpdateController: ObservableObject {
    /// Kept in step with `debian/changelog` and `Resources/Info.plist`.
    static let currentVersion = "0.1.0"

    private static let releasesAPI = URL(
        string: "https://api.github.com/repos/FesterCluck/bl00p/releases/latest"
    )!
    private static let releasesPage = "https://github.com/FesterCluck/bl00p/releases/latest"

    @Published private(set) var isChecking = false
    @Published private(set) var statusMessage: String?

    func checkForUpdates() {
        guard !isChecking else { return }
        isChecking = true
        statusMessage = "Checking for updates…"

        Task {
            let latest = await Self.fetchLatestVersion()
            isChecking = false

            guard let latest else {
                statusMessage = "Could not reach the release feed."
                return
            }

            if Self.isNewer(latest, than: Self.currentVersion) {
                statusMessage = "Version \(latest) is available."
                Self.open(Self.releasesPage)
            } else {
                statusMessage = "bl00p \(Self.currentVersion) is up to date."
            }
        }
    }

    private static func fetchLatestVersion() async -> String? {
        var request = URLRequest(url: releasesAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse,
            http.statusCode == 200,
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tag = payload["tag_name"] as? String
        else { return nil }

        return tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// Numeric component comparison; avoids "0.10.0" sorting below "0.9.0".
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let right = current.split(separator: ".").map { Int($0) ?? 0 }

        for index in 0..<max(left.count, right.count) {
            let lhs = index < left.count ? left[index] : 0
            let rhs = index < right.count ? right[index] : 0
            if lhs != rhs { return lhs > rhs }
        }

        return false
    }

    private static func open(_ url: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["xdg-open", url]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject var controller: UpdateController

    var body: some View {
        Button("Check for Updates…") {
            controller.checkForUpdates()
        }
        .disabled(controller.isChecking)
    }
}

#endif
