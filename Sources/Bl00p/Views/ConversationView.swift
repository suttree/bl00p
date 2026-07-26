import SwiftUI

struct ConversationView: View {
    @ObservedObject var model: AppModel
    @State private var draft = ""

    var body: some View {
        if let profile = model.selectedProfile {
            let session = model.session(for: profile.id)

            VStack(spacing: 0) {
                ConversationHeader(
                    profile: profile,
                    session: session,
                    launch: { model.launch(profile.id) },
                    stop: { model.stop(profile.id) },
                    showSettings: { model.isInspectorVisible.toggle() }
                )

                Divider()

                if session.entries.isEmpty {
                    EmptySessionView(profile: profile) {
                        model.launch(profile.id)
                    }
                } else {
                    TranscriptView(
                        entries: session.entries,
                        profile: profile,
                        resolveApproval: { entryID, approved in
                            model.resolveApproval(entryID, approved: approved, for: profile.id)
                        }
                    )
                }

                Divider()

                ComposerView(
                    draft: $draft,
                    isEnabled: session.status != .launching && session.status != .working,
                    send: {
                        let outgoing = draft
                        draft = ""
                        model.send(outgoing, to: profile.id)
                    }
                )
            }
            .background(Color(nsColor: .textBackgroundColor))
        } else {
            ContentUnavailableView(
                "No Bot Selected",
                systemImage: "bubble.left.and.exclamationmark.bubble.right",
                description: Text("Choose or add a bot to begin.")
            )
        }
    }
}

private struct ConversationHeader: View {
    let profile: BotProfile
    let session: AgentSessionState
    let launch: () -> Void
    let stop: () -> Void
    let showSettings: () -> Void

    private var isRunning: Bool {
        session.status == .launching || session.status == .working
    }

    var body: some View {
        HStack(spacing: 12) {
            BotAvatar(provider: profile.provider, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(profile.name)
                        .font(.bl00p(.headline, weight: .semibold))
                    StatusPill(status: session.status)
                }

                Text(directoryLabel)
                    .font(.bl00p(.caption1))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if isRunning {
                Button("Stop", systemImage: "stop.fill", action: stop)
                    .buttonStyle(.bordered)
            } else {
                Button(profile.role.launchLabel, systemImage: "play.fill", action: launch)
                    .buttonStyle(.borderedProminent)
            }

            Button(action: showSettings) {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            .help("Bot settings")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var directoryLabel: String {
        if profile.workingDirectory.isEmpty {
            return "Working directory not set"
        }
        return profile.workingDirectory
    }
}

private struct EmptySessionView: View {
    let profile: BotProfile
    let launch: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            BotAvatar(provider: profile.provider, size: 64)
                .shadow(color: .bl00pPink.opacity(0.16), radius: 18, y: 8)

            VStack(spacing: 7) {
                Text("\(profile.role.displayName) is ready")
                    .font(.bl00p(.title2, weight: .bold, design: .rounded))

                Text("Launch the session, then give this bot its part of the loop.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(profile.role.launchLabel, systemImage: "play.fill", action: launch)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct TranscriptView: View {
    let entries: [TimelineEntry]
    let profile: BotProfile
    let resolveApproval: (UUID, Bool) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(entries) { entry in
                        TimelineEntryView(
                            entry: entry,
                            profile: profile,
                            resolveApproval: resolveApproval
                        )
                        .id(entry.id)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: entries.count) { _, _ in
                if let lastID = entries.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }
}

private struct TimelineEntryView: View {
    let entry: TimelineEntry
    let profile: BotProfile
    let resolveApproval: (UUID, Bool) -> Void

    var body: some View {
        switch entry.kind {
        case .user:
            userMessage
        case .assistant:
            assistantMessage
        case .system:
            systemMessage
        case .command:
            eventCard(icon: "terminal", tint: .bl00pInk)
        case .diff:
            eventCard(icon: "doc.text.magnifyingglass", tint: .orange)
        case .question:
            eventCard(icon: "questionmark.bubble.fill", tint: .bl00pPink)
        case .approval:
            approvalCard
        }
    }

    private var userMessage: some View {
        HStack {
            Spacer(minLength: 100)
            Text(entry.text)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.bl00pPink, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .foregroundStyle(.white)
        }
    }

    private var assistantMessage: some View {
        HStack(alignment: .top, spacing: 10) {
            BotAvatar(provider: profile.provider, size: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.bl00p(.caption1, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(entry.text)
                    .textSelection(.enabled)
                    .lineSpacing(3)
            }
            Spacer(minLength: 60)
        }
    }

    private var systemMessage: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.text)
                if let detail = entry.detail {
                    Text(detail)
                        .font(.bl00p(.caption1))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .font(.bl00p(.callout))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func eventCard(icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 7) {
                if let title = entry.title {
                    Text(title)
                        .font(.bl00p(.callout, weight: .semibold))
                }

                Text(entry.text)
                    .font(
                        entry.kind == .command
                            ? .bl00p(.callout, design: .monospaced)
                            : .bl00p(.callout)
                    )
                    .textSelection(.enabled)

                if let detail = entry.detail {
                    Text(detail)
                        .font(.bl00p(.caption1))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Spacer()
        }
        .padding(14)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var approvalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(entry.title ?? "Approval required", systemImage: "hand.raised.fill")
                    .font(.bl00p(.callout, weight: .bold))
                    .foregroundStyle(Color.bl00pPink)
                Spacer()
                if let state = entry.approvalState, state != .pending {
                    Text(state == .approved ? "Approved" : "Declined")
                        .font(.bl00p(.caption1, weight: .semibold))
                        .foregroundStyle(state == .approved ? .green : .secondary)
                }
            }

            Text(entry.text)
                .font(.bl00p(.callout, design: .monospaced))
                .textSelection(.enabled)

            if let detail = entry.detail {
                Text(detail)
                    .font(.bl00p(.caption1))
                    .foregroundStyle(.secondary)
            }

            if entry.approvalState == .pending {
                HStack {
                    Button("Decline") {
                        resolveApproval(entry.id, false)
                    }
                    .buttonStyle(.bordered)

                    Button("Approve") {
                        resolveApproval(entry.id, true)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(15)
        .background(Color.bl00pPinkSoft.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.bl00pPink.opacity(0.25), lineWidth: 1)
        }
    }
}

private struct ComposerView: View {
    @Binding var draft: String
    let isEnabled: Bool
    let send: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                TextEditor(text: $draft)
                    .font(.bl00p(.body))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 44, maxHeight: 110)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.quaternary, lineWidth: 1)
                    }

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
                .disabled(!isEnabled || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: [.command])
            }

            Text(isEnabled ? "⌘↩ to send · You remain in control of approvals" : "The bot is working…")
                .font(.bl00p(.caption1))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.bar)
    }
}
