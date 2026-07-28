import SwiftUI

struct AddBotSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = NewBotDraft()

    let add: (BotProfile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                BotAvatar(
                    name: draft.name,
                    provider: draft.provider,
                    role: draft.role,
                    size: 44
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add a bot")
                        .font(.bl00p(.title2, weight: .bold))
                    Text("Give this bot a clear job in the loop.")
                        .foregroundStyle(.secondary)
                }
            }

            Form {
                TextField("Name", text: $draft.name)

                Picker("Provider", selection: providerSelection) {
                    ForEach(AgentProvider.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }

                Picker("Model", selection: $draft.modelID) {
                    ForEach(draft.provider.modelOptions) { option in
                        Text(option.displayName).tag(option.id)
                    }
                }

                Picker("Role", selection: $draft.role) {
                    ForEach(AgentRole.allCases) { role in
                        Text(role.displayName).tag(role)
                    }
                }

                TextEditor(text: $draft.instructions)
                    .font(.bl00p(.body, sizeOffset: 1))
                    .frame(minHeight: 130)
                    .overlay(alignment: .topLeading) {
                        if draft.instructions.isEmpty {
                            Text("Role prompt and working guidelines…")
                                .font(.bl00p(.body, sizeOffset: 1))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Add Bot") {
                    add(draft.profile())
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(Color.bl00pAvatarInk)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.trimmedName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520, height: 530)
        .font(.bl00p(.body, sizeOffset: 1))
        .tint(.bl00pPink)
        .onAppear {
            draft = NewBotDraft()
        }
    }

    private var providerSelection: Binding<AgentProvider> {
        Binding(
            get: { draft.provider },
            set: { draft.selectProvider($0) }
        )
    }
}

struct NewBotDraft {
    var name = AgentProvider.codex.displayName
    private(set) var provider = AgentProvider.codex
    var role = AgentProvider.codex.defaultRole
    var modelID = ""
    var instructions = ""

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func selectProvider(_ newProvider: AgentProvider) {
        let previousProvider = provider
        let wasUsingDefaultRole = role == previousProvider.defaultRole
        provider = newProvider
        if name == previousProvider.displayName || name == "New Bot" {
            name = newProvider.displayName
        }
        if wasUsingDefaultRole {
            role = newProvider.defaultRole
        }
        modelID = ""
    }

    func profile() -> BotProfile {
        BotProfile(
            name: trimmedName,
            provider: provider,
            role: role,
            instructions: instructions,
            modelID: modelID.isEmpty ? nil : modelID
        )
    }
}
