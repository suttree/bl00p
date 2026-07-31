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
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var isUpdateAvailable = false
    @Published private(set) var isInstallationRequested = false

    private var controller: SPUStandardUpdaterController?
    private var immediateInstallationHandler: (() -> Void)?
    private var didBeginInstallation = false

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    /// Avoids starting Sparkle in state-transition tests.
    init(startingUpdater: Bool) {
        super.init()
        if startingUpdater {
            controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: self,
                userDriverDelegate: nil
            )
        }
    }

    var updater: SPUUpdater {
        guard let controller else {
            preconditionFailure("Sparkle is unavailable when the updater is not started")
        }
        return controller.updater
    }

    func requestInstallation() {
        guard isUpdateAvailable, !isInstallationRequested else { return }
        isInstallationRequested = true
        beginInstallationIfReady()
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        updateWasFound()
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        updateWasNotFound()
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        installHandlerBecameAvailable(immediateInstallHandler)
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        installationWillBegin()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        updateDidFail()
    }

    func updater(
        _ updater: SPUUpdater,
        failedToDownloadUpdate item: SUAppcastItem,
        error: Error
    ) {
        updateDidFail()
    }

    func userDidCancelDownload(_ updater: SPUUpdater) {
        updateWasCancelled()
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        guard isUpdateAvailable else { return }
        resetAvailability()
    }

    func updateWasFound() {
        immediateInstallationHandler = nil
        didBeginInstallation = false
        isInstallationRequested = false
        isUpdateAvailable = true
    }

    @discardableResult
    func installHandlerBecameAvailable(
        _ immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        guard isUpdateAvailable, !didBeginInstallation else { return false }
        immediateInstallationHandler = immediateInstallHandler
        beginInstallationIfReady()
        return true
    }

    func updateWasNotFound() {
        resetAvailability()
    }

    func updateWasCancelled() {
        resetAvailability()
    }

    func updateDidFail() {
        resetAvailability()
    }

    func installationWillBegin() {
        guard !didBeginInstallation else { return }
        didBeginInstallation = true
        immediateInstallationHandler = nil
        isUpdateAvailable = false
    }

    private func beginInstallationIfReady() {
        guard
            isInstallationRequested,
            !didBeginInstallation,
            let immediateInstallationHandler
        else { return }

        didBeginInstallation = true
        self.immediateInstallationHandler = nil
        isUpdateAvailable = false
        immediateInstallationHandler()
    }

    private func resetAvailability() {
        immediateInstallationHandler = nil
        didBeginInstallation = false
        isInstallationRequested = false
        isUpdateAvailable = false
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
        string: "https://api.github.com/repos/suttree/bl00p/releases/latest"
    )!
    private static let releasesPage = "https://github.com/suttree/bl00p/releases/latest"

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
