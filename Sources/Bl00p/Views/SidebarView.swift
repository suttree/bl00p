import Foundation

#if os(macOS)
import AppKit
import SwiftUI
#else
import SwiftOpenUI
#endif

struct SidebarView: View {
    @ObservedObject var model: AppModel
    let windowColorScheme: ColorScheme
    @State private var renameTargetID: UUID?
    @State private var renameDraft = ""
    #if !os(macOS)
    // macOS surfaces this through the app's Command menu (Platform/MacEntry.swift);
    // SwiftOpenUI's menu-bar Commands support is untested here, so the Linux
    // build exposes the same check as a sidebar affordance instead.
    @StateObject private var updateController = UpdateController()
    #endif

    var body: some View {
        VStack(spacing: 0) {
            brand
            rows
            Divider()

            Button {
                model.isAddingBot = true
            } label: {
                Label("Add Bot", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(14)

            #if !os(macOS)
            updateFooter
            #endif
        }
        .background(
            LinearGradient(
                colors: Bl00pTheme.sidebarColors(for: windowColorScheme),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .modifier(RenameAlert(
            renameTargetID: $renameTargetID,
            renameDraft: $renameDraft,
            deletionError: $model.profileDeletionError,
            rename: { id, name in model.rename(id, to: name) }
        ))
    }

    #if !os(macOS)
    private var updateFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            CheckForUpdatesView(controller: updateController)
                .buttonStyle(.plain)
                .font(.bl00p(.caption1))

            if let statusMessage = updateController.statusMessage {
                Text(statusMessage)
                    .font(.bl00p(.caption2))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }
    #endif

    private var brand: some View {
        HStack {
            Text("bl00p")
                .font(.bl00p(.title3, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.bl00pInk)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    #if os(macOS)
    private var rows: some View {
        List(selection: $model.selectedBotID) {
            ForEach(model.profiles) { profile in
                BotRow(
                    profile: profile,
                    sessions: model.sessions(for: profile.id),
                    windowColorScheme: windowColorScheme
                )
                .tag(Optional(profile.id))
                .contextMenu {
                    Button("Rename…") {
                        renameDraft = profile.name
                        renameTargetID = profile.id
                    }

                    Button("Edit Prompt") {
                        model.showSettings(for: profile.id)
                    }

                    Button("Set Working Directory…") {
                        model.chooseWorkingDirectory(for: profile.id)
                    }

                    Divider()

                    Button("Duplicate Bot") {
                        model.duplicate(profile.id)
                    }

                    Button("Delete Bot", role: .destructive) {
                        model.delete(profile.id)
                    }
                    .disabled(model.profiles.count == 1)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }
    #else
    /// SwiftOpenUI's `List` has no selection binding and its `contextMenu`
    /// takes a declarative `MenuElement` list rather than `Button` views, so
    /// the row list and its menu are rebuilt from `ScrollView` + `LazyVStack`
    /// instead of ported modifier-for-modifier.
    private var rows: some View {
        ScrollView {
            LazyVStack(model.profiles) { profile in
                Button {
                    model.selectedBotID = profile.id
                } label: {
                    BotRow(
                        profile: profile,
                        sessions: model.sessions(for: profile.id),
                        windowColorScheme: windowColorScheme
                    )
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        model.selectedBotID == profile.id
                            ? Color.bl00pPink.opacity(0.14)
                            : Color.clear
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    MenuItem("Rename…") {
                        renameDraft = profile.name
                        renameTargetID = profile.id
                    }
                    MenuItem("Edit Prompt") {
                        model.showSettings(for: profile.id)
                    }
                    MenuItem("Set Working Directory…") {
                        model.chooseWorkingDirectory(for: profile.id)
                    }
                    MenuDivider()
                    MenuItem("Duplicate Bot") {
                        model.duplicate(profile.id)
                    }
                    if model.profiles.count > 1 {
                        MenuItem("Delete Bot") {
                            model.delete(profile.id)
                        }
                    }
                }
            }
        }
    }
    #endif
}

/// Renaming needs a text field inside the confirmation surface. SwiftOpenUI's
/// `alert` only accepts a plain message string, so the Linux build presents
/// the same flow as a small sheet instead of a native alert dialog.
private struct RenameAlert: ViewModifier {
    @Binding var renameTargetID: UUID?
    @Binding var renameDraft: String
    @Binding var deletionError: String?
    let rename: (UUID, String) -> Void

    func body(content: Content) -> some View {
        #if os(macOS)
        content.alert(
            "Rename bot",
            isPresented: Binding(
                get: { renameTargetID != nil },
                set: { isPresented in
                    if !isPresented {
                        renameTargetID = nil
                    }
                }
            )
        ) {
            RenameTextField(text: $renameDraft)
            Button("Cancel", role: .cancel) {
                renameTargetID = nil
            }
            Button("Rename") {
                if let renameTargetID {
                    rename(renameTargetID, renameDraft)
                }
                renameTargetID = nil
            }
            .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Choose the name shown in the sidebar and conversation.")
        }
        .alert(
            "Could not delete bot",
            isPresented: Binding(
                get: { deletionError != nil },
                set: { if !$0 { deletionError = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(deletionError ?? "")
        }
        #else
        content.sheet(
            isPresented: Binding(
                get: { renameTargetID != nil },
                set: { isPresented in
                    if !isPresented {
                        renameTargetID = nil
                    }
                }
            )
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Rename bot")
                    .font(.bl00p(.headline, weight: .semibold))

                Text("Choose the name shown in the sidebar and conversation.")
                    .font(.bl00p(.caption1))
                    .foregroundStyle(.secondary)

                TextField("Bot name", text: $renameDraft)

                HStack {
                    Spacer()
                    Button("Cancel") {
                        renameTargetID = nil
                    }
                    Button("Rename") {
                        if let renameTargetID {
                            rename(renameTargetID, renameDraft)
                        }
                        renameTargetID = nil
                    }
                    .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 320)
        }
        .sheet(
            isPresented: Binding(
                get: { deletionError != nil },
                set: { if !$0 { deletionError = nil } }
            )
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Could not delete bot")
                    .font(.bl00p(.headline, weight: .semibold))
                Text(deletionError ?? "")
                HStack {
                    Spacer()
                    Button("OK") {
                        deletionError = nil
                    }
                }
            }
            .padding(20)
            .frame(width: 360)
        }
        #endif
    }
}

#if os(macOS)
private struct RenameTextField: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> RenameTextFieldControl {
        let field = RenameTextFieldControl(string: text)
        field.placeholderString = "Bot name"
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: RenameTextFieldControl, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

private final class RenameTextFieldControl: NSTextField {
    private var keyWindowObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeKeyWindowObserver()

        guard let window else { return }
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.focusWhenPresented()
            }
        }
        focusWhenPresented()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            removeKeyWindowObserver()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    private func focusWhenPresented() {
        guard let window else { return }

        let editor = currentEditor()
        guard window.firstResponder !== self, window.firstResponder !== editor else {
            return
        }
        guard window.makeFirstResponder(self) else { return }

        // Native alert presentation may select the whole field. Put the caret
        // at the end without replacing text the user entered while it appeared.
        currentEditor()?.selectedRange = NSRange(
            location: stringValue.utf16.count,
            length: 0
        )
    }

    private func removeKeyWindowObserver() {
        if let keyWindowObserver {
            NotificationCenter.default.removeObserver(keyWindowObserver)
            self.keyWindowObserver = nil
        }
    }
}
#endif

private struct BotRow: View {
    let profile: BotProfile
    let sessions: [AgentSessionState]
    let windowColorScheme: ColorScheme

    private var showsAttention: Bool {
        sessions.contains {
            $0.status.needsAttention || $0.hasUnreadCompletion
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            BotAvatar(
                name: profile.name,
                provider: profile.provider,
                role: profile.role,
                size: 32
            )
                .overlay(alignment: .topTrailing) {
                    if showsAttention {
                        Circle()
                            .fill(Color.bl00pPink)
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle()
                                    .stroke(
                                        Bl00pTheme.sidebarTop(for: windowColorScheme),
                                        lineWidth: 2
                                    )
                            )
                            .offset(x: 3, y: -3)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.bl00p(.callout, weight: .semibold))
                    .lineLimit(1)

                Text("\(profile.provider.displayName) · \(profile.modelDisplayName)")
                    .font(.bl00p(.caption2))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            if sessions.contains(where: {
                $0.status == .working || $0.status == .launching
            }) {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
