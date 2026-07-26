import SwiftUI

struct ProfileInspectorView: View {
    @Binding var profile: BotProfile
    let chooseDirectory: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    BotAvatar(name: profile.name, provider: profile.provider, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bot settings")
                            .font(.bl00p(.headline, weight: .semibold))
                        Text("Changes save automatically")
                            .font(.bl00p(.caption1))
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Name") {
                    TextField("Bot name", text: $profile.name)
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

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("WORKING DIRECTORY")
                        .font(.bl00p(.caption2, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        TextField(
                            "Repository path",
                            text: .constant(profile.workingDirectory)
                        )
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)

                        Button(action: chooseDirectory) {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.bordered)
                        .help("Browse for a working directory")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("ROLE PROMPT")
                        .font(.bl00p(.caption2, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $profile.instructions)
                        .font(.bl00p(.body))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 220)
                        .padding(8)
                        .background(
                            Color(nsColor: .controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.quaternary, lineWidth: 1)
                        }
                }

                Text(
                    profile.provider == .codex
                        ? "Codex receives this prompt as developer instructions when the session launches."
                        : "Claude receives this prompt through its resumable CLI session. Destructive git and publishing actions remain blocked."
                )
                    .font(.bl00p(.caption1))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var modelSelection: Binding<String> {
        Binding(
            get: { profile.modelID ?? "" },
            set: { profile.modelID = $0.isEmpty ? nil : $0 }
        )
    }
}
