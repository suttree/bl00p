#if os(macOS)
import Testing
@testable import Bl00p

@MainActor
@Test
func updateControllerStartsWithoutAnAvailableUpdate() {
    let controller = UpdateController(startingUpdater: false)

    #expect(!controller.isUpdateAvailable)
    #expect(!controller.isInstallationRequested)
}

@MainActor
@Test
func findingAnUpdateExposesTheAffordance() {
    let controller = UpdateController(startingUpdater: false)

    controller.updateWasFound()

    #expect(controller.isUpdateAvailable)
    #expect(!controller.isInstallationRequested)
}

@MainActor
@Test
func requestingInstallationBeforePreparationQueuesTheRequest() {
    let controller = UpdateController(startingUpdater: false)
    controller.updateWasFound()

    controller.requestInstallation()

    #expect(controller.isUpdateAvailable)
    #expect(controller.isInstallationRequested)
}

@MainActor
@Test
func aPreparedQueuedUpdateInstallsExactlyOnce() {
    let controller = UpdateController(startingUpdater: false)
    var installationCount = 0
    controller.updateWasFound()
    controller.requestInstallation()

    controller.installHandlerBecameAvailable {
        installationCount += 1
    }
    controller.installHandlerBecameAvailable {
        installationCount += 1
    }

    #expect(installationCount == 1)
    #expect(!controller.isUpdateAvailable)
    #expect(controller.isInstallationRequested)
}

@MainActor
@Test
func requestingAPreparedUpdateInstallsImmediately() {
    let controller = UpdateController(startingUpdater: false)
    var installationCount = 0
    controller.updateWasFound()
    controller.installHandlerBecameAvailable {
        installationCount += 1
    }

    controller.requestInstallation()

    #expect(installationCount == 1)
    #expect(!controller.isUpdateAvailable)
}

@MainActor
@Test
func duplicateInstallationRequestsDoNotInstallTwice() {
    let controller = UpdateController(startingUpdater: false)
    var installationCount = 0
    controller.updateWasFound()
    controller.installHandlerBecameAvailable {
        installationCount += 1
    }

    controller.requestInstallation()
    controller.requestInstallation()

    #expect(installationCount == 1)
}

@MainActor
@Test
func beginningInstallationClearsTheAffordance() {
    let controller = UpdateController(startingUpdater: false)
    controller.updateWasFound()

    controller.installationWillBegin()

    #expect(!controller.isUpdateAvailable)
}

@MainActor
@Test(arguments: [
    UpdateUnavailableTransition.notFound,
    .cancelled,
    .failed
])
func unavailableUpdateTransitionsClearTheAffordance(
    transition: UpdateUnavailableTransition
) {
    let controller = UpdateController(startingUpdater: false)
    controller.updateWasFound()
    controller.requestInstallation()

    switch transition {
    case .notFound:
        controller.updateWasNotFound()
    case .cancelled:
        controller.updateWasCancelled()
    case .failed:
        controller.updateDidFail()
    }

    #expect(!controller.isUpdateAvailable)
    #expect(!controller.isInstallationRequested)
}

enum UpdateUnavailableTransition: Sendable {
    case notFound
    case cancelled
    case failed
}
#endif
