import Foundation

#if os(macOS)
import AppKit
import SwiftUI
#else
import SwiftOpenUI
#endif

// The platform entry points live in `Platform/MacEntry.swift` and `main.swift`;
// each is excluded from the other platform's target in Package.swift. Only the
// shared window content lives here.

struct RootView: View {
    @ObservedObject var model: AppModel
    #if os(macOS)
    @ObservedObject var updateController: UpdateController
    #endif
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        #if os(macOS)
        splitView
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
        #else
        // `navigationSplitViewStyle`, `tint`, and `onReceive` have no
        // SwiftOpenUI equivalent. The first two are cosmetic; `onReceive`
        // tracked macOS app activation, which the GTK4 backend does not report.
        splitView
            .font(.bl00p(.body))
            .sheet(isPresented: isAddingBotBinding) {
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
        #endif
    }

    #if !os(macOS)
    // SwiftOpenUI's `ObservedObject` has no projectedValue, so `$model` does
    // not exist; this constructs the one binding this view needs manually.
    private var isAddingBotBinding: Binding<Bool> {
        Binding(
            get: { model.isAddingBot },
            set: { model.isAddingBot = $0 }
        )
    }
    #endif

    private var splitView: some View {
        NavigationSplitView {
            #if os(macOS)
            SidebarView(
                model: model,
                updateController: updateController,
                windowColorScheme: colorScheme
            )
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
            #else
            SidebarView(model: model, windowColorScheme: colorScheme)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
            #endif
        } detail: {
            detail
        }
    }

    private var detail: some View {
        #if os(macOS)
        return HStack(spacing: 0) {
            ConversationView(model: model)

            if model.isInspectorVisible, let selectedID = model.selectedBotID {
                Divider()
                ProfileInspectorView(
                    profile: model.binding(for: selectedID),
                    profiles: model.profiles,
                    chatSession: model.selectedSessionID(for: selectedID)
                        .flatMap { model.sessionBinding(for: $0) }
                )
                .frame(width: 330)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: model.isInspectorVisible)
        #else
        // SwiftOpenUI has no `transition`; the inspector appears without the
        // slide-in. The width animation is kept.
        return HStack(spacing: 0) {
            ConversationView(model: model)

            if model.isInspectorVisible, let selectedID = model.selectedBotID {
                Divider()
                ProfileInspectorView(
                    profile: model.binding(for: selectedID),
                    profiles: model.profiles,
                    chatSession: model.selectedSessionID(for: selectedID)
                        .flatMap { model.sessionBinding(for: $0) }
                )
                .frame(width: 330)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: model.isInspectorVisible)
        #endif
    }
}
