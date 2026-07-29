import AppKit
import SwiftUI

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

private struct RootView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model, windowColorScheme: colorScheme)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            HStack(spacing: 0) {
                ConversationView(model: model)

                if model.isInspectorVisible, let selectedID = model.selectedBotID {
                    Divider()
                    ProfileInspectorView(
                        profile: model.binding(for: selectedID),
                        profiles: model.profiles
                    )
                    .frame(width: 330)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: model.isInspectorVisible)
        }
        .navigationSplitViewStyle(.balanced)
        .font(.bl00p(.body))
        .tint(.bl00pPink)
        .sheet(isPresented: $model.isAddingBot) {
            AddBotSheet { profile in
                model.add(profile)
            }
        }
        .task {
            model.prepareNotifications()
        }
        .onChange(of: model.selectedBotID) { _, newValue in
            if let newValue {
                model.markViewed(newValue)
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            if let selectedBotID = model.selectedBotID {
                model.markViewed(selectedBotID)
            }
        }
    }
}
