import AppKit
import SwiftUI

struct ConversationView: View {
    @ObservedObject var model: AppModel
    @State private var draft = ""
    @State private var attachments: [ImageAttachment] = []

    var body: some View {
        if let profile = model.selectedProfile {
            let session = model.session(for: profile.id)

            VStack(spacing: 0) {
                ConversationHeader(
                    profile: profile,
                    session: session,
                    stop: { model.stop(profile.id) },
                    showSettings: { model.isInspectorVisible.toggle() }
                )

                Divider()

                if session.entries.isEmpty {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TranscriptView(
                        entries: session.entries,
                        profile: profile,
                        resolveApproval: { entryID, approved in
                            model.resolveApproval(entryID, approved: approved, for: profile.id)
                        }
                    )
                }

                ComposerView(
                    profileID: profile.id,
                    draft: $draft,
                    attachments: $attachments,
                    isEnabled: session.status != .launching && session.status != .working,
                    send: {
                        let outgoing = draft
                        let outgoingAttachments = attachments
                        draft = ""
                        attachments = []
                        model.send(
                            outgoing,
                            attachments: outgoingAttachments,
                            to: profile.id
                        )
                    }
                )
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: profile.id) { _, _ in
                draft = ""
                attachments = []
            }
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
    let stop: () -> Void
    let showSettings: () -> Void

    private var isRunning: Bool {
        session.status == .launching || session.status == .working
    }

    var body: some View {
        HStack(spacing: 12) {
            BotAvatar(name: profile.name, provider: profile.provider, size: 38)

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

                    Color.clear
                        .frame(height: 24)
                        .id("transcript-bottom-\(profile.id.uuidString)")
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)
                .frame(maxWidth: 884)
                .frame(maxWidth: .infinity)
            }
            .task(id: profile.id) {
                try? await Task.sleep(for: .milliseconds(60))
                proxy.scrollTo(
                    "transcript-bottom-\(profile.id.uuidString)",
                    anchor: .bottom
                )
            }
            .onChange(of: entries.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(
                        "transcript-bottom-\(profile.id.uuidString)",
                        anchor: .bottom
                    )
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
            ToolCallCard(entry: entry, icon: "terminal", tint: .bl00pInk)
        case .diff:
            ToolCallCard(
                entry: entry,
                icon: "doc.text.magnifyingglass",
                tint: .orange
            )
        case .question:
            eventCard(icon: "questionmark.bubble.fill", tint: .bl00pPinkText)
        case .approval:
            approvalCard
        }
    }

    private var userMessage: some View {
        HStack {
            Spacer(minLength: 100)
            VStack(alignment: .leading, spacing: 9) {
                if !entry.text.isEmpty {
                    Text(entry.text)
                        .textSelection(.enabled)
                }

                if let attachments = entry.attachments, !attachments.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(attachments) { attachment in
                            AttachmentThumbnail(attachment: attachment)
                        }
                    }
                }
            }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Color.bl00pUserBubble,
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )
                .foregroundStyle(Color.bl00pUserBubbleText)
        }
    }

    private var assistantMessage: some View {
        HStack(alignment: .top, spacing: 10) {
            BotAvatar(name: profile.name, provider: profile.provider, size: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.bl00p(.caption1, weight: .semibold))
                    .foregroundStyle(.secondary)
                MarkdownMessageView(source: entry.text)
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
                    .foregroundStyle(Color.bl00pPinkText)
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
                    .foregroundStyle(Color.bl00pAvatarInk)
                }
            }
        }
        .padding(15)
        .background(Color.bl00pPinkSoft, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.bl00pPink.opacity(0.40), lineWidth: 1)
        }
    }
}

private struct ToolCallCard: View {
    let entry: TimelineEntry
    let icon: String
    let tint: Color
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 28, height: 28)
                        .background(
                            tint.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 8)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.title ?? "Tool call")
                            .font(.bl00p(.callout, weight: .semibold))
                        Text(entry.text)
                            .font(
                                entry.kind == .command
                                    ? .bl00p(.caption1, design: .monospaced)
                                    : .bl00p(.caption1)
                            )
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.vertical, 12)

                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.text)
                        .font(
                            entry.kind == .command
                                ? .bl00p(.callout, design: .monospaced)
                                : .bl00p(.callout)
                        )
                        .textSelection(.enabled)

                    if let detail = entry.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.bl00p(.caption1, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
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
}

private struct AttachmentThumbnail: View {
    let attachment: ImageAttachment

    var body: some View {
        Group {
            if let image = NSImage(contentsOfFile: attachment.path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 20))
            }
        }
        .frame(width: 72, height: 58)
        .background(.white.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.35), lineWidth: 1)
        }
        .help(attachment.filename)
    }
}

private struct ComposerView: View {
    let profileID: UUID
    @Binding var draft: String
    @Binding var attachments: [ImageAttachment]
    let isEnabled: Bool
    let send: () -> Void
    @State private var isDropTargeted = false
    @State private var editorWidth: CGFloat = 600
    @State private var didReachCharacterLimit = false
    @FocusState private var isEditorFocused: Bool

    private var editorHeight: CGFloat {
        ComposerTextMetrics.editorHeight(
            for: draft,
            width: editorWidth
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { attachment in
                            attachmentChip(attachment)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextEditor(text: limitedDraft)
                    .focused($isEditorFocused)
                    .font(.bl00p(.body))
                    .scrollContentBackground(.hidden)
                    .frame(height: editorHeight)
                    .padding(.horizontal, 12)
                    .padding(.top, 11)
                    .padding(.bottom, 5)
                    .background {
                        GeometryReader { geometry in
                            Color.clear
                                .onAppear {
                                    editorWidth = geometry.size.width
                                }
                                .onChange(of: geometry.size.width) { _, width in
                                    editorWidth = width
                                }
                        }
                    }
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
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.bl00pAvatarInk)
                        .frame(width: 36, height: 36)
                        .background(Color.bl00pPink, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled || !hasContent)
                .opacity(
                    isEnabled && hasContent ? 1 : 0.35
                )
                .keyboardShortcut(.return, modifiers: [.command])
            }

            HStack {
                Text(
                    isEnabled
                        ? "Drop images here · ⌘↩ to send"
                        : "Working…"
                )

                Spacer()

                Text(characterCountLabel)
                    .foregroundStyle(
                        didReachCharacterLimit ? Color.bl00pPinkText : .secondary
                    )
            }
            .font(.bl00p(.caption1))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.bar)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.bl00pPink, style: .init(lineWidth: 2, dash: [6]))
                    .padding(7)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            addImages(urls)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .task(id: profileID) {
            await Task.yield()
            isEditorFocused = true
        }
    }

    private var hasContent: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !attachments.isEmpty
    }

    private var limitedDraft: Binding<String> {
        Binding(
            get: { draft },
            set: { proposedValue in
                didReachCharacterLimit =
                    proposedValue.count > ComposerLimits.maximumCharacters
                draft = ComposerLimits.clamp(proposedValue)
            }
        )
    }

    private var characterCountLabel: String {
        if didReachCharacterLimit {
            return "\(ComposerLimits.maximumCharacters.formatted()) character limit"
        }
        return "\(draft.count.formatted()) / \(ComposerLimits.maximumCharacters.formatted())"
    }

    private func attachmentChip(_ attachment: ImageAttachment) -> some View {
        HStack(spacing: 7) {
            if let image = NSImage(contentsOfFile: attachment.path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }

            Text(attachment.filename)
                .font(.bl00p(.caption1, weight: .medium))
                .lineLimit(1)

            Button {
                attachments.removeAll { $0.id == attachment.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove image")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private func addImages(_ urls: [URL]) -> Bool {
        let existingPaths = Set(attachments.map(\.path))
        let additions = urls.compactMap { url -> ImageAttachment? in
            let standardized = url.standardizedFileURL
            guard standardized.isFileURL,
                  !existingPaths.contains(standardized.path),
                  NSImage(contentsOf: standardized) != nil else { return nil }
            return ImageAttachment(path: standardized.path)
        }
        attachments.append(contentsOf: additions)
        return !additions.isEmpty
    }
}

private struct MarkdownMessageView: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(TranscriptMarkdown.blocks(source)) { block in
                switch block.content {
                case .prose(let text):
                    Text(text)
                        .textSelection(.enabled)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)

                case .code(let code):
                    Text(code)
                        .font(.bl00p(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            Color(nsColor: .controlBackgroundColor),
                            in: RoundedRectangle(
                                cornerRadius: 10,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: 10,
                                style: .continuous
                            )
                            .stroke(.quaternary, lineWidth: 1)
                        }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

enum TranscriptMarkdown {
    struct Block: Identifiable {
        enum Content {
            case prose(AttributedString)
            case code(String)
        }

        let id: Int
        let content: Content
    }

    static func attributed(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: source, options: options))
            ?? AttributedString(source)
    }

    static func blocks(_ source: String) -> [Block] {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)

        var result: [Block] = []
        var proseLines: [String] = []
        var codeLines: [String] = []
        var activeFence: String?

        func appendProse() {
            let prose = proseLines
                .joined(separator: "\n")
                .trimmingCharacters(in: .newlines)
            guard !prose.isEmpty else {
                proseLines.removeAll()
                return
            }
            result.append(
                Block(id: result.count, content: .prose(attributed(prose)))
            )
            proseLines.removeAll()
        }

        func appendCode() {
            result.append(
                Block(
                    id: result.count,
                    content: .code(codeLines.joined(separator: "\n"))
                )
            )
            codeLines.removeAll()
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let fence = activeFence {
                if isClosingFence(trimmed, matching: fence) {
                    appendCode()
                    activeFence = nil
                } else {
                    codeLines.append(line)
                }
                continue
            }

            if let fence = openingFence(in: trimmed) {
                appendProse()
                activeFence = fence
            } else {
                proseLines.append(line)
            }
        }

        if activeFence != nil {
            appendCode()
        } else {
            appendProse()
        }
        return result
    }

    private static func openingFence(in line: String) -> String? {
        guard let marker = line.first, marker == "`" || marker == "~" else {
            return nil
        }
        let count = line.prefix { $0 == marker }.count
        guard count >= 3 else { return nil }
        return String(repeating: marker, count: count)
    }

    private static func isClosingFence(
        _ line: String,
        matching fence: String
    ) -> Bool {
        guard let marker = fence.first,
              line.count >= fence.count,
              line.allSatisfy({ $0 == marker }) else {
            return false
        }
        return true
    }
}

enum ComposerLimits {
    static let maximumCharacters = 50_000
    static let maximumEditorHeight: CGFloat = 240

    static func clamp(_ text: String) -> String {
        guard text.count > maximumCharacters else { return text }
        return String(text.prefix(maximumCharacters))
    }
}

enum ComposerTextMetrics {
    static func editorHeight(
        for text: String,
        width: CGFloat
    ) -> CGFloat {
        if text.count > 5_000 {
            return ComposerLimits.maximumEditorHeight
        }

        let font = NSFont.systemFont(
            ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize + 2
        )
        let availableWidth = max(80, width - 36)
        let measuredText = (text.isEmpty ? " " : text) + "\u{200B}"
        let bounds = (measuredText as NSString).boundingRect(
            with: NSSize(
                width: availableWidth,
                height: .greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return min(
            ComposerLimits.maximumEditorHeight,
            max(24, ceil(bounds.height) + 6)
        )
    }
}
