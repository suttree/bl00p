#if os(macOS)

import SwiftUI

/// macOS entry point. Excluded from the Linux target in Package.swift, which
/// uses `main.swift` and an explicit backend launch instead.
@main
struct Bl00pApp: App {
    @StateObject private var model: AppModel
    private let updateController: UpdateController

    init() {
        _model = StateObject(wrappedValue: AppModel())
        updateController = UpdateController()
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1240, height: 780)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updateController.updater)
            }

            CommandGroup(after: .sidebar) {
                Button("Show Bot Settings") {
                    model.isInspectorVisible.toggle()
                }
                .keyboardShortcut(",", modifiers: [.command, .shift])
            }
        }
    }
}

#endif
