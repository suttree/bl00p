import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: AppModel
    @State private var renameTargetID: UUID?
    @State private var renameDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            brand

            List(selection: $model.selectedBotID) {
                ForEach(model.profiles) { profile in
                    BotRow(
                        profile: profile,
                        session: model.session(for: profile.id)
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
                colors: [.white, .bl00pPinkSoft.opacity(0.5)],
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
    let session: AgentSessionState

    private var showsAttention: Bool {
        session.status.needsAttention || session.hasUnreadCompletion
    }

    var body: some View {
        HStack(spacing: 10) {
            BotAvatar(name: profile.name, provider: profile.provider, size: 32)
                .overlay(alignment: .topTrailing) {
                    if showsAttention {
                        Circle()
                            .fill(Color.bl00pPink)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
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

            if session.status == .working || session.status == .launching {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
