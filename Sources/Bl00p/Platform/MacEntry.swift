#if os(macOS)

import AppKit
import SwiftUI

/// macOS entry point. Excluded from the Linux target in Package.swift, which
/// uses `main.swift` and an explicit backend launch instead.
@main
struct Bl00pApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self)
    private var appDelegate
    @StateObject private var model: AppModel
    private let updateController: UpdateController

    init() {
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        updateController = UpdateController()
        appDelegate.model = model
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
                ForEach(1...9, id: \.self) { position in
                    Button("Select Chat \(position)") {
                        guard let profileID = model.selectedProfile?.id else {
                            return
                        }
                        model.selectTab(at: position, viewing: profileID)
                    }
                    .keyboardShortcut(
                        KeyEquivalent(Character(String(position))),
                        modifiers: [.command]
                    )
                    .disabled(
                        model.selectedProfile.map {
                            !model.canSelectTab(
                                at: position,
                                viewing: $0.id
                            )
                        } ?? true
                    )
                }

                Button("Show Bot Settings") {
                    model.isInspectorVisible.toggle()
                }
                .keyboardShortcut(",", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
private final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var didReplyToTermination = false

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        didReplyToTermination = false
        Task {
            await model.flushPersistence()
            finishTermination(sender)
        }
        Task {
            try? await Task.sleep(for: .seconds(3))
            finishTermination(sender)
        }
        return .terminateLater
    }

    private func finishTermination(_ sender: NSApplication) {
        guard !didReplyToTermination else { return }
        didReplyToTermination = true
        sender.reply(toApplicationShouldTerminate: true)
    }
}

#endif
