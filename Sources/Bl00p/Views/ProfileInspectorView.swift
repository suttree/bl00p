import Foundation

#if os(macOS)
import SwiftUI
#else
import SwiftOpenUI
#endif

struct ProfileInspectorView: View {
    @Binding var profile: BotProfile
    let profiles: [BotProfile]
    /// The currently selected chat session for this bot, if any. When
    /// present, the prompt editor edits this chat's override rather than the
    /// bot's global default.
    var chatSession: Binding<AgentSessionState>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    BotAvatar(
                        name: profile.name,
                        provider: profile.provider,
                        role: profile.role,
                        size: 38
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bot settings")
                            .font(.bl00p(.headline, weight: .semibold))
                        Text("Changes save automatically")
                            .font(.bl00p(.caption1))
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Name") {
                    TextField("Bot name", text: nameBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 180)
                }

                LabeledContent("Model") {
                    Picker("Model", selection: modelSelection) {
                        ForEach(profile.provider.modelOptions) { option in
                            Text(option.displayName).tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 180)
                }

                LabeledContent("Role") {
                    Picker("Role", selection: roleBinding) {
                        ForEach(AgentRole.allCases) { role in
                            Text(role.displayName).tag(role)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 180)
                }

                if profile.role == .manager {
                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("MANAGED WORKFLOW")
                            .font(.bl00p(.caption2, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(.secondary)

                        teamPicker(
                            "Builder",
                            role: .builder,
                            selection: teamSelection(\.builderProfileID)
                        )
                        teamPicker(
                            "Reviewer",
                            role: .reviewer,
                            selection: teamSelection(\.reviewerProfileID)
                        )
                        teamPicker(
                            "Documenter",
                            role: .publisher,
                            selection: teamSelection(\.publisherProfileID)
                        )

                        Text(
                            profile.managerTeam?.isComplete == true
                                ? "Messages to this Manager start the delivery workflow. Other bots remain available for ordinary standalone chats."
                                : "Optional orchestration is off until all three roles are assigned. This Manager still works as a normal standalone bot."
                        )
                            .font(.bl00p(.caption1))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if profile.provider == .codex || profile.provider == .claude {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("APPROVALS")
                            .font(.bl00p(.caption2, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(.secondary)

                        Picker("Approval mode", selection: approvalModeBinding) {
                            ForEach(ApprovalMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .disabled(!profile.canSelectApprovalMode)

                        Text(approvalModeDescription)
                            .font(.bl00p(.caption1))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(chatSession != nil ? "CHAT PROMPT" : "ROLE PROMPT")
                            .font(.bl00p(.caption2, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(.secondary)

                        if isUsingChatOverride {
                            Text("Custom")
                                .font(.bl00p(.caption2, weight: .semibold))
                                .foregroundStyle(Color.bl00pPink)
                        }

                        Spacer()

                        if isUsingChatOverride {
                            Button("Reset to bot default") {
                                chatSession?.wrappedValue.instructionsOverride = nil
                            }
                            .font(.bl00p(.caption1))
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }

                    TextEditor(text: instructionsBinding)
                        .font(.bl00p(.body))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 220)
                        .padding(8)
                        .background(
                            Color.bl00pControlBackground,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.quaternary, lineWidth: 1)
                        }
                }

                Text(promptCaption)
                    .font(.bl00p(.caption1))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
        }
        .background(Color.bl00pWindowBackground)
    }

    private var modelSelection: Binding<String> {
        Binding(
            get: { profile.modelID ?? "" },
            set: { profile.modelID = $0.isEmpty ? nil : $0 }
        )
    }

    // SwiftOpenUI's `Binding` has no dynamic-member-lookup subscript to
    // derive `Binding<Field>` from `Binding<BotProfile>` the way SwiftUI's
    // `$profile.field` sugar does, so each field binding is constructed
    // explicitly. Portable on both platforms, not just a Linux workaround.
    private var nameBinding: Binding<String> {
        Binding(get: { profile.name }, set: { profile.name = $0 })
    }

    private var roleBinding: Binding<AgentRole> {
        Binding(get: { profile.role }, set: { profile.role = $0 })
    }

    private var approvalModeBinding: Binding<ApprovalMode> {
        Binding(get: { profile.approvalMode }, set: { profile.approvalMode = $0 })
    }

    /// Edits this chat's prompt override when a chat session is selected,
    /// falling back to the bot's global default otherwise (e.g. when editing
    /// a bot with no chats yet). Shows the effective prompt as starting text;
    /// any edit writes the full text back as this chat's override, leaving
    /// the bot default and other chats untouched.
    private var instructionsBinding: Binding<String> {
        guard let chatSession else {
            return Binding(get: { profile.instructions }, set: { profile.instructions = $0 })
        }
        return Binding(
            get: {
                chatSession.wrappedValue.instructionsOverride ?? profile.instructions
            },
            set: { chatSession.wrappedValue.instructionsOverride = $0 }
        )
    }

    private var isUsingChatOverride: Bool {
        guard let override = chatSession?.wrappedValue.instructionsOverride else { return false }
        return !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var promptCaption: String {
        let providerCaption = profile.provider == .codex
            ? "Codex receives this prompt as developer instructions when the session launches."
            : "Claude receives this prompt through its resumable CLI session. Structured approvals enforce read-only roles and keep elevated actions visible."
        guard chatSession != nil else { return providerCaption }
        return "This prompt applies only to the selected chat. \(providerCaption)"
    }

    private var approvalModeDescription: String {
        if profile.provider == .claude {
            if profile.role == .manager {
                return "Claude Managers remain read-only and cannot escalate permissions. Approval mode is unavailable for this role."
            }
            if profile.role == .reviewer {
                return profile.approvalMode == .auto
                    ? "Claude automatically approves supported repository inspection actions. Built-in file-edit tools and write-capable shell commands remain blocked. Mode changes take effect the next time this bot connects."
                    : "Claude asks before additional inspection actions. Built-in file-edit tools and write-capable shell commands remain blocked. Mode changes take effect the next time this bot connects."
            }
            return profile.approvalMode == .auto
                ? "Claude automatically approves supported actions inside this workspace. Destructive and publishing actions remain blocked; other unclassified actions require explicit approval. Changes take effect the next time this bot connects."
                : "Claude asks before actions that need approval through its structured permission protocol. Changes take effect the next time this bot connects."
        }

        return profile.approvalMode == .auto
            ? "Codex can edit this workspace and runs approved actions without asking. Only takes effect the next time this bot connects."
            : "Codex can edit this workspace and asks before actions that need extra access, including GitHub changes."
    }

    private func teamSelection(
        _ keyPath: WritableKeyPath<ManagerTeamConfiguration, UUID?>
    ) -> Binding<UUID?> {
        Binding(
            get: {
                profile.managerTeam?[keyPath: keyPath]
            },
            set: { newValue in
                var team = profile.managerTeam ?? ManagerTeamConfiguration()
                team[keyPath: keyPath] = newValue
                profile.managerTeam = team
            }
        )
    }

    @ViewBuilder
    private func teamPicker(
        _ label: String,
        role: AgentRole,
        selection: Binding<UUID?>
    ) -> some View {
        LabeledContent(label) {
            Picker(label, selection: selection) {
                Text("Choose…").tag(nil as UUID?)
                ForEach(
                    profiles.filter {
                        $0.id != profile.id && $0.role == role
                    }
                ) { candidate in
                    Text(candidate.name).tag(Optional(candidate.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 180)
        }
    }
}
