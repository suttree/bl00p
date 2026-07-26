import AppKit
import Foundation
import Testing
@testable import Bl00p

@Test
func updateFeedUsesSignedGitHubReleaseAssets() throws {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let infoURL = projectRoot
        .appendingPathComponent("Resources")
        .appendingPathComponent("Info.plist")
    let data = try Data(contentsOf: infoURL)
    let info = try #require(
        PropertyListSerialization.propertyList(from: data, format: nil)
            as? [String: Any]
    )
    let publicKey = try #require(info["SUPublicEDKey"] as? String)
    let decodedPublicKey = try #require(Data(base64Encoded: publicKey))

    #expect(
        info["SUFeedURL"] as? String
            == "https://github.com/suttree/bl00p/releases/latest/download/appcast.xml"
    )
    #expect(info["SUEnableAutomaticChecks"] as? Bool == true)
    #expect(info["SUAutomaticallyUpdate"] as? Bool == true)
    #expect(info["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
    #expect(publicKey == "O2mHaTZMsDiYGGPMKTgkR2dR9wuOsOjiCyNiY0UsLhc=")
    #expect(decodedPublicKey.count == 32)
}

@Test
func themeAdaptsToSystemAppearanceWithLegibleBrandSurfaces() throws {
    let light = try #require(NSAppearance(named: .aqua))
    let dark = try #require(NSAppearance(named: .darkAqua))
    let lightAccent = resolved(Bl00pTheme.accent, for: light)
    let darkAccent = resolved(Bl00pTheme.accent, for: dark)
    let lightAccentText = resolved(Bl00pTheme.accentText, for: light)
    let darkAccentText = resolved(Bl00pTheme.accentText, for: dark)
    let lightBubble = resolved(Bl00pTheme.userBubble, for: light)
    let darkBubble = resolved(Bl00pTheme.userBubble, for: dark)
    let lightBubbleText = resolved(Bl00pTheme.userBubbleText, for: light)
    let darkBubbleText = resolved(Bl00pTheme.userBubbleText, for: dark)
    let lightApproval = resolved(Bl00pTheme.approvalBackground, for: light)
    let darkApproval = resolved(Bl00pTheme.approvalBackground, for: dark)

    for surface in [lightAccent, darkAccent, lightBubble, darkBubble] {
        #expect(abs(surface.redComponent - 1.00) < 0.001)
        #expect(abs(surface.greenComponent - 105.0 / 255.0) < 0.001)
        #expect(abs(surface.blueComponent - 180.0 / 255.0) < 0.001)
    }
    for textColor in [lightBubbleText, darkBubbleText] {
        #expect(abs(textColor.redComponent - 1.00) < 0.001)
        #expect(abs(textColor.greenComponent - 1.00) < 0.001)
        #expect(abs(textColor.blueComponent - 1.00) < 0.001)
    }
    #expect(lightApproval != darkApproval)
    #expect(
        Bl00pTheme.sidebarColors(for: .light)
            != Bl00pTheme.sidebarColors(for: .dark)
    )
    #expect(contrastRatio(lightBubble, Bl00pTheme.avatarInk) >= 4.5)
    #expect(contrastRatio(darkBubble, Bl00pTheme.avatarInk) >= 4.5)
    #expect(contrastRatio(lightAccentText, lightApproval) >= 4.5)
    #expect(contrastRatio(darkAccentText, darkApproval) >= 4.5)

    for appearance in [light, dark] {
        let mint = resolved(Bl00pTheme.mint, for: appearance)
        #expect(contrastRatio(mint, Bl00pTheme.avatarInk) >= 4.5)
    }
}

@Test
func avatarBackgroundUsesPinkForManagersAndMintForOtherRoles() throws {
    let light = try #require(NSAppearance(named: .aqua))
    let dark = try #require(NSAppearance(named: .darkAqua))

    for appearance in [light, dark] {
        let managerBackground = resolved(
            Bl00pTheme.avatarBackground(for: .manager),
            for: appearance
        )
        let pink = resolved(Bl00pTheme.hotPink, for: appearance)
        #expect(managerBackground == pink)
        #expect(contrastRatio(managerBackground, Bl00pTheme.avatarInk) >= 4.5)

        for role in AgentRole.allCases where role != .manager {
            let background = resolved(
                Bl00pTheme.avatarBackground(for: role),
                for: appearance
            )
            let mint = resolved(Bl00pTheme.mint, for: appearance)
            #expect(background == mint)
        }
    }
}

@Test
func defaultProfilesCoverTheLoop() {
    #expect(BotProfile.defaults.map(\.role) == [.builder, .reviewer, .publisher])
    #expect(Set(BotProfile.defaults.map(\.provider)) == [.claude, .codex])
    #expect(BotProfile.defaults.map(\.name) == ["Claude", "Codex", "Claude"])
}

private func contrastRatio(_ first: NSColor, _ second: NSColor) -> CGFloat {
    let firstLuminance = relativeLuminance(first)
    let secondLuminance = relativeLuminance(second)
    let lighter = max(firstLuminance, secondLuminance)
    let darker = min(firstLuminance, secondLuminance)
    return (lighter + 0.05) / (darker + 0.05)
}

private func resolved(_ color: NSColor, for appearance: NSAppearance) -> NSColor {
    var result = color
    appearance.performAsCurrentDrawingAppearance {
        result = color.usingColorSpace(.sRGB) ?? color
    }
    return result
}

private func relativeLuminance(_ color: NSColor) -> CGFloat {
    guard let rgb = color.usingColorSpace(.sRGB) else { return 0 }
    let components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
        .map { component in
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
    return 0.2126 * components[0]
        + 0.7152 * components[1]
        + 0.0722 * components[2]
}

@Test
func providersChooseSensibleHiddenRolesForNewBots() {
    #expect(AgentProvider.claude.defaultRole == .builder)
    #expect(AgentProvider.codex.defaultRole == .reviewer)
}

@Test
func addBotDraftSubmitsTheProviderCurrentlyShown() {
    var draft = NewBotDraft()
    draft.selectProvider(.claude)
    draft.selectProvider(.codex)

    let profile = draft.profile()

    #expect(draft.provider == .codex)
    #expect(profile.provider == .codex)
    #expect(profile.name == "Codex")
    #expect(profile.role == .reviewer)
}

@Test
func addBotDraftPreservesAnExplicitRoleAcrossProviderChanges() {
    var draft = NewBotDraft()
    draft.role = .publisher

    draft.selectProvider(.claude)
    let profile = draft.profile()

    #expect(profile.provider == .claude)
    #expect(profile.role == .publisher)
}

@Test
func attentionStatesAreExplicit() {
    #expect(AgentStatus.needsApproval.needsAttention)
    #expect(AgentStatus.needsAnswer.needsAttention)
    #expect(AgentStatus.failed.needsAttention)
    #expect(!AgentStatus.working.needsAttention)
    #expect(!AgentStatus.completed.needsAttention)
}

@Test
func attentionNoticesOnlyFireOnRelevantStatusTransitions() {
    #expect(
        AgentAttentionNotice.transition(from: .working, to: .needsAnswer)
            == .needsAnswer
    )
    #expect(
        AgentAttentionNotice.transition(from: .working, to: .needsApproval)
            == .needsApproval
    )
    #expect(
        AgentAttentionNotice.transition(from: .working, to: .completed)
            == .completed
    )
    #expect(
        AgentAttentionNotice.transition(from: .needsAnswer, to: .needsAnswer)
            == nil
    )
    #expect(
        AgentAttentionNotice.transition(from: .launching, to: .working)
            == nil
    )
}

@MainActor
@Test
func completedAgentPostsNotificationAndUpdatesDockBadge() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-notifications-\(UUID().uuidString)", isDirectory: true)
    let notifications = RecordingNotificationDelivery()
    let model = AppModel(
        runtime: ImmediateRecordingRuntime(),
        store: AppStateStore(fileURL: directory.appendingPathComponent("state.json")),
        notifications: notifications,
        isAppWindowActive: { false }
    )
    let backgroundProfile = try #require(model.profiles.dropFirst().first)

    model.prepareNotifications()
    model.send("Finish this task", to: backgroundProfile.id)

    for _ in 0..<30
        where model.session(for: backgroundProfile.id).status != .completed {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(notifications.authorizationRequestCount == 1)
    #expect(notifications.notices.map(\.notice) == [.completed])
    #expect(notifications.notices.first?.profileID == backgroundProfile.id)
    #expect(notifications.badgeCounts.last == 1)

    model.markViewed(backgroundProfile.id)
    #expect(notifications.badgeCounts.last == 0)
    try? FileManager.default.removeItem(at: directory)
}

@MainActor
@Test
func activeWindowSuppressesNotificationButKeepsDockBadge() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-active-notifications-\(UUID().uuidString)",
            isDirectory: true
        )
    let notifications = RecordingNotificationDelivery()
    let model = AppModel(
        runtime: ImmediateRecordingRuntime(),
        store: AppStateStore(fileURL: directory.appendingPathComponent("state.json")),
        notifications: notifications,
        isAppWindowActive: { true }
    )
    let backgroundProfile = try #require(model.profiles.dropFirst().first)

    model.prepareNotifications()
    model.send("Finish this task", to: backgroundProfile.id)

    for _ in 0..<30
        where model.session(for: backgroundProfile.id).status != .completed {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(notifications.authorizationRequestCount == 1)
    #expect(notifications.notices.isEmpty)
    #expect(notifications.badgeCounts.last == 1)

    model.markViewed(backgroundProfile.id)
    #expect(notifications.badgeCounts.last == 0)
    try? FileManager.default.removeItem(at: directory)
}

@Test
func composerGrowsWhenTextWrapsWithoutANewline() {
    let shortHeight = ComposerTextMetrics.editorHeight(
        for: "Short message",
        width: 420
    )
    let wrappedHeight = ComposerTextMetrics.editorHeight(
        for: String(repeating: "A long command with several words ", count: 8),
        width: 420
    )

    #expect(wrappedHeight > shortHeight)
    #expect(wrappedHeight <= ComposerLimits.maximumEditorHeight)
}

@Test
func composerUsesAGenerousExplicitCharacterLimit() {
    let oversized = String(
        repeating: "a",
        count: ComposerLimits.maximumCharacters + 1_000
    )
    let clamped = ComposerLimits.clamp(oversized)

    #expect(clamped.count == 50_000)
    #expect(
        ComposerTextMetrics.editorHeight(for: clamped, width: 420)
            == ComposerLimits.maximumEditorHeight
    )
}

@Test
func assistantMarkdownProducesClickableLinksAndPreservesLayout() throws {
    let rendered = TranscriptMarkdown.attributed(
        """
        Draft PR created: [suttree/bl00p#1](https://github.com/suttree/bl00p/pull/1)

        - Branch: `feature/improve-agent-workflows`
        """
    )
    let link = try #require(rendered.runs.compactMap(\.link).first)

    #expect(link.absoluteString == "https://github.com/suttree/bl00p/pull/1")
    #expect(String(rendered.characters).contains("suttree/bl00p#1"))
    #expect(String(rendered.characters).contains("\n\n- Branch:"))
    #expect(!String(rendered.characters).contains("https://github.com"))
}

@Test
func fencedMarkdownAndShellBlocksPreserveLinesWithoutLanguageLabels() throws {
    let blocks = TranscriptMarkdown.blocks(
        """
        Example:

        ```markdown
        # Planned Features
        ## Now
        - Suppress notifications
        ```

        Then run:

        ```sh
        swift test
        git status
        ```
        """
    )
    let code = blocks.compactMap { block -> String? in
        guard case .code(let text) = block.content else { return nil }
        return text
    }

    #expect(code.count == 2)
    #expect(
        try #require(code.first)
            == "# Planned Features\n## Now\n- Suppress notifications"
    )
    #expect(try #require(code.last) == "swift test\ngit status")
    #expect(!code.joined().contains("markdown"))
    #expect(!code.joined().contains("```"))
}

@Test
func codexBotsUseGeneralTurnsInsteadOfInheritingReviewMode() {
    let request = CodexTurnRequest.make(
        threadID: "document-thread",
        message: "Document the existing changes",
        attachments: [],
        modelID: nil
    )

    #expect(request.method == "turn/start")
    #expect(request.params["threadId"]?.stringValue == "document-thread")
    #expect(
        request.params["input"]?.arrayValue?.first?["text"]?.stringValue
            == "Document the existing changes"
    )
}

@Test
func codexThreadConfigurationKeepsBotPromptsSeparate() {
    let reviewer = BotProfile(
        name: "Review",
        provider: .codex,
        role: .reviewer,
        instructions: "Review this code."
    )
    let documenter = BotProfile(
        name: "Document",
        provider: .codex,
        role: .publisher,
        instructions: "Document this code."
    )

    let reviewParameters = CodexThreadConfiguration.parameters(
        profile: reviewer,
        workingDirectory: "/tmp/project"
    )
    let documentParameters = CodexThreadConfiguration.parameters(
        profile: documenter,
        workingDirectory: "/tmp/project"
    )

    #expect(
        reviewParameters["developerInstructions"]?.stringValue?
            .hasPrefix("Review this code.\n\n") == true
    )
    #expect(
        documentParameters["developerInstructions"]?.stringValue?
            .hasPrefix("Document this code.\n\n") == true
    )
    #expect(
        reviewParameters["developerInstructions"]?.stringValue?
            .contains("request elevated permission through Codex") == true
    )
    #expect(
        documentParameters["developerInstructions"]?.stringValue?
            .contains("Prefer the authenticated GitHub connected app") == true
    )
}

@Test
func codexThreadConfigurationHonorsTheApprovalModeToggle() {
    var profile = BotProfile(
        name: "Review",
        provider: .codex,
        role: .reviewer,
        instructions: "Review this code."
    )

    profile.approvalMode = .ask
    let askParameters = CodexThreadConfiguration.parameters(
        profile: profile,
        workingDirectory: "/tmp/project"
    )
    #expect(askParameters["approvalPolicy"]?.stringValue == "on-request")
    #expect(askParameters["sandbox"]?.stringValue == "workspace-write")

    profile.approvalMode = .auto
    let autoParameters = CodexThreadConfiguration.parameters(
        profile: profile,
        workingDirectory: "/tmp/project"
    )
    #expect(autoParameters["approvalPolicy"]?.stringValue == "on-request")
    #expect(autoParameters["sandbox"]?.stringValue == "workspace-write")
}

@Test
func codexManagersHaveANonEscalatableReadOnlyBoundary() {
    let manager = BotProfile(
        name: "Manager",
        provider: .codex,
        role: .manager,
        instructions: "Coordinate the configured team.",
        approvalMode: .auto
    )

    let parameters = CodexThreadConfiguration.parameters(
        profile: manager,
        workingDirectory: "/tmp/project"
    )
    let instructions = parameters["developerInstructions"]?.stringValue

    #expect(parameters["sandbox"]?.stringValue == "read-only")
    #expect(parameters["approvalPolicy"]?.stringValue == "never")
    #expect(instructions?.contains("selected working directory is read-only") == true)
    #expect(instructions?.contains("Do not spawn or delegate") == true)
    #expect(
        instructions?
            .contains("Workspace file writes are enabled") == false
    )
}

@Test
func codexApprovalResponsesMatchEachAppServerRequestType() {
    #expect(
        CodexApprovalResponse.decision.result(approved: true)
            == .object(["decision": .string("accept")])
    )
    #expect(
        CodexApprovalResponse.mcpElicitation.result(approved: false)
            == .object(["action": .string("decline")])
    )

    let requested: JSONValue = .object([
        "network": .object(["enabled": .bool(true)]),
        "fileSystem": .null
    ])
    #expect(
        CodexApprovalResponse.permissions(requested).result(approved: true)
            == .object([
                "permissions": .object([
                    "network": .object(["enabled": .bool(true)])
                ]),
                "scope": .string("session")
            ])
    )
    #expect(
        CodexApprovalResponse.permissions(requested).result(approved: false)
            == .object([
                "permissions": .object([:]),
                "scope": .string("session")
            ])
    )
}

@Test
func botProfileDecodesLegacyJSONMissingApprovalMode() throws {
    let legacyJSON = """
    {
        "id": "D24E2670-03E9-420B-9AB5-00A589E09249",
        "name": "Claude",
        "provider": "claude",
        "role": "builder",
        "instructions": "Do the work.",
        "workingDirectory": "",
        "loadProjectInstructions": true,
        "requireApprovalBeforePush": true
    }
    """.data(using: .utf8)!

    let profile = try JSONDecoder().decode(BotProfile.self, from: legacyJSON)

    #expect(profile.approvalMode == .ask)
    #expect(profile.name == "Claude")
}

@Test
func persistedStateRoundTrips() throws {
    var profile = BotProfile.defaults[0]
    profile.worktree = GitWorktreeOwnership(
        ownerProfileID: profile.id,
        repositoryPath: "/tmp/project",
        worktreePath: "/tmp/.bl00p-worktrees/project-builder",
        branch: "bl00p/builder-12345678",
        baseRevision: "abc123"
    )
    let handoff = GitHandoffPackage(
        sourceProfileID: profile.id,
        sourceName: profile.name,
        repositoryPath: "/tmp/project",
        worktreePath: "/tmp/.bl00p-worktrees/project-builder",
        branch: "bl00p/builder-12345678",
        baseRevision: "abc123",
        headRevision: "def456",
        taskContext: "Implement the feature",
        testStatus: .passed,
        testSummary: "`swift test`",
        workingTreeSummary: "Clean"
    )
    let state = PersistedAppState(
        profiles: [profile],
        sessions: [
            profile.id: AgentSessionState(
                status: .completed,
                entries: [
                    TimelineEntry(kind: .assistant, text: "Done")
                ],
                hasUnreadCompletion: true,
                sessionID: "session-1",
                pendingHandoff: handoff
            )
        ],
        selectedBotID: profile.id
    )

    let data = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(PersistedAppState.self, from: data)

    #expect(decoded.profiles == [profile])
    #expect(decoded.sessions[profile.id]?.status == .completed)
    #expect(decoded.sessions[profile.id]?.entries.first?.text == "Done")
    #expect(decoded.profiles.first?.worktree?.branch == handoff.branch)
    #expect(decoded.sessions[profile.id]?.pendingHandoff == handoff)
}

@Test
func worktreeManagerCreatesIsolatedBranchesAndHandoffSnapshots() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-worktrees-\(UUID().uuidString)",
            isDirectory: true
        )
    let repository = root.appendingPathComponent("project", isDirectory: true)
    try FileManager.default.createDirectory(
        at: repository,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: root) }

    try runGit(["init", "-b", "main"], in: repository)
    try Data("initial\n".utf8).write(
        to: repository.appendingPathComponent("README.md")
    )
    try runGit(["add", "README.md"], in: repository)
    try runGit(
        [
            "-c", "user.name=bl00p Tests",
            "-c", "user.email=tests@bl00p.dev",
            "commit", "-m", "Initial commit"
        ],
        in: repository
    )

    var first = BotProfile(
        id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
        name: "Implementation One",
        provider: .claude,
        role: .builder,
        instructions: "",
        workingDirectory: repository.path
    )
    let manager = GitWorktreeManager()
    let firstOwnership = try await manager.prepareWorktree(
        for: first,
        startingPoint: nil,
        handoffID: nil
    )
    first.worktree = firstOwnership

    #expect(firstOwnership.repositoryPath == repository.path)
    #expect(firstOwnership.worktreePath != repository.path)
    #expect(firstOwnership.branch.hasPrefix("bl00p/implementation-one-"))
    #expect(
        try gitOutput(["branch", "--show-current"], in: URL(
            fileURLWithPath: firstOwnership.worktreePath
        )) == firstOwnership.branch
    )

    let firstWorktree = URL(fileURLWithPath: firstOwnership.worktreePath)
    try Data("handoff\n".utf8).write(
        to: firstWorktree.appendingPathComponent("handoff.txt")
    )
    try runGit(["add", "handoff.txt"], in: firstWorktree)
    try runGit(
        [
            "-c", "user.name=bl00p Tests",
            "-c", "user.email=tests@bl00p.dev",
            "commit", "-m", "Handoff commit"
        ],
        in: firstWorktree
    )

    let session = AgentSessionState(
        status: .completed,
        entries: [
            .init(kind: .user, text: "Implement isolated worktrees"),
            .init(
                kind: .command,
                title: "Command finished",
                text: "swift test --disable-sandbox",
                detail: "44 tests passed"
            )
        ]
    )
    let package = try await manager.makeHandoff(from: first, session: session)

    #expect(package.branch == firstOwnership.branch)
    #expect(package.taskContext == "Implement isolated worktrees")
    #expect(package.testStatus == .passed)
    #expect(package.testSummary.contains("44 tests passed"))
    #expect(package.workingTreeSummary == "Clean")

    let second = BotProfile(
        id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
        name: "Implementation Two",
        provider: .claude,
        role: .builder,
        instructions: "",
        workingDirectory: repository.path
    )
    let secondOwnership = try await manager.prepareWorktree(
        for: second,
        startingPoint: package.branch,
        handoffID: package.id
    )
    let secondHead = try gitOutput(
        ["rev-parse", "HEAD"],
        in: URL(fileURLWithPath: secondOwnership.worktreePath)
    )

    #expect(secondOwnership.worktreePath != firstOwnership.worktreePath)
    #expect(secondOwnership.branch != firstOwnership.branch)
    #expect(secondHead == package.headRevision)
}

@MainActor
@Test
func handoffPackageIsDeliveredWithTheRecipientsNextMessage() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-handoff-\(UUID().uuidString)",
            isDirectory: true
        )
    defer { try? FileManager.default.removeItem(at: directory) }

    var source = BotProfile.defaults[0]
    source.workingDirectory = "/tmp/project"
    source.worktree = GitWorktreeOwnership(
        ownerProfileID: source.id,
        repositoryPath: "/tmp/project",
        worktreePath: "/tmp/project-builder",
        branch: "bl00p/source-12345678",
        baseRevision: "abc123"
    )
    let target = BotProfile.defaults[1]
    let package = GitHandoffPackage(
        sourceProfileID: source.id,
        sourceName: source.name,
        repositoryPath: "/tmp/project",
        worktreePath: "/tmp/project-builder",
        branch: "bl00p/source-12345678",
        baseRevision: "abc123",
        headRevision: "def456",
        taskContext: "Implement isolated worktrees",
        testStatus: .passed,
        testSummary: "`swift test` — passed",
        workingTreeSummary: "Clean"
    )
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    store.save(
        PersistedAppState(
            profiles: [source, target],
            sessions: [
                source.id: AgentSessionState(
                    status: .completed,
                    entries: [.init(kind: .user, text: package.taskContext)]
                ),
                target.id: AgentSessionState()
            ],
            selectedBotID: source.id
        )
    )
    let runtime = HandoffRecordingRuntime()
    let model = AppModel(
        runtime: runtime,
        worktrees: StubWorktreeManager(package: package),
        store: store
    )

    model.handoff(from: source.id, to: target.id)
    for _ in 0..<30
        where model.session(for: target.id).pendingHandoff == nil {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(model.selectedBotID == target.id)
    #expect(model.session(for: target.id).entries.last?.kind == .handoff)
    #expect(model.profiles.first(where: { $0.id == target.id })?.workingDirectory
        == package.worktreePath)

    model.send("Review this implementation", to: target.id)
    for _ in 0..<30 where await runtime.messages.isEmpty {
        try await Task.sleep(for: .milliseconds(10))
    }

    let delivered = try #require(await runtime.messages.first)
    #expect(delivered.contains("Source branch: \(package.branch)"))
    #expect(delivered.contains("Test state: Passed"))
    #expect(delivered.contains("Next instruction:\nReview this implementation"))
    #expect(model.session(for: target.id).pendingHandoff == nil)
}

@MainActor
@Test
func configuredManagerRunsTheOptionalDeliveryWorkflowEndToEnd() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-manager-workflow-\(UUID().uuidString)",
            isDirectory: true
        )
    defer { try? FileManager.default.removeItem(at: directory) }

    let builderID = UUID()
    let reviewerID = UUID()
    let publisherID = UUID()
    let managerID = UUID()
    let ownership = GitWorktreeOwnership(
        ownerProfileID: builderID,
        repositoryPath: "/tmp/project",
        worktreePath: "/tmp/.bl00p-worktrees/project-builder",
        branch: "bl00p/managed-feature",
        baseRevision: "abc123"
    )
    let package = GitHandoffPackage(
        sourceProfileID: builderID,
        sourceName: "Builder",
        repositoryPath: ownership.repositoryPath,
        worktreePath: ownership.worktreePath,
        branch: ownership.branch,
        baseRevision: ownership.baseRevision,
        headRevision: "def456",
        taskContext: "Add optional orchestration",
        testStatus: .passed,
        testSummary: "`swift test` — passed",
        workingTreeSummary: "Clean"
    )
    let manager = BotProfile(
        id: managerID,
        name: "Manager",
        provider: .codex,
        role: .manager,
        instructions: "Coordinate the team.",
        workingDirectory: "/tmp/project",
        managerTeam: ManagerTeamConfiguration(
            builderProfileID: builderID,
            reviewerProfileID: reviewerID,
            publisherProfileID: publisherID
        )
    )
    let builder = BotProfile(
        id: builderID,
        name: "Builder",
        provider: .claude,
        role: .builder,
        instructions: "Implement the work.",
        workingDirectory: "/tmp/project"
    )
    let reviewer = BotProfile(
        id: reviewerID,
        name: "Reviewer",
        provider: .codex,
        role: .reviewer,
        instructions: "Review the work.",
        workingDirectory: "/tmp/project"
    )
    let publisher = BotProfile(
        id: publisherID,
        name: "Documenter",
        provider: .claude,
        role: .publisher,
        instructions: "Document and publish the work.",
        workingDirectory: "/tmp/project"
    )
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    let olderManagerEntry = TimelineEntry(
        kind: .assistant,
        text: "Earlier unrelated Manager guidance."
    )
    var initialSessions = Dictionary(
        uniqueKeysWithValues: [manager, builder, reviewer, publisher]
            .map { ($0.id, AgentSessionState()) }
    )
    initialSessions[managerID] = AgentSessionState(
        entries: [olderManagerEntry]
    )
    store.save(
        PersistedAppState(
            profiles: [manager, builder, reviewer, publisher],
            sessions: initialSessions,
            selectedBotID: managerID
        )
    )
    let runtime = OrchestrationRecordingRuntime()
    let model = AppModel(
        runtime: runtime,
        worktrees: StubWorktreeManager(
            package: package,
            preparedOwnership: ownership
        ),
        store: store
    )

    model.send("Add optional orchestration", to: managerID)

    for _ in 0..<100
        where model.session(for: managerID).status != .needsApproval {
        try await Task.sleep(for: .milliseconds(10))
    }

    let awaitingApproval = try #require(model.workflow(for: managerID))
    let approvalEntry = try #require(
        model.session(for: managerID).entries.last(where: {
            $0.kind == .approval && $0.approvalState == .pending
        })
    )
    let planText = "Implement the feature with persistence and tests."
    let managerEntries = model.session(for: managerID).entries
    let displayedPlanEntries = managerEntries.filter {
        $0.text == planText
    }
    #expect(displayedPlanEntries.count == 1)
    #expect(displayedPlanEntries.first?.kind == .approval)
    #expect(displayedPlanEntries.first?.id == approvalEntry.id)
    #expect(managerEntries.contains(where: { $0.id == olderManagerEntry.id }))
    #expect(
        managerEntries.first(where: { $0.id == olderManagerEntry.id })?.text
            == olderManagerEntry.text
    )
    #expect(awaitingApproval.stage == .planning)
    #expect(awaitingApproval.isPaused)
    #expect(
        awaitingApproval.pauseReason
            == "Waiting for your approval of the implementation plan."
    )
    #expect(
        awaitingApproval.implementationPlan
            == planText
    )
    let planningCalls = await runtime.calls
    #expect(planningCalls.map(\.role) == [.manager])
    #expect(planningCalls[0].message.contains("planning phase"))
    #expect(planningCalls[0].message.contains("Do not edit files"))
    #expect(planningCalls[0].message.contains("spawn or delegate"))

    model.send("Looks good; start coding", to: managerID)
    #expect(await runtime.calls.map(\.role) == [.manager])
    #expect(model.session(for: managerID).status == .needsApproval)
    #expect(
        model.workflow(for: managerID)?.planApprovalEntryID
            == approvalEntry.id
    )

    model.resolveApproval(
        approvalEntry.id,
        approved: true,
        for: managerID
    )

    for _ in 0..<200
        where model.workflow(for: managerID)?.stage != .completed {
        try await Task.sleep(for: .milliseconds(10))
    }

    let workflow = try #require(model.workflow(for: managerID))
    let calls = await runtime.calls
    #expect(workflow.stage == .completed)
    #expect(workflow.branch == ownership.branch)
    #expect(
        workflow.pullRequestURL
            == "https://github.com/suttree/bl00p/pull/99"
    )
    #expect(
        calls.map(\.role)
            == [
                .manager,
                .builder,
                .reviewer,
                .builder,
                .reviewer,
                .publisher,
                .manager
            ]
    )
    #expect(calls[1].message.contains("Manager brief:"))
    #expect(calls[1].message.contains(planText))
    #expect(calls[2].message.contains("Source branch: \(ownership.branch)"))
    #expect(calls[3].message.contains("Review finding"))
    #expect(calls[4].message.contains("Re-check the updated"))
    #expect(calls[5].message.contains("create a draft pull request"))
    #expect(calls[6].message.contains("https://github.com/suttree/bl00p/pull/99"))
    #expect(await runtime.approvalResolutionCount == 0)
    #expect(
        model.profiles.first(where: { $0.id == reviewerID })?
            .workingDirectory == ownership.worktreePath
    )
    #expect(
        model.profiles.first(where: { $0.id == publisherID })?
            .workingDirectory == ownership.worktreePath
    )
}

@MainActor
@Test
func decliningAManagerPlanPausesBeforeAnyBuilderHandoff() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-manager-plan-decline-\(UUID().uuidString)",
            isDirectory: true
        )
    defer { try? FileManager.default.removeItem(at: directory) }

    var builder = BotProfile.defaults[0]
    var reviewer = BotProfile.defaults[1]
    var publisher = BotProfile.defaults[2]
    builder.id = UUID()
    reviewer.id = UUID()
    publisher.id = UUID()
    let manager = BotProfile(
        name: "Manager",
        provider: .codex,
        role: .manager,
        instructions: "Coordinate.",
        managerTeam: ManagerTeamConfiguration(
            builderProfileID: builder.id,
            reviewerProfileID: reviewer.id,
            publisherProfileID: publisher.id
        )
    )
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    store.save(
        PersistedAppState(
            profiles: [manager, builder, reviewer, publisher],
            sessions: Dictionary(
                uniqueKeysWithValues: [manager, builder, reviewer, publisher]
                    .map { ($0.id, AgentSessionState()) }
            ),
            selectedBotID: manager.id
        )
    )
    let runtime = OrchestrationRecordingRuntime()
    let model = AppModel(runtime: runtime, store: store)

    model.send("Plan this change", to: manager.id)
    for _ in 0..<100
        where model.session(for: manager.id).status != .needsApproval {
        try await Task.sleep(for: .milliseconds(10))
    }

    let approvalEntry = try #require(
        model.session(for: manager.id).entries.last(where: {
            $0.kind == .approval && $0.approvalState == .pending
        })
    )
    let initialPlan = "Implement the feature with persistence and tests."
    #expect(
        model.session(for: manager.id).entries.filter {
            $0.text == initialPlan
        }.map(\.kind) == [.approval]
    )
    let restoredModel = AppModel(runtime: runtime, store: store)
    #expect(restoredModel.session(for: manager.id).status == .needsApproval)
    #expect(
        restoredModel.workflow(for: manager.id)?.planApprovalEntryID
            == approvalEntry.id
    )

    restoredModel.resolveApproval(
        approvalEntry.id,
        approved: false,
        for: manager.id
    )

    let workflow = try #require(restoredModel.workflow(for: manager.id))
    let resolvedEntry = try #require(
        restoredModel.session(for: manager.id).entries.first(where: {
            $0.id == approvalEntry.id
        })
    )
    #expect(workflow.stage == .planning)
    #expect(workflow.isPaused)
    #expect(workflow.planApprovalEntryID == nil)
    #expect(
        workflow.pauseReason
            == "Plan declined. Send feedback to the Manager to request a revised plan."
    )
    #expect(resolvedEntry.approvalState == .declined)
    #expect(restoredModel.session(for: manager.id).status == .needsAnswer)
    #expect(await runtime.calls.map(\.role) == [.manager])
    #expect(await runtime.approvalResolutionCount == 0)

    let resolvedRestoredModel = AppModel(runtime: runtime, store: store)
    let restoredDeclinedEntry = try #require(
        resolvedRestoredModel.session(for: manager.id).entries.first(where: {
            $0.id == approvalEntry.id
        })
    )
    #expect(restoredDeclinedEntry.approvalState == .declined)
    #expect(
        resolvedRestoredModel.session(for: manager.id).entries.filter {
            $0.text == initialPlan
        }.map(\.kind) == [.approval]
    )

    resolvedRestoredModel.send(
        "Revise the plan to include restoration coverage",
        to: manager.id
    )
    for _ in 0..<100
        where resolvedRestoredModel.session(for: manager.id).status
            != .needsApproval {
        try await Task.sleep(for: .milliseconds(10))
    }

    let revisedPlan =
        "Revised plan: implement the feature with restoration coverage."
    let revisedApproval = try #require(
        resolvedRestoredModel.session(for: manager.id).entries.last(where: {
            $0.kind == .approval && $0.approvalState == .pending
        })
    )
    let revisedEntries = resolvedRestoredModel.session(for: manager.id).entries
    #expect(revisedApproval.text == revisedPlan)
    #expect(revisedEntries.filter { $0.text == revisedPlan }.count == 1)
    #expect(
        revisedEntries.filter { $0.kind == .approval }.map(\.approvalState)
            == [.declined, .pending]
    )
    #expect(
        revisedEntries.contains(where: {
            $0.kind == .assistant
                && ($0.text == initialPlan || $0.text == revisedPlan)
        }) == false
    )

    let revisedRestoredModel = AppModel(runtime: runtime, store: store)
    #expect(revisedRestoredModel.session(for: manager.id).status == .needsApproval)
    #expect(
        revisedRestoredModel.workflow(for: manager.id)?.implementationPlan
            == revisedPlan
    )
    #expect(
        revisedRestoredModel.session(for: manager.id).entries.first(where: {
            $0.id == revisedApproval.id
        })?.approvalState == .pending
    )
}

@MainActor
@Test
func managerWithoutATeamRemainsAStandaloneBot() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-standalone-manager-\(UUID().uuidString)",
            isDirectory: true
        )
    defer { try? FileManager.default.removeItem(at: directory) }

    let manager = BotProfile(
        name: "Solo Manager",
        provider: .codex,
        role: .manager,
        instructions: "Help plan work."
    )
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    store.save(
        PersistedAppState(
            profiles: [manager],
            sessions: [manager.id: AgentSessionState()],
            selectedBotID: manager.id
        )
    )
    let runtime = ImmediateRecordingRuntime()
    let model = AppModel(runtime: runtime, store: store)

    model.send("Help me scope this change", to: manager.id)
    for _ in 0..<30
        where model.session(for: manager.id).status != .completed {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(model.workflow(for: manager.id) == nil)
    #expect(await runtime.responseCount == 1)
    #expect(
        model.session(for: manager.id).entries.map(\.kind)
            == [.user, .assistant]
    )
}

@MainActor
@Test
func managedPublishingPausesUntilADraftPRURLIsReturned() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-publisher-gate-\(UUID().uuidString)",
            isDirectory: true
        )
    defer { try? FileManager.default.removeItem(at: directory) }

    var builder = BotProfile.defaults[0]
    var reviewer = BotProfile.defaults[1]
    var publisher = BotProfile.defaults[2]
    builder.id = UUID()
    reviewer.id = UUID()
    publisher.id = UUID()
    let team = ManagerTeamConfiguration(
        builderProfileID: builder.id,
        reviewerProfileID: reviewer.id,
        publisherProfileID: publisher.id
    )
    let manager = BotProfile(
        name: "Manager",
        provider: .codex,
        role: .manager,
        instructions: "Coordinate.",
        managerTeam: team
    )
    let workflow = ManagerWorkflow(
        managerProfileID: manager.id,
        team: team,
        request: "Ship the feature",
        stage: .publishing
    )
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    store.save(
        PersistedAppState(
            profiles: [manager, builder, reviewer, publisher],
            sessions: [
                manager.id: AgentSessionState(),
                builder.id: AgentSessionState(),
                reviewer.id: AgentSessionState(),
                publisher.id: AgentSessionState()
            ],
            selectedBotID: publisher.id,
            managerWorkflows: [manager.id: workflow]
        )
    )
    let model = AppModel(
        runtime: ImmediateRecordingRuntime(),
        store: store
    )

    model.send("Finish publishing", to: publisher.id)
    for _ in 0..<30
        where model.session(for: publisher.id).status != .completed {
        try await Task.sleep(for: .milliseconds(10))
    }

    let paused = try #require(model.workflow(for: manager.id))
    #expect(paused.stage == .publishing)
    #expect(paused.isPaused)
    #expect(paused.pauseReason?.contains("without a draft PR URL") == true)
    #expect(
        model.session(for: publisher.id).entries.last?.title
            == "Draft PR URL required"
    )
}

@MainActor
@Test
func deletingAnAssignedBotClearsTheManagersStaleTeamReference() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-manager-delete-\(UUID().uuidString)",
            isDirectory: true
        )
    defer { try? FileManager.default.removeItem(at: directory) }

    var builder = BotProfile.defaults[0]
    var reviewer = BotProfile.defaults[1]
    var publisher = BotProfile.defaults[2]
    builder.id = UUID()
    reviewer.id = UUID()
    publisher.id = UUID()
    let manager = BotProfile(
        name: "Manager",
        provider: .codex,
        role: .manager,
        instructions: "Coordinate.",
        managerTeam: ManagerTeamConfiguration(
            builderProfileID: builder.id,
            reviewerProfileID: reviewer.id,
            publisherProfileID: publisher.id
        )
    )
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    store.save(
        PersistedAppState(
            profiles: [manager, builder, reviewer, publisher],
            sessions: Dictionary(
                uniqueKeysWithValues: [manager, builder, reviewer, publisher]
                    .map { ($0.id, AgentSessionState()) }
            ),
            selectedBotID: manager.id
        )
    )
    let model = AppModel(runtime: DemoAgentRuntime(), store: store)

    model.delete(builder.id)

    let updatedManager = try #require(
        model.profiles.first(where: { $0.id == manager.id })
    )
    #expect(updatedManager.managerTeam?.builderProfileID == nil)
    #expect(updatedManager.managerTeam?.reviewerProfileID == reviewer.id)
    #expect(updatedManager.managerTeam?.publisherProfileID == publisher.id)
    #expect(!model.isManagerTeamReady(manager.id))
    #expect(
        store.load()?
            .profiles
            .first(where: { $0.id == manager.id })?
            .managerTeam?
            .builderProfileID == nil
    )
}

@MainActor
@Test
func implementationBotRunsInsideItsOwnedWorktree() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-owned-worktree-\(UUID().uuidString)",
            isDirectory: true
        )
    defer { try? FileManager.default.removeItem(at: directory) }

    var profile = BotProfile.defaults[0]
    profile.workingDirectory = "/tmp/project"
    let ownership = GitWorktreeOwnership(
        ownerProfileID: profile.id,
        repositoryPath: "/tmp/project",
        worktreePath: "/tmp/.bl00p-worktrees/project-builder",
        branch: "bl00p/builder-12345678",
        baseRevision: "abc123"
    )
    let package = GitHandoffPackage(
        sourceProfileID: profile.id,
        sourceName: profile.name,
        repositoryPath: ownership.repositoryPath,
        worktreePath: ownership.worktreePath,
        branch: ownership.branch,
        baseRevision: ownership.baseRevision,
        headRevision: "def456",
        taskContext: "Implement the feature",
        testStatus: .notRun,
        testSummary: "No test command was recorded.",
        workingTreeSummary: "Clean"
    )
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    store.save(
        PersistedAppState(
            profiles: [profile],
            sessions: [profile.id: AgentSessionState()],
            selectedBotID: profile.id
        )
    )
    let runtime = HandoffRecordingRuntime()
    let model = AppModel(
        runtime: runtime,
        worktrees: StubWorktreeManager(
            package: package,
            preparedOwnership: ownership
        ),
        store: store
    )

    model.send("Implement the feature", to: profile.id)
    for _ in 0..<30 where await runtime.respondedDirectories.isEmpty {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(await runtime.startedDirectories == [ownership.worktreePath])
    #expect(await runtime.respondedDirectories == [ownership.worktreePath])
    #expect(model.profiles.first?.worktree == ownership)
    #expect(model.profiles.first?.workingDirectory == ownership.repositoryPath)
}

@Test
func appStateStoreReadsWhatItWrites() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-tests-\(UUID().uuidString)", isDirectory: true)
    let fileURL = directory.appendingPathComponent("state.json")
    let profile = BotProfile.defaults[1]
    let expected = PersistedAppState(
        profiles: [profile],
        sessions: [
            profile.id: AgentSessionState(
                status: .needsAnswer,
                entries: [TimelineEntry(kind: .question, text: "Which PR?")],
                sessionID: "session-2"
            )
        ],
        selectedBotID: profile.id
    )
    let store = AppStateStore(fileURL: fileURL)

    store.save(expected)
    let actual = try #require(store.load())

    #expect(actual.selectedBotID == expected.selectedBotID)
    #expect(actual.sessions[profile.id]?.entries.first?.timestamp != nil)
    #expect(actual.sessions[profile.id]?.entries.first?.text == "Which PR?")

    try? FileManager.default.removeItem(at: directory)
}

@Test
func jsonValuePreservesRPCPayloads() throws {
    let source = """
    {"id":7,"result":{"thread":{"id":"thr_123"}},"ok":true}
    """
    let value = try JSONDecoder().decode(
        JSONValue.self,
        from: Data(source.utf8)
    )

    #expect(value["id"]?.intValue == 7)
    #expect(value["id"]?.requestIDKey == "n:7")
    #expect(value["result"]?["thread"]?["id"]?.stringValue == "thr_123")
    #expect(value["ok"]?.boolValue == true)
}

@Test
func jsonValueAcceptsFoundationJSONObjects() throws {
    let data = Data(
        """
        {"method":"turn/completed","params":{"count":2,"ready":false,"error":null}}
        """.utf8
    )
    let raw = try JSONSerialization.jsonObject(with: data)
    let value = try JSONValue(any: raw)

    #expect(value["method"]?.stringValue == "turn/completed")
    #expect(value["params"]?["count"]?.intValue == 2)
    #expect(value["params"]?["ready"]?.boolValue == false)
    #expect(value["params"]?["error"] == .null)
}

@Test
func locatesBundledCodexBeforeBrokenShellShims() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-codex-locator-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let bundled = directory
        .appendingPathComponent("ChatGPT.app/Contents/Resources/codex")
    let shellShim = directory.appendingPathComponent("bin/codex")
    try makeExecutable(at: bundled)
    try makeExecutable(at: shellShim)

    let url = try #require(
        CodexExecutableLocator(candidateURLs: [bundled, shellShim]).locate()
    )
    #expect(url == bundled)
}

@Test
func locatesInstalledClaudeCLI() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-claude-locator-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("bin/claude")
    try makeExecutable(at: executable)

    let url = try #require(
        ClaudeExecutableLocator(candidateURLs: [executable]).locate()
    )
    #expect(url.lastPathComponent == "claude")
    #expect(FileManager.default.isExecutableFile(atPath: url.path))
}

private func makeExecutable(at url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: url.path
    )
}

@Test
func claudeBuilderInvocationIsResumableAndConservative() throws {
    var profile = BotProfile.defaults[0]
    profile.workingDirectory = "/tmp/project"
    let invocation = try ClaudeInvocation(
        sessionID: "64bfaf39-9db2-45b9-9f10-03a13ea2e772",
        resume: false,
        profile: profile,
        prompt: "Implement BLOOP-42"
    )

    #expect(invocation.arguments.contains("--session-id"))
    #expect(!invocation.arguments.contains("--resume"))
    #expect(invocation.arguments.contains("Edit"))
    #expect(invocation.arguments.contains("Write"))
    #expect(invocation.arguments.contains("Bash(swift test:*)"))
    #expect(invocation.arguments.contains("Bash(xcrun swift test:*)"))
    #expect(invocation.arguments.contains("--input-format"))
    #expect(invocation.arguments.contains("--permission-prompt-tool"))
    #expect(invocation.arguments.contains("stdio"))
    #expect(!invocation.arguments.contains("dontAsk"))
    let toolRules = invocation.arguments.filter { $0.hasPrefix("Bash(") }
    #expect(!toolRules.contains(where: { $0.contains("git push") }))
    #expect(!toolRules.contains(where: { $0.contains("git reset") }))
    #expect(
        invocation.inputMessage["message"]?["content"]?.stringValue
            == "Implement BLOOP-42"
    )
}

@Test
func claudeReviewerInvocationStaysReadOnly() throws {
    let profile = BotProfile.defaults[1]
    let invocation = try ClaudeInvocation(
        sessionID: "64bfaf39-9db2-45b9-9f10-03a13ea2e772",
        resume: true,
        profile: profile,
        prompt: "Review HEAD"
    )

    #expect(invocation.arguments.contains("--resume"))
    #expect(!invocation.arguments.contains("--session-id"))
    #expect(!invocation.arguments.contains("Edit"))
    #expect(!invocation.arguments.contains("Write"))
    #expect(invocation.arguments.contains("Read"))
    #expect(invocation.arguments.contains("Bash(git diff:*)"))
}

@Test
func claudeInvocationPassesTheSelectedModelAndAttachedImages() throws {
    var profile = BotProfile.defaults[0]
    profile.modelID = "sonnet"

    let sourceDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00pTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: sourceDirectory) }
    let sourceFile = sourceDirectory.appendingPathComponent("failure.png")
    try Data("fake image".utf8).write(to: sourceFile)

    let invocation = try ClaudeInvocation(
        sessionID: "64bfaf39-9db2-45b9-9f10-03a13ea2e772",
        resume: false,
        profile: profile,
        prompt: "What is wrong with this screenshot?",
        attachments: [
            ImageAttachment(path: sourceFile.path)
        ]
    )
    defer {
        if let directory = invocation.stagedAttachmentDirectory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    #expect(invocation.arguments.contains("--model"))
    #expect(invocation.arguments.contains("sonnet"))
    #expect(invocation.arguments.contains("--add-dir"))
    #expect(!invocation.arguments.contains(sourceDirectory.path))
    let input = try #require(
        invocation.inputMessage["message"]?["content"]?.stringValue
    )
    #expect(input.contains("failure.png"))
    #expect(!input.contains(sourceFile.path))
}

@Test
func claudeToolApprovalsUseTheSDKControlProtocol() throws {
    let request = try JSONDecoder().decode(
        JSONValue.self,
        from: Data(
            """
            {
              "subtype": "can_use_tool",
              "tool_name": "Bash",
              "input": {
                "command": "git push origin feature/example",
                "description": "Push the feature branch"
              },
              "title": "Claude wants to push a branch",
              "display_name": "Push branch",
              "description": "Publishes local commits to GitHub",
              "decision_reason": "Git operations require approval",
              "blocked_path": "/tmp/project/.git",
              "tool_use_id": "toolu_123"
            }
            """.utf8
        )
    )
    let approval = try #require(ClaudeToolApprovalRequest(request: request))
    let entry = approval.timelineEntry(
        id: UUID(uuidString: "BD1F67B4-F1B8-48EE-89B9-D68B3510A0A7")!
    )

    #expect(entry.kind == .approval)
    #expect(entry.title == "Push branch")
    #expect(entry.text == "git push origin feature/example")
    #expect(entry.detail?.contains("Git operations require approval") == true)
    #expect(entry.approvalState == .pending)
    #expect(
        ClaudeToolApprovalResponse.result(
            approved: true,
            toolInput: approval.toolInput
        ) == .object([
            "behavior": .string("allow"),
            "updatedInput": approval.toolInput
        ])
    )
    #expect(
        ClaudeToolApprovalResponse.result(
            approved: false,
            toolInput: approval.toolInput
        ) == .object([
            "behavior": .string("deny"),
            "message": .string("The user declined this action in bl00p.")
        ])
    )
}

@Test
func claudeCLIClientCompletesThePermissionRoundTrip() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-claude-control-\(UUID().uuidString)",
            isDirectory: true
        )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("fake-claude")
    try """
    #!/usr/bin/env python3
    import json
    import sys

    for line in sys.stdin:
        message = json.loads(line)
        if message.get("type") == "control_request":
            request = message.get("request", {})
            if request.get("subtype") == "initialize":
                print(json.dumps({
                    "type": "control_response",
                    "response": {
                        "subtype": "success",
                        "request_id": message["request_id"],
                        "response": {"commands": []}
                    }
                }), flush=True)
        elif message.get("type") == "user":
            print(json.dumps({
                "type": "control_request",
                "request_id": "permission-1",
                "request": {
                    "subtype": "can_use_tool",
                    "tool_name": "Bash",
                    "input": {"command": "git push origin feature/example"},
                    "tool_use_id": "toolu_1"
                }
            }), flush=True)
        elif message.get("type") == "control_response":
            behavior = message["response"]["response"]["behavior"]
            print(json.dumps({
                "type": "result",
                "is_error": False,
                "result": behavior,
                "permission_denials": []
            }), flush=True)
            break
    """.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: executable.path
    )

    let client = ClaudeCLIClient(executableURL: executable)
    try await client.connect(arguments: [], workingDirectory: directory)
    try await client.send(
        .object([
            "type": .string("user"),
            "message": .object([
                "role": .string("user"),
                "content": .string("Publish the branch")
            ])
        ])
    )

    var receivedPermission = false
    var receivedResult: String?
    for await message in client.messages {
        if message["type"]?.stringValue == "control_request" {
            receivedPermission = true
            try await client.respond(
                to: "permission-1",
                result: ClaudeToolApprovalResponse.result(
                    approved: true,
                    toolInput: .object([
                        "command": .string("git push origin feature/example")
                    ])
                )
            )
        } else if message["type"]?.stringValue == "result" {
            receivedResult = message["result"]?.stringValue
            break
        }
    }
    await client.stop()

    #expect(receivedPermission)
    #expect(receivedResult == "allow")
}

@Test
func missingClaudeConversationTriggersFreshSessionRecovery() throws {
    let event = try JSONDecoder().decode(
        JSONValue.self,
        from: Data(
            """
            {
              "type": "result",
              "is_error": true,
              "num_turns": 0,
              "duration_api_ms": 0,
              "errors": ["No conversation found with session ID: missing"]
            }
            """.utf8
        )
    )

    #expect(ClaudeResumeRecovery.shouldStartFresh(after: event))
}

@Test
func ordinaryClaudeTurnFailureDoesNotDiscardTheSession() throws {
    let event = try JSONDecoder().decode(
        JSONValue.self,
        from: Data(
            """
            {
              "type": "result",
              "is_error": true,
              "num_turns": 1,
              "duration_api_ms": 250,
              "errors": ["The request failed after starting"]
            }
            """.utf8
        )
    )

    #expect(!ClaudeResumeRecovery.shouldStartFresh(after: event))
}

@Test
func earlyUnrelatedFailureDoesNotDiscardTheSession() throws {
    let event = try JSONDecoder().decode(
        JSONValue.self,
        from: Data(
            """
            {
              "type": "result",
              "is_error": true,
              "num_turns": 0,
              "duration_api_ms": 0,
              "errors": ["Invalid model: not-a-real-model"]
            }
            """.utf8
        )
    )

    #expect(!ClaudeResumeRecovery.shouldStartFresh(after: event))
}

@Test
func permissionDenialsProduceAReadableAttentionState() throws {
    let denial = try JSONDecoder().decode(
        JSONValue.self,
        from: Data(
            """
            {
              "tool_name": "Bash",
              "tool_input": {
                "description": "Run tests using Xcode",
                "command": "xcrun swift test"
              }
            }
            """.utf8
        )
    )

    #expect(
        ClaudeTurnOutcome.status(
            failed: false,
            permissionDenials: [denial]
        ) == .needsAnswer
    )
    #expect(
        ClaudePermissionDenials.readableDetail(for: [denial])
            == "• Run tests using Xcode\n  xcrun swift test"
    )
}

@MainActor
@Test
func activeSessionsRestoreAsStopped() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-restore-\(UUID().uuidString)", isDirectory: true)
    let profile = BotProfile.defaults[1]
    let store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    store.save(
        PersistedAppState(
            profiles: [profile],
            sessions: [
                profile.id: AgentSessionState(
                    status: .working,
                    entries: [],
                    sessionID: "thread-to-resume",
                    codexTurnModeVersion: CodexThreadConfiguration.turnModeVersion
                )
            ],
            selectedBotID: profile.id
        )
    )

    let model = AppModel(runtime: DemoAgentRuntime(), store: store)

    #expect(model.session(for: profile.id).status == .stopped)
    #expect(model.session(for: profile.id).sessionID == "thread-to-resume")
    try? FileManager.default.removeItem(at: directory)
}

@MainActor
@Test
func legacyCodexReviewThreadsRestartWithoutLosingTheirTranscript() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-codex-mode-\(UUID().uuidString)", isDirectory: true)
    let profile = BotProfile.defaults[1]
    let store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    store.save(
        PersistedAppState(
            profiles: [profile],
            sessions: [
                profile.id: AgentSessionState(
                    status: .completed,
                    entries: [.init(kind: .assistant, text: "Previous review output")],
                    sessionID: "legacy-review-thread"
                )
            ],
            selectedBotID: profile.id
        )
    )

    let model = AppModel(runtime: DemoAgentRuntime(), store: store)
    let restored = model.session(for: profile.id)

    #expect(restored.sessionID == nil)
    #expect(restored.status == .stopped)
    #expect(restored.entries.map(\.text) == ["Previous review output"])
    try? FileManager.default.removeItem(at: directory)
}

@MainActor
@Test
func codexThreadsFromAnOlderPermissionBoundaryStartFresh() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-codex-permissions-\(UUID().uuidString)", isDirectory: true)
    let profile = BotProfile.defaults[1]
    let store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    store.save(
        PersistedAppState(
            profiles: [profile],
            sessions: [
                profile.id: AgentSessionState(
                    status: .completed,
                    entries: [.init(kind: .assistant, text: "Keep this transcript")],
                    sessionID: "read-only-thread",
                    codexTurnModeVersion: CodexThreadConfiguration.turnModeVersion - 1
                )
            ],
            selectedBotID: profile.id
        )
    )

    let model = AppModel(runtime: DemoAgentRuntime(), store: store)
    let restored = model.session(for: profile.id)

    #expect(restored.sessionID == nil)
    #expect(restored.status == .stopped)
    #expect(restored.entries.map(\.text) == ["Keep this transcript"])
    try? FileManager.default.removeItem(at: directory)
}

@MainActor
@Test
func prototypeStarterCardsAreRemovedWhenStateIsRestored() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-starters-\(UUID().uuidString)", isDirectory: true)
    let profile = BotProfile.defaults[1]
    let store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    store.save(
        PersistedAppState(
            profiles: [profile],
            sessions: [
                profile.id: AgentSessionState(
                    status: .needsAnswer,
                    entries: [
                        TimelineEntry(
                            kind: .system,
                            text: "Resumed Codex review session"
                        ),
                        TimelineEntry(
                            kind: .question,
                            title: "What should I review?",
                            text: "Which PR?"
                        ),
                        TimelineEntry(
                            kind: .assistant,
                            text: "A real saved response"
                        )
                    ]
                )
            ],
            selectedBotID: profile.id
        )
    )

    let model = AppModel(runtime: DemoAgentRuntime(), store: store)

    #expect(model.session(for: profile.id).entries.count == 1)
    #expect(model.session(for: profile.id).entries.first?.text == "A real saved response")
    try? FileManager.default.removeItem(at: directory)
}

@MainActor
@Test
func legacyPermissionBoundaryIsRestoredAsReadableAttention() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-permission-\(UUID().uuidString)", isDirectory: true)
    let profile = BotProfile.defaults[0]
    let store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    let rawDenial = """
    {"tool_name":"Bash","tool_input":{"description":"Run tests","command":"xcrun swift test"}}
    """
    store.save(
        PersistedAppState(
            profiles: [profile],
            sessions: [
                profile.id: AgentSessionState(
                    status: .completed,
                    entries: [
                        TimelineEntry(kind: .assistant, text: "Changes applied."),
                        TimelineEntry(
                            kind: .system,
                            text: "Claude stopped at a permission boundary",
                            detail: rawDenial
                        )
                    ],
                    sessionID: "permission-session"
                )
            ],
            selectedBotID: profile.id
        )
    )

    let model = AppModel(runtime: DemoAgentRuntime(), store: store)
    let session = model.session(for: profile.id)

    #expect(session.status == .needsAnswer)
    #expect(session.entries.last?.kind == .question)
    #expect(session.entries.last?.title == "Some actions were blocked")
    #expect(session.entries.last?.detail?.contains("xcrun swift test") == true)
    #expect(session.entries.last?.detail?.contains("tool_input") == false)
    try? FileManager.default.removeItem(at: directory)
}

@MainActor
@Test
func legacyDefaultNamesMigrateButCustomNamesRemain() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-names-\(UUID().uuidString)", isDirectory: true)
    let store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    var builder = BotProfile.defaults[0]
    builder.name = "Claude Builder"
    var reviewer = BotProfile.defaults[1]
    reviewer.name = "Security pass"
    store.save(
        PersistedAppState(
            profiles: [builder, reviewer],
            sessions: [
                builder.id: AgentSessionState(),
                reviewer.id: AgentSessionState()
            ],
            selectedBotID: builder.id
        )
    )

    let model = AppModel(runtime: DemoAgentRuntime(), store: store)

    #expect(model.profiles[0].name == "Claude")
    #expect(model.profiles[1].name == "Security pass")
    try? FileManager.default.removeItem(at: directory)
}

@MainActor
@Test
func renamingABotTrimsAndPersistsTheName() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-rename-\(UUID().uuidString)", isDirectory: true)
    let store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    let model = AppModel(runtime: DemoAgentRuntime(), store: store)
    let profileID = try #require(model.profiles.first?.id)

    model.rename(profileID, to: "  Release notes  ")

    #expect(model.profiles.first?.name == "Release notes")
    #expect(store.load()?.profiles.first?.name == "Release notes")
    try? FileManager.default.removeItem(at: directory)
}

@MainActor
@Test
func firstMessageLaunchesAStoppedBotWithoutAddingAQuestionCard() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-autolaunch-\(UUID().uuidString)", isDirectory: true)
    let runtime = ImmediateRecordingRuntime()
    let model = AppModel(
        runtime: runtime,
        store: AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    )
    let profileID = try #require(model.profiles.first?.id)

    model.send("Inspect the repository", to: profileID)

    for _ in 0..<20 where model.session(for: profileID).status != .completed {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(await runtime.startCount == 1)
    #expect(await runtime.responseCount == 1)
    #expect(model.session(for: profileID).status == .completed)
    #expect(
        model.session(for: profileID).entries.map(\.kind)
            == [.user, .assistant]
    )
    try? FileManager.default.removeItem(at: directory)
}

@MainActor
@Test
func resumingAStoppedBotKeepsItsExistingTranscript() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-resume-\(UUID().uuidString)", isDirectory: true)
    let profile = BotProfile.defaults[0]
    let store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    store.save(
        PersistedAppState(
            profiles: [profile],
            sessions: [
                profile.id: AgentSessionState(
                    status: .stopped,
                    entries: [.init(kind: .assistant, text: "Earlier answer")],
                    sessionID: "existing-session"
                )
            ],
            selectedBotID: profile.id
        )
    )
    let runtime = ImmediateRecordingRuntime()
    let model = AppModel(runtime: runtime, store: store)

    model.send("Continue", to: profile.id)

    for _ in 0..<20 where model.session(for: profile.id).status != .completed {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(
        model.session(for: profile.id).entries.map(\.text)
            == ["Earlier answer", "Continue", "Working on Continue"]
    )
    try? FileManager.default.removeItem(at: directory)
}

@MainActor
@Test
func persistedCompletedBotReconnectsBeforeItsNextMessage() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-reconnect-\(UUID().uuidString)", isDirectory: true)
    let profile = BotProfile.defaults[0]
    let store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    store.save(
        PersistedAppState(
            profiles: [profile],
            sessions: [
                profile.id: AgentSessionState(
                    status: .completed,
                    entries: [.init(kind: .assistant, text: "Previous result")],
                    sessionID: "persisted-session"
                )
            ],
            selectedBotID: profile.id
        )
    )
    let runtime = ImmediateRecordingRuntime()
    let model = AppModel(runtime: runtime, store: store)

    model.send("Resume this work", to: profile.id)

    for _ in 0..<20 where model.session(for: profile.id).status != .completed {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(await runtime.startCount == 1)
    #expect(await runtime.responseCount == 1)
    #expect(
        model.session(for: profile.id).entries.map(\.text)
            == ["Previous result", "Resume this work", "Working on Resume this work"]
    )
    try? FileManager.default.removeItem(at: directory)
}

@MainActor
@Test
func aLongLivedStartupStreamDoesNotBlockTheFirstTurn() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-startup-stream-\(UUID().uuidString)", isDirectory: true)
    let runtime = LongLivedStartupRuntime()
    let model = AppModel(
        runtime: runtime,
        store: AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    )
    let profileID = try #require(model.profiles.first?.id)

    model.send("Run the review", to: profileID)

    for _ in 0..<30 where model.session(for: profileID).status != .completed {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(await runtime.responseCount == 1)
    #expect(model.session(for: profileID).status == .completed)
    #expect(model.session(for: profileID).entries.last?.text == "Review started")
    try? FileManager.default.removeItem(at: directory)
}

@MainActor
@Test
func failedMessageCanRetryInPlaceWithItsAttachments() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-retry-\(UUID().uuidString)", isDirectory: true)
    let runtime = FailOnceRuntime()
    let profile = BotProfile.defaults[0]
    let earlierEntry = TimelineEntry(kind: .user, text: "Earlier message")
    let store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    store.save(
        PersistedAppState(
            profiles: [profile],
            sessions: [
                profile.id: AgentSessionState(entries: [earlierEntry])
            ],
            selectedBotID: profile.id
        )
    )
    let model = AppModel(
        runtime: runtime,
        store: store
    )
    let profileID = profile.id
    let attachment = ImageAttachment(path: "/tmp/retry-screenshot.png")

    model.send(
        "Try this once more",
        attachments: [attachment],
        to: profileID
    )

    for _ in 0..<30 where model.session(for: profileID).status != .failed {
        try await Task.sleep(for: .milliseconds(10))
    }

    let failedEntry = try #require(
        model.session(for: profileID).entries.last(where: { $0.kind == .user })
    )
    #expect(failedEntry.id != earlierEntry.id)
    #expect(failedEntry.deliveryFailed == true)
    #expect(
        model.session(for: profileID).entries.first(where: {
            $0.id == earlierEntry.id
        })?.deliveryFailed != true
    )

    model.retry(failedEntry.id, for: profileID)

    for _ in 0..<30 where model.session(for: profileID).status != .completed {
        try await Task.sleep(for: .milliseconds(10))
    }

    let session = model.session(for: profileID)
    let userEntries = session.entries.filter { $0.kind == .user }
    #expect(session.status == .completed)
    #expect(userEntries.count == 2)
    #expect(userEntries.filter { $0.id == failedEntry.id }.count == 1)
    #expect(
        userEntries.first(where: { $0.id == failedEntry.id })?.deliveryFailed
            != true
    )
    #expect(
        userEntries.first(where: { $0.id == failedEntry.id })?.attachments
            == [attachment]
    )
    #expect(await runtime.messages == ["Try this once more", "Try this once more"])
    #expect(await runtime.attachments == [[attachment], [attachment]])
    try? FileManager.default.removeItem(at: directory)
}

@MainActor
@Test
func pendingQuestionAndApprovalStatesBlockFailedMessageRetry() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-blocked-retry-\(UUID().uuidString)",
            isDirectory: true
        )
    let runtime = ImmediateRecordingRuntime()
    let model = AppModel(
        runtime: runtime,
        store: AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    )
    let profileID = try #require(model.profiles.first?.id)
    let failedEntry = TimelineEntry(
        kind: .user,
        text: "Do not resend this",
        deliveryFailed: true
    )

    for status in [AgentStatus.needsAnswer, .needsApproval] {
        model.sessions[profileID] = AgentSessionState(
            status: status,
            entries: [failedEntry]
        )

        #expect(!status.allowsFailedMessageRetry)
        model.retry(failedEntry.id, for: profileID)
        #expect(model.session(for: profileID).status == status)
        #expect(
            model.session(for: profileID).entries.first?.deliveryFailed == true
        )
    }

    #expect(await runtime.startCount == 0)
    #expect(await runtime.responseCount == 0)
    try? FileManager.default.removeItem(at: directory)
}

@MainActor
@Test
func anotherRetryFailureKeepsTheSameBubbleRetryable() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-repeat-retry-\(UUID().uuidString)",
            isDirectory: true
        )
    let runtime = FailOnceRuntime(failuresBeforeSuccess: 2)
    let model = AppModel(
        runtime: runtime,
        store: AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    )
    let profileID = try #require(model.profiles.first?.id)

    model.send("Still failing", to: profileID)
    for _ in 0..<30 where model.session(for: profileID).status != .failed {
        try await Task.sleep(for: .milliseconds(10))
    }
    let entryID = try #require(model.session(for: profileID).entries.first?.id)

    model.retry(entryID, for: profileID)
    for _ in 0..<30 {
        if await runtime.messages.count == 2,
           model.session(for: profileID).status == .failed {
            break
        }
        try await Task.sleep(for: .milliseconds(10))
    }

    let userEntries = model.session(for: profileID).entries.filter {
        $0.kind == .user
    }
    #expect(userEntries.count == 1)
    #expect(userEntries.first?.id == entryID)
    #expect(userEntries.first?.deliveryFailed == true)
    #expect(await runtime.messages == ["Still failing", "Still failing"])
    try? FileManager.default.removeItem(at: directory)
}

@MainActor
@Test
func idleDisconnectDoesNotMakeACompletedMessageRetryable() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-idle-disconnect-\(UUID().uuidString)",
            isDirectory: true
        )
    let runtime = LongLivedStartupRuntime()
    let model = AppModel(
        runtime: runtime,
        store: AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    )
    let profileID = try #require(model.profiles.first?.id)

    model.send("Complete before disconnecting", to: profileID)

    for _ in 0..<30 where model.session(for: profileID).status != .completed {
        try await Task.sleep(for: .milliseconds(10))
    }
    await runtime.disconnect()
    for _ in 0..<30 where model.session(for: profileID).status != .failed {
        try await Task.sleep(for: .milliseconds(10))
    }

    let userEntry = try #require(
        model.session(for: profileID).entries.first(where: { $0.kind == .user })
    )
    #expect(model.session(for: profileID).status == .failed)
    #expect(userEntry.deliveryFailed != true)
    try? FileManager.default.removeItem(at: directory)
}

private func runGit(_ arguments: [String], in directory: URL) throws {
    _ = try gitOutput(arguments, in: directory)
}

private func gitOutput(_ arguments: [String], in directory: URL) throws -> String {
    let process = Process()
    let output = Pipe()
    let error = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = directory
    process.standardOutput = output
    process.standardError = error
    try process.run()
    process.waitUntilExit()

    let standardOutput = String(
        data: output.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
    ) ?? ""
    let standardError = String(
        data: error.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
    ) ?? ""
    guard process.terminationStatus == 0 else {
        throw GitWorktreeError.commandFailed(
            standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
    return standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
}

private actor StubWorktreeManager: GitWorktreeManaging {
    let package: GitHandoffPackage
    let preparedOwnership: GitWorktreeOwnership?

    init(
        package: GitHandoffPackage,
        preparedOwnership: GitWorktreeOwnership? = nil
    ) {
        self.package = package
        self.preparedOwnership = preparedOwnership
    }

    func prepareWorktree(
        for profile: BotProfile,
        startingPoint: String?,
        handoffID: UUID?
    ) async throws -> GitWorktreeOwnership {
        try #require(preparedOwnership ?? profile.worktree)
    }

    func makeHandoff(
        from profile: BotProfile,
        session: AgentSessionState
    ) async throws -> GitHandoffPackage {
        package
    }
}

private actor HandoffRecordingRuntime: AgentRuntime {
    private(set) var messages: [String] = []
    private(set) var startedDirectories: [String] = []
    private(set) var respondedDirectories: [String] = []

    func start(
        profile: BotProfile,
        resumeThreadID: String?
    ) async -> AsyncStream<AgentEvent> {
        startedDirectories.append(profile.workingDirectory)
        return AsyncStream { continuation in
            continuation.yield(.sessionID("handoff-session"))
            continuation.yield(.status(.needsAnswer))
            continuation.finish()
        }
    }

    func respond(
        to message: String,
        attachments: [ImageAttachment],
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent> {
        messages.append(message)
        respondedDirectories.append(profile.workingDirectory)
        return AsyncStream { continuation in
            continuation.yield(.status(.completed))
            continuation.finish()
        }
    }

    func resolveApproval(
        entryID: UUID,
        approved: Bool,
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent> {
        AsyncStream { $0.finish() }
    }

    func stop(profile: BotProfile) async {}
}

private actor OrchestrationRecordingRuntime: AgentRuntime {
    struct Call: Sendable {
        let role: AgentRole
        let message: String
    }

    private(set) var calls: [Call] = []
    private(set) var approvalResolutionCount = 0
    private var roleResponseCounts: [AgentRole: Int] = [:]

    func start(
        profile: BotProfile,
        resumeThreadID: String?
    ) async -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            continuation.yield(
                .sessionID(
                    resumeThreadID
                        ?? "workflow-\(profile.id.uuidString)"
                )
            )
            continuation.yield(.status(.needsAnswer))
            continuation.finish()
        }
    }

    func respond(
        to message: String,
        attachments: [ImageAttachment],
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent> {
        calls.append(.init(role: profile.role, message: message))
        let count = roleResponseCounts[profile.role, default: 0]
        roleResponseCounts[profile.role] = count + 1

        let response: String
        switch profile.role {
        case .manager:
            if message.contains("planning phase") {
                response = count == 0
                    ? "Implement the feature with persistence and tests."
                    : "Revised plan: implement the feature with restoration coverage."
            } else {
                response =
                    "Complete: [draft PR](https://github.com/suttree/bl00p/pull/99)"
            }
        case .builder:
            response = count == 0
                ? "Implementation committed and tests passed."
                : "Review finding fixed, committed, and tests passed."
        case .reviewer:
            response = count == 0
                ? "Review finding: add a regression test."
                : "Review clean. Ready to publish."
        case .publisher:
            response = "Documentation committed. Draft PR: https://github.com/suttree/bl00p/pull/99"
        }

        return AsyncStream { continuation in
            continuation.yield(.status(.working))
            continuation.yield(
                .entry(.init(kind: .assistant, text: response))
            )
            continuation.yield(.status(.completed))
            continuation.finish()
        }
    }

    func resolveApproval(
        entryID: UUID,
        approved: Bool,
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent> {
        approvalResolutionCount += 1
        return AsyncStream { $0.finish() }
    }

    func stop(profile: BotProfile) async {}
}

private actor ImmediateRecordingRuntime: AgentRuntime {
    private(set) var startCount = 0
    private(set) var responseCount = 0

    func start(
        profile: BotProfile,
        resumeThreadID: String?
    ) async -> AsyncStream<AgentEvent> {
        startCount += 1
        return AsyncStream { continuation in
            continuation.yield(.sessionID("session-\(profile.id.uuidString)"))
            continuation.yield(
                .entry(.init(kind: .question, text: "What should I do?"))
            )
            continuation.yield(.status(.needsAnswer))
            continuation.finish()
        }
    }

    func respond(
        to message: String,
        attachments: [ImageAttachment],
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent> {
        responseCount += 1
        return AsyncStream { continuation in
            continuation.yield(
                .entry(.init(kind: .assistant, text: "Working on \(message)"))
            )
            continuation.yield(.status(.completed))
            continuation.finish()
        }
    }

    func resolveApproval(
        entryID: UUID,
        approved: Bool,
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent> {
        AsyncStream { $0.finish() }
    }

    func stop(profile: BotProfile) async {}
}

private actor FailOnceRuntime: AgentRuntime {
    private(set) var messages: [String] = []
    private(set) var attachments: [[ImageAttachment]] = []
    private let failuresBeforeSuccess: Int

    init(failuresBeforeSuccess: Int = 1) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
    }

    func start(
        profile: BotProfile,
        resumeThreadID: String?
    ) async -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            continuation.yield(
                .sessionID(resumeThreadID ?? "retry-\(profile.id.uuidString)")
            )
            continuation.yield(.status(.needsAnswer))
            continuation.finish()
        }
    }

    func respond(
        to message: String,
        attachments: [ImageAttachment],
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent> {
        messages.append(message)
        self.attachments.append(attachments)
        let shouldFail = messages.count <= failuresBeforeSuccess
        return AsyncStream { continuation in
            if shouldFail {
                continuation.yield(.status(.failed))
            } else {
                continuation.yield(
                    .entry(.init(kind: .assistant, text: "Retry succeeded"))
                )
                continuation.yield(.status(.completed))
            }
            continuation.finish()
        }
    }

    func resolveApproval(
        entryID: UUID,
        approved: Bool,
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent> {
        AsyncStream { $0.finish() }
    }

    func stop(profile: BotProfile) async {}
}

@MainActor
private final class RecordingNotificationDelivery: AgentNotificationDelivering {
    struct PostedNotice {
        let notice: AgentAttentionNotice
        let profileID: UUID
    }

    private(set) var authorizationRequestCount = 0
    private(set) var notices: [PostedNotice] = []
    private(set) var badgeCounts: [Int] = []

    func requestAuthorization() {
        authorizationRequestCount += 1
    }

    func post(_ notice: AgentAttentionNotice, for profile: BotProfile) {
        notices.append(.init(notice: notice, profileID: profile.id))
    }

    func setBadgeCount(_ count: Int) {
        badgeCounts.append(count)
    }
}

private actor LongLivedStartupRuntime: AgentRuntime {
    private var startupContinuation: AsyncStream<AgentEvent>.Continuation?
    private(set) var responseCount = 0

    func start(
        profile: BotProfile,
        resumeThreadID: String?
    ) async -> AsyncStream<AgentEvent> {
        let pair = AsyncStream.makeStream(of: AgentEvent.self)
        startupContinuation = pair.continuation
        pair.continuation.yield(.sessionID(resumeThreadID ?? "review-session"))
        pair.continuation.yield(.status(.needsAnswer))
        return pair.stream
    }

    func respond(
        to message: String,
        attachments: [ImageAttachment],
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent> {
        responseCount += 1
        return AsyncStream { continuation in
            continuation.yield(.status(.working))
            continuation.yield(.entry(.init(kind: .assistant, text: "Review started")))
            continuation.yield(.status(.completed))
            continuation.finish()
        }
    }

    func resolveApproval(
        entryID: UUID,
        approved: Bool,
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent> {
        AsyncStream { $0.finish() }
    }

    func stop(profile: BotProfile) async {
        startupContinuation?.finish()
        startupContinuation = nil
    }

    func disconnect() {
        startupContinuation?.yield(.status(.failed))
        startupContinuation?.finish()
        startupContinuation = nil
    }
}
