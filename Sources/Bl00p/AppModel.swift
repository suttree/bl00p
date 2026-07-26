import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var profiles: [BotProfile]
    @Published var sessions: [UUID: AgentSessionState]
    @Published var selectedBotID: UUID?
    @Published var isInspectorVisible = false
    @Published var isAddingBot = false

    private let runtime: any AgentRuntime
    private let store: AppStateStore
    private var runGenerations: [UUID: UUID] = [:]

    init(
        runtime: any AgentRuntime = AgentRuntimeRouter(),
        store: AppStateStore = AppStateStore()
    ) {
        self.runtime = runtime
        self.store = store

        if let saved = store.load(), !saved.profiles.isEmpty {
            profiles = saved.profiles
            sessions = saved.sessions.mapValues { restoredSession in
                var session = restoredSession
                if session.status == .launching
                    || session.status == .working
                    || session.status == .needsApproval
                    || session.status == .needsAnswer {
                    session.status = .stopped
                }
                return session
            }
            selectedBotID = saved.selectedBotID ?? saved.profiles.first?.id
        } else {
            profiles = BotProfile.defaults
            sessions = Dictionary(
                uniqueKeysWithValues: BotProfile.defaults.map { ($0.id, AgentSessionState()) }
            )
            selectedBotID = BotProfile.defaults.first?.id
        }
    }

    var selectedProfile: BotProfile? {
        guard let selectedBotID else { return nil }
        return profiles.first { $0.id == selectedBotID }
    }

    func session(for profileID: UUID) -> AgentSessionState {
        sessions[profileID] ?? AgentSessionState()
    }

    func binding(for profileID: UUID) -> Binding<BotProfile> {
        Binding(
            get: { [weak self] in
                self?.profiles.first(where: { $0.id == profileID })
                    ?? BotProfile(
                        id: profileID,
                        name: "Bot",
                        provider: .codex,
                        role: .builder,
                        instructions: ""
                    )
            },
            set: { [weak self] updated in
                self?.update(updated)
            }
        )
    }

    func add(_ profile: BotProfile) {
        profiles.append(profile)
        sessions[profile.id] = AgentSessionState()
        selectedBotID = profile.id
        isAddingBot = false
        isInspectorVisible = true
        save()
    }

    func duplicate(_ profileID: UUID) {
        guard var copy = profiles.first(where: { $0.id == profileID }) else { return }
        copy.id = UUID()
        copy.name += " Copy"
        add(copy)
    }

    func delete(_ profileID: UUID) {
        guard profiles.count > 1 else { return }
        if let profile = profiles.first(where: { $0.id == profileID }) {
            Task {
                await runtime.stop(profile: profile)
            }
        }
        runGenerations[profileID] = UUID()
        profiles.removeAll { $0.id == profileID }
        sessions[profileID] = nil
        if selectedBotID == profileID {
            selectedBotID = profiles.first?.id
        }
        save()
    }

    func update(_ profile: BotProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        save()
    }

    func showSettings(for profileID: UUID) {
        selectedBotID = profileID
        isInspectorVisible = true
    }

    func chooseWorkingDirectory(for profileID: UUID) {
        let panel = NSOpenPanel()
        panel.title = "Choose a working directory"
        panel.message = "bl00p will launch this bot in the selected folder."
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let path = panel.url?.path,
           let index = profiles.firstIndex(where: { $0.id == profileID }) {
            profiles[index].workingDirectory = path
            save()
        }
    }

    func launch(_ profileID: UUID) {
        guard let profile = profiles.first(where: { $0.id == profileID }) else { return }
        let previousThreadID = sessions[profileID]?.sessionID
        let generation = UUID()
        runGenerations[profileID] = generation
        sessions[profileID] = AgentSessionState(sessionID: previousThreadID)

        Task {
            await runtime.stop(profile: profile)
            let stream = await runtime.start(
                profile: profile,
                resumeThreadID: previousThreadID
            )
            consume(stream, for: profileID, generation: generation)
        }
    }

    func launchAll() {
        for profile in profiles {
            launch(profile.id)
        }
    }

    func stop(_ profileID: UUID) {
        guard let profile = profiles.first(where: { $0.id == profileID }) else { return }
        runGenerations[profileID] = UUID()
        Task {
            await runtime.stop(profile: profile)
        }
        apply(.status(.stopped), to: profileID)
        append(
            .init(kind: .system, text: "Session stopped by you."),
            to: profileID
        )
    }

    func send(_ text: String, to profileID: UUID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let profile = profiles.first(where: { $0.id == profileID }) else { return }

        append(.init(kind: .user, text: trimmed), to: profileID)
        let generation = runGenerations[profileID] ?? UUID()
        runGenerations[profileID] = generation
        Task {
            let stream = await runtime.respond(to: trimmed, profile: profile)
            consume(stream, for: profileID, generation: generation)
        }
    }

    func resolveApproval(_ entryID: UUID, approved: Bool, for profileID: UUID) {
        guard let profile = profiles.first(where: { $0.id == profileID }) else { return }

        let generation = runGenerations[profileID] ?? UUID()
        runGenerations[profileID] = generation
        Task {
            let stream = await runtime.resolveApproval(
                entryID: entryID,
                approved: approved,
                profile: profile
            )
            consume(stream, for: profileID, generation: generation)
        }
    }

    func markViewed(_ profileID: UUID) {
        guard var state = sessions[profileID] else { return }
        if state.status == .completed {
            state.hasUnreadCompletion = false
            sessions[profileID] = state
            save()
        }
    }

    private func consume(
        _ stream: AsyncStream<AgentEvent>,
        for profileID: UUID,
        generation: UUID
    ) {
        Task { [weak self] in
            for await event in stream {
                guard !Task.isCancelled else { break }
                guard self?.runGenerations[profileID] == generation else { break }
                self?.apply(event, to: profileID)
            }
        }
    }

    private func apply(_ event: AgentEvent, to profileID: UUID) {
        var state = sessions[profileID] ?? AgentSessionState()

        switch event {
        case .status(let status):
            state.status = status
            if status == .completed {
                state.hasUnreadCompletion = selectedBotID != profileID
            }
        case .entry(let entry):
            state.entries.append(entry)
        case .upsertEntry(let entry):
            if let index = state.entries.firstIndex(where: { $0.id == entry.id }) {
                state.entries[index] = entry
            } else {
                state.entries.append(entry)
            }
        case .approvalResolved(let entryID, let approvalState):
            if let index = state.entries.firstIndex(where: { $0.id == entryID }) {
                state.entries[index].approvalState = approvalState
            }
        case .sessionID(let sessionID):
            state.sessionID = sessionID
        }

        sessions[profileID] = state
        save()
    }

    private func append(_ entry: TimelineEntry, to profileID: UUID) {
        var state = sessions[profileID] ?? AgentSessionState()
        state.entries.append(entry)
        sessions[profileID] = state
        save()
    }

    private func save() {
        store.save(
            PersistedAppState(
                profiles: profiles,
                sessions: sessions,
                selectedBotID: selectedBotID
            )
        )
    }
}

struct AppStateStore: Sendable {
    private let fileURL: URL?

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
            return
        }

        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        self.fileURL = base?
            .appendingPathComponent("bl00p", isDirectory: true)
            .appendingPathComponent("state.json", isDirectory: false)
    }

    func load() -> PersistedAppState? {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder.iso8601.decode(PersistedAppState.self, from: data)
    }

    func save(_ state: PersistedAppState) {
        guard let fileURL,
              let data = try? JSONEncoder.pretty.encode(state) else { return }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Persistence failure should not interrupt an active coding session.
        }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
