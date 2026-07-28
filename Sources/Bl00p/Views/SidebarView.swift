import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: AppModel
    let windowColorScheme: ColorScheme
    @State private var renameTargetID: UUID?
    @State private var renameDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            brand

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

            Divider()

            Button {
                model.isAddingBot = true
            } label: {
                Label("Add Bot", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(14)
        }
        .background(
            LinearGradient(
                colors: Bl00pTheme.sidebarColors(for: windowColorScheme)
                    .map(Color.init(nsColor:)),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .alert(
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
            TextField("Bot name", text: $renameDraft)
            Button("Cancel", role: .cancel) {
                renameTargetID = nil
            }
            Button("Rename") {
                if let renameTargetID {
                    model.rename(renameTargetID, to: renameDraft)
                }
                renameTargetID = nil
            }
            .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Choose the name shown in the sidebar and conversation.")
        }
    }

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
}

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
                                        Color(
                                            nsColor: Bl00pTheme.sidebarTop(
                                                for: windowColorScheme
                                            )
                                        ),
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
