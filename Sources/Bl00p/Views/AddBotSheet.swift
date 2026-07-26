import SwiftUI

struct AddBotSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = "New Bot"
    @State private var provider = AgentProvider.codex
    @State private var role = AgentRole.reviewer
    @State private var instructions = ""

    let add: (BotProfile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                BotAvatar(provider: provider, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add a bot")
                        .font(.bl00p(.title2, weight: .bold))
                    Text("Give this bot a clear job in the loop.")
                        .foregroundStyle(.secondary)
                }
            }

            Form {
                TextField("Name", text: $name)

                Picker("Provider", selection: $provider) {
                    ForEach(AgentProvider.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }

                Picker("Role", selection: $role) {
                    ForEach(AgentRole.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }

                TextEditor(text: $instructions)
                    .frame(minHeight: 130)
                    .overlay(alignment: .topLeading) {
                        if instructions.isEmpty {
                            Text("Role prompt and working guidelines…")
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
                    add(
                        BotProfile(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            provider: provider,
                            role: role,
                            instructions: instructions
                        )
                    )
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520, height: 490)
        .tint(.bl00pPink)
    }
}
