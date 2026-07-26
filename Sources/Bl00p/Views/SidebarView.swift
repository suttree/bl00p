import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            brand

            List(selection: $model.selectedBotID) {
                Section("BOT LOOP") {
                    ForEach(model.profiles) { profile in
                        BotRow(
                            profile: profile,
                            session: model.session(for: profile.id)
                        )
                        .tag(Optional(profile.id))
                        .contextMenu {
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
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()

            VStack(spacing: 10) {
                Button {
                    model.launchAll()
                } label: {
                    Label("Launch Loop", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    model.isAddingBot = true
                } label: {
                    Label("Add Bot", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(14)
        }
        .background(
            LinearGradient(
                colors: [.white, .bl00pPinkSoft.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var brand: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.bl00pPink)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text("bl00p")
                    .font(.bl00p(.title3, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.bl00pInk)
                Text("BOT LOOP")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(Color.bl00pPink)
            }

            Spacer()

            Button {
                model.isInspectorVisible.toggle()
            } label: {
                Image(systemName: "sidebar.trailing")
            }
            .buttonStyle(.plain)
            .help("Toggle bot settings")
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
            BotAvatar(provider: profile.provider, size: 32)
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

                Text("\(profile.provider.displayName) · \(profile.role.displayName)")
                    .font(.bl00p(.caption1))
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
