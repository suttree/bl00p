import SwiftUI

struct AddBotSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = AgentProvider.codex.displayName
    @State private var provider = AgentProvider.codex
    @State private var modelID = ""
    @State private var instructions = ""

    let add: (BotProfile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                BotAvatar(name: name, provider: provider, size: 44)
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

                Picker("Model", selection: $modelID) {
                    ForEach(provider.modelOptions) { option in
                        Text(option.displayName).tag(option.id)
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
                            role: provider.defaultRole,
                            instructions: instructions,
                            modelID: modelID.isEmpty ? nil : modelID
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
        .onChange(of: provider) { previous, current in
            if name == previous.displayName || name == "New Bot" {
                name = current.displayName
            }
            modelID = ""
        }
    }
}
