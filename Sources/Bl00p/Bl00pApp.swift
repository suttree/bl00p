import SwiftUI

@main
struct Bl00pApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1240, height: 780)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Show Bot Settings") {
                    model.isInspectorVisible.toggle()
                }
                .keyboardShortcut(",", modifiers: [.command, .shift])
            }
        }
    }
}

private struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            HStack(spacing: 0) {
                ConversationView(model: model)

                if model.isInspectorVisible, let selectedID = model.selectedBotID {
                    Divider()
                    ProfileInspectorView(
                        profile: model.binding(for: selectedID),
                        chooseDirectory: { model.chooseWorkingDirectory(for: selectedID) }
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
        .onChange(of: model.selectedBotID) { _, newValue in
            if let newValue {
                model.markViewed(newValue)
            }
        }
    }
}
