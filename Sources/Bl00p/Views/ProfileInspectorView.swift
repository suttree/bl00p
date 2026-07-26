import SwiftUI

struct ProfileInspectorView: View {
    @Binding var profile: BotProfile
    let chooseDirectory: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    BotAvatar(provider: profile.provider, size: 38)
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

                Picker("Provider", selection: $profile.provider) {
                    ForEach(AgentProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }

                Picker("Role", selection: $profile.role) {
                    ForEach(AgentRole.allCases) { role in
                        Text(role.displayName).tag(role)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("WORKING DIRECTORY")
                        .font(.bl00p(.caption2, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        TextField("Repository path", text: $profile.workingDirectory)
                            .textFieldStyle(.roundedBorder)

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

                Toggle("Load project instructions", isOn: $profile.loadProjectInstructions)
                Toggle("Approve before pushing", isOn: $profile.requireApprovalBeforePush)

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
}
