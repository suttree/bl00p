#if os(macOS)
import AppKit
#else
import SwiftOpenUI
#endif
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

#if os(macOS)
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
#else
// `Bl00pTheme`'s `adaptive()` colors resolve against `Bl00pAppearance.current`,
// which is read once at process launch (there is no live-appearance
// resolution API on the GTK4 backend to force both light and dark the way
// `NSAppearance.performAsCurrentDrawingAppearance` does above). These tests
// exercise the constants and explicitly-parameterized functions that do not
// depend on that fixed, launch-time value.
@Test
func themeBrandSurfacesUseTheExpectedHotPink() {
    for surface in [Bl00pTheme.accent, Bl00pTheme.userBubble, Bl00pTheme.hotPink] {
        #expect(abs(surface.red - 1.00) < 0.001)
        #expect(abs(surface.green - 105.0 / 255.0) < 0.001)
        #expect(abs(surface.blue - 180.0 / 255.0) < 0.001)
    }
    #expect(abs(Bl00pTheme.userBubbleText.red - 1.00) < 0.001)
    #expect(abs(Bl00pTheme.userBubbleText.green - 1.00) < 0.001)
    #expect(abs(Bl00pTheme.userBubbleText.blue - 1.00) < 0.001)
}

@Test
func sidebarColorsDifferBetweenLightAndDark() {
    #expect(
        Bl00pTheme.sidebarColors(for: .light)
            != Bl00pTheme.sidebarColors(for: .dark)
    )
    #expect(
        Bl00pTheme.sidebarTop(for: .light) == Bl00pTheme.sidebarLightTop
    )
    #expect(
        Bl00pTheme.sidebarTop(for: .dark) == Bl00pTheme.sidebarDarkTop
    )
    #expect(contrastRatio(Bl00pTheme.userBubble, Bl00pTheme.avatarInk) >= 4.5)
}

@Test
func avatarBackgroundUsesPinkForManagersAndMintForOtherRoles() {
    #expect(Bl00pTheme.avatarBackground(for: .manager) == Bl00pTheme.hotPink)
    #expect(
        contrastRatio(
            Bl00pTheme.avatarBackground(for: .manager),
            Bl00pTheme.avatarInk
        ) >= 4.5
    )

    for role in AgentRole.allCases where role != .manager {
        #expect(Bl00pTheme.avatarBackground(for: role) == Bl00pTheme.mint)
    }
}
#endif

@Test
func defaultProfilesCoverTheLoop() {
    #expect(BotProfile.defaults.map(\.role) == [.builder, .reviewer, .publisher])
    #expect(Set(BotProfile.defaults.map(\.provider)) == [.claude, .codex])
    #expect(BotProfile.defaults.map(\.name) == ["Claude", "Codex", "Claude"])
}

@Test
func defaultProfilesIncludeEasolWorkingGuidelines() {
    let distinctiveSubstrings = [
        "implementation owner",
        "pull-request reviewer",
        "draft pull requests"
    ]

    for (profile, distinctiveSubstring) in zip(BotProfile.defaults, distinctiveSubstrings) {
        #expect(profile.instructions.contains(BotProfile.easolWorkingGuidelines))
        #expect(profile.instructions.contains(distinctiveSubstring))
    }
}

#if os(macOS)
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
#else
private func contrastRatio(_ first: Color, _ second: Color) -> Double {
    let firstLuminance = relativeLuminance(first)
    let secondLuminance = relativeLuminance(second)
    let lighter = max(firstLuminance, secondLuminance)
    let darker = min(firstLuminance, secondLuminance)
    return (lighter + 0.05) / (darker + 0.05)
}

private func relativeLuminance(_ color: Color) -> Double {
    let components = [color.red, color.green, color.blue]
        .map { component in
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
    return 0.2126 * components[0]
        + 0.7152 * components[1]
        + 0.0722 * components[2]
}
#endif

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
    #expect(AgentStatus.blocked.needsAttention)
    #expect(AgentStatus.failed.needsAttention)
    #expect(!AgentStatus.working.needsAttention)
    #expect(!AgentStatus.completed.needsAttention)
}

@Test
func blockedStatusIsLabeledDistinctlyFromAQuestion() {
    #expect(AgentStatus.blocked.label == "Blocked")
    #expect(AgentStatus.needsAnswer.label == "Question")
    #expect(AgentStatus.blocked.allowsFailedMessageRetry)
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
        AgentAttentionNotice.transition(from: .working, to: .blocked)
            == .blocked
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
    let backgroundSessionID = try #require(
        model.selectedSessionID(for: backgroundProfile.id)
    )
    #expect(model.setRepositoryPath("/tmp", for: backgroundSessionID))

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
    let backgroundSessionID = try #require(
        model.selectedSessionID(for: backgroundProfile.id)
    )
    #expect(model.setRepositoryPath("/tmp", for: backgroundSessionID))

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

#if os(macOS)
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
#else
// SwiftOpenUI's Text only renders plain String, and this toolchain's
// AttributedString does not expose Markdown parsing, so
// `TranscriptMarkdown.attributed` is a passthrough on Linux (see
// Views/ConversationView.swift) — there is no link-run behavior to verify.
@Test
func assistantMarkdownPassesSourceThroughUnparsed() {
    let source = "Draft PR created: [suttree/bl00p#1](https://github.com/suttree/bl00p/pull/1)"
    #expect(TranscriptMarkdown.attributed(source) == source)
}
#endif

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
func markdownTablesRenderAsMonospacedAsciiBlocks() throws {
    let blocks = TranscriptMarkdown.blocks(
        """
        ## Status

        | # | Finding | Status |
        |---|---|---|
        | 1 | Missing test | Not addressed |
        | 2 | Unsafe command | Fixed |

        Continue with the remaining work.
        """
    )
    let code = blocks.compactMap { block -> String? in
        guard case .code(let text) = block.content else { return nil }
        return text
    }
    let prose = blocks.compactMap { block -> String? in
        guard case .prose(let text) = block.content else { return nil }
        #if os(macOS)
        return String(text.characters)
        #else
        return text
        #endif
    }.joined(separator: "\n")

    #expect(code.count == 1)
    #expect(code[0].contains("| # | Finding | Status |"))
    #expect(code[0].contains("| 2 | Unsafe command | Fixed |"))
    #expect(prose.contains("Continue with the remaining work."))
}

@Test
func reviewDispositionParsesAndRemovesItsProtocolLine() {
    let response = """
    Two findings remain.

    BL00P_REVIEW_DISPOSITION: changesRequested
    """

    #expect(ReviewDisposition.parse(from: response) == .changesRequested)
    #expect(
        ReviewDisposition.removingProtocolLines(from: response)
            == "Two findings remain."
    )
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
func codexThreadConfigurationUsesAResolvedPerChatPromptOverride() {
    let botDefault = BotProfile(
        name: "Review",
        provider: .codex,
        role: .reviewer,
        instructions: "Review this code."
    )
    var session = AgentSessionState()
    session.instructionsOverride = "Only look at the database layer."

    // Mirrors what AppModel.runtimeProfile does: resolve the effective
    // instructions for the chat before handing the profile to the runtime.
    var resolvedProfile = botDefault
    resolvedProfile.instructions = AgentSessionState.effectiveInstructions(
        profile: botDefault,
        session: session
    )

    let parameters = CodexThreadConfiguration.parameters(
        profile: resolvedProfile,
        workingDirectory: "/tmp/project"
    )

    #expect(
        parameters["developerInstructions"]?.stringValue?
            .hasPrefix("Only look at the database layer.\n\n") == true
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
func claudeReviewerAndManagerCanBothSelectApprovalMode() {
    let reviewer = BotProfile(
        name: "Reviewer",
        provider: .claude,
        role: .reviewer,
        instructions: "Review."
    )
    let manager = BotProfile(
        name: "Manager",
        provider: .claude,
        role: .manager,
        instructions: "Coordinate."
    )

    #expect(reviewer.canSelectApprovalMode)
    #expect(manager.canSelectApprovalMode)
    for role in AgentRole.allCases {
        let codex = BotProfile(
            name: role.displayName,
            provider: .codex,
            role: role,
            instructions: ""
        )
        #expect(codex.canSelectApprovalMode)
    }
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
func effectiveInstructionsPrefersANonBlankSessionOverride() {
    let profile = BotProfile(
        name: "Claude",
        provider: .claude,
        role: .builder,
        instructions: "Bot default prompt."
    )
    var session = AgentSessionState()
    session.instructionsOverride = "Chat-specific prompt."

    #expect(
        AgentSessionState.effectiveInstructions(profile: profile, session: session)
            == "Chat-specific prompt."
    )
}

@Test
func effectiveInstructionsFallsBackToTheBotDefault() {
    let profile = BotProfile(
        name: "Claude",
        provider: .claude,
        role: .builder,
        instructions: "Bot default prompt."
    )

    // No session at all (e.g. editing the bot before any chat exists).
    #expect(
        AgentSessionState.effectiveInstructions(profile: profile, session: nil)
            == "Bot default prompt."
    )

    // A session with no override.
    #expect(
        AgentSessionState.effectiveInstructions(profile: profile, session: AgentSessionState())
            == "Bot default prompt."
    )

    // A session whose override is present but blank/whitespace-only.
    var blankOverrideSession = AgentSessionState()
    blankOverrideSession.instructionsOverride = "   \n  "
    #expect(
        AgentSessionState.effectiveInstructions(profile: profile, session: blankOverrideSession)
            == "Bot default prompt."
    )
}

@Test
func agentSessionStateRoundTripsInstructionsOverride() throws {
    var session = AgentSessionState()
    session.instructionsOverride = "Chat-specific prompt."

    let data = try JSONEncoder().encode(session)
    let decoded = try JSONDecoder().decode(AgentSessionState.self, from: data)

    #expect(decoded.instructionsOverride == "Chat-specific prompt.")
}

@Test
func legacySessionJSONMissingInstructionsOverrideDecodesAsNil() throws {
    let legacyJSON = """
    {
        "id": "D24E2670-03E9-420B-9AB5-00A589E09249",
        "repositoryPath": "/tmp/project",
        "title": "New chat"
    }
    """.data(using: .utf8)!

    let session = try JSONDecoder().decode(AgentSessionState.self, from: legacyJSON)

    #expect(session.instructionsOverride == nil)
}

@Test
func persistedStateRoundTrips() throws {
    var profile = BotProfile.defaults[0]
    profile.approvalMode = .auto
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
                repositoryPath: "/tmp/project",
                status: .completed,
                entries: [
                    TimelineEntry(kind: .assistant, text: "Done")
                ],
                hasUnreadCompletion: true,
                sessionID: "session-1",
                pendingHandoff: handoff
            )
        ],
        selectedBotID: profile.id,
        managerWorkflows: [
            profile.id: ManagerWorkflow(
                managerProfileID: profile.id,
                repositoryPath: "/tmp/project",
                team: ManagerTeamConfiguration(),
                request: "Persist the retry cap",
                revisionRounds: 2
            )
        ]
    )

    let data = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(PersistedAppState.self, from: data)

    #expect(decoded.profiles == [profile])
    #expect(decoded.profiles.first?.approvalMode == .auto)
    #expect(decoded.sessions[profile.id]?.status == .completed)
    #expect(decoded.sessions[profile.id]?.entries.first?.text == "Done")
    #expect(decoded.profiles.first?.worktree?.branch == handoff.branch)
    #expect(decoded.sessions[profile.id]?.pendingHandoff == handoff)
    #expect(decoded.sessions[profile.id]?.repositoryPath == "/tmp/project")
    #expect(decoded.managerWorkflows[profile.id]?.revisionRounds == 2)
    #expect(
        decoded.managerWorkflows[profile.id]?.repositoryPath == "/tmp/project"
    )
}

@MainActor
@Test
func legacyProfileSessionsMigrateIntoSelectedTabsWithTheirWorktree() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-tab-migration-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    var profile = BotProfile.defaults[0]
    profile.worktree = GitWorktreeOwnership(
        ownerProfileID: profile.id,
        repositoryPath: "/tmp/project",
        worktreePath: "/tmp/.bl00p-worktrees/project-legacy",
        branch: "bl00p/legacy",
        baseRevision: "abc123"
    )
    let store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    store.save(
        PersistedAppState(
            profiles: [profile],
            sessions: [
                profile.id: AgentSessionState(
                    entries: [.init(kind: .user, text: "Preserve this conversation")]
                )
            ],
            selectedBotID: profile.id
        )
    )

    let model = AppModel(runtime: ImmediateRecordingRuntime(), store: store)
    let migrated = try #require(model.sessions[profile.id])

    #expect(migrated.id == profile.id)
    #expect(migrated.ownerProfileID == profile.id)
    #expect(migrated.title == "Preserve this conversation")
    #expect(migrated.repositoryPath == "/tmp/project")
    #expect(migrated.worktree?.ownerSessionID == profile.id)
    #expect(model.sessionOrder[profile.id] == [profile.id])
    #expect(model.selectedSessionIDs[profile.id] == profile.id)
}

@MainActor
@Test
func chatTabsKeepIndependentDraftsHistoriesAndRuntimeIdentities() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-tab-isolation-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let runtime = SessionRecordingRuntime()
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    let model = AppModel(
        runtime: runtime,
        store: store
    )
    let profile = try #require(model.profiles.dropFirst().first)
    let firstID = try #require(model.selectedSessionID(for: profile.id))
    #expect(model.setRepositoryPath("/tmp/repository-a", for: firstID))
    model.updateDraft("first draft", for: firstID)
    model.send("First task", to: profile.id)

    let secondID = model.newChat(for: profile.id)
    #expect(model.setRepositoryPath("/tmp/repository-b", for: secondID))
    model.updateDraft("second draft", for: secondID)
    model.send("Second task", to: profile.id)

    for _ in 0..<50 where await runtime.respondedSessionIDs.count < 2 {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(firstID != secondID)
    #expect(Set(await runtime.respondedSessionIDs) == Set([firstID, secondID]))
    #expect(await runtime.respondedDirectories[firstID] == "/tmp/repository-a")
    #expect(await runtime.respondedDirectories[secondID] == "/tmp/repository-b")
    #expect(model.sessions[firstID]?.draft == "first draft")
    #expect(model.sessions[secondID]?.draft == "second draft")
    #expect(model.sessions[firstID]?.entries.contains(where: { $0.text.contains("First task") }) == true)
    #expect(model.sessions[firstID]?.entries.contains(where: { $0.text.contains("Second task") }) == false)
    #expect(model.sessions[secondID]?.entries.contains(where: { $0.text.contains("Second task") }) == true)
    #expect(model.sessions[firstID]?.title == "First task")
    #expect(model.sessions[secondID]?.title == "Second task")

    await model.flushPersistence()
    let restored = AppModel(runtime: SessionRecordingRuntime(), store: store)
    #expect(restored.sessions[firstID]?.repositoryPath == "/tmp/repository-a")
    #expect(restored.sessions[secondID]?.repositoryPath == "/tmp/repository-b")
}

@MainActor
@Test
func launchPreservesTheChatsPromptOverrideOnColdStart() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-launch-override-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let profile = BotProfile.defaults[0]
    var session = AgentSessionState(id: profile.id, ownerProfileID: profile.id)
    session.repositoryPath = "/tmp/project"
    session.instructionsOverride = "Only touch the migration scripts."
    let store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    store.save(
        PersistedAppState(
            profiles: [profile],
            sessions: [profile.id: session],
            selectedBotID: profile.id
        )
    )

    let model = AppModel(runtime: ImmediateRecordingRuntime(), store: store)
    // No `sessionID` was persisted, so this hits launch()'s cold-start
    // branch that rebuilds the session state from scratch.
    #expect(model.sessions[profile.id]?.sessionID == nil)

    model.launch(profile.id)

    #expect(
        model.sessions[profile.id]?.instructionsOverride
            == "Only touch the migration scripts."
    )
}

@MainActor
@Test
func positionalTabSelectionTracksCurrentSessionOrder() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-positional-tab-selection-\(UUID().uuidString)"
        )
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = AppModel(
        runtime: ImmediateRecordingRuntime(),
        store: AppStateStore(
            fileURL: directory.appendingPathComponent("state.json")
        )
    )
    let profile = try #require(model.profiles.first)
    let firstID = try #require(model.selectedSessionID(for: profile.id))
    let secondID = model.newChat(for: profile.id)
    let thirdID = model.newChat(for: profile.id)

    #expect(!model.selectTab(at: 0, viewing: profile.id))
    #expect(!model.selectTab(at: 4, viewing: profile.id))
    #expect(model.selectedSessionID(for: profile.id) == thirdID)

    #expect(model.selectTab(at: 2, viewing: profile.id))
    #expect(model.selectedSessionID(for: profile.id) == secondID)

    let closeError = await model.closeSession(
        firstID,
        confirmedDestructiveCleanup: true
    )
    #expect(closeError == nil)
    #expect(model.tabSessions(for: profile.id).map(\.id) == [secondID, thirdID])
    #expect(model.selectTab(at: 1, viewing: profile.id))
    #expect(model.selectedSessionID(for: profile.id) == secondID)
    #expect(!model.selectTab(at: 3, viewing: profile.id))

    let fourthID = model.newChat(for: profile.id)
    #expect(model.selectTab(at: 3, viewing: profile.id))
    #expect(model.selectedSessionID(for: profile.id) == fourthID)
}

@MainActor
@Test
func sidebarIndicatorSessionsIgnoreBackgroundChatsForStandaloneBots() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-sidebar-indicator-standalone-\(UUID().uuidString)"
        )
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = AppModel(
        runtime: ImmediateRecordingRuntime(),
        store: AppStateStore(
            fileURL: directory.appendingPathComponent("state.json")
        )
    )
    let profile = try #require(model.profiles.first)
    let backgroundID = try #require(model.selectedSessionID(for: profile.id))
    let currentID = model.newChat(for: profile.id)
    #expect(model.selectedSessionID(for: profile.id) == currentID)

    model.sessions[backgroundID]?.status = .blocked
    model.sessions[backgroundID]?.hasUnreadCompletion = true
    model.sessions[currentID]?.status = .stopped

    let indicatorSessions = model.sidebarIndicatorSessions(for: profile.id)
    #expect(indicatorSessions.map(\.id) == [currentID])
    #expect(!indicatorSessions.contains { $0.status.needsAttention })
    #expect(!indicatorSessions.contains { $0.hasUnreadCompletion })

    model.sessions[currentID]?.status = .working
    let workingIndicatorSessions = model.sidebarIndicatorSessions(for: profile.id)
    #expect(workingIndicatorSessions.contains { $0.status == .working })

    model.selectSession(backgroundID, for: profile.id)
    let switchedIndicatorSessions = model.sidebarIndicatorSessions(for: profile.id)
    #expect(switchedIndicatorSessions.map(\.id) == [backgroundID])
    #expect(switchedIndicatorSessions.contains { $0.status.needsAttention })
}

@MainActor
@Test
func sidebarIndicatorSessionsForManagerScopeToTheSelectedWorkflow() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-sidebar-indicator-manager-\(UUID().uuidString)"
        )
    defer { try? FileManager.default.removeItem(at: directory) }
    let managerID = UUID()
    let builderID = UUID()
    let manager = BotProfile(
        id: managerID,
        name: "Manager",
        provider: .codex,
        role: .manager,
        instructions: "",
        managerTeam: ManagerTeamConfiguration(builderProfileID: builderID)
    )
    let builder = BotProfile(
        id: builderID,
        name: "Builder",
        provider: .claude,
        role: .builder,
        instructions: ""
    )
    let currentManagerChatID = UUID()
    let backgroundManagerChatID = UUID()
    let currentBuilderSessionID = UUID()
    let backgroundBuilderSessionID = UUID()

    // Built fresh and mutated in place (rather than restored from a saved
    // PersistedAppState) because restore resets any `.working` status back
    // to `.stopped`, which would defeat this test.
    let model = AppModel(
        runtime: ImmediateRecordingRuntime(),
        store: AppStateStore(
            fileURL: directory.appendingPathComponent("state.json")
        )
    )
    model.profiles = [manager, builder]
    model.sessions = [
        currentManagerChatID: AgentSessionState(
            id: currentManagerChatID,
            ownerProfileID: managerID,
            status: .stopped
        ),
        backgroundManagerChatID: AgentSessionState(
            id: backgroundManagerChatID,
            ownerProfileID: managerID,
            status: .stopped
        ),
        currentBuilderSessionID: AgentSessionState(
            id: currentBuilderSessionID,
            ownerProfileID: builderID,
            status: .stopped
        ),
        backgroundBuilderSessionID: AgentSessionState(
            id: backgroundBuilderSessionID,
            ownerProfileID: builderID,
            status: .working
        )
    ]
    model.sessionOrder = [
        managerID: [currentManagerChatID, backgroundManagerChatID]
    ]
    model.selectedBotID = managerID
    model.selectedSessionIDs = [managerID: currentManagerChatID]
    model.managerWorkflows = [
        currentManagerChatID: ManagerWorkflow(
            managerProfileID: managerID,
            team: ManagerTeamConfiguration(builderProfileID: builderID),
            request: "Current workflow",
            participantSessionIDs: [.builder: currentBuilderSessionID]
        ),
        backgroundManagerChatID: ManagerWorkflow(
            managerProfileID: managerID,
            team: ManagerTeamConfiguration(builderProfileID: builderID),
            request: "Background workflow",
            participantSessionIDs: [.builder: backgroundBuilderSessionID]
        )
    ]

    let indicatorSessions = model.sidebarIndicatorSessions(for: managerID)
    #expect(
        Set(indicatorSessions.map(\.id))
            == [currentManagerChatID, currentBuilderSessionID]
    )
    #expect(!indicatorSessions.contains { $0.status == .working })

    model.selectSession(backgroundManagerChatID, for: managerID)
    let switchedIndicatorSessions = model.sidebarIndicatorSessions(for: managerID)
    #expect(
        Set(switchedIndicatorSessions.map(\.id))
            == [backgroundManagerChatID, backgroundBuilderSessionID]
    )
    #expect(switchedIndicatorSessions.contains { $0.status == .working })
}

@MainActor
@Test
func newChatsRequireARepositoryAndLockItAfterStarting() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-chat-repository-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let runtime = HandoffRecordingRuntime()
    let model = AppModel(
        runtime: runtime,
        store: AppStateStore(
            fileURL: directory.appendingPathComponent("state.json")
        )
    )
    let profile = try #require(model.profiles.dropFirst().first)
    let sessionID = try #require(model.selectedSessionID(for: profile.id))

    #expect(model.sessions[sessionID]?.repositoryPath == "")
    model.send("Cannot start yet", to: profile.id)
    #expect(await runtime.messages.isEmpty)
    #expect(
        model.sessions[sessionID]?.entries.last?.text
            == "Choose a repository before starting this chat"
    )

    #expect(model.setRepositoryPath("/tmp/repository-a", for: sessionID))
    model.send("Start now", to: profile.id)
    for _ in 0..<30 where await runtime.messages.isEmpty {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(await runtime.respondedDirectories == ["/tmp/repository-a"])
    #expect(!model.repositoryCanBeChanged(for: sessionID))
    #expect(!model.setRepositoryPath("/tmp/repository-b", for: sessionID))
    #expect(model.sessions[sessionID]?.repositoryPath == "/tmp/repository-a")

    let newSessionID = model.newChat(for: profile.id)
    #expect(model.sessions[newSessionID]?.repositoryPath == "")
    #expect(model.repositoryCanBeChanged(for: newSessionID))
}

@MainActor
@Test
func builderWorktreesUseEachChatsRepository() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-builder-chat-repositories-\(UUID().uuidString)"
        )
    defer { try? FileManager.default.removeItem(at: directory) }
    var builder = BotProfile.defaults[0]
    builder.workingDirectory = ""
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    store.save(
        PersistedAppState(
            profiles: [builder],
            sessions: [
                builder.id: AgentSessionState(
                    id: builder.id,
                    ownerProfileID: builder.id
                )
            ],
            selectedBotID: builder.id
        )
    )
    let runtime = HandoffRecordingRuntime()
    let worktrees = RepositoryRecordingWorktreeManager()
    let model = AppModel(
        runtime: runtime,
        worktrees: worktrees,
        store: store
    )
    let firstID = try #require(model.selectedSessionID(for: builder.id))
    #expect(model.setRepositoryPath("/tmp/repository-a", for: firstID))
    model.send("First build", to: builder.id)
    for _ in 0..<30 where await runtime.messages.count < 1 {
        try await Task.sleep(for: .milliseconds(10))
    }

    let secondID = model.newChat(for: builder.id)
    #expect(model.setRepositoryPath("/tmp/repository-b", for: secondID))
    model.send("Second build", to: builder.id)
    for _ in 0..<30 where await runtime.messages.count < 2 {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(
        await worktrees.repositories
            == ["/tmp/repository-a", "/tmp/repository-b"]
    )
    #expect(
        model.sessions[firstID]?.worktree?.repositoryPath
            == "/tmp/repository-a"
    )
    #expect(
        model.sessions[secondID]?.worktree?.repositoryPath
            == "/tmp/repository-b"
    )
}

@MainActor
@Test
func draftPersistenceIsDebouncedInsteadOfWritingOnEveryKeystroke() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-draft-debounce-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let profile = BotProfile.defaults[1]
    let store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    store.save(
        PersistedAppState(
            profiles: [profile],
            sessions: [
                profile.id: AgentSessionState(
                    id: profile.id,
                    ownerProfileID: profile.id
                )
            ],
            selectedBotID: profile.id
        )
    )
    let model = AppModel(runtime: ImmediateRecordingRuntime(), store: store)

    model.updateDraft("h", for: profile.id)
    model.updateDraft("he", for: profile.id)
    model.updateDraft("hello", for: profile.id)

    #expect(store.load()?.sessions[profile.id]?.draft == "")
    try await Task.sleep(for: .milliseconds(500))
    #expect(store.load()?.sessions[profile.id]?.draft == "hello")
}

@MainActor
@Test
func managedWorkflowsCreateDedicatedSessionsAndCanRunConcurrently() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-workflow-tabs-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let managerID = UUID()
    let builderID = UUID()
    let reviewerID = UUID()
    let publisherID = UUID()
    let manager = BotProfile(
        id: managerID,
        name: "Manager",
        provider: .codex,
        role: .manager,
        instructions: "",
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
        instructions: ""
    )
    let reviewer = BotProfile(
        id: reviewerID,
        name: "Reviewer",
        provider: .codex,
        role: .reviewer,
        instructions: ""
    )
    let publisher = BotProfile(
        id: publisherID,
        name: "Publisher",
        provider: .claude,
        role: .publisher,
        instructions: ""
    )
    let profiles = [manager, builder, reviewer, publisher]
    let store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    store.save(
        PersistedAppState(
            profiles: profiles,
            sessions: Dictionary(
                uniqueKeysWithValues: profiles.map {
                    ($0.id, AgentSessionState(id: $0.id, ownerProfileID: $0.id))
                }
            ),
            selectedBotID: managerID
        )
    )
    let model = AppModel(runtime: ImmediateRecordingRuntime(), store: store)
    let standaloneBuilderSessionID = try #require(
        model.selectedSessionID(for: builderID)
    )
    let standaloneReviewerSessionID = try #require(
        model.selectedSessionID(for: reviewerID)
    )
    let standalonePublisherSessionID = try #require(
        model.selectedSessionID(for: publisherID)
    )
    #expect(model.setRepositoryPath("/tmp/repository-a", for: managerID))
    model.send("Plan this change", to: managerID)
    let firstWorkflow = try #require(model.workflow(for: managerID))
    let firstBuilderSessionID = try #require(
        firstWorkflow.participantSessionIDs[.builder]
    )

    #expect(firstBuilderSessionID != standaloneBuilderSessionID)
    #expect(firstWorkflow.repositoryPath == "/tmp/repository-a")
    #expect(firstWorkflow.participantSessionIDs[.manager] == managerID)
    #expect(
        model.sessions[firstBuilderSessionID]?.repositoryPath
            == "/tmp/repository-a"
    )
    #expect(
        model.selectedSessionID(for: builderID) == standaloneBuilderSessionID
    )
    #expect(
        model.selectedSessionID(for: reviewerID) == standaloneReviewerSessionID
    )
    #expect(
        model.selectedSessionID(for: publisherID)
            == standalonePublisherSessionID
    )
    for role in [AgentRole.builder, .reviewer, .publisher] {
        let participantID = try #require(
            firstWorkflow.participantSessionIDs[role]
        )
        #expect(
            model.sessions[participantID]?.repositoryPath
                == "/tmp/repository-a"
        )
    }

    let secondManagerSessionID = model.newChat(for: managerID)
    #expect(model.workflow(for: managerID) == nil)
    #expect(
        model.setRepositoryPath(
            "/tmp/repository-b",
            for: secondManagerSessionID
        )
    )
    model.send("Start another workflow", to: managerID)
    let secondWorkflow = try #require(
        model.managerWorkflows[secondManagerSessionID]
    )
    let secondBuilderSessionID = try #require(
        secondWorkflow.participantSessionIDs[.builder]
    )
    #expect(secondWorkflow.repositoryPath == "/tmp/repository-b")
    #expect(secondBuilderSessionID != firstBuilderSessionID)
    #expect(
        model.sessions[secondBuilderSessionID]?.repositoryPath
            == "/tmp/repository-b"
    )

    let closeError = await model.closeSession(
        managerID,
        confirmedDestructiveCleanup: true
    )
    try await Task.sleep(for: .milliseconds(20))
    #expect(closeError == nil)
    #expect(model.sessions[managerID] == nil)
    #expect(model.managerWorkflows[managerID] == nil)
}

@MainActor
@Test
func managedWorkflowConversationsFollowManagerTabSelection() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-manager-scoped-tabs-\(UUID().uuidString)"
        )
    defer { try? FileManager.default.removeItem(at: directory) }
    let fixture = managedWorkflowFixture()
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    store.save(
        PersistedAppState(
            profiles: fixture.profiles,
            sessions: Dictionary(
                uniqueKeysWithValues: fixture.profiles.map {
                    (
                        $0.id,
                        AgentSessionState(
                            id: $0.id,
                            ownerProfileID: $0.id
                        )
                    )
                }
            ),
            selectedBotID: fixture.manager.id
        )
    )
    let model = AppModel(
        runtime: ImmediateRecordingRuntime(),
        store: store
    )
    let standaloneBuilderSessionID = try #require(
        model.selectedSessionID(for: fixture.builder.id)
    )

    model.send("First workflow", to: fixture.manager.id)
    let firstWorkflow = try #require(
        model.managerWorkflows[fixture.manager.id]
    )
    let firstBuilderSessionID = try #require(
        firstWorkflow.participantSessionIDs[.builder]
    )

    let secondManagerSessionID = model.newChat(for: fixture.manager.id)
    #expect(
        model.setRepositoryPath(
            "/tmp/second-project",
            for: secondManagerSessionID
        )
    )
    model.send("Second workflow", to: fixture.manager.id)
    let secondWorkflow = try #require(
        model.managerWorkflows[secondManagerSessionID]
    )

    let expectedTabIDs = [fixture.manager.id, secondManagerSessionID]
    for profile in fixture.profiles {
        #expect(
            model.tabSessions(for: profile.id).map(\.id)
                == expectedTabIDs
        )
        #expect(
            model.selectedTabSessionID(for: profile.id)
                == secondManagerSessionID
        )
    }

    #expect(
        model.conversationSessionID(for: fixture.builder.id)
            == secondWorkflow.participantSessionIDs[.builder]
    )
    #expect(
        model.conversationSessionID(for: fixture.reviewer.id)
            == secondWorkflow.participantSessionIDs[.reviewer]
    )
    #expect(
        model.conversationSessionID(for: fixture.publisher.id)
            == secondWorkflow.participantSessionIDs[.publisher]
    )
    #expect(
        model.selectedSessionID(for: fixture.builder.id)
            == standaloneBuilderSessionID
    )

    #expect(model.selectTab(at: 1, viewing: fixture.manager.id))

    for profile in fixture.profiles {
        #expect(
            model.selectedTabSessionID(for: profile.id)
                == fixture.manager.id
        )
    }
    #expect(
        model.conversationSessionID(for: fixture.builder.id)
            == firstBuilderSessionID
    )
    #expect(
        model.conversationSessionID(for: fixture.reviewer.id)
            == firstWorkflow.participantSessionIDs[.reviewer]
    )
    #expect(
        model.conversationSessionID(for: fixture.publisher.id)
            == firstWorkflow.participantSessionIDs[.publisher]
    )
    #expect(
        model.selectedSessionID(for: fixture.builder.id)
            == standaloneBuilderSessionID
    )

    let emptyManagerSessionID = model.newChat(for: fixture.manager.id)

    for profile in fixture.profiles {
        #expect(
            model.selectedTabSessionID(for: profile.id)
                == emptyManagerSessionID
        )
    }
    #expect(model.conversationSessionID(for: fixture.builder.id) == nil)
    #expect(model.conversationSessionID(for: fixture.reviewer.id) == nil)
    #expect(model.conversationSessionID(for: fixture.publisher.id) == nil)
    #expect(
        model.selectedSessionID(for: fixture.builder.id)
            == standaloneBuilderSessionID
    )
}

@MainActor
@Test
func managerCannotStartAWorkflowWithoutARepository() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-manager-repository-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let fixture = managedWorkflowFixture()
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    store.save(
        PersistedAppState(
            profiles: fixture.profiles.map {
                var profile = $0
                profile.workingDirectory = ""
                return profile
            },
            sessions: Dictionary(
                uniqueKeysWithValues: fixture.profiles.map {
                    (
                        $0.id,
                        AgentSessionState(
                            id: $0.id,
                            ownerProfileID: $0.id
                        )
                    )
                }
            ),
            selectedBotID: fixture.manager.id
        )
    )
    let model = AppModel(runtime: ImmediateRecordingRuntime(), store: store)

    model.send("Plan this change", to: fixture.manager.id)

    #expect(model.workflow(for: fixture.manager.id) == nil)
    #expect(
        model.session(for: fixture.manager.id).entries.last?.text
            == "Choose a repository before starting this workflow"
    )
}

@MainActor
@Test
func closingTheFinalTabCreatesAFreshUsableReplacement() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-close-final-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = AppModel(
        runtime: ImmediateRecordingRuntime(),
        store: AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    )
    let profile = try #require(model.profiles.first)
    let originalID = try #require(model.selectedSessionID(for: profile.id))

    let error = await model.closeSession(
        originalID,
        confirmedDestructiveCleanup: true
    )
    let replacementID = try #require(model.selectedSessionID(for: profile.id))

    #expect(error == nil)
    #expect(model.sessions[originalID] == nil)
    #expect(replacementID != originalID)
    #expect(model.sessions[replacementID]?.entries.isEmpty == true)
    #expect(model.sessions[replacementID]?.sessionID == nil)
}

@MainActor
@Test
func failedWorktreeCleanupRetainsTheChatAndShowsAnActionableError() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-close-failure-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    var profile = BotProfile.defaults[0]
    let otherProfile = BotProfile.defaults[1]
    profile.workingDirectory = "/tmp/project"
    let ownership = GitWorktreeOwnership(
        ownerProfileID: profile.id,
        ownerSessionID: profile.id,
        repositoryPath: "/tmp/project",
        worktreePath: "/tmp/.bl00p-worktrees/project-session",
        branch: "bl00p/session",
        baseRevision: "abc123"
    )
    let store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    store.save(
        PersistedAppState(
            profiles: [profile, otherProfile],
            sessions: [
                profile.id: AgentSessionState(
                    id: profile.id,
                    ownerProfileID: profile.id,
                    worktree: ownership
                ),
                otherProfile.id: AgentSessionState(
                    id: otherProfile.id,
                    ownerProfileID: otherProfile.id
                )
            ],
            selectedBotID: profile.id
        )
    )
    let model = AppModel(
        runtime: ImmediateRecordingRuntime(),
        worktrees: FailingCleanupWorktreeManager(ownership: ownership),
        store: store
    )

    let error = await model.closeSession(
        profile.id,
        confirmedDestructiveCleanup: true
    )

    #expect(error == "Simulated cleanup failure.")
    #expect(model.sessions[profile.id] != nil)
    #expect(model.sessions[profile.id]?.entries.last?.text == "Could not close chat")
    #expect(model.sessionOrder[profile.id] == [profile.id])

    model.delete(profile.id)
    for _ in 0..<30 where model.profileDeletionError == nil {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(model.profileDeletionError == "Simulated cleanup failure.")
    #expect(model.profiles.contains(where: { $0.id == profile.id }))
}

@MainActor
@Test
func unregisteredWorktreeCanBeClosedWhileLeavingItOnDisk() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-close-orphan-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let profile = BotProfile.defaults[0]
    let otherProfile = BotProfile.defaults[1]
    let ownership = GitWorktreeOwnership(
        ownerProfileID: profile.id,
        ownerSessionID: profile.id,
        repositoryPath: "/tmp/project",
        worktreePath: "/tmp/.bl00p-worktrees/project-detached",
        branch: "bl00p/old-branch",
        baseRevision: "abc123"
    )
    let store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    store.save(
        PersistedAppState(
            profiles: [profile, otherProfile],
            sessions: [
                profile.id: AgentSessionState(
                    id: profile.id,
                    ownerProfileID: profile.id,
                    worktree: ownership
                ),
                otherProfile.id: AgentSessionState(
                    id: otherProfile.id,
                    ownerProfileID: otherProfile.id
                )
            ],
            selectedBotID: profile.id
        )
    )
    let worktrees = UnremovableWorktreeManager(ownership: ownership)
    let model = AppModel(
        runtime: ImmediateRecordingRuntime(),
        worktrees: worktrees,
        store: store
    )

    let assessment = await model.closeAssessment(for: profile.id)
    #expect(assessment.leavesWorktreeOnDisk)
    #expect(assessment.worktreeWarning?.contains("different branch") == true)

    model.delete(profile.id)
    for _ in 0..<30 where model.profileDeletionError == nil {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(model.profileDeletionError?.contains("Close that chat first") == true)
    #expect(model.profiles.contains(where: { $0.id == profile.id }))

    let error = await model.closeSession(
        profile.id,
        confirmedDestructiveCleanup: true
    )

    #expect(error == nil)
    #expect(model.sessions[profile.id] == nil)
    #expect(await worktrees.removeCount == 0)
}

@MainActor
@Test
func lateRuntimeEventsCannotResurrectAClosedSession() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-late-closed-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let runtime = LateEventRuntime()
    let model = AppModel(
        runtime: runtime,
        store: AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    )
    let profile = try #require(model.profiles.first(where: { $0.role == .reviewer }))
    let sessionID = try #require(model.selectedSessionID(for: profile.id))
    model.send("Hold this response", to: profile.id)
    for _ in 0..<30 where await !runtime.didStartResponse {
        try await Task.sleep(for: .milliseconds(10))
    }

    let error = await model.closeSession(
        sessionID,
        confirmedDestructiveCleanup: true
    )
    await runtime.emitLateEvent()
    try await Task.sleep(for: .milliseconds(20))

    #expect(error == nil)
    #expect(model.sessions[sessionID] == nil)
    #expect(model.sessionOrder[profile.id]?.contains(sessionID) == false)
}

@Test
func timelineTimestampsRespectDayLocaleAndTimeZone() throws {
    let timeZone = try #require(TimeZone(identifier: "Europe/London"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let now = try #require(
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 28, hour: 18))
    )
    let today = try #require(
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 28, hour: 9, minute: 5))
    )
    let older = try #require(
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 27, hour: 21, minute: 30))
    )

    let todayText = TimelineTimestampFormatter.string(
        for: today,
        now: now,
        calendar: calendar,
        locale: Locale(identifier: "en_GB"),
        timeZone: timeZone
    )
    let olderText = TimelineTimestampFormatter.string(
        for: older,
        now: now,
        calendar: calendar,
        locale: Locale(identifier: "en_GB"),
        timeZone: timeZone
    )

    #expect(todayText.contains("09:05"))
    #expect(!todayText.contains("2026"))
    #expect(olderText.contains("27"))
    #expect(olderText.contains("2026"))
    #expect(olderText.contains("21:30"))
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

@Test
func makeHandoffFallsBackToTheLatestHandoffEntryWhenNoUserEntryExists() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-worktrees-fallback-\(UUID().uuidString)",
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

    var builder = BotProfile(
        id: UUID(),
        name: "Handed-off Builder",
        provider: .claude,
        role: .builder,
        instructions: "",
        workingDirectory: repository.path
    )
    let manager = GitWorktreeManager()
    let ownership = try await manager.prepareWorktree(
        for: builder,
        startingPoint: nil,
        handoffID: nil
    )
    builder.worktree = ownership

    let sessionWithNoUserEntry = AgentSessionState(
        entries: [
            .init(
                kind: .handoff,
                title: "Handoff from Manager",
                text: "Implement isolated worktrees from a resumed handoff"
            )
        ]
    )
    let package = try await manager.makeHandoff(
        from: builder,
        session: sessionWithNoUserEntry
    )
    #expect(
        package.taskContext
            == "Implement isolated worktrees from a resumed handoff"
    )

    let sessionWithNoContextAtAll = AgentSessionState(
        entries: [.init(kind: .system, text: "Session recovered")]
    )
    let fallbackPackage = try await manager.makeHandoff(
        from: builder,
        session: sessionWithNoContextAtAll
    )
    #expect(fallbackPackage.taskContext == "No task context was captured.")
}

@Test
func handoffEvidenceRecognizesWrapperCommandsAndSuccessTitles() {
    let timestamp = Date()
    let evidence = HandoffTestEvidence.latest(
        in: [
            .init(
                kind: .command,
                title: "Process exited 0",
                text: "./ci/verify",
                detail: "61 tests passed",
                timestamp: timestamp
            )
        ]
    )

    #expect(evidence.status == .passed)
    #expect(evidence.summary.contains("./ci/verify"))
    #expect(evidence.recordedAt == timestamp)

    let makeEvidence = HandoffTestEvidence.latest(
        in: [
            .init(
                kind: .command,
                title: "Tool finished",
                text: "make test",
                detail: "All checks green"
            )
        ]
    )
    #expect(makeEvidence.status == .passed)
}

@Test
func handoffEvidenceIgnoresGenericToolOutputThatMentionsTests() {
    let evidence = HandoffTestEvidence.latest(
        in: [
            .init(
                kind: .command,
                title: "Tool finished",
                text: "Read",
                detail: "A changelog entry says 61 tests passed."
            ),
            .init(
                kind: .command,
                title: "Using Grep",
                text: "Grep",
                detail: "0 failures"
            )
        ]
    )

    #expect(evidence.status == .notRun)
    #expect(evidence.recordedAt == nil)
}

@Test
func oneBuilderProfileGetsUniqueSessionWorktreesAndCleanupRetainsBranches() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-session-worktrees-\(UUID().uuidString)")
    let repository = root.appendingPathComponent("project", isDirectory: true)
    try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try runGit(["init", "-b", "main"], in: repository)
    try Data("initial\n".utf8).write(to: repository.appendingPathComponent("README.md"))
    try runGit(["add", "README.md"], in: repository)
    try runGit(
        [
            "-c", "user.name=bl00p Tests",
            "-c", "user.email=tests@bl00p.dev",
            "commit", "-m", "Initial commit"
        ],
        in: repository
    )

    let profile = BotProfile(
        name: "Builder",
        provider: .claude,
        role: .builder,
        instructions: "",
        workingDirectory: repository.path
    )
    let firstSessionID = UUID()
    let secondSessionID = UUID()
    let manager = GitWorktreeManager()
    let first = try await manager.prepareWorktree(
        for: profile,
        sessionID: firstSessionID,
        startingPoint: nil,
        handoffID: nil
    )
    let second = try await manager.prepareWorktree(
        for: profile,
        sessionID: secondSessionID,
        startingPoint: nil,
        handoffID: nil
    )

    #expect(first.ownerSessionID == firstSessionID)
    #expect(second.ownerSessionID == secondSessionID)
    #expect(first.worktreePath != second.worktreePath)
    #expect(first.branch != second.branch)
    #expect(try await manager.worktreeIsDirty(first) == false)

    try await manager.removeWorktree(first, force: false)
    #expect(!FileManager.default.fileExists(atPath: first.worktreePath))
    try runGit(
        ["show-ref", "--verify", "--quiet", "refs/heads/\(first.branch)"],
        in: repository
    )

    try Data("dirty\n".utf8).write(
        to: URL(fileURLWithPath: second.worktreePath)
            .appendingPathComponent("uncommitted.txt")
    )
    #expect(try await manager.worktreeIsDirty(second))
    try await manager.removeWorktree(second, force: true)
    #expect(!FileManager.default.fileExists(atPath: second.worktreePath))
    try runGit(
        ["show-ref", "--verify", "--quiet", "refs/heads/\(second.branch)"],
        in: repository
    )

    let unsafe = GitWorktreeOwnership(
        ownerProfileID: profile.id,
        ownerSessionID: UUID(),
        repositoryPath: repository.path,
        worktreePath: repository.path,
        branch: "main",
        baseRevision: "HEAD"
    )
    await #expect(throws: GitWorktreeError.self) {
        _ = try await manager.worktreeIsDirty(unsafe)
    }
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
    try store.saveFixture(
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
    #expect(model.session(for: target.id).repositoryPath
        == package.repositoryPath)

    model.send("Review this implementation", to: target.id)
    for _ in 0..<30 where await runtime.messages.isEmpty {
        try await Task.sleep(for: .milliseconds(10))
    }

    let delivered = try #require(await runtime.messages.first)
    #expect(delivered.contains("Source branch: \(package.branch)"))
    #expect(delivered.contains("Test state: Passed"))
    #expect(delivered.contains("Next instruction:\nReview this implementation"))
    #expect(await runtime.respondedDirectories == [package.worktreePath])
    #expect(model.session(for: target.id).pendingHandoff == nil)
}

@MainActor
@Test
func manualHandoffButtonDeliversTheWorkflowPlanInsteadOfTheFallbackString() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-manual-handoff-workflow-\(UUID().uuidString)",
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
    let managerID = UUID()
    let team = ManagerTeamConfiguration(
        builderProfileID: source.id,
        reviewerProfileID: target.id
    )
    let manager = BotProfile(
        id: managerID,
        name: "Manager",
        provider: .codex,
        role: .manager,
        instructions: "Coordinate.",
        managerTeam: team
    )
    let workflow = ManagerWorkflow(
        managerProfileID: managerID,
        team: team,
        request: "Ship the feature",
        implementationPlan: "Implement the feature end to end, with tests.",
        stage: .building,
        participantSessionIDs: [.builder: source.id, .reviewer: target.id]
    )
    let package = GitHandoffPackage(
        sourceProfileID: source.id,
        sourceName: source.name,
        repositoryPath: "/tmp/project",
        worktreePath: "/tmp/project-builder",
        branch: "bl00p/source-12345678",
        baseRevision: "abc123",
        headRevision: "def456",
        taskContext: "No task context was captured.",
        testStatus: .passed,
        testSummary: "`swift test` — passed",
        workingTreeSummary: "Clean"
    )
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    try store.saveFixture(
        PersistedAppState(
            profiles: [manager, source, target],
            sessions: [
                source.id: AgentSessionState(status: .completed),
                target.id: AgentSessionState()
            ],
            selectedBotID: source.id,
            managerWorkflows: [managerID: workflow]
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

    #expect(
        model.session(for: target.id).pendingHandoff?.taskContext
            == "Implement the feature end to end, with tests."
    )
    #expect(
        model.session(for: target.id).entries.last?.text
            == "Implement the feature end to end, with tests."
    )
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
    let initialPackage = GitHandoffPackage(
        sourceProfileID: builderID,
        sourceName: "Builder",
        repositoryPath: ownership.repositoryPath,
        worktreePath: ownership.worktreePath,
        branch: ownership.branch,
        baseRevision: ownership.baseRevision,
        headRevision: "def456",
        taskContext: "Add optional orchestration",
        testStatus: .passed,
        testSummary: "`swift test` — 12 tests passed",
        testEvidenceAt: .distantFuture,
        workingTreeSummary: "Clean"
    )
    let revisedPackage = GitHandoffPackage(
        sourceProfileID: builderID,
        sourceName: "Builder",
        repositoryPath: ownership.repositoryPath,
        worktreePath: ownership.worktreePath,
        branch: ownership.branch,
        baseRevision: ownership.baseRevision,
        headRevision: "789abc",
        taskContext: "Add optional orchestration",
        testStatus: .passed,
        testSummary: "`swift test` — 42 tests passed",
        testEvidenceAt: .distantFuture,
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
    try store.saveFixture(
        PersistedAppState(
            profiles: [manager, builder, reviewer, publisher],
            sessions: initialSessions,
            selectedBotID: managerID
        )
    )
    let runtime = OrchestrationRecordingRuntime(
        reviewerResponseBlocks: [
            [
                "Review finding: add a regression test.",
                """
                Also verify pipeline permissions.
                BL00P_REVIEW_DISPOSITION: changesRequested
                """
            ],
            [
                """
                Review clean. Ready to publish.
                BL00P_REVIEW_DISPOSITION: clean
                """
            ]
        ],
        managerPlanningResponses: [orchestrationImplementationPlan]
    )
    let model = AppModel(
        runtime: runtime,
        worktrees: StubWorktreeManager(
            packages: [initialPackage, revisedPackage],
            preparedOwnership: ownership
        ),
        store: store
    )

    let originalRequest = "Add optional orchestration"
    model.send(originalRequest, to: managerID)

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
    let planText = orchestrationImplementationPlan
    let managerEntries = model.session(for: managerID).entries
    let displayedPlanEntries = managerEntries.filter {
        $0.text == planText
    }
    let runtimePlanEntryID = try #require(
        await runtime.assistantEntryIDs.first
    )
    #expect(displayedPlanEntries.count == 1)
    #expect(displayedPlanEntries.first?.kind == .approval)
    #expect(displayedPlanEntries.first?.id == approvalEntry.id)
    #expect(displayedPlanEntries.first?.contentFormat == .markdown)
    #expect(approvalEntry.id != runtimePlanEntryID)
    #expect(managerEntries.last?.id == approvalEntry.id)
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
    let builderSessionID = try #require(
        workflow.participantSessionIDs[.builder]
    )
    let reviewerSessionID = try #require(
        workflow.participantSessionIDs[.reviewer]
    )
    let publisherSessionID = try #require(
        workflow.participantSessionIDs[.publisher]
    )
    let builderBrief = try #require(
        model.sessions[builderSessionID]?.entries.first(where: {
            $0.title == "Implementation brief"
        })
    )
    let runtimePlan = try #require(
        taggedField(
            "approved_implementation_plan",
            in: calls[1].message
        )
    )
    #expect(workflow.stage == .completed)
    #expect(workflow.implementationPlan == orchestrationImplementationPlan)
    #expect(workflow.approvedPlanEntryID == approvalEntry.id)
    #expect(workflow.branch == ownership.branch)
    #expect(
        workflow.reviewSummary?.contains(
            "Review finding: add a regression test."
        ) == true
    )
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
                .publisher
            ]
    )
    #expect(builderBrief.text == orchestrationImplementationPlan)
    #expect(
        builderBrief.detail?.contains(
            "Original request:\n\(originalRequest)"
        ) == true
    )
    #expect(runtimePlan == orchestrationImplementationPlan)
    #expect(
        taggedField("original_request", in: calls[1].message)
            == originalRequest
    )
    #expect(calls[2].message.contains("Source branch: \(ownership.branch)"))
    #expect(calls[2].message.contains("Test state: Passed"))
    #expect(calls[2].message.contains(initialPackage.testSummary))
    #expect(calls[3].message.contains("Review finding"))
    #expect(calls[3].message.contains("Also verify pipeline permissions."))
    #expect(calls[4].message.contains("Re-check the updated"))
    #expect(calls[5].message.contains("create a draft pull request"))
    #expect(!calls[5].message.contains("Review finding:"))
    #expect(calls[5].message.contains("Source branch: \(ownership.branch)"))
    #expect(calls[5].message.contains("Source HEAD: \(revisedPackage.headRevision)"))
    #expect(calls[5].message.contains("Test state: Passed"))
    #expect(calls[5].message.contains(revisedPackage.testSummary))
    #expect(workflow.verificationSummary?.contains("Review clean") == true)
    #expect(workflow.publisherSummary?.contains("Documentation committed") == true)
    #expect(await runtime.approvalResolutionCount == 0)
    #expect(calls[0].workingDirectory == ownership.repositoryPath)
    #expect(calls[1].workingDirectory == ownership.worktreePath)
    #expect(calls[2].workingDirectory == ownership.worktreePath)
    #expect(calls[5].workingDirectory == ownership.worktreePath)
    #expect(
        model.sessions[publisherSessionID]?.entries.contains(where: {
            $0.title == "Workflow handoff from Reviewer"
                && $0.detail?.contains(revisedPackage.headRevision) == true
        }) == true
    )
    let reviewerHandoff = try #require(
        model.sessions[reviewerSessionID]?.entries.first(where: {
            $0.kind == .handoff
                && $0.title?.hasPrefix("Workflow handoff") == true
        })
    )
    #expect(reviewerHandoff.text == orchestrationImplementationPlan)

    let restoredModel = AppModel(runtime: runtime, store: store)
    let restoredWorkflow = try #require(
        restoredModel.workflow(for: managerID)
    )
    let restoredApproval = try #require(
        restoredModel.session(for: managerID).entries.first(where: {
            $0.id == approvalEntry.id
        })
    )
    #expect(
        restoredWorkflow.implementationPlan
            == orchestrationImplementationPlan
    )
    #expect(restoredWorkflow.approvedPlanEntryID == approvalEntry.id)
    #expect(restoredApproval.text == orchestrationImplementationPlan)
    #expect(restoredApproval.approvalState == .approved)
}

@MainActor
@Test
func managerPlanInASecondaryChatBecomesAnApprovalCard() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-secondary-manager-plan-\(UUID().uuidString)",
            isDirectory: true
        )
    defer { try? FileManager.default.removeItem(at: directory) }

    let fixture = managedWorkflowFixture()
    let plan = """
    ## Implementation plan

    1. Make plan capture session-aware.
    2. Add a regression test.
    """
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    try store.saveFixture(
        PersistedAppState(
            profiles: fixture.profiles,
            sessions: Dictionary(
                uniqueKeysWithValues: fixture.profiles.map {
                    ($0.id, AgentSessionState())
                }
            ),
            selectedBotID: fixture.manager.id
        )
    )
    let runtime = OrchestrationRecordingRuntime(
        managerPlanningResponses: [plan]
    )
    let model = AppModel(runtime: runtime, store: store)
    let managerChatID = model.newChat(for: fixture.manager.id)
    #expect(
        model.setRepositoryPath("/tmp/project", for: managerChatID)
    )

    model.send("Plan this change", to: fixture.manager.id)
    for _ in 0..<100
        where model.session(for: fixture.manager.id).status
            != .needsApproval {
        try await Task.sleep(for: .milliseconds(10))
    }

    let session = try #require(model.sessions[managerChatID])
    let approval = try #require(
        session.entries.last(where: {
            $0.kind == .approval && $0.approvalState == .pending
        })
    )
    #expect(managerChatID != fixture.manager.id)
    #expect(session.status == .needsApproval)
    #expect(approval.title == "Approve implementation plan")
    #expect(approval.text == plan)
    #expect(approval.contentFormat == .markdown)
    #expect(
        session.entries.contains(where: {
            $0.kind == .assistant && $0.text == plan
        }) == false
    )
    #expect(
        model.managerWorkflows[managerChatID]?.planApprovalEntryID
            == approval.id
    )
}

@MainActor
@Test
func invalidRevisedBuilderHandoffPausesBeforeDocumenterRuns() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-invalid-revision-handoff-\(UUID().uuidString)",
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
    let revisionStartedAt = Date()
    let initialPackage = GitHandoffPackage(
        sourceProfileID: builderID,
        sourceName: "Builder",
        repositoryPath: ownership.repositoryPath,
        worktreePath: ownership.worktreePath,
        branch: ownership.branch,
        baseRevision: ownership.baseRevision,
        headRevision: "def456",
        taskContext: "Ship the feature",
        testStatus: .passed,
        testSummary: "`swift test` — passed",
        testEvidenceAt: .distantFuture,
        workingTreeSummary: "Clean"
    )
    let missingCommitRevision = GitHandoffPackage(
        sourceProfileID: builderID,
        sourceName: "Builder",
        repositoryPath: ownership.repositoryPath,
        worktreePath: ownership.worktreePath,
        branch: ownership.branch,
        baseRevision: ownership.baseRevision,
        headRevision: initialPackage.headRevision,
        taskContext: "Ship the feature",
        testStatus: .passed,
        testSummary: "`swift test` — passed",
        workingTreeSummary: "Clean"
    )
    let dirtyRevision = GitHandoffPackage(
        sourceProfileID: builderID,
        sourceName: "Builder",
        repositoryPath: ownership.repositoryPath,
        worktreePath: ownership.worktreePath,
        branch: ownership.branch,
        baseRevision: ownership.baseRevision,
        headRevision: "789abc",
        taskContext: "Ship the feature",
        testStatus: .passed,
        testSummary: "`swift test` — passed",
        testEvidenceAt: .distantFuture,
        workingTreeSummary: " M Sources/Feature.swift"
    )
    let failingRevision = GitHandoffPackage(
        sourceProfileID: builderID,
        sourceName: "Builder",
        repositoryPath: ownership.repositoryPath,
        worktreePath: ownership.worktreePath,
        branch: ownership.branch,
        baseRevision: ownership.baseRevision,
        headRevision: "789abc",
        taskContext: "Ship the feature",
        testStatus: .failed,
        testSummary: "`swift test` — failed",
        testEvidenceAt: .distantFuture,
        workingTreeSummary: "Clean"
    )
    let untestedRevision = GitHandoffPackage(
        sourceProfileID: builderID,
        sourceName: "Builder",
        repositoryPath: ownership.repositoryPath,
        worktreePath: ownership.worktreePath,
        branch: ownership.branch,
        baseRevision: ownership.baseRevision,
        headRevision: "789abc",
        taskContext: "Ship the feature",
        testStatus: .notRun,
        testSummary: "No test command was recorded.",
        workingTreeSummary: "Clean"
    )
    let staleTestRevision = GitHandoffPackage(
        sourceProfileID: builderID,
        sourceName: "Builder",
        repositoryPath: ownership.repositoryPath,
        worktreePath: ownership.worktreePath,
        branch: ownership.branch,
        baseRevision: ownership.baseRevision,
        headRevision: "789abc",
        taskContext: "Ship the feature",
        testStatus: .passed,
        testSummary: "`swift test` — passed before review",
        testEvidenceAt: revisionStartedAt.addingTimeInterval(-1),
        workingTreeSummary: "Clean"
    )
    let team = ManagerTeamConfiguration(
        builderProfileID: builderID,
        reviewerProfileID: reviewerID,
        publisherProfileID: publisherID
    )
    let manager = BotProfile(
        id: managerID,
        name: "Manager",
        provider: .codex,
        role: .manager,
        instructions: "Coordinate.",
        managerTeam: team
    )
    let builder = BotProfile(
        id: builderID,
        name: "Builder",
        provider: .claude,
        role: .builder,
        instructions: "Implement.",
        workingDirectory: ownership.repositoryPath,
        worktree: ownership
    )
    let reviewer = BotProfile(
        id: reviewerID,
        name: "Reviewer",
        provider: .codex,
        role: .reviewer,
        instructions: "Review."
    )
    let publisher = BotProfile(
        id: publisherID,
        name: "Documenter",
        provider: .claude,
        role: .publisher,
        instructions: "Publish."
    )
    let workflow = ManagerWorkflow(
        managerProfileID: managerID,
        team: team,
        request: "Ship the feature",
        stage: .revising,
        branch: ownership.branch,
        latestHandoff: initialPackage,
        reviewSummary: """
        Review finding: add a regression test.

        Review status: changes requested
        """,
        revisionStartedAt: revisionStartedAt
    )
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    store.save(
        PersistedAppState(
            profiles: [manager, builder, reviewer, publisher],
            sessions: [
                managerID: AgentSessionState(),
                builderID: AgentSessionState(),
                reviewerID: AgentSessionState(
                    entries: [
                        .init(
                            kind: .assistant,
                            text: "Review finding: add a regression test."
                        )
                    ]
                ),
                publisherID: AgentSessionState()
            ],
            selectedBotID: builderID,
            managerWorkflows: [managerID: workflow]
        )
    )
    let runtime = OrchestrationRecordingRuntime()
    let model = AppModel(
        runtime: runtime,
        worktrees: StubWorktreeManager(
            packages: [
                missingCommitRevision,
                dirtyRevision,
                failingRevision,
                untestedRevision,
                staleTestRevision
            ],
            preparedOwnership: ownership
        ),
        store: store
    )

    model.send("Finish the revision pass", to: builderID)
    for _ in 0..<100
        where model.workflow(for: managerID)?.pauseReason
            != "The Builder revision pass has no new local commit." {
        try await Task.sleep(for: .milliseconds(10))
    }

    let paused = try #require(model.workflow(for: managerID))
    #expect(paused.stage == .revising)
    #expect(paused.isPaused)
    #expect(
        paused.pauseReason
            == "The Builder revision pass has no new local commit."
    )
    #expect(paused.latestHandoff?.headRevision == initialPackage.headRevision)
    #expect(await runtime.calls.map(\.role) == [.builder])
    #expect(model.session(for: publisherID).entries.isEmpty)

    model.send("Commit the remaining changes", to: builderID)
    for _ in 0..<100
        where model.workflow(for: managerID)?.pauseReason
            != "The Builder handoff still has uncommitted changes." {
        try await Task.sleep(for: .milliseconds(10))
    }

    let dirty = try #require(model.workflow(for: managerID))
    #expect(dirty.stage == .revising)
    #expect(dirty.isPaused)
    #expect(
        dirty.pauseReason
            == "The Builder handoff still has uncommitted changes."
    )
    #expect(dirty.latestHandoff?.headRevision == initialPackage.headRevision)
    #expect(await runtime.calls.map(\.role) == [.builder, .builder])
    #expect(model.session(for: publisherID).entries.isEmpty)

    model.send("Fix the tests", to: builderID)
    for _ in 0..<100
        where model.workflow(for: managerID)?.pauseReason
            != "The Builder handoff does not report passing tests from the revision pass." {
        try await Task.sleep(for: .milliseconds(10))
    }

    let failing = try #require(model.workflow(for: managerID))
    #expect(failing.stage == .revising)
    #expect(failing.isPaused)
    #expect(
        failing.pauseReason
            == "The Builder handoff does not report passing tests from the revision pass."
    )
    #expect(failing.latestHandoff?.headRevision == initialPackage.headRevision)
    #expect(
        await runtime.calls.map(\.role)
            == [.builder, .builder, .builder]
    )
    #expect(model.session(for: publisherID).entries.isEmpty)

    model.send("Run the tests after review", to: builderID)
    for _ in 0..<100 where await runtime.calls.count < 4 {
        try await Task.sleep(for: .milliseconds(10))
    }

    let untested = try #require(model.workflow(for: managerID))
    #expect(untested.stage == .revising)
    #expect(untested.isPaused)
    #expect(
        untested.pauseReason
            == "The Builder handoff does not report passing tests from the revision pass."
    )
    #expect(
        untested.latestHandoff?.headRevision
            == initialPackage.headRevision
    )
    #expect(
        await runtime.calls.map(\.role)
            == [.builder, .builder, .builder, .builder]
    )
    #expect(model.session(for: publisherID).entries.isEmpty)

    model.send("Re-run the tests after review", to: builderID)
    for _ in 0..<100 where await runtime.calls.count < 5 {
        try await Task.sleep(for: .milliseconds(10))
    }

    let stale = try #require(model.workflow(for: managerID))
    #expect(stale.stage == .revising)
    #expect(stale.isPaused)
    #expect(
        stale.pauseReason
            == "The Builder handoff does not report passing tests from the revision pass."
    )
    #expect(stale.latestHandoff?.headRevision == initialPackage.headRevision)
    #expect(
        await runtime.calls.map(\.role)
            == [.builder, .builder, .builder, .builder, .builder]
    )
    #expect(model.session(for: publisherID).entries.isEmpty)
}

@MainActor
@Test
func blockedBuilderTurnWithReadyHandoffAdvancesWorkflowAutomatically() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-blocked-builder-ready-\(UUID().uuidString)",
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
    let readyPackage = GitHandoffPackage(
        sourceProfileID: builderID,
        sourceName: "Builder",
        repositoryPath: ownership.repositoryPath,
        worktreePath: ownership.worktreePath,
        branch: ownership.branch,
        baseRevision: ownership.baseRevision,
        headRevision: "def456",
        taskContext: "This gets overwritten with the implementation plan.",
        testStatus: .passed,
        testSummary: "`swift test` — passed",
        testEvidenceAt: .distantFuture,
        workingTreeSummary: "Clean"
    )
    let team = ManagerTeamConfiguration(
        builderProfileID: builderID,
        reviewerProfileID: reviewerID,
        publisherProfileID: publisherID
    )
    let manager = BotProfile(
        id: managerID,
        name: "Manager",
        provider: .codex,
        role: .manager,
        instructions: "Coordinate.",
        managerTeam: team
    )
    let builder = BotProfile(
        id: builderID,
        name: "Builder",
        provider: .claude,
        role: .builder,
        instructions: "Implement.",
        workingDirectory: ownership.repositoryPath,
        worktree: ownership
    )
    let reviewer = BotProfile(
        id: reviewerID,
        name: "Reviewer",
        provider: .codex,
        role: .reviewer,
        instructions: "Review.",
        workingDirectory: ownership.repositoryPath
    )
    let publisher = BotProfile(
        id: publisherID,
        name: "Documenter",
        provider: .claude,
        role: .publisher,
        instructions: "Publish.",
        workingDirectory: ownership.repositoryPath
    )
    let workflow = ManagerWorkflow(
        managerProfileID: managerID,
        repositoryPath: ownership.repositoryPath,
        team: team,
        request: "Ship the feature",
        implementationPlan: "Implement the feature end to end.",
        stage: .building,
        branch: ownership.branch
    )
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    store.save(
        PersistedAppState(
            profiles: [manager, builder, reviewer, publisher],
            sessions: [
                managerID: AgentSessionState(),
                builderID: AgentSessionState(
                    entries: [
                        TimelineEntry(
                            kind: .handoff,
                            title: "Implementation brief",
                            text: "Implement the feature end to end."
                        )
                    ]
                ),
                reviewerID: AgentSessionState(),
                publisherID: AgentSessionState()
            ],
            selectedBotID: builderID,
            managerWorkflows: [managerID: workflow]
        )
    )
    let runtime = BuilderStatusStubRuntime(builderFinalStatus: .blocked)
    let model = AppModel(
        runtime: runtime,
        worktrees: StubWorktreeManager(
            package: readyPackage,
            preparedOwnership: ownership
        ),
        store: store
    )

    model.send("Implement the feature", to: builderID)
    for _ in 0..<100 where await runtime.calls.count < 2 {
        try await Task.sleep(for: .milliseconds(10))
    }

    let advanced = try #require(model.workflow(for: managerID))
    #expect(advanced.stage == .reviewing)
    #expect(!advanced.isPaused)
    #expect(
        advanced.latestHandoff?.taskContext
            == "Implement the feature end to end."
    )
    #expect(await runtime.calls == [.builder, .reviewer])
    #expect(model.session(for: reviewerID).entries.contains {
        $0.kind == .handoff
    })
}

@MainActor
@Test
func blockedBuilderTurnWithUnverifiedTestsAdvancesWithACaveat() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-blocked-builder-unverified-\(UUID().uuidString)",
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
    let unverifiedPackage = GitHandoffPackage(
        sourceProfileID: builderID,
        sourceName: "Builder",
        repositoryPath: ownership.repositoryPath,
        worktreePath: ownership.worktreePath,
        branch: ownership.branch,
        baseRevision: ownership.baseRevision,
        headRevision: "def456",
        taskContext: "This gets overwritten with the implementation plan.",
        testStatus: .notRun,
        testSummary: "No test command was recorded.",
        workingTreeSummary: "Clean"
    )
    let team = ManagerTeamConfiguration(
        builderProfileID: builderID,
        reviewerProfileID: reviewerID,
        publisherProfileID: publisherID
    )
    let manager = BotProfile(
        id: managerID,
        name: "Manager",
        provider: .codex,
        role: .manager,
        instructions: "Coordinate.",
        managerTeam: team
    )
    let builder = BotProfile(
        id: builderID,
        name: "Builder",
        provider: .claude,
        role: .builder,
        instructions: "Implement.",
        workingDirectory: ownership.repositoryPath,
        worktree: ownership
    )
    let reviewer = BotProfile(
        id: reviewerID,
        name: "Reviewer",
        provider: .codex,
        role: .reviewer,
        instructions: "Review.",
        workingDirectory: ownership.repositoryPath
    )
    let publisher = BotProfile(
        id: publisherID,
        name: "Documenter",
        provider: .claude,
        role: .publisher,
        instructions: "Publish.",
        workingDirectory: ownership.repositoryPath
    )
    let workflow = ManagerWorkflow(
        managerProfileID: managerID,
        repositoryPath: ownership.repositoryPath,
        team: team,
        request: "Ship the feature",
        implementationPlan: "Implement the feature end to end.",
        stage: .building,
        branch: ownership.branch
    )
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    store.save(
        PersistedAppState(
            profiles: [manager, builder, reviewer, publisher],
            sessions: [
                managerID: AgentSessionState(),
                builderID: AgentSessionState(
                    entries: [
                        TimelineEntry(
                            kind: .handoff,
                            title: "Implementation brief",
                            text: "Implement the feature end to end."
                        )
                    ]
                ),
                reviewerID: AgentSessionState(),
                publisherID: AgentSessionState()
            ],
            selectedBotID: builderID,
            managerWorkflows: [managerID: workflow]
        )
    )
    let runtime = BuilderStatusStubRuntime(
        builderFinalStatus: .blocked,
        blockedActionDetail: "• swift test"
    )
    let model = AppModel(
        runtime: runtime,
        worktrees: StubWorktreeManager(
            package: unverifiedPackage,
            preparedOwnership: ownership
        ),
        store: store
    )

    model.send("Implement the feature", to: builderID)
    for _ in 0..<100 where await runtime.calls.count < 2 {
        try await Task.sleep(for: .milliseconds(10))
    }

    let advanced = try #require(model.workflow(for: managerID))
    #expect(advanced.stage == .reviewing)
    #expect(!advanced.isPaused)
    #expect(!advanced.awaitingBuilderHandoffRetry)
    #expect(advanced.latestHandoff?.testStatus == .unverified)
    #expect(
        advanced.latestHandoff?.testSummary.contains("action was blocked")
            == true
    )
    #expect(
        advanced.latestHandoff?.testSummary.contains("swift test") == true
    )
    #expect(await runtime.calls == [.builder, .reviewer])
    #expect(model.session(for: reviewerID).entries.contains {
        $0.kind == .handoff
            && $0.detail?.contains("Unverified (blocked)") == true
    })
}

@MainActor
@Test
func blockedBuilderTurnWithUnrelatedDenialDoesNotEarnATestCaveat() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-blocked-builder-unrelated-denial-\(UUID().uuidString)",
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
    let revisionStartedAt = Date()
    let untestedRevision = GitHandoffPackage(
        sourceProfileID: builderID,
        sourceName: "Builder",
        repositoryPath: ownership.repositoryPath,
        worktreePath: ownership.worktreePath,
        branch: ownership.branch,
        baseRevision: ownership.baseRevision,
        headRevision: "def456",
        taskContext: "Ship the feature",
        testStatus: .notRun,
        testSummary: "No test command was recorded.",
        workingTreeSummary: "Clean"
    )
    let team = ManagerTeamConfiguration(
        builderProfileID: builderID,
        reviewerProfileID: reviewerID,
        publisherProfileID: publisherID
    )
    let manager = BotProfile(
        id: managerID,
        name: "Manager",
        provider: .codex,
        role: .manager,
        instructions: "Coordinate.",
        managerTeam: team
    )
    let builder = BotProfile(
        id: builderID,
        name: "Builder",
        provider: .claude,
        role: .builder,
        instructions: "Implement.",
        workingDirectory: ownership.repositoryPath,
        worktree: ownership
    )
    let reviewer = BotProfile(
        id: reviewerID,
        name: "Reviewer",
        provider: .codex,
        role: .reviewer,
        instructions: "Review.",
        workingDirectory: ownership.repositoryPath
    )
    let publisher = BotProfile(
        id: publisherID,
        name: "Documenter",
        provider: .claude,
        role: .publisher,
        instructions: "Publish.",
        workingDirectory: ownership.repositoryPath
    )
    let workflow = ManagerWorkflow(
        managerProfileID: managerID,
        repositoryPath: ownership.repositoryPath,
        team: team,
        request: "Ship the feature",
        stage: .revising,
        branch: ownership.branch,
        latestHandoff: GitHandoffPackage(
            sourceProfileID: builderID,
            sourceName: "Builder",
            repositoryPath: ownership.repositoryPath,
            worktreePath: ownership.worktreePath,
            branch: ownership.branch,
            baseRevision: ownership.baseRevision,
            headRevision: "abc123",
            taskContext: "Ship the feature",
            testStatus: .passed,
            testSummary: "`swift test` — passed",
            workingTreeSummary: "Clean"
        ),
        reviewSummary: "Review finding: add a regression test.",
        revisionStartedAt: revisionStartedAt
    )
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    store.save(
        PersistedAppState(
            profiles: [manager, builder, reviewer, publisher],
            sessions: [
                managerID: AgentSessionState(),
                builderID: AgentSessionState(
                    entries: [
                        TimelineEntry(
                            kind: .handoff,
                            title: "Implementation brief",
                            text: "Implement the feature end to end."
                        )
                    ]
                ),
                reviewerID: AgentSessionState(),
                publisherID: AgentSessionState()
            ],
            selectedBotID: builderID,
            managerWorkflows: [managerID: workflow]
        )
    )
    // The denial is real, but it has nothing to do with running tests, so it
    // must not be treated as evidence that the test command itself was
    // blocked.
    let runtime = BuilderStatusStubRuntime(
        builderFinalStatus: .blocked,
        blockedActionDetail: "• rm -rf build"
    )
    let model = AppModel(
        runtime: runtime,
        worktrees: StubWorktreeManager(
            package: untestedRevision,
            preparedOwnership: ownership
        ),
        store: store
    )

    model.send("Finish the revision pass", to: builderID)
    for _ in 0..<100
        where model.workflow(for: managerID)?.pauseReason == nil {
        try await Task.sleep(for: .milliseconds(10))
    }

    let paused = try #require(model.workflow(for: managerID))
    #expect(paused.stage == .revising)
    #expect(paused.isPaused)
    #expect(
        paused.pauseReason
            == "The Builder handoff does not report passing tests from the revision pass."
    )
    #expect(paused.awaitingBuilderHandoffRetry)
    #expect(model.session(for: reviewerID).entries.isEmpty)
}

@MainActor
@Test
func revisitedBuilderTurnDoesNotReuseAStaleBlockedActionFromAnEarlierTurn() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-stale-blocked-action-\(UUID().uuidString)",
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
    let noCommitPackage = GitHandoffPackage(
        sourceProfileID: builderID,
        sourceName: "Builder",
        repositoryPath: ownership.repositoryPath,
        worktreePath: ownership.worktreePath,
        branch: ownership.branch,
        baseRevision: ownership.baseRevision,
        headRevision: ownership.baseRevision,
        taskContext: "Ship the feature",
        testStatus: .notRun,
        testSummary: "No test command was recorded.",
        workingTreeSummary: "Clean"
    )
    let untestedButCommittedPackage = GitHandoffPackage(
        sourceProfileID: builderID,
        sourceName: "Builder",
        repositoryPath: ownership.repositoryPath,
        worktreePath: ownership.worktreePath,
        branch: ownership.branch,
        baseRevision: ownership.baseRevision,
        headRevision: "def456",
        taskContext: "This gets overwritten with the implementation plan.",
        testStatus: .notRun,
        testSummary: "No test command was recorded.",
        workingTreeSummary: "Clean"
    )
    let team = ManagerTeamConfiguration(
        builderProfileID: builderID,
        reviewerProfileID: reviewerID,
        publisherProfileID: publisherID
    )
    let manager = BotProfile(
        id: managerID,
        name: "Manager",
        provider: .codex,
        role: .manager,
        instructions: "Coordinate.",
        managerTeam: team
    )
    let builder = BotProfile(
        id: builderID,
        name: "Builder",
        provider: .claude,
        role: .builder,
        instructions: "Implement.",
        workingDirectory: ownership.repositoryPath,
        worktree: ownership
    )
    let reviewer = BotProfile(
        id: reviewerID,
        name: "Reviewer",
        provider: .codex,
        role: .reviewer,
        instructions: "Review.",
        workingDirectory: ownership.repositoryPath
    )
    let publisher = BotProfile(
        id: publisherID,
        name: "Documenter",
        provider: .claude,
        role: .publisher,
        instructions: "Publish.",
        workingDirectory: ownership.repositoryPath
    )
    let workflow = ManagerWorkflow(
        managerProfileID: managerID,
        repositoryPath: ownership.repositoryPath,
        team: team,
        request: "Ship the feature",
        implementationPlan: "Implement the feature end to end.",
        stage: .building,
        branch: ownership.branch
    )
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    store.save(
        PersistedAppState(
            profiles: [manager, builder, reviewer, publisher],
            sessions: [
                managerID: AgentSessionState(),
                builderID: AgentSessionState(
                    entries: [
                        TimelineEntry(
                            kind: .handoff,
                            title: "Implementation brief",
                            text: "Implement the feature end to end."
                        )
                    ]
                ),
                reviewerID: AgentSessionState(),
                publisherID: AgentSessionState()
            ],
            selectedBotID: builderID,
            managerWorkflows: [managerID: workflow]
        )
    )
    let runtime = TwoTurnBuilderRuntime()
    let model = AppModel(
        runtime: runtime,
        worktrees: StubWorktreeManager(
            packages: [noCommitPackage, untestedButCommittedPackage],
            preparedOwnership: ownership
        ),
        store: store
    )

    // Turn 1: blocked on a test-related denial, but with no commit at all,
    // so the gate hard-pauses without ever advancing. This leaves a
    // test-related "Some actions were blocked" entry in the transcript.
    model.send("Implement the feature", to: builderID)
    for _ in 0..<100
        where model.workflow(for: managerID)?.pauseReason == nil {
        try await Task.sleep(for: .milliseconds(10))
    }
    let afterFirstTurn = try #require(model.workflow(for: managerID))
    #expect(
        afterFirstTurn.pauseReason?
            .hasPrefix("The Builder handoff has no local commit.") == true
    )

    // Turn 2: a fresh explicit send resets the turn boundary. This turn ends
    // blocked again but records no denial of its own. If the stale turn-1
    // "swift test" denial were wrongly reused, it would correlate as
    // test-related and wrongly advance this turn to the Reviewer with a
    // caveat; instead it must hard-pause like any other untested pass.
    model.send("Commit the remaining changes", to: builderID)
    for _ in 0..<100
        where model.workflow(for: managerID)?.pauseReason == nil
            || model.workflow(for: managerID)?.pauseReason
                == afterFirstTurn.pauseReason {
        try await Task.sleep(for: .milliseconds(10))
    }

    let afterSecondTurn = try #require(model.workflow(for: managerID))
    #expect(afterSecondTurn.stage == .building)
    #expect(afterSecondTurn.isPaused)
    #expect(
        afterSecondTurn.pauseReason
            == "The Builder handoff does not report passing tests."
    )
    #expect(afterSecondTurn.awaitingBuilderHandoffRetry)
    #expect(afterSecondTurn.latestHandoff == nil)
    #expect(model.session(for: reviewerID).entries.isEmpty)
}

@MainActor
@Test
func blockedBuilderTurnWithFailingTestsStillPauses() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-blocked-builder-failing-tests-\(UUID().uuidString)",
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
    let failingPackage = GitHandoffPackage(
        sourceProfileID: builderID,
        sourceName: "Builder",
        repositoryPath: ownership.repositoryPath,
        worktreePath: ownership.worktreePath,
        branch: ownership.branch,
        baseRevision: ownership.baseRevision,
        headRevision: "def456",
        taskContext: "This gets overwritten with the implementation plan.",
        testStatus: .failed,
        testSummary: "`swift test` — 1 failure",
        testEvidenceAt: .distantFuture,
        workingTreeSummary: "Clean"
    )
    let team = ManagerTeamConfiguration(
        builderProfileID: builderID,
        reviewerProfileID: reviewerID,
        publisherProfileID: publisherID
    )
    let manager = BotProfile(
        id: managerID,
        name: "Manager",
        provider: .codex,
        role: .manager,
        instructions: "Coordinate.",
        managerTeam: team
    )
    let builder = BotProfile(
        id: builderID,
        name: "Builder",
        provider: .claude,
        role: .builder,
        instructions: "Implement.",
        workingDirectory: ownership.repositoryPath,
        worktree: ownership
    )
    let reviewer = BotProfile(
        id: reviewerID,
        name: "Reviewer",
        provider: .codex,
        role: .reviewer,
        instructions: "Review.",
        workingDirectory: ownership.repositoryPath
    )
    let publisher = BotProfile(
        id: publisherID,
        name: "Documenter",
        provider: .claude,
        role: .publisher,
        instructions: "Publish.",
        workingDirectory: ownership.repositoryPath
    )
    let workflow = ManagerWorkflow(
        managerProfileID: managerID,
        repositoryPath: ownership.repositoryPath,
        team: team,
        request: "Ship the feature",
        implementationPlan: "Implement the feature end to end.",
        stage: .building,
        branch: ownership.branch
    )
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    store.save(
        PersistedAppState(
            profiles: [manager, builder, reviewer, publisher],
            sessions: [
                managerID: AgentSessionState(),
                builderID: AgentSessionState(
                    entries: [
                        TimelineEntry(
                            kind: .handoff,
                            title: "Implementation brief",
                            text: "Implement the feature end to end."
                        )
                    ]
                ),
                reviewerID: AgentSessionState(),
                publisherID: AgentSessionState()
            ],
            selectedBotID: builderID,
            managerWorkflows: [managerID: workflow]
        )
    )
    // A blocked action unrelated to the failing tests must not paper over
    // a genuine test failure.
    let runtime = BuilderStatusStubRuntime(
        builderFinalStatus: .blocked,
        blockedActionDetail: "• rm -rf build"
    )
    let model = AppModel(
        runtime: runtime,
        worktrees: StubWorktreeManager(
            package: failingPackage,
            preparedOwnership: ownership
        ),
        store: store
    )

    model.send("Implement the feature", to: builderID)
    for _ in 0..<100
        where model.workflow(for: managerID)?.pauseReason == nil {
        try await Task.sleep(for: .milliseconds(10))
    }

    let paused = try #require(model.workflow(for: managerID))
    #expect(paused.stage == .building)
    #expect(paused.isPaused)
    #expect(paused.pauseReason == "The Builder reported failing tests.")
    #expect(paused.awaitingBuilderHandoffRetry)
    #expect(paused.latestHandoff == nil)
    #expect(await runtime.calls == [.builder])
    #expect(model.session(for: reviewerID).entries.isEmpty)
}

@MainActor
@Test
func pausedBuilderHandoffSelfHealsWhenTheBuilderNextFinishesReady() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-self-healing-handoff-\(UUID().uuidString)",
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
    let noCommitPackage = GitHandoffPackage(
        sourceProfileID: builderID,
        sourceName: "Builder",
        repositoryPath: ownership.repositoryPath,
        worktreePath: ownership.worktreePath,
        branch: ownership.branch,
        baseRevision: ownership.baseRevision,
        headRevision: ownership.baseRevision,
        taskContext: "Ship the feature",
        testStatus: .passed,
        testSummary: "`swift test` — passed",
        testEvidenceAt: .distantFuture,
        workingTreeSummary: "Clean"
    )
    let readyPackage = GitHandoffPackage(
        sourceProfileID: builderID,
        sourceName: "Builder",
        repositoryPath: ownership.repositoryPath,
        worktreePath: ownership.worktreePath,
        branch: ownership.branch,
        baseRevision: ownership.baseRevision,
        headRevision: "def456",
        taskContext: "This gets overwritten with the implementation plan.",
        testStatus: .passed,
        testSummary: "`swift test` — passed",
        testEvidenceAt: .distantFuture,
        workingTreeSummary: "Clean"
    )
    let team = ManagerTeamConfiguration(
        builderProfileID: builderID,
        reviewerProfileID: reviewerID,
        publisherProfileID: publisherID
    )
    let manager = BotProfile(
        id: managerID,
        name: "Manager",
        provider: .codex,
        role: .manager,
        instructions: "Coordinate.",
        managerTeam: team
    )
    let builder = BotProfile(
        id: builderID,
        name: "Builder",
        provider: .claude,
        role: .builder,
        instructions: "Implement.",
        workingDirectory: ownership.repositoryPath,
        worktree: ownership
    )
    let reviewer = BotProfile(
        id: reviewerID,
        name: "Reviewer",
        provider: .codex,
        role: .reviewer,
        instructions: "Review.",
        workingDirectory: ownership.repositoryPath
    )
    let publisher = BotProfile(
        id: publisherID,
        name: "Documenter",
        provider: .claude,
        role: .publisher,
        instructions: "Publish.",
        workingDirectory: ownership.repositoryPath
    )
    let workflow = ManagerWorkflow(
        managerProfileID: managerID,
        repositoryPath: ownership.repositoryPath,
        team: team,
        request: "Ship the feature",
        implementationPlan: "Implement the feature end to end.",
        stage: .building,
        branch: ownership.branch
    )
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    store.save(
        PersistedAppState(
            profiles: [manager, builder, reviewer, publisher],
            sessions: [
                managerID: AgentSessionState(),
                builderID: AgentSessionState(
                    entries: [
                        TimelineEntry(
                            kind: .handoff,
                            title: "Implementation brief",
                            text: "Implement the feature end to end."
                        )
                    ]
                ),
                reviewerID: AgentSessionState(),
                publisherID: AgentSessionState()
            ],
            selectedBotID: builderID,
            managerWorkflows: [managerID: workflow]
        )
    )
    let runtime = RetryableBuilderRuntime()
    let model = AppModel(
        runtime: runtime,
        worktrees: StubWorktreeManager(
            packages: [noCommitPackage, readyPackage],
            preparedOwnership: ownership
        ),
        store: store
    )

    model.send("Implement the feature", to: builderID)
    for _ in 0..<100
        where model.workflow(for: managerID)?.pauseReason == nil {
        try await Task.sleep(for: .milliseconds(10))
    }

    let paused = try #require(model.workflow(for: managerID))
    #expect(paused.stage == .building)
    #expect(paused.isPaused)
    #expect(paused.awaitingBuilderHandoffRetry)

    // The user approves the previously blocked action directly (not an
    // explicit chat "send"); the Builder's session then reaches a new
    // terminal status entirely on its own.
    model.resolveApproval(UUID(), approved: true, for: builderID)

    for _ in 0..<300
        where model.workflow(for: managerID)?.stage != .reviewing
            || model.workflow(for: managerID)?.latestHandoff?.headRevision
                != readyPackage.headRevision
            || !model.session(for: reviewerID).entries.contains(where: {
                $0.kind == .handoff
            }) {
        try await Task.sleep(for: .milliseconds(10))
    }

    let healed = try #require(model.workflow(for: managerID))
    #expect(healed.stage == .reviewing)
    #expect(!healed.isPaused)
    #expect(!healed.awaitingBuilderHandoffRetry)
    #expect(healed.latestHandoff?.headRevision == readyPackage.headRevision)
    #expect(
        healed.latestHandoff?.taskContext
            == "Implement the feature end to end."
    )
    #expect(model.session(for: reviewerID).entries.contains {
        $0.kind == .handoff
    })
}

@MainActor
@Test
func blockedBuilderTurnWithoutCommitStillPausesWithAnActionableReason() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-blocked-builder-no-commit-\(UUID().uuidString)",
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
    let noCommitPackage = GitHandoffPackage(
        sourceProfileID: builderID,
        sourceName: "Builder",
        repositoryPath: ownership.repositoryPath,
        worktreePath: ownership.worktreePath,
        branch: ownership.branch,
        baseRevision: ownership.baseRevision,
        headRevision: ownership.baseRevision,
        taskContext: "Ship the feature",
        testStatus: .passed,
        testSummary: "`swift test` — passed",
        testEvidenceAt: .distantFuture,
        workingTreeSummary: "Clean"
    )
    let team = ManagerTeamConfiguration(
        builderProfileID: builderID,
        reviewerProfileID: reviewerID,
        publisherProfileID: publisherID
    )
    let manager = BotProfile(
        id: managerID,
        name: "Manager",
        provider: .codex,
        role: .manager,
        instructions: "Coordinate.",
        managerTeam: team
    )
    let builder = BotProfile(
        id: builderID,
        name: "Builder",
        provider: .claude,
        role: .builder,
        instructions: "Implement.",
        workingDirectory: ownership.repositoryPath,
        worktree: ownership
    )
    let reviewer = BotProfile(
        id: reviewerID,
        name: "Reviewer",
        provider: .codex,
        role: .reviewer,
        instructions: "Review.",
        workingDirectory: ownership.repositoryPath
    )
    let publisher = BotProfile(
        id: publisherID,
        name: "Documenter",
        provider: .claude,
        role: .publisher,
        instructions: "Publish.",
        workingDirectory: ownership.repositoryPath
    )
    let workflow = ManagerWorkflow(
        managerProfileID: managerID,
        repositoryPath: ownership.repositoryPath,
        team: team,
        request: "Ship the feature",
        implementationPlan: "Implement the feature end to end.",
        stage: .building,
        branch: ownership.branch
    )
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    store.save(
        PersistedAppState(
            profiles: [manager, builder, reviewer, publisher],
            sessions: [
                managerID: AgentSessionState(),
                builderID: AgentSessionState(
                    entries: [
                        TimelineEntry(
                            kind: .handoff,
                            title: "Implementation brief",
                            text: "Implement the feature end to end."
                        )
                    ]
                ),
                reviewerID: AgentSessionState(),
                publisherID: AgentSessionState()
            ],
            selectedBotID: builderID,
            managerWorkflows: [managerID: workflow]
        )
    )
    let runtime = BuilderStatusStubRuntime(
        builderFinalStatus: .blocked,
        blockedActionDetail: "• git commit -m \"Ship the feature\""
    )
    let model = AppModel(
        runtime: runtime,
        worktrees: StubWorktreeManager(
            package: noCommitPackage,
            preparedOwnership: ownership
        ),
        store: store
    )

    model.send("Implement the feature", to: builderID)
    for _ in 0..<100
        where model.workflow(for: managerID)?.pauseReason == nil {
        try await Task.sleep(for: .milliseconds(10))
    }

    let paused = try #require(model.workflow(for: managerID))
    #expect(paused.stage == .building)
    #expect(paused.isPaused)
    #expect(
        paused.pauseReason
            == "The Builder handoff has no local commit. `git commit -m \"Ship the feature\"` was blocked by a deny rule — approve the bl00p prompt or adjust the rule. The handoff will retry automatically once resolved."
    )
    #expect(paused.awaitingBuilderHandoffRetry)
    #expect(paused.latestHandoff == nil)
    #expect(await runtime.calls == [.builder])
    #expect(model.session(for: reviewerID).entries.isEmpty)
    #expect(
        model.session(for: builderID).entries.last(where: { $0.kind == .question })?
            .text
            == paused.pauseReason
    )
}

@MainActor
@Test
func codexBuilderGenuineQuestionStillPausesTheWorkflow() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-codex-builder-question-\(UUID().uuidString)",
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
    let team = ManagerTeamConfiguration(
        builderProfileID: builderID,
        reviewerProfileID: reviewerID,
        publisherProfileID: publisherID
    )
    let manager = BotProfile(
        id: managerID,
        name: "Manager",
        provider: .codex,
        role: .manager,
        instructions: "Coordinate.",
        managerTeam: team
    )
    let builder = BotProfile(
        id: builderID,
        name: "Builder",
        provider: .codex,
        role: .builder,
        instructions: "Implement.",
        workingDirectory: ownership.repositoryPath,
        worktree: ownership
    )
    let reviewer = BotProfile(
        id: reviewerID,
        name: "Reviewer",
        provider: .codex,
        role: .reviewer,
        instructions: "Review.",
        workingDirectory: ownership.repositoryPath
    )
    let publisher = BotProfile(
        id: publisherID,
        name: "Documenter",
        provider: .claude,
        role: .publisher,
        instructions: "Publish.",
        workingDirectory: ownership.repositoryPath
    )
    let workflow = ManagerWorkflow(
        managerProfileID: managerID,
        repositoryPath: ownership.repositoryPath,
        team: team,
        request: "Ship the feature",
        implementationPlan: "Implement the feature end to end.",
        stage: .building,
        branch: ownership.branch
    )
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    store.save(
        PersistedAppState(
            profiles: [manager, builder, reviewer, publisher],
            sessions: [
                managerID: AgentSessionState(),
                builderID: AgentSessionState(),
                reviewerID: AgentSessionState(),
                publisherID: AgentSessionState()
            ],
            selectedBotID: builderID,
            managerWorkflows: [managerID: workflow]
        )
    )
    let runtime = BuilderStatusStubRuntime(
        builderFinalStatus: .needsAnswer,
        builderResponseText: "Which persistence layer should this use?"
    )
    let model = AppModel(
        runtime: runtime,
        worktrees: StubWorktreeManager(
            package: GitHandoffPackage(
                sourceProfileID: builderID,
                sourceName: "Builder",
                repositoryPath: ownership.repositoryPath,
                worktreePath: ownership.worktreePath,
                branch: ownership.branch,
                baseRevision: ownership.baseRevision,
                headRevision: "def456",
                taskContext: "Ship the feature",
                testStatus: .passed,
                testSummary: "`swift test` — passed",
                testEvidenceAt: .distantFuture,
                workingTreeSummary: "Clean"
            ),
            preparedOwnership: ownership
        ),
        store: store
    )

    model.send("Implement the feature", to: builderID)
    for _ in 0..<300
        where model.workflow(for: managerID)?.stage != .building
            || model.workflow(for: managerID)?.isPaused != true
            || model.session(for: builderID).status != .needsAnswer {
        try await Task.sleep(for: .milliseconds(10))
    }

    let paused = try #require(model.workflow(for: managerID))
    #expect(paused.stage == .building)
    #expect(paused.isPaused)
    #expect(model.session(for: builderID).status == .needsAnswer)
    #expect(await runtime.calls == [.builder])
    #expect(model.session(for: reviewerID).entries.isEmpty)
}

@MainActor
@Test
func cleanReviewPublishesWithoutAnEmptyRevisionCommit() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-clean-review-\(UUID().uuidString)",
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
        branch: "bl00p/clean-review",
        baseRevision: "abc123"
    )
    let initialPackage = GitHandoffPackage(
        sourceProfileID: builderID,
        sourceName: "Builder",
        repositoryPath: ownership.repositoryPath,
        worktreePath: ownership.worktreePath,
        branch: ownership.branch,
        baseRevision: ownership.baseRevision,
        headRevision: "def456",
        taskContext: "Ship the clean change",
        testStatus: .passed,
        testSummary: "`swift test` — passed",
        workingTreeSummary: "Clean"
    )
    let cleanRevisionPackage = GitHandoffPackage(
        sourceProfileID: builderID,
        sourceName: "Builder",
        repositoryPath: ownership.repositoryPath,
        worktreePath: ownership.worktreePath,
        branch: ownership.branch,
        baseRevision: ownership.baseRevision,
        headRevision: initialPackage.headRevision,
        taskContext: "Ship the clean change",
        testStatus: .passed,
        testSummary: "`swift test` — passed after review",
        testEvidenceAt: .distantFuture,
        workingTreeSummary: "Clean"
    )
    let team = ManagerTeamConfiguration(
        builderProfileID: builderID,
        reviewerProfileID: reviewerID,
        publisherProfileID: publisherID
    )
    let manager = BotProfile(
        id: managerID,
        name: "Manager",
        provider: .codex,
        role: .manager,
        instructions: "Coordinate.",
        managerTeam: team
    )
    let builder = BotProfile(
        id: builderID,
        name: "Builder",
        provider: .claude,
        role: .builder,
        instructions: "Implement.",
        workingDirectory: ownership.repositoryPath,
        worktree: ownership
    )
    let reviewer = BotProfile(
        id: reviewerID,
        name: "Reviewer",
        provider: .codex,
        role: .reviewer,
        instructions: "Review."
    )
    let publisher = BotProfile(
        id: publisherID,
        name: "Documenter",
        provider: .claude,
        role: .publisher,
        instructions: "Publish."
    )
    let reviewSummary = """
    No actionable findings.
    BL00P_REVIEW_DISPOSITION: clean
    """
    let workflow = ManagerWorkflow(
        managerProfileID: managerID,
        team: team,
        request: "Ship the clean change",
        stage: .reviewing,
        branch: ownership.branch,
        latestHandoff: initialPackage,
        reviewSummary: reviewSummary
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
            selectedBotID: builderID,
            managerWorkflows: [managerID: workflow]
        )
    )
    let runtime = OrchestrationRecordingRuntime(
        reviewerResponses: [reviewSummary]
    )
    let model = AppModel(
        runtime: runtime,
        worktrees: StubWorktreeManager(
            package: cleanRevisionPackage,
            preparedOwnership: ownership
        ),
        store: store
    )

    model.send("Finish the clean review", to: reviewerID)
    for _ in 0..<100
        where model.workflow(for: managerID)?.stage != .completed {
        try await Task.sleep(for: .milliseconds(10))
    }

    let completed = try #require(model.workflow(for: managerID))
    #expect(completed.stage == .completed)
    #expect(
        completed.latestHandoff?.id == initialPackage.id
    )
    #expect(
        completed.latestHandoff?.headRevision
            == initialPackage.headRevision
    )
    #expect(
        await runtime.calls.map(\.role)
            == [.reviewer, .publisher]
    )
    let publisherCall = try #require(
        await runtime.calls.first(where: { $0.role == .publisher })
    )
    #expect(publisherCall.message.contains("No actionable findings."))
    #expect(!publisherCall.message.contains(ReviewDisposition.marker))
    #expect(
        publisherCall.message.contains(
            "Source HEAD: \(initialPackage.headRevision)"
        )
    )
}

@MainActor
@Test
func missingPublisherPausesBeforeLeavingRevisionStage() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-missing-publisher-\(UUID().uuidString)",
            isDirectory: true
        )
    defer { try? FileManager.default.removeItem(at: directory) }

    let builderID = UUID()
    let reviewerID = UUID()
    let managerID = UUID()
    let ownership = GitWorktreeOwnership(
        ownerProfileID: builderID,
        repositoryPath: "/tmp/project",
        worktreePath: "/tmp/.bl00p-worktrees/project-builder",
        branch: "bl00p/missing-publisher",
        baseRevision: "abc123"
    )
    let team = ManagerTeamConfiguration(
        builderProfileID: builderID,
        reviewerProfileID: reviewerID,
        publisherProfileID: nil
    )
    let manager = BotProfile(
        id: managerID,
        name: "Manager",
        provider: .codex,
        role: .manager,
        instructions: "Coordinate.",
        managerTeam: team
    )
    let builder = BotProfile(
        id: builderID,
        name: "Builder",
        provider: .claude,
        role: .builder,
        instructions: "Implement.",
        workingDirectory: ownership.repositoryPath,
        worktree: ownership
    )
    let reviewer = BotProfile(
        id: reviewerID,
        name: "Reviewer",
        provider: .codex,
        role: .reviewer,
        instructions: "Review."
    )
    let revisionPackage = GitHandoffPackage(
        sourceProfileID: builderID,
        sourceName: "Builder",
        repositoryPath: ownership.repositoryPath,
        worktreePath: ownership.worktreePath,
        branch: ownership.branch,
        baseRevision: ownership.baseRevision,
        headRevision: "def456",
        taskContext: "Ship the feature",
        testStatus: .passed,
        testSummary: "`swift test` — passed",
        testEvidenceAt: .distantFuture,
        workingTreeSummary: "Clean"
    )
    let workflow = ManagerWorkflow(
        managerProfileID: managerID,
        team: team,
        request: "Ship the feature",
        stage: .revising,
        reviewSummary: "Review status: changes requested",
        revisionStartedAt: .now
    )
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    store.save(
        PersistedAppState(
            profiles: [manager, builder, reviewer],
            sessions: [
                managerID: AgentSessionState(),
                builderID: AgentSessionState(),
                reviewerID: AgentSessionState()
            ],
            selectedBotID: builderID,
            managerWorkflows: [managerID: workflow]
        )
    )
    let runtime = OrchestrationRecordingRuntime(
        reviewerResponses: [
            """
            Review clean.
            BL00P_REVIEW_DISPOSITION: clean
            """
        ]
    )
    let model = AppModel(
        runtime: runtime,
        worktrees: StubWorktreeManager(
            package: revisionPackage,
            preparedOwnership: ownership
        ),
        store: store
    )

    model.send("Finish the revision", to: builderID)
    for _ in 0..<100
        where model.workflow(for: managerID)?.pauseReason
            != "The assigned Documenter / PR Writer is no longer available." {
        try await Task.sleep(for: .milliseconds(10))
    }

    let paused = try #require(model.workflow(for: managerID))
    #expect(paused.stage == .verifying)
    #expect(paused.isPaused)
    #expect(
        paused.pauseReason
            == "The assigned Documenter / PR Writer is no longer available."
    )
    #expect(await runtime.calls.map(\.role) == [.builder, .reviewer])
}

@MainActor
@Test
func persistedLegacyVerifyingWorkflowStillDecodesAndRecovers() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-legacy-verifying-\(UUID().uuidString)",
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
    let package = GitHandoffPackage(
        sourceProfileID: builder.id,
        sourceName: builder.name,
        repositoryPath: "/tmp/project",
        worktreePath: "/tmp/.bl00p-worktrees/project-builder",
        branch: "bl00p/legacy-workflow",
        baseRevision: "abc123",
        headRevision: "def456",
        taskContext: "Resume a saved delivery",
        testStatus: .passed,
        testSummary: "`swift test` — passed",
        workingTreeSummary: "Clean"
    )
    let legacyWorkflow = ManagerWorkflow(
        managerProfileID: manager.id,
        team: team,
        request: "Resume a saved delivery",
        stage: .verifying,
        branch: package.branch,
        latestHandoff: package
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
                publisher.id: AgentSessionState(
                    status: .completed,
                    entries: [
                        .init(kind: .assistant, text: "Earlier publishing work")
                    ],
                    sessionID: "stale-publisher-thread"
                )
            ],
            selectedBotID: manager.id,
            managerWorkflows: [manager.id: legacyWorkflow]
        )
    )

    let decoded = try #require(store.load())
    #expect(decoded.managerWorkflows[manager.id]?.stage == .publishing)

    let runtime = OrchestrationRecordingRuntime()
    _ = AppModel(runtime: runtime, store: store)
    let model = AppModel(runtime: runtime, store: store)
    let restored = try #require(model.workflow(for: manager.id))
    #expect(restored.stage == .publishing)
    #expect(
        restored.stage.progressIndex
            == ManagerWorkflowStage.publishing.progressIndex
    )
    #expect(restored.isPaused)
    #expect(model.session(for: publisher.id).sessionID == nil)
    #expect(model.session(for: publisher.id).repositoryPath
        == package.repositoryPath)
    #expect(model.session(for: publisher.id).pendingHandoff?.worktreePath
        == package.worktreePath)
    #expect(
        model.session(for: publisher.id).entries.filter {
            $0.kind == .handoff
                && $0.detail == package.timelineDetail
        }.count == 1
    )

    model.send("Resume the saved workflow", to: publisher.id)
    for _ in 0..<100
        where model.workflow(for: manager.id)?.stage != .completed {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(model.workflow(for: manager.id)?.stage == .completed)
    #expect(
        await runtime.calls.map(\.role)
            == [.publisher]
    )
    #expect(
        model.session(for: publisher.id).entries.contains(where: {
            $0.title == "Recovered workflow handoff from \(builder.name)"
                && $0.detail?.contains(package.headRevision) == true
        })
    )
}

@Test
func reviewDispositionRequiresExactlyOneValidStructuredMarker() {
    #expect(
        ReviewDisposition.parse(
            from: "No findings.\nBL00P_REVIEW_DISPOSITION: clean"
        ) == .clean
    )
    #expect(
        ReviewDisposition.parse(
            from: "One issue.\nBL00P_REVIEW_DISPOSITION: changesRequested"
        ) == .changesRequested
    )
    #expect(ReviewDisposition.parse(from: "Review clean.") == nil)
    #expect(
        ReviewDisposition.parse(
            from: """
            BL00P_REVIEW_DISPOSITION: clean
            BL00P_REVIEW_DISPOSITION: changesRequested
            """
        ) == nil
    )
    #expect(
        ReviewDisposition.parse(
            from: "BL00P_REVIEW_DISPOSITION: CLEAN"
        ) == nil
    )
}

@MainActor
@Test
func cleanManagedWorkflowUsesExactlyFourAgentTurns() async throws {
    let harness = try makeManagedWorkflowHarness(
        reviewerResponses: [
            """
            No actionable findings.
            BL00P_REVIEW_DISPOSITION: clean
            """
        ]
    )
    defer { try? FileManager.default.removeItem(at: harness.directory) }

    try await runManagedWorkflow(harness)

    let calls = await harness.runtime.calls
    let workflow = try #require(
        harness.model.workflow(for: harness.managerID)
    )
    #expect(calls.map(\.role) == [.manager, .builder, .reviewer, .publisher])
    #expect(workflow.stage == .completed)
    #expect(workflow.branch == harness.ownership.branch)
    #expect(workflow.verificationSummary?.contains("No actionable") == true)
    #expect(workflow.publisherSummary?.contains("Draft PR") == true)
    #expect(
        workflow.pullRequestURL
            == "https://github.com/suttree/bl00p/pull/99"
    )
    let completion = try #require(
        harness.model.session(for: harness.managerID).entries.last(where: {
            $0.text == "Managed workflow complete"
        })
    )
    #expect(completion.detail?.contains("Verification: Passed") == true)
    #expect(completion.detail?.contains("Publisher:") == true)
    #expect(completion.detail?.contains(workflow.pullRequestURL!) == true)
}

@MainActor
@Test
func reviewerDispositionCanArriveInASeparateAssistantBlock() async throws {
    let harness = try makeManagedWorkflowHarness(
        reviewerResponseBlocks: [[
            "No actionable findings across the completed review.",
            "BL00P_REVIEW_DISPOSITION: clean"
        ]]
    )
    defer { try? FileManager.default.removeItem(at: harness.directory) }

    try await runManagedWorkflow(harness)

    let workflow = try #require(
        harness.model.workflow(for: harness.managerID)
    )
    let calls = await harness.runtime.calls
    #expect(workflow.stage == .completed)
    #expect(
        workflow.verificationSummary
            == "No actionable findings across the completed review."
    )
    #expect(
        calls.map(\.role) == [.manager, .builder, .reviewer, .publisher]
    )
    #expect(!calls[3].message.contains(ReviewDisposition.marker))
    let completion = try #require(
        harness.model.session(for: harness.managerID).entries.last(where: {
            $0.text == "Managed workflow complete"
        })
    )
    #expect(completion.detail?.contains(ReviewDisposition.marker) == false)
}

@MainActor
@Test
func malformedReviewDispositionConservativelyUsesFixAndVerificationTurns() async throws {
    let harness = try makeManagedWorkflowHarness(
        reviewerResponses: [
            "Review appears clean, but the marker is missing.",
            """
            Verified after the conservative fallback.
            BL00P_REVIEW_DISPOSITION: clean
            """
        ]
    )
    defer { try? FileManager.default.removeItem(at: harness.directory) }

    try await runManagedWorkflow(harness)

    let calls = await harness.runtime.calls
    #expect(
        calls.map(\.role)
            == [.manager, .builder, .reviewer, .builder, .reviewer, .publisher]
    )
    #expect(calls[3].message.contains("Treat this conservatively"))
    #expect(!calls[3].message.contains(ReviewDisposition.marker))
    #expect(calls[4].message.contains("Re-check the updated"))
    #expect(harness.model.workflow(for: harness.managerID)?.stage == .completed)
}

@MainActor
@Test
func managedWorkflowPausesAfterTwoUnresolvedRevisionRounds() async throws {
    let unresolved = """
    A blocking finding remains.
    BL00P_REVIEW_DISPOSITION: changesRequested
    """
    let harness = try makeManagedWorkflowHarness(
        reviewerResponses: [unresolved, unresolved, unresolved]
    )
    defer { try? FileManager.default.removeItem(at: harness.directory) }

    harness.model.send("Speed up orchestration", to: harness.managerID)
    for _ in 0..<100
        where harness.model.session(for: harness.managerID).status
            != .needsApproval {
        try await Task.sleep(for: .milliseconds(10))
    }
    let approval = try #require(
        harness.model.session(for: harness.managerID).entries.last(where: {
            $0.kind == .approval && $0.approvalState == .pending
        })
    )
    harness.model.resolveApproval(
        approval.id,
        approved: true,
        for: harness.managerID
    )
    for _ in 0..<200 {
        if harness.model.workflow(for: harness.managerID)?.isPaused == true,
           harness.model.workflow(for: harness.managerID)?.revisionRounds == 2 {
            break
        }
        try await Task.sleep(for: .milliseconds(10))
    }

    let workflow = try #require(
        harness.model.workflow(for: harness.managerID)
    )
    let calls = await harness.runtime.calls
    #expect(workflow.stage == .verifying)
    #expect(workflow.isPaused)
    #expect(workflow.revisionRounds == 2)
    #expect(
        workflow.pauseReason?.contains("after 2 revision rounds") == true
    )
    #expect(
        calls.map(\.role)
            == [.manager, .builder, .reviewer, .builder, .reviewer, .builder, .reviewer]
    )
    #expect(!calls.map(\.role).contains(.publisher))
    #expect(
        harness.model.session(for: harness.managerID).entries.contains(where: {
            $0.title == "Review loop needs attention"
        })
    )
}

@MainActor
@Test
func pendingManagerDispatchRecoversOnceAndDeliveredWorkCanResume() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-manager-dispatch-recovery-\(UUID().uuidString)",
            isDirectory: true
        )
    defer { try? FileManager.default.removeItem(at: directory) }

    let builderID = UUID()
    let reviewerID = UUID()
    let publisherID = UUID()
    let managerID = UUID()
    let dispatchID = UUID()
    let approvalID = UUID()
    let team = ManagerTeamConfiguration(
        builderProfileID: builderID,
        reviewerProfileID: reviewerID,
        publisherProfileID: publisherID
    )
    let ownership = GitWorktreeOwnership(
        ownerProfileID: builderID,
        repositoryPath: "/tmp/project",
        worktreePath: "/tmp/.bl00p-worktrees/project-builder",
        branch: "bl00p/recovered-build",
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
        taskContext: "Recover the approved plan",
        testStatus: .passed,
        testSummary: "`swift test` — passed",
        workingTreeSummary: "Clean"
    )
    let manager = BotProfile(
        id: managerID,
        name: "Manager",
        provider: .codex,
        role: .manager,
        instructions: "Coordinate.",
        workingDirectory: ownership.repositoryPath,
        managerTeam: team
    )
    let builder = BotProfile(
        id: builderID,
        name: "Builder",
        provider: .claude,
        role: .builder,
        instructions: "Implement.",
        workingDirectory: ownership.repositoryPath
    )
    let reviewer = BotProfile(
        id: reviewerID,
        name: "Reviewer",
        provider: .codex,
        role: .reviewer,
        instructions: "Review.",
        workingDirectory: ownership.repositoryPath
    )
    let publisher = BotProfile(
        id: publisherID,
        name: "Publisher",
        provider: .claude,
        role: .publisher,
        instructions: "Publish.",
        workingDirectory: ownership.repositoryPath
    )
    let workflow = ManagerWorkflow(
        managerProfileID: managerID,
        team: team,
        request: "Recover the approved plan",
        implementationPlan: "Use the stored implementation brief.",
        approvedPlanEntryID: approvalID,
        pendingDispatch: ManagerWorkflowDispatch(
            id: dispatchID,
            kind: .initialBuild,
            sourceProfileID: managerID,
            targetProfileID: builderID,
            summary: "Use the stored implementation brief."
        ),
        stage: .building,
        isPaused: true
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
            ).merging(
                [
                    managerID: AgentSessionState(
                        entries: [
                            TimelineEntry(
                                id: approvalID,
                                kind: .approval,
                                title: "Approve implementation plan",
                                text: "Use the stored implementation brief.",
                                approvalState: .approved,
                                contentFormat: .markdown
                            )
                        ]
                    )
                ],
                uniquingKeysWith: { _, approved in approved }
            ),
            selectedBotID: managerID,
            managerWorkflows: [managerID: workflow]
        )
    )
    let worktrees = StubWorktreeManager(
        package: package,
        preparedOwnership: ownership
    )
    let firstRuntime = SuspendedWorkflowRuntime()
    let firstModel = AppModel(
        runtime: firstRuntime,
        worktrees: worktrees,
        store: store
    )

    firstModel.recoverPendingWorkflowDispatches()
    firstModel.recoverPendingWorkflowDispatches()
    for _ in 0..<100 where await firstRuntime.calls.count != 1 {
        try await Task.sleep(for: .milliseconds(10))
    }

    let deliveredWorkflow = try #require(firstModel.workflow(for: managerID))
    #expect(deliveredWorkflow.pendingDispatch == nil)
    #expect(deliveredWorkflow.deliveredDispatchID == dispatchID)
    #expect(await firstRuntime.calls.count == 1)
    #expect(
        await firstRuntime.calls.first?.message.contains(
            "Use the stored implementation brief."
        ) == true
    )
    #expect(
        firstModel.session(for: builderID).entries.filter {
            $0.id == dispatchID && $0.title == "Implementation brief"
        }.count == 1
    )

    let resumedRuntime = SuspendedWorkflowRuntime()
    let restoredModel = AppModel(
        runtime: resumedRuntime,
        worktrees: worktrees,
        store: store
    )
    try await Task.sleep(for: .milliseconds(30))

    let restoredWorkflow = try #require(restoredModel.workflow(for: managerID))
    #expect(restoredWorkflow.resumeAvailableAfterRestart == true)
    #expect(restoredWorkflow.isPaused)
    #expect(await resumedRuntime.calls.isEmpty)
    #expect(
        restoredModel.session(for: builderID).entries.filter {
            $0.id == dispatchID && $0.title == "Implementation brief"
        }.count == 1
    )

    restoredModel.resumeWorkflow(managerID)
    restoredModel.resumeWorkflow(managerID)
    for _ in 0..<100 where await resumedRuntime.calls.count != 1 {
        try await Task.sleep(for: .milliseconds(10))
    }

    let resumeCall = try #require(await resumedRuntime.calls.first)
    #expect(resumeCall.role == .builder)
    #expect(resumeCall.message.contains("Resume the managed Builder task"))
    #expect(resumeCall.message.contains("Use the stored implementation brief."))
    #expect(restoredModel.workflow(for: managerID)?.isPaused == false)
    #expect(
        restoredModel.workflow(for: managerID)?
            .resumeAvailableAfterRestart == false
    )
    #expect(
        restoredModel.session(for: builderID).entries.filter {
            $0.id == dispatchID && $0.title == "Implementation brief"
        }.count == 1
    )
}

@MainActor
@Test
func laterStageDispatchRecoveryRestoresReviewerAndPublisherCheckouts() async throws {
    try await assertRecoveredWorkflowDispatch(
        kind: .initialReview,
        expectedRole: .reviewer
    )
    try await assertRecoveredWorkflowDispatch(
        kind: .publishing,
        expectedRole: .publisher
    )
}

@MainActor
@Test
func workflowRejectsAHandoffFromAnotherRepository() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-repository-mismatch-\(UUID().uuidString)"
        )
    defer { try? FileManager.default.removeItem(at: directory) }
    let fixture = managedWorkflowFixture()
    let managerSessionID = UUID()
    let publisherSessionID = UUID()
    let package = GitHandoffPackage(
        sourceProfileID: fixture.builder.id,
        sourceName: fixture.builder.name,
        repositoryPath: "/tmp/repository-b",
        worktreePath: "/tmp/.bl00p-worktrees/repository-b",
        branch: "bl00p/wrong-repository",
        baseRevision: "abc123",
        headRevision: "def456",
        taskContext: "Wrong repository",
        testStatus: .passed,
        testSummary: "Passed",
        workingTreeSummary: "Clean"
    )
    let dispatch = ManagerWorkflowDispatch(
        kind: .publishing,
        sourceProfileID: fixture.reviewer.id,
        targetProfileID: fixture.publisher.id,
        summary: "Publish",
        handoff: package
    )
    let workflow = ManagerWorkflow(
        managerProfileID: fixture.manager.id,
        repositoryPath: "/tmp/repository-a",
        team: fixture.team,
        request: "Keep repository context isolated",
        pendingDispatch: dispatch,
        stage: .publishing,
        isPaused: true,
        participantSessionIDs: [
            .manager: managerSessionID,
            .publisher: publisherSessionID
        ]
    )
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    store.save(
        PersistedAppState(
            profiles: fixture.profiles,
            sessions: [
                managerSessionID: AgentSessionState(
                    id: managerSessionID,
                    ownerProfileID: fixture.manager.id,
                    repositoryPath: "/tmp/repository-a"
                ),
                publisherSessionID: AgentSessionState(
                    id: publisherSessionID,
                    ownerProfileID: fixture.publisher.id,
                    repositoryPath: "/tmp/repository-a"
                )
            ],
            selectedBotID: fixture.manager.id,
            managerWorkflows: [managerSessionID: workflow],
            sessionOrder: [
                fixture.manager.id: [managerSessionID],
                fixture.publisher.id: [publisherSessionID]
            ],
            selectedSessionIDs: [
                fixture.manager.id: managerSessionID,
                fixture.publisher.id: publisherSessionID
            ]
        )
    )
    let runtime = SuspendedWorkflowRuntime()
    let model = AppModel(runtime: runtime, store: store)
    model.recoverPendingWorkflowDispatches()
    for _ in 0..<30
        where model.managerWorkflows[managerSessionID]?.pauseReason?
            .contains("different repository") != true {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(
        model.managerWorkflows[managerSessionID]?.pauseReason?
            .contains("different repository") == true
    )
    #expect(await runtime.calls.isEmpty)
    #expect(model.sessions[publisherSessionID]?.repositoryPath
        == "/tmp/repository-a")
}

@MainActor
private func assertRecoveredWorkflowDispatch(
    kind: ManagerWorkflowDispatchKind,
    expectedRole: AgentRole
) async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-\(kind.rawValue)-recovery-\(UUID().uuidString)",
            isDirectory: true
        )
    defer { try? FileManager.default.removeItem(at: directory) }

    let builderID = UUID()
    let reviewerID = UUID()
    let publisherID = UUID()
    let managerID = UUID()
    let dispatchID = UUID()
    let team = ManagerTeamConfiguration(
        builderProfileID: builderID,
        reviewerProfileID: reviewerID,
        publisherProfileID: publisherID
    )
    let ownership = GitWorktreeOwnership(
        ownerProfileID: builderID,
        repositoryPath: "/tmp/project",
        worktreePath: "/tmp/.bl00p-worktrees/recovered-review",
        branch: "bl00p/recovered-review",
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
        taskContext: "Recover the later stage",
        testStatus: .passed,
        testSummary: "`swift test` — passed",
        workingTreeSummary: "Clean"
    )
    let manager = BotProfile(
        id: managerID,
        name: "Manager",
        provider: .codex,
        role: .manager,
        instructions: "Coordinate.",
        workingDirectory: ownership.repositoryPath,
        managerTeam: team
    )
    let builder = BotProfile(
        id: builderID,
        name: "Builder",
        provider: .claude,
        role: .builder,
        instructions: "Implement.",
        workingDirectory: ownership.repositoryPath,
        worktree: ownership
    )
    let reviewer = BotProfile(
        id: reviewerID,
        name: "Reviewer",
        provider: .codex,
        role: .reviewer,
        instructions: "Review.",
        workingDirectory: "/tmp/wrong-review-checkout"
    )
    let publisher = BotProfile(
        id: publisherID,
        name: "Publisher",
        provider: .claude,
        role: .publisher,
        instructions: "Publish.",
        workingDirectory: "/tmp/wrong-publisher-checkout"
    )
    let targetID = expectedRole == .reviewer ? reviewerID : publisherID
    let dispatch = ManagerWorkflowDispatch(
        id: dispatchID,
        kind: kind,
        sourceProfileID:
            expectedRole == .reviewer ? builderID : reviewerID,
        targetProfileID: targetID,
        summary: "Persisted stage summary",
        handoff: kind == .publishing ? package : nil
    )
    let workflow = ManagerWorkflow(
        managerProfileID: managerID,
        team: team,
        request: "Recover the later stage",
        implementationPlan: "Implement and verify.",
        pendingDispatch: dispatch,
        stage: kind.stage,
        latestHandoff: kind == .publishing ? package : nil,
        isPaused: true
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
            selectedBotID: managerID,
            managerWorkflows: [managerID: workflow]
        )
    )
    let runtime = SuspendedWorkflowRuntime()
    let model = AppModel(
        runtime: runtime,
        worktrees: StubWorktreeManager(
            package: package,
            preparedOwnership: ownership
        ),
        store: store
    )

    model.recoverPendingWorkflowDispatches()
    model.recoverPendingWorkflowDispatches()
    for _ in 0..<100 where await runtime.calls.count != 1 {
        try await Task.sleep(for: .milliseconds(10))
    }

    let call = try #require(await runtime.calls.first)
    #expect(call.role == expectedRole)
    #expect(call.workingDirectory == package.worktreePath)
    #expect(model.session(for: targetID).repositoryPath
        == package.repositoryPath)
    #expect(model.workflow(for: managerID)?.pendingDispatch == nil)
    #expect(model.workflow(for: managerID)?.deliveredDispatchID == dispatchID)
    #expect(
        model.workflow(for: managerID)?.deliveredDispatch?.id == dispatchID
    )
    #expect(
        model.session(for: targetID).entries.filter {
            $0.id == dispatchID
        }.count == 1
    )
    #expect(await runtime.calls.count == 1)

    let resumedRuntime = SuspendedWorkflowRuntime()
    let restoredModel = AppModel(
        runtime: resumedRuntime,
        worktrees: StubWorktreeManager(
            package: package,
            preparedOwnership: ownership
        ),
        store: store
    )
    try await Task.sleep(for: .milliseconds(20))
    #expect(
        restoredModel.workflow(for: managerID)?
            .resumeAvailableAfterRestart == true
    )
    #expect(await resumedRuntime.calls.isEmpty)

    restoredModel.resumeWorkflow(managerID)
    for _ in 0..<100 where await resumedRuntime.calls.count != 1 {
        try await Task.sleep(for: .milliseconds(10))
    }
    let resumeCall = try #require(await resumedRuntime.calls.first)
    #expect(resumeCall.role == expectedRole)
    #expect(resumeCall.workingDirectory == package.worktreePath)
    #expect(resumeCall.message.contains(package.branch))
    if kind == .publishing {
        #expect(resumeCall.message.contains("Persisted stage summary"))
    }
    #expect(
        restoredModel.session(for: targetID).entries.filter {
            $0.id == dispatchID
        }.count == 1
    )
}

@MainActor
@Test
func pendingDispatchPayloadsSurviveRestartBeforeRuntimeResponse() async throws {
    for kind in [
        ManagerWorkflowDispatchKind.revision,
        .publishing,
        .reporting
    ] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "bl00p-\(kind.rawValue)-payload-recovery-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }

        let managerID = UUID()
        let builderID = UUID()
        let reviewerID = UUID()
        let publisherID = UUID()
        let managerSessionID = UUID()
        let builderSessionID = UUID()
        let reviewerSessionID = UUID()
        let publisherSessionID = UUID()
        let ownership = GitWorktreeOwnership(
            ownerProfileID: builderID,
            repositoryPath: "/tmp/project",
            worktreePath: "/tmp/.bl00p-worktrees/payload-recovery",
            branch: "bl00p/payload-recovery",
            baseRevision: "abc123"
        )
        let team = ManagerTeamConfiguration(
            builderProfileID: builderID,
            reviewerProfileID: reviewerID,
            publisherProfileID: publisherID
        )
        let manager = BotProfile(
            id: managerID,
            name: "Manager",
            provider: .codex,
            role: .manager,
            instructions: "Coordinate.",
            workingDirectory: "/tmp/project",
            managerTeam: team
        )
        let builder = BotProfile(
            id: builderID,
            name: "Builder",
            provider: .claude,
            role: .builder,
            instructions: "Implement.",
            workingDirectory: kind == .revision ? "" : ownership.repositoryPath,
            worktree: kind == .revision ? nil : ownership
        )
        let reviewer = BotProfile(
            id: reviewerID,
            name: "Reviewer",
            provider: .codex,
            role: .reviewer,
            instructions: "Review.",
            workingDirectory: "/tmp/project"
        )
        let publisher = BotProfile(
            id: publisherID,
            name: "Publisher",
            provider: .claude,
            role: .publisher,
            instructions: "Publish.",
            workingDirectory: "/tmp/wrong-publisher-checkout"
        )
        let package = GitHandoffPackage(
            sourceProfileID: builderID,
            sourceName: "Builder",
            repositoryPath: ownership.repositoryPath,
            worktreePath: ownership.worktreePath,
            branch: ownership.branch,
            baseRevision: ownership.baseRevision,
            headRevision: "def456",
            taskContext: "Recover the delivered payload",
            testStatus: .passed,
            testSummary: "`swift test` — passed",
            workingTreeSummary: "Clean"
        )
        let dispatch = ManagerWorkflowDispatch(
            kind: kind,
            sourceProfileID:
                kind == .reporting ? publisherID : reviewerID,
            targetProfileID:
                kind == .revision
                    ? builderID
                    : kind == .publishing
                        ? publisherID
                        : managerID,
            summary: kind == .revision
                ? "Reviewer found a missing regression test."
                : kind == .publishing
                    ? "Publisher completed the documentation pass."
                    : "Draft PR: https://github.com/suttree/bl00p/pull/123",
            handoff: kind == .publishing ? package : nil
        )
        let workflow = ManagerWorkflow(
            managerProfileID: managerID,
            team: team,
            request: "Recover the delivered payload",
            pendingDispatch: dispatch,
            stage: kind.stage,
            latestHandoff: kind == .publishing ? package : nil,
            isPaused: true,
            pauseReason: "Preparing the persisted workflow handoff.",
            participantSessionIDs: [
                .manager: managerSessionID,
                .builder: builderSessionID,
                .reviewer: reviewerSessionID,
                .publisher: publisherSessionID
            ]
        )
        let store = AppStateStore(
            fileURL: directory.appendingPathComponent("state.json")
        )
        store.save(
            PersistedAppState(
                profiles: [manager, builder, reviewer, publisher],
                sessions: [
                    managerSessionID: AgentSessionState(
                        id: managerSessionID,
                        ownerProfileID: managerID
                    ),
                    builderSessionID: AgentSessionState(
                        id: builderSessionID,
                        ownerProfileID: builderID,
                        worktree: ownership
                    ),
                    reviewerSessionID: AgentSessionState(
                        id: reviewerSessionID,
                        ownerProfileID: reviewerID
                    ),
                    publisherSessionID: AgentSessionState(
                        id: publisherSessionID,
                        ownerProfileID: publisherID
                    )
                ],
                selectedBotID: managerID,
                managerWorkflows: [managerSessionID: workflow],
                sessionOrder: [
                    managerID: [managerSessionID],
                    builderID: [builderSessionID],
                    reviewerID: [reviewerSessionID],
                    publisherID: [publisherSessionID]
                ],
                selectedSessionIDs: [
                    managerID: managerSessionID,
                    builderID: builderSessionID,
                    reviewerID: reviewerSessionID,
                    publisherID: publisherSessionID
                ]
            )
        )

        let blockedRuntime = BlockingWorkflowRuntime()
        let worktrees = StubWorktreeManager(
            packages: [],
            preparedOwnership: ownership
        )
        let model = AppModel(
            runtime: blockedRuntime,
            worktrees: worktrees,
            store: store
        )
        for _ in 0..<100 where await blockedRuntime.responseStarted == false {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await blockedRuntime.responseStarted)
        #expect(model.workflow(for: managerID)?.pendingDispatch == nil)
        #expect(
            model.workflow(for: managerID)?.deliveredDispatch?.id == dispatch.id
        )

        let restoredRuntime = SuspendedWorkflowRuntime()
        let restoredModel = AppModel(
            runtime: restoredRuntime,
            worktrees: worktrees,
            store: store
        )
        #expect(
            restoredModel.workflow(for: managerID)?
                .resumeAvailableAfterRestart == true
        )
        restoredModel.resumeWorkflow(managerID)
        for _ in 0..<100 where await restoredRuntime.calls.count != 1 {
            try await Task.sleep(for: .milliseconds(10))
        }

        let call = try #require(await restoredRuntime.calls.first)
        #expect(call.message.contains(dispatch.summary))
        await blockedRuntime.release()
    }
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
    try store.saveFixture(
        PersistedAppState(
            profiles: [manager, builder, reviewer, publisher],
            sessions: Dictionary(
                uniqueKeysWithValues: [manager, builder, reviewer, publisher]
                    .map { ($0.id, AgentSessionState()) }
            ),
            selectedBotID: manager.id
        )
    )
    let initialPlan = orchestrationImplementationPlan
    let revisedPlan = """
    ## Revised plan

    1. Preserve every line.
    2. Follow [the contract](https://example.com/handoff).
    """
    let runtime = OrchestrationRecordingRuntime(
        managerPlanningResponses: [initialPlan, revisedPlan]
    )
    let workflowOwnership = GitWorktreeOwnership(
        ownerProfileID: builder.id,
        repositoryPath: "/tmp/project",
        worktreePath: "/tmp/.bl00p-worktrees/declined-plan",
        branch: "bl00p/declined-plan",
        baseRevision: "abc123"
    )
    let unfinishedPackage = GitHandoffPackage(
        sourceProfileID: builder.id,
        sourceName: builder.name,
        repositoryPath: workflowOwnership.repositoryPath,
        worktreePath: workflowOwnership.worktreePath,
        branch: workflowOwnership.branch,
        baseRevision: workflowOwnership.baseRevision,
        headRevision: workflowOwnership.baseRevision,
        taskContext: "Plan this change",
        testStatus: .notRun,
        testSummary: "Not run",
        workingTreeSummary: "Clean"
    )
    let workflowWorktrees = StubWorktreeManager(
        packages: [unfinishedPackage],
        preparedOwnership: workflowOwnership
    )
    let model = AppModel(
        runtime: runtime,
        worktrees: workflowWorktrees,
        store: store
    )
    #expect(model.setRepositoryPath("/tmp/project", for: manager.id))

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
    await model.flushPersistence()
    #expect(
        model.session(for: manager.id).entries.filter {
            $0.text == initialPlan
        }.map(\.kind) == [.approval]
    )
    let restoredModel = AppModel(
        runtime: runtime,
        worktrees: workflowWorktrees,
        store: AppStateStore(fileURL: store.fileURL)
    )
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
    await restoredModel.flushPersistence()

    let resolvedRestoredModel = AppModel(
        runtime: runtime,
        worktrees: workflowWorktrees,
        store: AppStateStore(fileURL: store.fileURL)
    )
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

    let revisedApproval = try #require(
        resolvedRestoredModel.session(for: manager.id).entries.last(where: {
            $0.kind == .approval && $0.approvalState == .pending
        })
    )
    let revisedEntries = resolvedRestoredModel.session(for: manager.id).entries
    #expect(revisedApproval.text == revisedPlan)
    #expect(revisedEntries.filter { $0.text == revisedPlan }.count == 1)
    #expect(revisedEntries.last?.id == revisedApproval.id)
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
    await resolvedRestoredModel.flushPersistence()

    let revisedRestoredModel = AppModel(
        runtime: runtime,
        worktrees: workflowWorktrees,
        store: AppStateStore(fileURL: store.fileURL)
    )
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

    revisedRestoredModel.resolveApproval(
        revisedApproval.id,
        approved: true,
        for: manager.id
    )
    for _ in 0..<100
        where await runtime.calls.filter({ $0.role == .builder }).isEmpty {
        try await Task.sleep(for: .milliseconds(10))
    }

    let builderBrief = try #require(
        revisedRestoredModel.sessions[
            revisedRestoredModel.workflow(for: manager.id)?
                .participantSessionIDs[.builder] ?? builder.id
        ]?.entries.first(where: {
            $0.title == "Implementation brief"
        })
    )
    let builderCall = try #require(
        await runtime.calls.first(where: { $0.role == .builder })
    )
    #expect(builderBrief.text == revisedPlan)
    #expect(
        taggedField(
            "approved_implementation_plan",
            in: builderCall.message
        ) == revisedPlan
    )
    #expect(!builderCall.message.contains(initialPlan))
}

@MainActor
@Test
func inconsistentApprovedManagerPlanPausesBeforeBuilderDispatch() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-manager-plan-inconsistent-\(UUID().uuidString)",
            isDirectory: true
        )
    defer { try? FileManager.default.removeItem(at: directory) }

    let fixture = managedWorkflowFixture()
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    try store.saveFixture(
        PersistedAppState(
            profiles: fixture.profiles,
            sessions: Dictionary(
                uniqueKeysWithValues: fixture.profiles.map {
                    ($0.id, AgentSessionState())
                }
            ),
            selectedBotID: fixture.manager.id
        )
    )
    let runtime = OrchestrationRecordingRuntime(
        managerPlanningResponses: [orchestrationImplementationPlan]
    )
    let model = AppModel(runtime: runtime, store: store)

    model.send("Implement the requested feature", to: fixture.manager.id)
    for _ in 0..<100
        where model.session(for: fixture.manager.id).status
            != .needsApproval {
        try await Task.sleep(for: .milliseconds(10))
    }

    let approval = try #require(
        model.session(for: fixture.manager.id).entries.last(where: {
            $0.kind == .approval && $0.approvalState == .pending
        })
    )
    var inconsistentWorkflow = try #require(
        model.workflow(for: fixture.manager.id)
    )
    inconsistentWorkflow.implementationPlan = "A different plan"
    model.managerWorkflows[fixture.manager.id] = inconsistentWorkflow

    model.resolveApproval(
        approval.id,
        approved: true,
        for: fixture.manager.id
    )

    let paused = try #require(model.workflow(for: fixture.manager.id))
    let resolvedApproval = try #require(
        model.session(for: fixture.manager.id).entries.first(where: {
            $0.id == approval.id
        })
    )
    #expect(paused.stage == .planning)
    #expect(paused.isPaused)
    #expect(paused.planApprovalEntryID == nil)
    #expect(paused.approvedPlanEntryID == nil)
    #expect(
        paused.pauseReason?.contains(
            "approved implementation plan is missing or inconsistent"
        ) == true
    )
    #expect(resolvedApproval.approvalState == .approved)
    #expect(
        model.session(for: fixture.manager.id).status == .needsAnswer
    )
    #expect(
        model.session(for: fixture.builder.id).entries.contains(where: {
            $0.title == "Implementation brief"
        }) == false
    )
    #expect(await runtime.calls.map(\.role) == [.manager])
}

@MainActor
@Test
func managerPlanningWithoutAPlanPausesWithoutAdoptingOlderMessages() async throws {
    for olderEntry in [
        nil,
        TimelineEntry(
            kind: .assistant,
            text: "Unrelated guidance from before the managed workflow."
        )
    ] as [TimelineEntry?] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "bl00p-manager-empty-plan-\(UUID().uuidString)",
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
        var sessions = Dictionary(
            uniqueKeysWithValues: [manager, builder, reviewer, publisher]
                .map { ($0.id, AgentSessionState()) }
        )
        if let olderEntry {
            sessions[manager.id] = AgentSessionState(entries: [olderEntry])
        }
        let store = AppStateStore(
            fileURL: directory.appendingPathComponent("state.json")
        )
        store.save(
            PersistedAppState(
                profiles: [manager, builder, reviewer, publisher],
                sessions: sessions,
                selectedBotID: manager.id
            )
        )
        let runtime = OrchestrationRecordingRuntime(
            managerPlanningResponses: [""]
        )
        let model = AppModel(runtime: runtime, store: store)
        #expect(model.setRepositoryPath("/tmp/project", for: manager.id))

        model.send("Plan this change", to: manager.id)
        for _ in 0..<100
            where model.workflow(for: manager.id)?.isPaused != true {
            try await Task.sleep(for: .milliseconds(10))
        }

        let workflow = try #require(model.workflow(for: manager.id))
        let entries = model.session(for: manager.id).entries
        #expect(workflow.stage == .planning)
        #expect(workflow.isPaused)
        #expect(workflow.implementationPlan == nil)
        #expect(workflow.planApprovalEntryID == nil)
        #expect(
            workflow.pauseReason?
                .contains("without returning an implementation plan") == true
        )
        #expect(entries.contains(where: { $0.kind == .approval }) == false)
        #expect(entries.last?.kind == .system)
        #expect(entries.last?.text == "Workflow paused")
        #expect(
            entries.last?.detail?
                .contains("without returning an implementation plan") == true
        )
        if let olderEntry {
            let preservedEntry = try #require(
                entries.first(where: { $0.id == olderEntry.id })
            )
            #expect(preservedEntry.kind == .assistant)
            #expect(preservedEntry.text == olderEntry.text)
        } else {
            #expect(entries.contains(where: { $0.kind == .assistant }) == false)
        }
    }
}

@MainActor
@Test
func relaunchRecoversACompletedManagerPlanAndDispatchesBuilderOnce() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-manager-plan-recovery-\(UUID().uuidString)",
            isDirectory: true
        )
    defer { try? FileManager.default.removeItem(at: directory) }

    let fixture = managedWorkflowFixture()
    let plan = "Implement idempotent plan approval recovery with tests."
    let workflow = ManagerWorkflow(
        managerProfileID: fixture.manager.id,
        team: fixture.team,
        request: "Recover missing approval cards"
    )
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    store.save(
        PersistedAppState(
            profiles: fixture.profiles,
            sessions: [
                fixture.manager.id: AgentSessionState(
                    status: .completed,
                    entries: [.init(kind: .assistant, text: plan)]
                ),
                fixture.builder.id: AgentSessionState(),
                fixture.reviewer.id: AgentSessionState(),
                fixture.publisher.id: AgentSessionState()
            ],
            selectedBotID: fixture.manager.id,
            managerWorkflows: [fixture.manager.id: workflow]
        )
    )

    let runtime = RecoveredApprovalRuntime()
    let recoveredOwnership = GitWorktreeOwnership(
        ownerProfileID: fixture.builder.id,
        repositoryPath: "/tmp/project",
        worktreePath: "/tmp/.bl00p-worktrees/recovered-plan",
        branch: "bl00p/recovered-plan",
        baseRevision: "abc123"
    )
    let worktrees = StubWorktreeManager(
        packages: [],
        preparedOwnership: recoveredOwnership
    )
    let firstRelaunch = AppModel(
        runtime: runtime,
        worktrees: worktrees,
        store: store
    )
    let firstApproval = try #require(
        firstRelaunch.session(for: fixture.manager.id).entries.first(where: {
            $0.kind == .approval && $0.approvalState == .pending
        })
    )
    #expect(firstApproval.text == plan)
    #expect(
        firstRelaunch.workflow(for: fixture.manager.id)?
            .planApprovalEntryID == firstApproval.id
    )
    #expect(
        firstRelaunch.session(for: fixture.manager.id).status
            == .needsApproval
    )

    let secondRelaunch = AppModel(
        runtime: runtime,
        worktrees: worktrees,
        store: store
    )
    let pendingApprovals = secondRelaunch
        .session(for: fixture.manager.id)
        .entries
        .filter {
            $0.kind == .approval && $0.approvalState == .pending
        }
    #expect(pendingApprovals.map(\.id) == [firstApproval.id])
    #expect(
        secondRelaunch.workflow(for: fixture.manager.id)?
            .planApprovalEntryID == firstApproval.id
    )

    secondRelaunch.resolveApproval(
        firstApproval.id,
        approved: true,
        for: fixture.manager.id
    )
    secondRelaunch.resolveApproval(
        firstApproval.id,
        approved: true,
        for: fixture.manager.id
    )
    for _ in 0..<100 where await runtime.builderDispatchCount == 0 {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(await runtime.builderDispatchCount == 1)
}

@MainActor
@Test
func relaunchDoesNotTurnARuntimeApprovalIntoAPlanApproval() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-manager-runtime-approval-\(UUID().uuidString)",
            isDirectory: true
        )
    defer { try? FileManager.default.removeItem(at: directory) }

    let fixture = managedWorkflowFixture()
    let runtimeApprovalID = UUID()
    let declinedPlan = "Previously declined implementation plan."
    let workflow = ManagerWorkflow(
        managerProfileID: fixture.manager.id,
        team: fixture.team,
        request: "Plan a repository change",
        implementationPlan: declinedPlan
    )
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    store.save(
        PersistedAppState(
            profiles: fixture.profiles,
            sessions: [
                fixture.manager.id: AgentSessionState(
                    status: .needsApproval,
                    entries: [
                        .init(
                            kind: .assistant,
                            text: "I need to inspect one more file."
                        ),
                        .init(
                            kind: .approval,
                            title: "Approve implementation plan",
                            text: declinedPlan,
                            approvalState: .declined
                        ),
                        .init(
                            id: runtimeApprovalID,
                            kind: .approval,
                            title: "Run repository inspection",
                            text: "git show HEAD:Package.swift",
                            approvalState: .pending
                        )
                    ],
                    sessionID: "legacy-manager-thread",
                    codexTurnModeVersion: CodexThreadConfiguration.turnModeVersion
                )
            ],
            selectedBotID: fixture.manager.id,
            managerWorkflows: [fixture.manager.id: workflow]
        )
    )

    let model = AppModel(
        runtime: RecoveredApprovalRuntime(),
        store: store
    )
    let restoredSession = model.session(for: fixture.manager.id)

    #expect(restoredSession.status == .stopped)
    #expect(
        restoredSession.entries.contains(where: {
            $0.id == runtimeApprovalID && $0.approvalState == .pending
        })
    )
    #expect(
        !restoredSession.entries.contains(where: {
            $0.title == "Approve implementation plan"
                && $0.approvalState == .pending
        })
    )
    #expect(
        model.workflow(for: fixture.manager.id)?
            .planApprovalEntryID == nil
    )
    #expect(
        model.workflow(for: fixture.manager.id)?
            .implementationPlan == declinedPlan
    )
}

@MainActor
@Test
func relaunchAdoptsAPlanApprovalCardWhoseWorkflowIDWasNotSaved() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-manager-plan-id-recovery-\(UUID().uuidString)",
            isDirectory: true
        )
    defer { try? FileManager.default.removeItem(at: directory) }

    let fixture = managedWorkflowFixture()
    let plan = "Adopt the already-persisted approval card."
    let approvalID = UUID()
    let duplicateID = UUID()
    let workflow = ManagerWorkflow(
        managerProfileID: fixture.manager.id,
        team: fixture.team,
        request: "Recover the workflow approval ID",
        implementationPlan: plan
    )
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    store.save(
        PersistedAppState(
            profiles: fixture.profiles,
            sessions: [
                fixture.manager.id: AgentSessionState(
                    status: .needsApproval,
                    entries: [
                        .init(
                            id: approvalID,
                            kind: .approval,
                            title: "Approve implementation plan",
                            text: plan,
                            approvalState: .pending
                        ),
                        .init(
                            kind: .system,
                            text: "Workflow paused after approval card"
                        ),
                        .init(
                            id: duplicateID,
                            kind: .approval,
                            title: "Approve implementation plan",
                            text: "Stale plan",
                            approvalState: .pending
                        )
                    ]
                )
            ],
            selectedBotID: fixture.manager.id,
            managerWorkflows: [fixture.manager.id: workflow]
        )
    )

    let model = AppModel(runtime: RecoveredApprovalRuntime(), store: store)
    let pendingApprovals = model
        .session(for: fixture.manager.id)
        .entries
        .filter {
            $0.kind == .approval && $0.approvalState == .pending
        }

    #expect(pendingApprovals.map(\.id) == [approvalID])
    #expect(
        model.workflow(for: fixture.manager.id)?.planApprovalEntryID
            == approvalID
    )
    let restoredEntries = model.session(for: fixture.manager.id).entries
    let approvalIndex = try #require(
        restoredEntries.firstIndex(where: { $0.id == approvalID })
    )
    let pausedEntryIndex = try #require(
        restoredEntries.firstIndex(where: {
            $0.text == "Workflow paused after approval card"
        })
    )
    #expect(approvalIndex < pausedEntryIndex)

    let missingEntryID = UUID()
    let missingEntryStore = AppStateStore(
        fileURL: directory.appendingPathComponent("missing-entry-state.json")
    )
    missingEntryStore.save(
        PersistedAppState(
            profiles: fixture.profiles,
            sessions: [
                fixture.manager.id: AgentSessionState(
                    status: .completed,
                    entries: [.init(kind: .assistant, text: plan)]
                )
            ],
            selectedBotID: fixture.manager.id,
            managerWorkflows: [
                fixture.manager.id: ManagerWorkflow(
                    managerProfileID: fixture.manager.id,
                    team: fixture.team,
                    request: "Recover the missing approval entry",
                    implementationPlan: plan,
                    planApprovalEntryID: missingEntryID
                )
            ]
        )
    )

    let missingEntryModel = AppModel(
        runtime: RecoveredApprovalRuntime(),
        store: missingEntryStore
    )
    let recoveredEntry = missingEntryModel
        .session(for: fixture.manager.id)
        .entries
        .first(where: { $0.id == missingEntryID })
    #expect(recoveredEntry?.approvalState == .pending)
    #expect(
        missingEntryModel.workflow(for: fixture.manager.id)?
            .planApprovalEntryID == missingEntryID
    )
}

@MainActor
@Test
func relaunchDoesNotRestoreIncompleteOrResolvedManagerPlans() {
    let fixture = managedWorkflowFixture()
    let plan = "This plan must not be restored."
    let declinedID = UUID()
    let failedID = UUID()
    let interruptedID = UUID()
    let partialID = UUID()
    let cases: [(String, UUID, AgentSessionState)] = [
        (
            "declined",
            declinedID,
            AgentSessionState(
                status: .needsAnswer,
                entries: [
                    .init(
                        id: declinedID,
                        kind: .approval,
                        title: "Approve implementation plan",
                        text: plan,
                        approvalState: .declined
                    )
                ]
            )
        ),
        (
            "failed",
            failedID,
            AgentSessionState(
                status: .failed,
                entries: [
                    .init(kind: .assistant, text: plan),
                    .init(
                        id: failedID,
                        kind: .approval,
                        title: "Approve implementation plan",
                        text: plan,
                        approvalState: .pending
                    )
                ]
            )
        ),
        (
            "interrupted",
            interruptedID,
            AgentSessionState(
                status: .working,
                entries: [
                    .init(kind: .assistant, text: plan),
                    .init(
                        id: interruptedID,
                        kind: .approval,
                        title: "Approve implementation plan",
                        text: plan,
                        approvalState: .pending
                    )
                ]
            )
        ),
        (
            "partial",
            partialID,
            AgentSessionState(
                status: .completed,
                entries: [
                    .init(kind: .assistant, text: "   "),
                    .init(
                        id: partialID,
                        kind: .approval,
                        title: "Approve implementation plan",
                        text: "   ",
                        approvalState: .pending
                    )
                ]
            )
        )
    ]

    for (name, approvalID, managerSession) in cases {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "bl00p-manager-plan-\(name)-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        let workflow = ManagerWorkflow(
            managerProfileID: fixture.manager.id,
            team: fixture.team,
            request: "Do not recover \(name)",
            implementationPlan: name == "partial" ? nil : plan,
            planApprovalEntryID: approvalID
        )
        let store = AppStateStore(
            fileURL: directory.appendingPathComponent("state.json")
        )
        store.save(
            PersistedAppState(
                profiles: fixture.profiles,
                sessions: [fixture.manager.id: managerSession],
                selectedBotID: fixture.manager.id,
                managerWorkflows: [fixture.manager.id: workflow]
            )
        )

        let model = AppModel(
            runtime: RecoveredApprovalRuntime(),
            store: store
        )
        let pendingApprovals = model
            .session(for: fixture.manager.id)
            .entries
            .filter {
                $0.kind == .approval && $0.approvalState == .pending
            }
        #expect(pendingApprovals.isEmpty, "Unexpected recovery for \(name)")
        #expect(
            model.workflow(for: fixture.manager.id)?
                .planApprovalEntryID == nil,
            "Unexpected workflow approval ID for \(name)"
        )
    }
}

@MainActor
@Test
func relaunchRecoversARevisedPlanWithoutResurrectingTheDeclinedPlan() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-manager-revised-plan-\(UUID().uuidString)",
            isDirectory: true
        )
    defer { try? FileManager.default.removeItem(at: directory) }

    let fixture = managedWorkflowFixture()
    let declinedPlan = "Change every workflow at once."
    let revisedPlan = "Change only plan approval restoration and its tests."
    let declinedID = UUID()
    let workflow = ManagerWorkflow(
        managerProfileID: fixture.manager.id,
        team: fixture.team,
        request: "Fix plan approval restoration",
        implementationPlan: declinedPlan,
        isPaused: true,
        pauseReason: "Plan declined."
    )
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    store.save(
        PersistedAppState(
            profiles: fixture.profiles,
            sessions: [
                fixture.manager.id: AgentSessionState(
                    status: .completed,
                    entries: [
                        .init(kind: .assistant, text: declinedPlan),
                        .init(
                            id: declinedID,
                            kind: .approval,
                            title: "Approve implementation plan",
                            text: declinedPlan,
                            approvalState: .declined
                        ),
                        .init(
                            kind: .user,
                            text: "Keep the revision narrowly scoped."
                        ),
                        .init(kind: .assistant, text: revisedPlan)
                    ]
                )
            ],
            selectedBotID: fixture.manager.id,
            managerWorkflows: [fixture.manager.id: workflow]
        )
    )

    let firstRelaunch = AppModel(
        runtime: RecoveredApprovalRuntime(),
        store: store
    )
    let secondRelaunch = AppModel(
        runtime: RecoveredApprovalRuntime(),
        store: store
    )
    let approvalEntries = secondRelaunch
        .session(for: fixture.manager.id)
        .entries
        .filter { $0.kind == .approval }

    #expect(approvalEntries.count == 2)
    #expect(
        approvalEntries.contains(where: {
            $0.id == declinedID
                && $0.text == declinedPlan
                && $0.approvalState == .declined
        })
    )
    #expect(
        approvalEntries.filter {
            $0.text == revisedPlan && $0.approvalState == .pending
        }.count == 1
    )
    #expect(
        firstRelaunch.workflow(for: fixture.manager.id)?
            .implementationPlan == revisedPlan
    )
    #expect(
        secondRelaunch.workflow(for: fixture.manager.id)?
            .implementationPlan == revisedPlan
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
    try store.saveFixture(
        PersistedAppState(
            profiles: [manager],
            sessions: [manager.id: AgentSessionState()],
            selectedBotID: manager.id
        )
    )
    let runtime = ImmediateRecordingRuntime()
    let model = AppModel(runtime: runtime, store: store)
    #expect(model.setRepositoryPath("/tmp", for: manager.id))

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
        repositoryPath: "/tmp/project",
        team: team,
        request: "Ship the feature",
        stage: .publishing
    )
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    try store.saveFixture(
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
func cleanReviewPausesBeforeTransitionWhenPublisherWasDeleted() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-missing-publisher-\(UUID().uuidString)",
            isDirectory: true
        )
    defer { try? FileManager.default.removeItem(at: directory) }

    var builder = BotProfile.defaults[0]
    var reviewer = BotProfile.defaults[1]
    builder.id = UUID()
    reviewer.id = UUID()
    let team = ManagerTeamConfiguration(
        builderProfileID: builder.id,
        reviewerProfileID: reviewer.id,
        publisherProfileID: nil
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
        repositoryPath: "/tmp/project",
        team: team,
        request: "Ship safely",
        stage: .reviewing
    )
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    try store.saveFixture(
        PersistedAppState(
            profiles: [manager, builder, reviewer],
            sessions: [
                manager.id: AgentSessionState(),
                builder.id: AgentSessionState(),
                reviewer.id: AgentSessionState()
            ],
            selectedBotID: reviewer.id,
            managerWorkflows: [manager.id: workflow]
        )
    )
    let runtime = OrchestrationRecordingRuntime(
        reviewerResponses: [
            """
            Review clean.
            BL00P_REVIEW_DISPOSITION: clean
            """
        ]
    )
    let model = AppModel(runtime: runtime, store: store)

    model.send("Finish the review", to: reviewer.id)
    for _ in 0..<50
        where model.workflow(for: manager.id)?.pauseReason
            != "The assigned Documenter / PR Writer is no longer available." {
        try await Task.sleep(for: .milliseconds(10))
    }

    let paused = try #require(model.workflow(for: manager.id))
    #expect(paused.stage == .reviewing)
    #expect(paused.isPaused)
    #expect(
        paused.pauseReason
            == "The assigned Documenter / PR Writer is no longer available."
    )
}

@MainActor
@Test
func legacyReportingWorkflowCompletesDuringRestore() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-legacy-reporting-\(UUID().uuidString)",
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
        request: "Restore delivery",
        stage: .reporting,
        branch: "bl00p/legacy-reporting",
        pullRequestURL: "https://github.com/suttree/bl00p/pull/77",
        verificationSummary: "Review clean.",
        publisherSummary: "Draft PR prepared."
    )
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    try store.saveFixture(
        PersistedAppState(
            profiles: [manager, builder, reviewer, publisher],
            sessions: Dictionary(
                uniqueKeysWithValues: [manager, builder, reviewer, publisher]
                    .map { ($0.id, AgentSessionState()) }
            ),
            selectedBotID: manager.id,
            managerWorkflows: [manager.id: workflow]
        )
    )

    let model = AppModel(runtime: DemoAgentRuntime(), store: store)
    let restored = try #require(model.workflow(for: manager.id))

    #expect(restored.stage == .completed)
    #expect(
        restored.pullRequestURL
            == "https://github.com/suttree/bl00p/pull/77"
    )
    #expect(
        model.session(for: manager.id).entries.last?.text
            == "Managed workflow complete"
    )
}

@MainActor
@Test
func deletingAnAssignedBotClearsTheManagersStaleTeamReference() async throws {
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
    try store.saveFixture(
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
    await model.flushPersistence()

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
    try store.saveFixture(
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
    #expect(model.session(for: profile.id).worktree?.worktreePath
        == ownership.worktreePath)
    #expect(model.session(for: profile.id).repositoryPath
        == ownership.repositoryPath)
}

@MainActor
@Test
func nonInitialBuilderTabReusesItsOwnWorktreeAcrossProfileSettingChanges() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-reuse-tab-worktree-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    var profile = BotProfile.defaults[0]
    profile.workingDirectory = "/tmp/project"
    profile.worktree = nil
    let sessionID = UUID()
    let ownership = GitWorktreeOwnership(
        ownerProfileID: profile.id,
        ownerSessionID: sessionID,
        repositoryPath: "/tmp/project",
        worktreePath: "/tmp/.bl00p-worktrees/project-session",
        branch: "bl00p/session",
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
        taskContext: "Reuse the tab worktree",
        testStatus: .notRun,
        testSummary: "Not run",
        workingTreeSummary: "Clean"
    )
    let store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    store.save(
        PersistedAppState(
            profiles: [profile],
            sessions: [
                sessionID: AgentSessionState(
                    id: sessionID,
                    ownerProfileID: profile.id,
                    worktree: ownership
                )
            ],
            selectedBotID: profile.id,
            sessionOrder: [profile.id: [sessionID]],
            selectedSessionIDs: [profile.id: sessionID]
        )
    )
    let worktrees = ReuseRecordingWorktreeManager(
        package: package,
        ownership: ownership
    )
    let model = AppModel(
        runtime: HandoffRecordingRuntime(),
        worktrees: worktrees,
        store: store
    )

    var updated = try #require(model.profiles.first)
    updated.workingDirectory = "/tmp/a-different-default"
    model.update(updated)
    #expect(model.sessions[sessionID]?.worktree == ownership)

    model.send("Continue", to: profile.id)
    for _ in 0..<30 where await worktrees.receivedWorktree == nil {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(await worktrees.receivedWorktree == ownership)
    #expect(await worktrees.receivedWorkingDirectory == ownership.repositoryPath)
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

    try store.saveFixture(expected)
    let actual = try #require(store.load())

    #expect(actual.selectedBotID == expected.selectedBotID)
    #expect(actual.sessions[profile.id]?.entries.first?.timestamp != nil)
    #expect(actual.sessions[profile.id]?.entries.first?.text == "Which PR?")

    try? FileManager.default.removeItem(at: directory)
}

@Test
func persistenceQueueCoalescesBurstsAndKeepsTheLatestState() async throws {
    let writer = CountingStateWriter()
    let scheduler = ManualPersistenceScheduler()
    let queue = AppStatePersistenceQueue(
        writer: writer,
        scheduler: scheduler,
        coalescingDelay: .seconds(1)
    )
    let profiles = BotProfile.defaults

    for revision in 1...3 {
        await queue.enqueue(
            PersistedAppState(
                profiles: profiles,
                sessions: [:],
                selectedBotID: profiles[revision - 1].id
            ),
            revision: UInt64(revision)
        )
    }
    for _ in 0..<20 where await scheduler.waiterCount == 0 {
        await Task.yield()
    }
    await scheduler.resumeAll()
    for _ in 0..<20 where await writer.writeCount == 0 {
        await Task.yield()
    }
    await queue.flushPending()

    #expect(await writer.writeCount == 1)
    #expect(await writer.lastState?.selectedBotID == profiles[2].id)
}

@Test
func persistenceQueueFlushesCriticalBoundariesImmediately() async {
    let writer = CountingStateWriter()
    let scheduler = ManualPersistenceScheduler()
    let queue = AppStatePersistenceQueue(
        writer: writer,
        scheduler: scheduler,
        coalescingDelay: .seconds(60)
    )
    let profile = BotProfile.defaults[0]
    let ordinary = PersistedAppState(
        profiles: [profile],
        sessions: [profile.id: AgentSessionState(status: .working)],
        selectedBotID: profile.id
    )
    let critical = PersistedAppState(
        profiles: [profile],
        sessions: [profile.id: AgentSessionState(status: .needsApproval)],
        selectedBotID: profile.id
    )

    await queue.enqueue(ordinary, revision: 1)
    await queue.flush(critical, revision: 2)

    #expect(await writer.writeCount == 1)
    #expect(await writer.lastState?.sessions[profile.id]?.status == .needsApproval)
}

@Test
func persistenceQueueMaintainsLastWriteWinsWithASlowWriter() async {
    let writer = CountingStateWriter(delay: .milliseconds(40))
    let scheduler = ManualPersistenceScheduler()
    let queue = AppStatePersistenceQueue(
        writer: writer,
        scheduler: scheduler,
        coalescingDelay: .seconds(1)
    )
    let profiles = BotProfile.defaults
    let first = PersistedAppState(
        profiles: profiles,
        sessions: [:],
        selectedBotID: profiles[0].id
    )
    let second = PersistedAppState(
        profiles: profiles,
        sessions: [:],
        selectedBotID: profiles[1].id
    )
    let latest = PersistedAppState(
        profiles: profiles,
        sessions: [:],
        selectedBotID: profiles[2].id
    )

    let firstFlush = Task {
        await queue.flush(first, revision: 1)
    }
    for _ in 0..<20 where await writer.startedWriteCount == 0 {
        await Task.yield()
    }
    await queue.enqueue(second, revision: 2)
    await queue.flush(latest, revision: 3)
    await firstFlush.value

    #expect(await writer.lastState?.selectedBotID == profiles[2].id)
    #expect(await writer.writeCount == 2)
}

@Test
func appStateStoreRotatesPreviousStateIntoBackupOnSave() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-tests-\(UUID().uuidString)", isDirectory: true)
    let fileURL = directory.appendingPathComponent("state.json")
    let backupURL = directory.appendingPathComponent("state.json.bak")
    let store = AppStateStore(fileURL: fileURL)
    let first = BotProfile.defaults[0]
    let second = BotProfile.defaults[1]

    store.save(
        PersistedAppState(profiles: [first], sessions: [:], selectedBotID: first.id)
    )
    store.save(
        PersistedAppState(profiles: [second], sessions: [:], selectedBotID: second.id)
    )

    let backupData = try #require(FileManager.default.contents(atPath: backupURL.path))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let backupState = try decoder.decode(PersistedAppState.self, from: backupData)
    #expect(backupState.selectedBotID == first.id)

    let current = try #require(store.load())
    #expect(current.selectedBotID == second.id)

    try? FileManager.default.removeItem(at: directory)
}

@Test
func appStateStoreLoadsBackupWhenPrimaryIsUnreadable() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-tests-\(UUID().uuidString)", isDirectory: true)
    let fileURL = directory.appendingPathComponent("state.json")
    let store = AppStateStore(fileURL: fileURL)
    let first = BotProfile.defaults[0]
    let second = BotProfile.defaults[1]

    store.save(
        PersistedAppState(profiles: [first], sessions: [:], selectedBotID: first.id)
    )
    store.save(
        PersistedAppState(profiles: [second], sessions: [:], selectedBotID: second.id)
    )
    try Data("not valid json".utf8).write(to: fileURL, options: .atomic)

    let recovered = try #require(store.load())

    #expect(recovered.selectedBotID == first.id)
    #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    let quarantined = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.hasPrefix("state.corrupt-") }
    #expect(quarantined.count == 1)

    try? FileManager.default.removeItem(at: directory)
}

@Test
func appStateStorePreservesPrimaryWhenBackupRotationFails() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-tests-\(UUID().uuidString)", isDirectory: true)
    let fileURL = directory.appendingPathComponent("state.json")
    let backupURL = directory.appendingPathComponent("state.json.bak")
    let store = AppStateStore(fileURL: fileURL)
    let first = BotProfile.defaults[0]
    let second = BotProfile.defaults[1]

    store.save(
        PersistedAppState(profiles: [first], sessions: [:], selectedBotID: first.id)
    )
    try FileManager.default.createDirectory(
        at: backupURL,
        withIntermediateDirectories: true
    )

    store.save(
        PersistedAppState(profiles: [second], sessions: [:], selectedBotID: second.id)
    )

    let preserved = try #require(store.load())
    #expect(preserved.selectedBotID == first.id)

    try? FileManager.default.removeItem(at: directory)
}

@Test
func appStateStoreQuarantinesUndecodableStateInsteadOfDiscardingIt() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-tests-\(UUID().uuidString)", isDirectory: true)
    let fileURL = directory.appendingPathComponent("state.json")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("not valid json".utf8).write(to: fileURL)
    let store = AppStateStore(fileURL: fileURL)

    let loaded = store.load()

    #expect(loaded == nil)
    #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    let quarantined = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.hasPrefix("state.corrupt-") }
    #expect(quarantined.count == 1)

    try? FileManager.default.removeItem(at: directory)
}

@MainActor
@Test
func fiveHundredEventStreamIsNotBlockedBySlowPersistence() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-500-events-\(UUID().uuidString)",
            isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let writer = BlockingStateWriter()
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json"),
        writer: writer
    )
    let runtime = FiveHundredEventRuntime()
    let model = AppModel(runtime: runtime, store: store)
    let profileID = try #require(model.profiles.dropFirst().first?.id)
    #expect(model.setRepositoryPath("/tmp", for: profileID))

    model.send("Stream a large result", to: profileID)
    for _ in 0..<200 {
        if model.session(for: profileID).status == .completed,
           await writer.startedWriteCount > 0 {
            break
        }
        try await Task.sleep(for: .milliseconds(5))
    }

    #expect(model.session(for: profileID).status == .completed)
    #expect(model.session(for: profileID).entries.count == 501)
    #expect(await writer.startedWriteCount > 0)
    #expect(await writer.writeCount == 0)
    await writer.release()
    await model.flushPersistence()
}

@Test
func providerPreflightCachesSuccessAndInvalidatesAuthentication() async throws {
    let cache = ProviderPreflightCache()
    let probe = LockedPreflightProbe()
    let executable = URL(fileURLWithPath: "/tmp/claude")

    for _ in 0..<2 {
        let located = await cache.executable {
            probe.recordExecutableProbe()
            return executable
        }
        #expect(located == executable)
        let status = await cache.claudeAuthentication(for: executable) { _ in
            probe.recordAuthenticationProbe()
            return .loggedIn
        }
        guard case .loggedIn = status else {
            Issue.record("Expected a cached logged-in status")
            return
        }
    }
    #expect(probe.executableProbeCount == 1)
    #expect(probe.authenticationProbeCount == 1)

    await cache.invalidateClaudeAuthentication(for: executable)
    _ = await cache.claudeAuthentication(for: executable) { _ in
        probe.recordAuthenticationProbe()
        return .loggedIn
    }
    #expect(probe.authenticationProbeCount == 2)
}

@Test
func repeatedClaudeLaunchesReuseSuccessfulAuthenticationProbe() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-claude-preflight-\(UUID().uuidString)",
            isDirectory: true
        )
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("claude")
    try makeExecutable(at: executable)
    let probe = LockedPreflightProbe()
    let runtime = ClaudeRuntime(
        locator: ClaudeExecutableLocator(candidateURLs: [executable]),
        authenticationProbe: { _ in
            probe.recordAuthenticationProbe()
            return .loggedIn
        }
    )
    var profile = BotProfile.defaults[0]
    profile.workingDirectory = directory.path

    for _ in 0..<2 {
        let stream = await runtime.start(
            profile: profile,
            resumeThreadID: nil
        )
        for await _ in stream {}
    }
    await runtime.stop(profile: profile)

    #expect(probe.authenticationProbeCount == 1)
}

@Test
func claudeRuntimeFailureInvalidatesCachedPreflight() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-claude-invalidation-\(UUID().uuidString)",
            isDirectory: true
        )
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("claude")
    try makeExecutable(at: executable)
    let probe = LockedPreflightProbe()
    let runtime = ClaudeRuntime(
        locator: ClaudeExecutableLocator(candidateURLs: [executable]),
        authenticationProbe: { _ in
            probe.recordAuthenticationProbe()
            return .loggedIn
        }
    )
    var profile = BotProfile.defaults[0]
    profile.workingDirectory = directory.path

    let launch = await runtime.start(
        profile: profile,
        resumeThreadID: nil
    )
    for await _ in launch {}
    let response = await runtime.respond(
        to: "Trigger the failing test executable",
        attachments: [],
        profile: profile
    )
    for await _ in response {}

    let relaunch = await runtime.start(
        profile: profile,
        resumeThreadID: nil
    )
    for await _ in relaunch {}
    await runtime.stop(profile: profile)

    #expect(probe.authenticationProbeCount == 2)
}

@MainActor
@Test
func legacyPlanApprovalEntriesGainMarkdownMetadataOnRestore() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-tests-\(UUID().uuidString)", isDirectory: true)
    let manager = BotProfile(
        name: "Manager",
        provider: .codex,
        role: .manager,
        instructions: "Coordinate."
    )
    let entry = TimelineEntry(
        kind: .approval,
        title: "Approve implementation plan",
        text: "## Plan\n\n- Implement the fix",
        approvalState: .pending
    )
    let workflow = ManagerWorkflow(
        managerProfileID: manager.id,
        team: ManagerTeamConfiguration(),
        request: "Implement the fix",
        implementationPlan: entry.text,
        planApprovalEntryID: entry.id
    )
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    store.save(
        PersistedAppState(
            profiles: [manager],
            sessions: [
                manager.id: AgentSessionState(
                    status: .needsApproval,
                    entries: [entry]
                )
            ],
            selectedBotID: manager.id,
            managerWorkflows: [manager.id: workflow]
        )
    )

    let model = AppModel(runtime: DemoAgentRuntime(), store: store)

    #expect(model.session(for: manager.id).entries.first?.contentFormat == .markdown)
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
func jsonValueCompactDescriptionSortsObjectKeys() {
    let first = JSONValue.object([
        "zeta": .number(2),
        "alpha": .object([
            "two": .bool(true),
            "one": .string("first")
        ])
    ])
    let second = JSONValue.object([
        "alpha": .object([
            "one": .string("first"),
            "two": .bool(true)
        ]),
        "zeta": .number(2)
    ])

    #expect(first.compactDescription == second.compactDescription)
    #expect(
        first.compactDescription
            == #"{"alpha":{"one":"first","two":true},"zeta":2}"#
    )
    #expect(
        ClaudePermissionDenials.actionKey(
            toolName: "Edit",
            toolInput: first
        ) == ClaudePermissionDenials.actionKey(
            toolName: "Edit",
            toolInput: second
        )
    )
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
    #expect(invocation.arguments.contains("Bash(swift build)"))
    #expect(invocation.arguments.contains("Bash(swift build *)"))
    #expect(invocation.arguments.contains("Bash(swift build:*)"))
    #expect(invocation.arguments.contains("Bash(swift test)"))
    #expect(invocation.arguments.contains("Bash(swift test *)"))
    #expect(invocation.arguments.contains("Bash(swift test:*)"))
    #expect(invocation.arguments.contains("Bash(xcrun swift build)"))
    #expect(invocation.arguments.contains("Bash(xcrun swift build *)"))
    #expect(invocation.arguments.contains("Bash(xcrun swift build:*)"))
    #expect(invocation.arguments.contains("Bash(xcrun swift test)"))
    #expect(invocation.arguments.contains("Bash(xcrun swift test *)"))
    #expect(invocation.arguments.contains("Bash(xcrun swift test:*)"))
    #expect(invocation.arguments.contains("Bash(tail -20)"))
    #expect(!invocation.arguments.contains("Bash(tail *)"))
    #expect(invocation.arguments.contains("--input-format"))
    #expect(invocation.arguments.contains("--permission-prompt-tool"))
    #expect(invocation.arguments.contains("stdio"))
    let permissionModeIndex = try #require(
        invocation.arguments.firstIndex(of: "--permission-mode")
    )
    #expect(invocation.arguments[permissionModeIndex + 1] == "default")
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
func claudeInvocationUsesAResolvedPerChatPromptOverride() throws {
    var botDefault = BotProfile.defaults[0]
    botDefault.workingDirectory = "/tmp/project"
    var session = AgentSessionState()
    session.instructionsOverride = "Only touch the migration scripts."

    // Mirrors what AppModel.runtimeProfile does: resolve the effective
    // instructions for the chat before handing the profile to the runtime.
    var resolvedProfile = botDefault
    resolvedProfile.instructions = AgentSessionState.effectiveInstructions(
        profile: botDefault,
        session: session
    )

    let invocation = try ClaudeInvocation(
        sessionID: "64bfaf39-9db2-45b9-9f10-03a13ea2e772",
        resume: false,
        profile: resolvedProfile,
        prompt: "Implement BLOOP-42"
    )

    let systemPromptIndex = try #require(
        invocation.arguments.firstIndex(of: "--append-system-prompt")
    )
    let systemPrompt = invocation.arguments[systemPromptIndex + 1]
    #expect(systemPrompt.contains("Only touch the migration scripts."))
    #expect(!systemPrompt.contains(botDefault.instructions))
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
    #expect(!invocation.arguments.contains(where: { $0.hasPrefix("Bash(") }))
}

@Test
func claudePublisherInvocationUsesExplicitBuildAndTestRules() throws {
    let profile = BotProfile.defaults[2]
    let invocation = try ClaudeInvocation(
        sessionID: "64bfaf39-9db2-45b9-9f10-03a13ea2e772",
        resume: false,
        profile: profile,
        prompt: "Run final verification"
    )

    #expect(invocation.arguments.contains("Edit"))
    #expect(invocation.arguments.contains("Write"))
    for command in [
        "swift build",
        "swift test",
        "xcrun swift build",
        "xcrun swift test",
        "xcodebuild build",
        "xcodebuild test"
    ] {
        #expect(invocation.arguments.contains("Bash(\(command))"))
        #expect(invocation.arguments.contains("Bash(\(command) *)"))
        #expect(invocation.arguments.contains("Bash(\(command):*)"))
    }
}

@Test
func claudeInvocationKeepsProjectDeniesAndInteractiveApprovalsEnabled() throws {
    var profile = BotProfile.defaults[1]
    profile.loadProjectInstructions = true
    let invocation = try ClaudeInvocation(
        sessionID: "64bfaf39-9db2-45b9-9f10-03a13ea2e772",
        resume: false,
        profile: profile,
        prompt: "Review HEAD"
    )

    let settingSourcesIndex = try #require(
        invocation.arguments.firstIndex(of: "--setting-sources")
    )
    #expect(
        invocation.arguments[settingSourcesIndex + 1]
            == "user,project,local"
    )
    #expect(invocation.arguments.contains("--permission-prompt-tool"))
    #expect(invocation.arguments.contains("--permission-mode"))
    #expect(!invocation.arguments.contains("--dangerously-skip-permissions"))
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
func structuredQuestionsPreserveOptionsAndBuildClaudeAnswers() throws {
    let request = try JSONDecoder().decode(
        JSONValue.self,
        from: Data(
            """
            {
              "subtype": "can_use_tool",
              "tool_name": "AskUserQuestion",
              "input": {
                "questions": [
                  {
                    "header": "Approach",
                    "question": "Which implementation should I use?",
                    "options": [
                      {
                        "label": "Focused fix",
                        "description": "Change only the broken prompt."
                      },
                      {
                        "label": "Shared component",
                        "description": "Use one question UI for both providers."
                      },
                      {
                        "label": "Defer",
                        "description": "Leave the current behavior unchanged."
                      }
                    ],
                    "multiSelect": false
                  },
                  {
                    "header": "Verification",
                    "question": "Which checks should I run?",
                    "options": [
                      {
                        "label": "Build",
                        "description": "Compile the application."
                      },
                      {
                        "label": "Tests",
                        "description": "Run the complete test suite."
                      }
                    ],
                    "multiSelect": true
                  }
                ],
                "context": "keep-this-field"
              }
            }
            """.utf8
        )
    )
    let questionRequest = try #require(
        ClaudeUserQuestionRequest(request: request)
    )
    let entry = questionRequest.timelineEntry()

    #expect(entry.kind == .question)
    #expect(entry.approvalState == nil)
    #expect(entry.questionResolution == .pending)
    #expect(entry.questions?.count == 2)
    #expect(entry.questions?.first?.header == "Approach")
    #expect(entry.questions?.first?.options.count == 3)
    #expect(
        entry.questions?.first?.options[1].description
            == "Use one question UI for both providers."
    )
    #expect(entry.questions?.last?.multiSelect == true)

    let response = questionRequest.response(
        for: [
            QuestionSelection(
                questionID: "question-0",
                answers: ["Shared component"]
            ),
            QuestionSelection(
                questionID: "question-1",
                answers: ["Build", "Tests"]
            )
        ]
    )
    #expect(response["behavior"]?.stringValue == "allow")
    #expect(
        response["updatedInput"]?["questions"]
            == request["input"]?["questions"]
    )
    #expect(
        response["updatedInput"]?["context"]?.stringValue
            == "keep-this-field"
    )
    #expect(
        response["updatedInput"]?["answers"]?[
            "Which implementation should I use?"
        ]?.stringValue == "Shared component"
    )
    #expect(
        response["updatedInput"]?["answers"]?[
            "Which checks should I run?"
        ]?.stringValue == "Build, Tests"
    )
}

@Test
func structuredQuestionPersistenceAndCodexAnswersRoundTrip() throws {
    let questions = [
        StructuredQuestion(
            id: "scope",
            header: "Scope",
            prompt: "What should change?",
            options: [
                .init(label: "UI", description: "Update the visible card."),
                .init(label: "Runtime", description: "Update provider handling.")
            ],
            multiSelect: true
        )
    ]
    let resolution = QuestionResolution(
        state: .submitted,
        selections: [
            QuestionSelection(
                questionID: "scope",
                answers: ["UI", "Runtime"]
            )
        ]
    )
    let entry = TimelineEntry(
        kind: .question,
        title: "Codex has a question",
        text: "",
        questions: questions,
        questionResolution: resolution
    )

    let decoded = try JSONDecoder().decode(
        TimelineEntry.self,
        from: JSONEncoder().encode(entry)
    )
    #expect(decoded == entry)
    #expect(
        CodexQuestionResponse.result(
            questions: questions,
            selections: resolution.selections
        ) == .object([
            "answers": .object([
                "scope": .object([
                    "answers": .array([
                        .string("UI"),
                        .string("Runtime")
                    ])
                ])
            ])
        ])
    )

    let legacy = try JSONDecoder().decode(
        TimelineEntry.self,
        from: Data(
            """
            {
              "id": "BD1F67B4-F1B8-48EE-89B9-D68B3510A0A7",
              "kind": "question",
              "title": "Legacy question",
              "text": "Type an answer",
              "timestamp": 0
            }
            """.utf8
        )
    )
    #expect(legacy.questions == nil)
    #expect(legacy.questionResolution == nil)
}

@Test
func claudeStructuredQuestionResumesAfterSubmission() async throws {
    let toolInput: JSONValue = .object([
        "questions": .array([
            .object([
                "header": .string("Approach"),
                "question": .string("Which approach?"),
                "options": .array([
                    .object([
                        "label": .string("Focused"),
                        "description": .string("Keep the change narrow.")
                    ]),
                    .object([
                        "label": .string("Shared"),
                        "description": .string("Use the shared flow.")
                    ])
                ]),
                "multiSelect": .bool(false)
            ])
        ])
    ])
    let client = ApprovalStubClaudeClient(
        toolName: "AskUserQuestion",
        toolInput: toolInput,
        emitToolUseBlock: true
    )
    let runtime = testClaudeRuntime(client: client)
    let profile = claudeProfile(role: .builder, approvalMode: .ask)
    await launchClaude(runtime, profile: profile)

    let stream = await runtime.respond(
        to: "Ask me which approach to use",
        attachments: [],
        profile: profile
    )
    var questionEntry: TimelineEntry?
    var submitted = false
    var sawRawToolCard = false
    var finalStatus: AgentStatus?

    for await event in stream {
        switch event {
        case .entry(let entry)
            where entry.questionResolution?.state == .pending:
            questionEntry = entry

        case .status(.needsAnswer):
            let entry = try #require(questionEntry)
            let resolution = await runtime.resolveQuestion(
                entryID: entry.id,
                selections: [
                    QuestionSelection(
                        questionID: "question-0",
                        answers: ["Shared"]
                    )
                ],
                profile: profile
            )
            for await _ in resolution {}

        case .questionResolved(let entryID, let resolution):
            submitted = entryID == questionEntry?.id
                && resolution.state == .submitted
                && resolution.selections.first?.answers == ["Shared"]

        case .entry(let entry)
            where entry.kind == .command
                && entry.detail?.contains("Which approach?") == true:
            sawRawToolCard = true

        case .upsertEntry(let entry)
            where entry.kind == .command
                && entry.detail?.contains("Which approach?") == true:
            sawRawToolCard = true

        case .status(let status):
            finalStatus = status

        default:
            break
        }
    }

    let responses = await client.responses
    #expect(submitted)
    #expect(!sawRawToolCard)
    #expect(finalStatus == .completed)
    #expect(
        responses.first?["updatedInput"]?["questions"]
            == toolInput["questions"]
    )
    #expect(
        responses.first?["updatedInput"]?["answers"]?[
            "Which approach?"
        ]?.stringValue == "Shared"
    )
}

@Test
func cancelledClaudeQuestionCannotBeSubmitted() async throws {
    let client = ApprovalStubClaudeClient(
        toolName: "AskUserQuestion",
        toolInput: .object([
            "questions": .array([
                .object([
                    "question": .string("Continue?"),
                    "options": .array([
                        .object(["label": .string("Yes")]),
                        .object(["label": .string("No")])
                    ])
                ])
            ])
        ]),
        cancelRequests: true
    )
    let runtime = testClaudeRuntime(client: client)
    let profile = claudeProfile(role: .builder, approvalMode: .ask)
    await launchClaude(runtime, profile: profile)

    let stream = await runtime.respond(
        to: "Ask and cancel",
        attachments: [],
        profile: profile
    )
    var entryID: UUID?
    var cancelled = false
    for await event in stream {
        switch event {
        case .entry(let entry)
            where entry.questionResolution?.state == .pending:
            entryID = entry.id
        case .questionResolved(let resolvedID, let resolution):
            cancelled = resolvedID == entryID
                && resolution.state == .cancelled
        default:
            break
        }
    }

    let resolution = await runtime.resolveQuestion(
        entryID: try #require(entryID),
        selections: [
            QuestionSelection(
                questionID: "question-0",
                answers: ["Yes"]
            )
        ],
        profile: profile
    )
    var lateEvents: [AgentEvent] = []
    for await event in resolution {
        lateEvents.append(event)
    }

    #expect(cancelled)
    #expect(lateEvents.isEmpty)
    #expect(await client.responses.isEmpty)
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
func unmatchedClaudeCommandReachesTheApprovalCardFlow() async throws {
    let toolInput = JSONValue.object([
        "command": .string("uname -a"),
        "description": .string("Inspect the host")
    ])
    let client = ApprovalStubClaudeClient(
        toolInput: toolInput,
        permissionDenials: [
            .object([
                "tool_name": .string("Bash"),
                "tool_input": toolInput
            ])
        ]
    )
    let runtime = testClaudeRuntime(client: client)
    let profile = claudeProfile(role: .builder, approvalMode: .ask)
    await launchClaude(runtime, profile: profile)

    let stream = await runtime.respond(
        to: "Run an unmatched command",
        attachments: [],
        profile: profile
    )
    var approvalEntry: TimelineEntry?
    var sawNeedsApproval = false
    var sawApprovedResolution = false
    var sawBlockedQuestion = false
    var finalStatus: AgentStatus?

    for await event in stream {
        switch event {
        case .entry(let entry) where entry.kind == .approval:
            approvalEntry = entry

        case .entry(let entry) where entry.title == "Some actions were blocked":
            sawBlockedQuestion = true

        case .status(.needsApproval):
            sawNeedsApproval = true
            let entry = try #require(approvalEntry)
            for await _ in await runtime.resolveApproval(
                entryID: entry.id,
                approved: true,
                profile: profile
            ) {}

        case .approvalResolved(let entryID, .approved):
            sawApprovedResolution = entryID == approvalEntry?.id

        case .status(let status):
            finalStatus = status

        default:
            break
        }
    }
    await runtime.stop(profile: profile)

    let arguments = await client.invocationArguments
    let permissionModeIndex = try #require(
        arguments.firstIndex(of: "--permission-mode")
    )
    let inputFormatIndex = try #require(
        arguments.firstIndex(of: "--input-format")
    )
    let permissionPromptToolIndex = try #require(
        arguments.firstIndex(of: "--permission-prompt-tool")
    )

    #expect(approvalEntry?.text == "uname -a")
    #expect(approvalEntry?.approvalState == .pending)
    #expect(sawNeedsApproval)
    #expect(sawApprovedResolution)
    #expect(!sawBlockedQuestion)
    #expect(finalStatus == .completed)
    #expect(arguments[permissionModeIndex + 1] == "default")
    #expect(arguments[inputFormatIndex + 1] == "stream-json")
    #expect(arguments[permissionPromptToolIndex + 1] == "stdio")
    #expect(arguments.contains("Bash(swift build)"))
    #expect(arguments.contains("Bash(swift build *)"))
    #expect(arguments.contains("Bash(swift build:*)"))
    #expect(arguments.contains("Bash(xcrun swift test)"))
    #expect(arguments.contains("Bash(xcrun swift test *)"))
    #expect(arguments.contains("Bash(xcrun swift test:*)"))
    #expect(arguments.contains("Bash(tail -20)"))
    #expect(!arguments.contains("Bash(tail *)"))
}

@Test
func claudeAskModeIsCapturedWhenTheSessionStarts() async throws {
    let client = ApprovalStubClaudeClient()
    let runtime = testClaudeRuntime(client: client)
    var profile = BotProfile(
        name: "Claude Builder",
        provider: .claude,
        role: .builder,
        instructions: "Implement the change.",
        workingDirectory: FileManager.default.temporaryDirectory.path,
        approvalMode: .ask
    )
    await launchClaude(runtime, profile: profile)

    profile.approvalMode = .auto
    let events = await collectClaudeTurn(
        runtime,
        profile: profile,
        approveRequests: true
    )
    let entries = timelineEntries(in: events)
    let statuses = agentStatuses(in: events)
    let responses = await client.responses

    #expect(entries.contains(where: {
        $0.kind == .approval && $0.approvalState == .pending
    }))
    #expect(statuses.contains(.needsApproval))
    #expect(statuses.last == .completed)
    #expect(
        responses.first?["behavior"]?.stringValue == "allow"
    )
}

@Test
func claudeReviewerAutoModeApprovesInspectionWithoutPausingAndAddsAnAuditEntry() async throws {
    let client = ApprovalStubClaudeClient()
    let runtime = testClaudeRuntime(client: client)
    let profile = BotProfile(
        name: "Claude Reviewer",
        provider: .claude,
        role: .reviewer,
        instructions: "Review the change.",
        workingDirectory: FileManager.default.temporaryDirectory.path,
        approvalMode: .auto
    )
    await launchClaude(runtime, profile: profile)

    let events = await collectClaudeTurn(runtime, profile: profile)
    let entries = timelineEntries(in: events)
    let statuses = agentStatuses(in: events)
    let responses = await client.responses
    let auditEntry = entries.first(where: {
        $0.title == "Auto-approved Claude action"
    })

    #expect(!entries.contains(where: { $0.kind == .approval }))
    #expect(!statuses.contains(.needsApproval))
    #expect(statuses.last == .completed)
    #expect(auditEntry?.kind == .system)
    #expect(auditEntry?.text == "rg -n TODO Sources")
    #expect(
        responses.first?["behavior"]?.stringValue == "allow"
    )
}

@Test
func claudeAutoResponseFailuresFailTheTurnVisibly() async throws {
    let client = ApprovalStubClaudeClient(failResponses: true)
    let runtime = testClaudeRuntime(client: client)
    let profile = BotProfile(
        name: "Claude Builder",
        provider: .claude,
        role: .builder,
        instructions: "Implement the change.",
        workingDirectory: FileManager.default.temporaryDirectory.path,
        approvalMode: .auto
    )
    await launchClaude(runtime, profile: profile)

    let events = await collectClaudeTurn(runtime, profile: profile)
    let entries = timelineEntries(in: events)
    let statuses = agentStatuses(in: events)
    let failureEntry = entries.first(where: {
        $0.title == "Claude permission response failed"
    })

    #expect(failureEntry?.text == "Could not auto-approve Claude's action")
    #expect(
        failureEntry?.detail?.contains("simulated response failure") == true
    )
    #expect(statuses.last == .failed)
}

@Test
func claudeAutoModeBlocksDestructiveCommands() async {
    for command in [
        "git push --force origin feature/example",
        "rm -rf .build/cache",
        "python3 -c 'import os; os.remove(\"Package.swift\")'"
    ] {
        let client = ApprovalStubClaudeClient(
            toolInput: .object([
                "command": .string(command)
            ])
        )
        let runtime = testClaudeRuntime(client: client)
        let profile = claudeProfile(role: .builder, approvalMode: .auto)
        await launchClaude(runtime, profile: profile)

        let events = await collectClaudeTurn(runtime, profile: profile)
        let entries = timelineEntries(in: events)
        let responses = await client.responses

        #expect(!entries.contains(where: { $0.kind == .approval }))
        #expect(
            entries.contains(where: {
                $0.title == "Claude action blocked"
                    && $0.detail?.isEmpty == false
            })
        )
        #expect(responses.first?["behavior"]?.stringValue == "deny")
    }
}

@Test
func claudeAutoModeBlocksFilesOutsideTheWorkspace() async {
    let client = ApprovalStubClaudeClient(
        toolName: "Edit",
        toolInput: .object([
            "file_path": .string("/etc/hosts")
        ])
    )
    let runtime = testClaudeRuntime(client: client)
    let profile = claudeProfile(role: .builder, approvalMode: .auto)
    await launchClaude(runtime, profile: profile)

    let events = await collectClaudeTurn(runtime, profile: profile)
    let entries = timelineEntries(in: events)
    let responses = await client.responses

    #expect(
        entries.contains(where: {
            $0.title == "Claude action blocked"
                && $0.detail?.contains("selected workspace") == true
        })
    )
    #expect(responses.first?["behavior"]?.stringValue == "deny")
}

@Test
func claudeAutoModeAsksForUnsupportedTools() async {
    let client = ApprovalStubClaudeClient(
        toolName: "mcp__github__delete_repository",
        toolInput: .object([
            "repository": .string("suttree/bl00p")
        ])
    )
    let runtime = testClaudeRuntime(client: client)
    let profile = claudeProfile(role: .publisher, approvalMode: .auto)
    await launchClaude(runtime, profile: profile)

    let events = await collectClaudeTurn(
        runtime,
        profile: profile,
        approveRequests: true
    )
    let entries = timelineEntries(in: events)
    let responses = await client.responses

    #expect(entries.contains(where: { $0.kind == .approval }))
    #expect(responses.first?["behavior"]?.stringValue == "allow")
}

@Test
func claudeReviewerWriteToolsRemainBlockedInEitherApprovalMode() async {
    for mode in ApprovalMode.allCases {
        for toolName in ["Edit", "Write", "NotebookEdit"] {
            let client = ApprovalStubClaudeClient(
                toolName: toolName,
                toolInput: .object([
                    "file_path": .string("Package.swift")
                ])
            )
            let runtime = testClaudeRuntime(client: client)
            let profile = claudeProfile(
                role: .reviewer,
                approvalMode: mode
            )
            await launchClaude(runtime, profile: profile)

            let events = await collectClaudeTurn(runtime, profile: profile)
            let entries = timelineEntries(in: events)
            let responses = await client.responses

            #expect(!entries.contains(where: { $0.kind == .approval }))
            #expect(
                entries.contains(where: {
                    $0.title == "Claude action blocked"
                        && $0.detail?.contains("file-edit tools") == true
                })
            )
            #expect(responses.first?["behavior"]?.stringValue == "deny")
        }
    }
}

@Test
func claudeLiveRoleChangeCannotInheritBuilderAutoApproval() async {
    let client = ApprovalStubClaudeClient(
        toolName: "Edit",
        toolInput: .object([
            "file_path": .string("Package.swift")
        ])
    )
    let runtime = testClaudeRuntime(client: client)
    var profile = claudeProfile(role: .builder, approvalMode: .auto)
    await launchClaude(runtime, profile: profile)

    profile.role = .reviewer
    let events = await collectClaudeTurn(runtime, profile: profile)
    let entries = timelineEntries(in: events)
    let responses = await client.responses

    #expect(!entries.contains(where: { $0.kind == .approval }))
    #expect(
        entries.contains(where: {
            $0.title == "Claude action blocked"
                && $0.detail?.contains("file-edit tools") == true
        })
    )
    #expect(responses.first?["behavior"]?.stringValue == "deny")
}

@Test
func claudeManagersCannotEscalateInEitherApprovalMode() async throws {
    for mode in [ApprovalMode.ask, .auto] {
        let client = ApprovalStubClaudeClient(
            toolName: "Edit",
            toolInput: .object([
                "file_path": .string("Package.swift")
            ])
        )
        let runtime = testClaudeRuntime(client: client)
        let profile = claudeProfile(role: .manager, approvalMode: mode)
        await launchClaude(runtime, profile: profile)

        let events = await collectClaudeTurn(runtime, profile: profile)
        let entries = timelineEntries(in: events)
        let responses = await client.responses
        let invocation = try ClaudeInvocation(
            sessionID: UUID().uuidString,
            resume: false,
            profile: profile,
            prompt: "Coordinate this change."
        )

        #expect(!entries.contains(where: { $0.kind == .approval }))
        #expect(
            entries.contains(where: {
                $0.title == "Claude action blocked"
                    && $0.detail?.contains("cannot edit files, commit, push, or publish") == true
            })
        )
        #expect(responses.first?["behavior"]?.stringValue == "deny")
        #expect(invocation.arguments.contains("--permission-prompt-tool"))
        #expect(!invocation.arguments.contains("bypassPermissions"))
        #expect(!invocation.arguments.contains("Edit"))
        #expect(!invocation.arguments.contains("Write"))
    }
}

@Test
func claudeReviewerCanInspectInAskModeButCannotEdit() throws {
    let workingDirectory = URL(fileURLWithPath: "/tmp/bl00p-reviewer")
    let inspection = try #require(
        ClaudeToolApprovalRequest(request: .object([
            "subtype": .string("can_use_tool"),
            "tool_name": .string("Bash"),
            "input": .object(["command": .string("wc -l")])
        ]))
    )
    let edit = try #require(
        ClaudeToolApprovalRequest(request: .object([
            "subtype": .string("can_use_tool"),
            "tool_name": .string("Edit"),
            "input": .object(["file_path": .string("README.md")])
        ]))
    )

    #expect(
        ClaudeToolApprovalPolicy.decision(
            for: inspection,
            mode: .ask,
            role: .reviewer,
            workingDirectory: workingDirectory,
            stagedAttachmentDirectory: nil
        ) == .ask
    )
    #expect(
        ClaudeToolApprovalPolicy.decision(
            for: inspection,
            mode: .auto,
            role: .reviewer,
            workingDirectory: workingDirectory,
            stagedAttachmentDirectory: nil
        ) == .allow
    )
    if case .deny = ClaudeToolApprovalPolicy.decision(
        for: edit,
        mode: .ask,
        role: .reviewer,
        workingDirectory: workingDirectory,
        stagedAttachmentDirectory: nil
    ) {
        // Expected: Reviewer write tools remain blocked in both modes.
    } else {
        Issue.record("Reviewer edit was not denied")
    }
}

@Test
func claudeReviewerBlocksWriteCapableShellCommandsInBothModes() throws {
    let workingDirectory = URL(fileURLWithPath: "/tmp/bl00p-reviewer")
    for mode in ApprovalMode.allCases {
        for command in [
            "git diff --output=review.txt",
            "git grep --open-files-in-pager=touch pattern",
            "cat README.md > review.txt",
            "unknown-writer README.md",
            "swift test",
            "npm run lint"
        ] {
            let request = try #require(
                ClaudeToolApprovalRequest(request: .object([
                    "subtype": .string("can_use_tool"),
                    "tool_name": .string("Bash"),
                    "input": .object(["command": .string(command)])
                ]))
            )
            if case .deny = ClaudeToolApprovalPolicy.decision(
                for: request,
                mode: mode,
                role: .reviewer,
                workingDirectory: workingDirectory,
                stagedAttachmentDirectory: nil
            ) {
                // Expected: Reviewer shell writes never reach an approval card.
            } else {
                Issue.record("\(command) was not denied in \(mode)")
            }
        }
    }
}

@Test
func claudeManagerCanRunTestsAndInspectionCommands() throws {
    let workingDirectory = URL(fileURLWithPath: "/tmp/bl00p-manager")
    for command in ["swift test", "pytest", "git status"] {
        let request = try #require(
            ClaudeToolApprovalRequest(request: .object([
                "subtype": .string("can_use_tool"),
                "tool_name": .string("Bash"),
                "input": .object(["command": .string(command)])
            ]))
        )
        #expect(
            ClaudeToolApprovalPolicy.decision(
                for: request,
                mode: .ask,
                role: .manager,
                workingDirectory: workingDirectory,
                stagedAttachmentDirectory: nil
            ) == .ask
        )
        #expect(
            ClaudeToolApprovalPolicy.decision(
                for: request,
                mode: .auto,
                role: .manager,
                workingDirectory: workingDirectory,
                stagedAttachmentDirectory: nil
            ) == .allow
        )
    }
}

@Test
func claudeManagerCannotEditFilesInEitherApprovalMode() throws {
    let workingDirectory = URL(fileURLWithPath: "/tmp/bl00p-manager")
    let edit = try #require(
        ClaudeToolApprovalRequest(request: .object([
            "subtype": .string("can_use_tool"),
            "tool_name": .string("Edit"),
            "input": .object(["file_path": .string("README.md")])
        ]))
    )
    for mode in ApprovalMode.allCases {
        if case .deny(let message) = ClaudeToolApprovalPolicy.decision(
            for: edit,
            mode: mode,
            role: .manager,
            workingDirectory: workingDirectory,
            stagedAttachmentDirectory: nil
        ) {
            #expect(message.contains("cannot edit files, commit, push, or publish"))
        } else {
            Issue.record("Manager edit was not denied in \(mode)")
        }
    }
}

@Test
func claudeManagerBlocksWriteCapableShellCommandsInBothModes() throws {
    let workingDirectory = URL(fileURLWithPath: "/tmp/bl00p-manager")
    for mode in ApprovalMode.allCases {
        for command in [
            "git diff --output=review.txt",
            "git commit -m done",
            "git push",
            "cat README.md > review.txt",
            "unknown-writer README.md",
            "cat /etc/passwd",
            "rm -rf build"
        ] {
            let request = try #require(
                ClaudeToolApprovalRequest(request: .object([
                    "subtype": .string("can_use_tool"),
                    "tool_name": .string("Bash"),
                    "input": .object(["command": .string(command)])
                ]))
            )
            if case .deny = ClaudeToolApprovalPolicy.decision(
                for: request,
                mode: mode,
                role: .manager,
                workingDirectory: workingDirectory,
                stagedAttachmentDirectory: nil
            ) {
                // Expected: Manager shell writes, redirects, and paths
                // outside the workspace never reach an approval card,
                // even in Ask mode.
            } else {
                Issue.record("\(command) was not denied in \(mode)")
            }
        }
    }
}

@Test
func claudeAutoApprovalRejectsExpandedOrFlagEmbeddedPaths() throws {
    let workingDirectory = URL(
        fileURLWithPath: "/tmp/bl00p-workspace",
        isDirectory: true
    )
    for command in [
        "cat $HOME/.ssh/id_rsa",
        "cat ${HOME}/.ssh/id_rsa",
        "grep --file=/etc/passwd .",
        "rg -f/etc/passwd ."
    ] {
        let request = try #require(
            ClaudeToolApprovalRequest(request: .object([
                "subtype": .string("can_use_tool"),
                "tool_name": .string("Bash"),
                "input": .object(["command": .string(command)])
            ]))
        )
        if case .deny = ClaudeToolApprovalPolicy.decision(
            for: request,
            mode: .auto,
            role: .builder,
            workingDirectory: workingDirectory,
            stagedAttachmentDirectory: nil
        ) {
            // Expected: shell expansion and paths embedded in flags are denied.
        } else {
            Issue.record("Auto-approval allowed \(command)")
        }
    }
}

@Test
func claudeAutoApprovalAsksForUnclassifiedActionsAndMatchesXcodebuildSubcommands() throws {
    let workingDirectory = URL(
        fileURLWithPath: "/tmp/bl00p-workspace",
        isDirectory: true
    )
    let unknown = try #require(
        ClaudeToolApprovalRequest(request: .object([
            "subtype": .string("can_use_tool"),
            "tool_name": .string("mcp__example__inspect"),
            "input": .object([
                "path": .string("/v1/issues/123"),
                "resource": .string("repository")
            ])
        ]))
    )
    let archive = try #require(
        ClaudeToolApprovalRequest(request: .object([
            "subtype": .string("can_use_tool"),
            "tool_name": .string("Bash"),
            "input": .object(["command": .string("xcodebuild archive")])
        ]))
    )
    let test = try #require(
        ClaudeToolApprovalRequest(request: .object([
            "subtype": .string("can_use_tool"),
            "tool_name": .string("Bash"),
            "input": .object(["command": .string("xcodebuild test")])
        ]))
    )

    #expect(
        ClaudeToolApprovalPolicy.decision(
            for: unknown,
            mode: .auto,
            role: .publisher,
            workingDirectory: workingDirectory,
            stagedAttachmentDirectory: nil
        ) == .ask
    )
    if case .deny = ClaudeToolApprovalPolicy.decision(
        for: archive,
        mode: .auto,
        role: .publisher,
        workingDirectory: workingDirectory,
        stagedAttachmentDirectory: nil
    ) {
        // Expected: only the first xcodebuild subcommand is classified.
    } else {
        Issue.record("xcodebuild archive was auto-approved")
    }
    #expect(
        ClaudeToolApprovalPolicy.decision(
            for: test,
            mode: .auto,
            role: .publisher,
            workingDirectory: workingDirectory,
            stagedAttachmentDirectory: nil
        ) == .allow
    )
}

@Test
func claudePreapprovedCommandsAndRuntimeClassificationStayAligned() throws {
    let builderTools = ClaudeToolApprovalPolicy.allowedTools(for: .builder)
    let reviewerTools = ClaudeToolApprovalPolicy.allowedTools(for: .reviewer)
    #expect(!reviewerTools.contains(where: { $0.hasPrefix("Bash(") }))
    #expect(builderTools.contains("AskUserQuestion"))
    #expect(reviewerTools.contains("AskUserQuestion"))
    #expect(builderTools.contains("Bash(env swift --version:*)"))
    #expect(builderTools.contains("Bash(xcode-select -p:*)"))
    #expect(builderTools.contains("Bash(pnpm typecheck:*)"))
    #expect(builderTools.contains("Bash(yarn typecheck:*)"))

    let workingDirectory = URL(fileURLWithPath: "/tmp/bl00p-workspace")
    for command in [
        "env swift --version",
        "xcode-select -p",
        "pnpm typecheck",
        "yarn typecheck"
    ] {
        let request = try #require(
            ClaudeToolApprovalRequest(request: .object([
                "subtype": .string("can_use_tool"),
                "tool_name": .string("Bash"),
                "input": .object(["command": .string(command)])
            ]))
        )
        #expect(
            ClaudeToolApprovalPolicy.decision(
                for: request,
                mode: .auto,
                role: .builder,
                workingDirectory: workingDirectory,
                stagedAttachmentDirectory: nil
            ) == .allow
        )
    }
}

@Test
func claudeDeduplicatesRepeatedControlRequestIDs() async {
    let client = ApprovalStubClaudeClient(
        requestIDs: ["permission-1", "permission-1"]
    )
    let runtime = testClaudeRuntime(client: client)
    let profile = claudeProfile(role: .builder, approvalMode: .auto)
    await launchClaude(runtime, profile: profile)

    let events = await collectClaudeTurn(runtime, profile: profile)
    let entries = timelineEntries(in: events)
    let responses = await client.responses

    #expect(responses.count == 1)
    #expect(
        entries.filter { $0.title == "Auto-approved Claude action" }.count == 1
    )
}

@Test
func claudeFreshSessionRecoveryCanReuseAControlRequestID() async {
    let staleClient = ApprovalStubClaudeClient(resultMode: .missingSession)
    let freshClient = ApprovalStubClaudeClient()
    let runtime = testClaudeRuntime(clients: [staleClient, freshClient])
    let profile = claudeProfile(role: .builder, approvalMode: .auto)
    await launchClaude(
        runtime,
        profile: profile,
        resumeThreadID: UUID().uuidString
    )

    let events = await collectClaudeTurn(runtime, profile: profile)
    let entries = timelineEntries(in: events)
    let statuses = agentStatuses(in: events)
    let staleResponseCount = await staleClient.responses.count
    let freshResponseCount = await freshClient.responses.count

    #expect(staleResponseCount == 1)
    #expect(freshResponseCount == 1)
    #expect(
        entries.contains(where: { $0.text == "Claude session recovered" })
    )
    #expect(statuses.last == .completed)
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
        ) == .blocked
    )
    #expect(
        ClaudePermissionDenials.readableDetail(for: [denial])
            == "• Run tests using Xcode\n  xcrun swift test"
    )
    #expect(
        ClaudeTurnOutcome.permissionDenialsRequiringAttention(
            [denial],
            role: .reviewer,
            responses: [
                """
                The implementation needs a regression test.

                BL00P_REVIEW_DISPOSITION: changesRequested
                """
            ]
        ).isEmpty
    )
    #expect(
        ClaudeTurnOutcome.permissionDenialsRequiringAttention(
            [denial],
            role: .builder,
            responses: [
                "BL00P_REVIEW_DISPOSITION: changesRequested"
            ]
        ) == [denial]
    )
}

@Test
func permissionDenialsAreDeduplicatedByUnderlyingAction() throws {
    let denials = try JSONDecoder().decode(
        [JSONValue].self,
        from: Data(
            """
            [
              {
                "tool_name": "Bash",
                "tool_input": {
                  "description": "Build the package",
                  "command": "swift build 2>&1 | tail -20"
                }
              },
              {
                "tool_name": "Bash",
                "tool_input": {
                  "description": "Build the package",
                  "command": "swift build"
                }
              }
            ]
            """.utf8
        )
    )

    let unresolved = ClaudePermissionDenials.unresolved(
        denials,
        resolvedActionKeys: []
    )

    #expect(unresolved.count == 1)
    #expect(
        ClaudePermissionDenials.readableDetail(for: unresolved)
            == "• Build the package\n  swift build"
    )
}

@Test
func successfulRetryClearsStalePermissionDenials() throws {
    let denial = try JSONDecoder().decode(
        JSONValue.self,
        from: Data(
            """
            {
              "tool_name": "Bash",
              "tool_input": {
                "description": "Build the package",
                "command": "swift build 2>&1 | tail -20"
              }
            }
            """.utf8
        )
    )
    let successfulAction = ClaudePermissionDenials.actionKey(
        toolName: "Bash",
        toolInput: .object([
            "command": .string("xcrun swift build")
        ])
    )
    let unresolved = ClaudePermissionDenials.unresolved(
        [denial],
        resolvedActionKeys: [successfulAction]
    )

    #expect(unresolved.isEmpty)
    #expect(
        ClaudeTurnOutcome.status(
            failed: false,
            permissionDenials: unresolved
        ) == .completed
    )
}

@Test
func successfulCommandDoesNotMaskBlockedPipelineOrRedirection() throws {
    let blockedPipeline = JSONValue.object([
        "tool_name": .string("Bash"),
        "tool_input": .object([
            "command": .string("swift build | upload-artifacts")
        ])
    ])
    let blockedRedirection = JSONValue.object([
        "tool_name": .string("Bash"),
        "tool_input": .object([
            "command": .string("swift build > /protected/build.log")
        ])
    ])
    let successfulBuild = ClaudePermissionDenials.actionKey(
        toolName: "Bash",
        toolInput: .object([
            "command": .string("swift build")
        ])
    )

    let unresolved = ClaudePermissionDenials.unresolved(
        [blockedPipeline, blockedRedirection],
        resolvedActionKeys: [successfulBuild]
    )

    #expect(unresolved == [blockedPipeline, blockedRedirection])
}

@Test
func permissionActionKeysNormalizeShellWhitespaceAndXcrun() {
    let direct = ClaudePermissionDenials.actionKey(
        toolName: "Bash",
        toolInput: .object([
            "command": .string("swift build")
        ])
    )
    let wrapped = ClaudePermissionDenials.actionKey(
        toolName: "Bash",
        toolInput: .object([
            "command": .string("  xcrun  swift \n build  ")
        ])
    )
    let quotedWhitespace = ClaudePermissionDenials.actionKey(
        toolName: "Bash",
        toolInput: .object([
            "command": .string(#"printf 'two  spaces'"#)
        ])
    )

    #expect(wrapped == direct)
    #expect(quotedWhitespace == #"Bash:printf 'two  spaces'"#)
}

@Test
func quotedShellOperatorsDoNotMergeDistinctPermissionActions() {
    let quotedAction = ClaudePermissionDenials.actionKey(
        toolName: "Bash",
        toolInput: .object([
            "command": .string(#"printf 'build|result>value'"#)
        ])
    )
    let escapedAction = ClaudePermissionDenials.actionKey(
        toolName: "Bash",
        toolInput: .object([
            "command": .string(#"printf build\|result\>value"#)
        ])
    )

    #expect(quotedAction == #"Bash:printf 'build|result>value'"#)
    #expect(escapedAction == #"Bash:printf build\|result\>value"#)
    #expect(quotedAction != "Bash:printf 'build")
}

@Test
func explicitPermissionDenialRemainsUnresolvedWithoutASuccessfulRetry() throws {
    let denial = try JSONDecoder().decode(
        JSONValue.self,
        from: Data(
            """
            {
              "tool_name": "Bash",
              "tool_input": {
                "description": "Publish the branch",
                "command": "git push origin feature/example"
              }
            }
            """.utf8
        )
    )
    let unrelatedSuccess = ClaudePermissionDenials.actionKey(
        toolName: "Bash",
        toolInput: .object([
            "command": .string("git status")
        ])
    )
    let unresolved = ClaudePermissionDenials.unresolved(
        [denial],
        resolvedActionKeys: [unrelatedSuccess]
    )

    #expect(unresolved == [denial])
    #expect(
        ClaudeTurnOutcome.status(
            failed: false,
            permissionDenials: unresolved
        ) == .blocked
    )
}

@MainActor
@Test
func activeSessionsRestoreAsStopped() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-restore-\(UUID().uuidString)", isDirectory: true)
    let profile = BotProfile.defaults[1]
    let store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    try store.saveFixture(
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
    try store.saveFixture(
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
    try store.saveFixture(
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
    try store.saveFixture(
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
    try store.saveFixture(
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
func interruptedLegacyPermissionBoundaryRestoresAsStopped() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-interrupted-permission-\(UUID().uuidString)",
            isDirectory: true
        )
    defer { try? FileManager.default.removeItem(at: directory) }

    let profile = BotProfile.defaults[0]
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    store.save(
        PersistedAppState(
            profiles: [profile],
            sessions: [
                profile.id: AgentSessionState(
                    status: .working,
                    entries: [
                        .init(
                            kind: .system,
                            text: "Claude stopped at a permission boundary"
                        )
                    ],
                    sessionID: "interrupted-permission-session"
                )
            ],
            selectedBotID: profile.id
        )
    )

    let model = AppModel(runtime: DemoAgentRuntime(), store: store)
    let restored = model.session(for: profile.id)

    #expect(restored.status == .stopped)
    #expect(restored.entries.last?.title == "Some actions were blocked")
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
    try store.saveFixture(
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
func renamingABotTrimsAndPersistsTheName() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-rename-\(UUID().uuidString)", isDirectory: true)
    let store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    let model = AppModel(runtime: DemoAgentRuntime(), store: store)
    let profileID = try #require(model.profiles.first?.id)

    model.rename(profileID, to: "  Release notes  ")
    await model.flushPersistence()

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
    let profileID = try #require(model.profiles.dropFirst().first?.id)
    #expect(model.setRepositoryPath("/tmp", for: profileID))

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
    var profile = BotProfile.defaults[1]
    profile.workingDirectory = "/tmp"
    let store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    try store.saveFixture(
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
    var profile = BotProfile.defaults[1]
    profile.workingDirectory = "/tmp"
    let store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    try store.saveFixture(
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
    let profileID = try #require(model.profiles.dropFirst().first?.id)
    #expect(model.setRepositoryPath("/tmp", for: profileID))

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
    var profile = BotProfile.defaults[1]
    profile.workingDirectory = "/tmp"
    let earlierEntry = TimelineEntry(kind: .user, text: "Earlier message")
    let store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    try store.saveFixture(
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
    let profileID = try #require(model.profiles.dropFirst().first?.id)
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
    let profileID = try #require(model.profiles.dropFirst().first?.id)
    #expect(model.setRepositoryPath("/tmp", for: profileID))

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
    let profileID = try #require(model.profiles.dropFirst().first?.id)
    #expect(model.setRepositoryPath("/tmp", for: profileID))

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

private actor ManualPersistenceScheduler: PersistenceScheduling {
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var waiterCount: Int {
        waiters.count
    }

    func sleep(for delay: Duration) async {
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func resumeAll() {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor CountingStateWriter: PersistedStateWriting {
    private let delay: Duration?
    private(set) var states: [PersistedAppState] = []
    private(set) var startedWriteCount = 0

    init(delay: Duration? = nil) {
        self.delay = delay
    }

    var writeCount: Int {
        states.count
    }

    var lastState: PersistedAppState? {
        states.last
    }

    func write(_ state: PersistedAppState) async {
        startedWriteCount += 1
        if let delay {
            try? await Task.sleep(for: delay)
        }
        states.append(state)
    }
}

private actor BlockingStateWriter: PersistedStateWriting {
    private var isReleased = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var states: [PersistedAppState] = []
    private(set) var startedWriteCount = 0

    var writeCount: Int {
        states.count
    }

    func write(_ state: PersistedAppState) async {
        startedWriteCount += 1
        if !isReleased {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
        states.append(state)
    }

    func release() {
        isReleased = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private final class LockedPreflightProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var executableProbes = 0
    private var authenticationProbes = 0

    var executableProbeCount: Int {
        lock.withLock { executableProbes }
    }

    var authenticationProbeCount: Int {
        lock.withLock { authenticationProbes }
    }

    func recordExecutableProbe() {
        lock.withLock {
            executableProbes += 1
        }
    }

    func recordAuthenticationProbe() {
        lock.withLock {
            authenticationProbes += 1
        }
    }
}

private func testClaudeRuntime(
    client: ApprovalStubClaudeClient
) -> ClaudeRuntime {
    testClaudeRuntime(clients: [client])
}

private func testClaudeRuntime(
    clients: [ApprovalStubClaudeClient]
) -> ClaudeRuntime {
    let queue = ClaudeClientQueue(clients)
    return ClaudeRuntime(
        locator: ClaudeExecutableLocator(
            candidateURLs: [URL(fileURLWithPath: "/usr/bin/true")]
        ),
        authenticationStatus: { _ in .loggedIn },
        clientFactory: { _ in queue.next() }
    )
}

private func claudeProfile(
    role: AgentRole,
    approvalMode: ApprovalMode
) -> BotProfile {
    BotProfile(
        name: "Claude \(role.displayName)",
        provider: .claude,
        role: role,
        instructions: "Stay within the assigned role.",
        workingDirectory: FileManager.default.temporaryDirectory.path,
        approvalMode: approvalMode
    )
}

private func launchClaude(
    _ runtime: ClaudeRuntime,
    profile: BotProfile,
    resumeThreadID: String? = nil
) async {
    let stream = await runtime.start(
        profile: profile,
        resumeThreadID: resumeThreadID
    )
    for await _ in stream {}
}

private func collectClaudeTurn(
    _ runtime: ClaudeRuntime,
    profile: BotProfile,
    approveRequests: Bool = false
) async -> [AgentEvent] {
    let stream = await runtime.respond(
        to: "Publish the branch",
        attachments: [],
        profile: profile
    )
    var events: [AgentEvent] = []

    for await event in stream {
        events.append(event)
        if approveRequests,
           case .entry(let entry) = event,
           entry.kind == .approval {
            let resolution = await runtime.resolveApproval(
                entryID: entry.id,
                approved: true,
                profile: profile
            )
            for await resolutionEvent in resolution {
                events.append(resolutionEvent)
            }
        }
    }
    return events
}

private func timelineEntries(in events: [AgentEvent]) -> [TimelineEntry] {
    events.compactMap { event in
        switch event {
        case .entry(let entry), .upsertEntry(let entry):
            entry
        default:
            nil
        }
    }
}

private func agentStatuses(in events: [AgentEvent]) -> [AgentStatus] {
    events.compactMap { event in
        guard case .status(let status) = event else { return nil }
        return status
    }
}

private enum ApprovalStubError: LocalizedError {
    case responseFailed

    var errorDescription: String? {
        "simulated response failure"
    }
}

private enum ApprovalStubResultMode {
    case success
    case missingSession
}

private final class ClaudeClientQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var clients: [ApprovalStubClaudeClient]

    init(_ clients: [ApprovalStubClaudeClient]) {
        self.clients = clients
    }

    func next() -> any ClaudeClient {
        lock.withLock {
            precondition(!clients.isEmpty, "Missing stub Claude client")
            return clients.removeFirst()
        }
    }
}

private actor FiveHundredEventRuntime: AgentRuntime {
    func start(
        profile: BotProfile,
        resumeThreadID: String?
    ) async -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            continuation.yield(.sessionID("synthetic-500"))
            continuation.yield(.status(.needsAnswer))
            continuation.finish()
        }
    }

    func respond(
        to message: String,
        attachments: [ImageAttachment],
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            continuation.yield(.status(.working))
            for index in 0..<500 {
                continuation.yield(
                    .entry(
                        .init(
                            kind: .assistant,
                            text: "Synthetic event \(index)"
                        )
                    )
                )
            }
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

private extension AppStateStore {
    func saveFixture(_ state: PersistedAppState) throws {
        let fileURL = try #require(fileURL)
        let data = try JSONEncoder.compactState.encode(state)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }
}

private actor ApprovalStubClaudeClient: ClaudeClient {
    nonisolated let messages: AsyncStream<JSONValue>

    private let messageContinuation: AsyncStream<JSONValue>.Continuation
    private let toolName: String
    private let toolInput: JSONValue
    private let requestIDs: [String]
    private let failResponses: Bool
    private let resultMode: ApprovalStubResultMode
    private let cancelRequests: Bool
    private let emitToolUseBlock: Bool
    private let permissionDenials: [JSONValue]
    private(set) var invocationArguments: [String] = []
    private(set) var responses: [JSONValue] = []

    init(
        toolName: String = "Bash",
        toolInput: JSONValue = .object([
            "command": .string("rg -n TODO Sources")
        ]),
        requestIDs: [String] = ["permission-1"],
        failResponses: Bool = false,
        resultMode: ApprovalStubResultMode = .success,
        cancelRequests: Bool = false,
        emitToolUseBlock: Bool = false,
        permissionDenials: [JSONValue] = []
    ) {
        let pair = AsyncStream.makeStream(of: JSONValue.self)
        messages = pair.stream
        messageContinuation = pair.continuation
        self.toolName = toolName
        self.toolInput = toolInput
        self.requestIDs = requestIDs
        self.failResponses = failResponses
        self.resultMode = resultMode
        self.cancelRequests = cancelRequests
        self.emitToolUseBlock = emitToolUseBlock
        self.permissionDenials = permissionDenials
    }

    func connect(arguments: [String], workingDirectory: URL) async throws {
        invocationArguments = arguments
    }

    func send(_ message: JSONValue) throws {
        if emitToolUseBlock {
            messageContinuation.yield(
                .object([
                    "type": .string("assistant"),
                    "message": .object([
                        "content": .array([
                            .object([
                                "type": .string("tool_use"),
                                "id": .string("toolu_question"),
                                "name": .string(toolName),
                                "input": toolInput
                            ])
                        ])
                    ])
                ])
            )
        }
        for requestID in requestIDs {
            messageContinuation.yield(
                .object([
                    "type": .string("control_request"),
                    "request_id": .string(requestID),
                    "request": .object([
                        "subtype": .string("can_use_tool"),
                        "tool_name": .string(toolName),
                        "input": toolInput,
                        "tool_use_id": .string("toolu_1")
                    ])
                ])
            )
            if cancelRequests {
                messageContinuation.yield(
                    .object([
                        "type": .string("control_cancel_request"),
                        "request_id": .string(requestID)
                    ])
                )
                messageContinuation.yield(
                    .object([
                        "type": .string("result"),
                        "is_error": .bool(false),
                        "result": .string("Question cancelled"),
                        "permission_denials": .array([])
                    ])
                )
            }
        }
    }

    func finishInput() {
        messageContinuation.finish()
    }

    func respond(to requestID: String, result: JSONValue) throws {
        guard !failResponses else {
            throw ApprovalStubError.responseFailed
        }
        responses.append(result)
        switch resultMode {
        case .success:
            messageContinuation.yield(
                .object([
                    "type": .string("result"),
                    "is_error": .bool(false),
                    "result": result["behavior"] ?? .string("completed"),
                    "permission_denials": .array(permissionDenials)
                ])
            )
        case .missingSession:
            messageContinuation.yield(
                .object([
                    "type": .string("result"),
                    "is_error": .bool(true),
                    "errors": .array([
                        .string("No conversation found with session ID: stale")
                    ]),
                    "permission_denials": .array([])
                ])
            )
        }
    }

    func respondError(to requestID: String, message: String) throws {
        throw ClaudeCLIError.control(message)
    }

    func stop() {
        messageContinuation.finish()
    }
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
    var packages: [GitHandoffPackage]
    let preparedOwnership: GitWorktreeOwnership?

    init(
        package: GitHandoffPackage,
        preparedOwnership: GitWorktreeOwnership? = nil
    ) {
        packages = [package]
        self.preparedOwnership = preparedOwnership
    }

    init(
        packages: [GitHandoffPackage],
        preparedOwnership: GitWorktreeOwnership? = nil
    ) {
        self.packages = packages
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
        try #require(!packages.isEmpty)
        return packages.removeFirst()
    }
}

private actor RepositoryRecordingWorktreeManager: GitWorktreeManaging {
    private(set) var repositories: [String] = []

    func prepareWorktree(
        for profile: BotProfile,
        startingPoint: String?,
        handoffID: UUID?
    ) async throws -> GitWorktreeOwnership {
        repositories.append(profile.workingDirectory)
        return GitWorktreeOwnership(
            ownerProfileID: profile.id,
            repositoryPath: profile.workingDirectory,
            worktreePath: "\(profile.workingDirectory)-worktree",
            branch: "bl00p/\(repositories.count)",
            baseRevision: "abc123"
        )
    }

    func makeHandoff(
        from profile: BotProfile,
        session: AgentSessionState
    ) async throws -> GitHandoffPackage {
        throw GitWorktreeError.commandFailed("No handoff expected.")
    }
}

private actor ReuseRecordingWorktreeManager: GitWorktreeManaging {
    let package: GitHandoffPackage
    let ownership: GitWorktreeOwnership
    private(set) var receivedWorktree: GitWorktreeOwnership?
    private(set) var receivedWorkingDirectory: String?

    init(package: GitHandoffPackage, ownership: GitWorktreeOwnership) {
        self.package = package
        self.ownership = ownership
    }

    func prepareWorktree(
        for profile: BotProfile,
        startingPoint: String?,
        handoffID: UUID?
    ) async throws -> GitWorktreeOwnership {
        receivedWorktree = profile.worktree
        receivedWorkingDirectory = profile.workingDirectory
        return ownership
    }

    func makeHandoff(
        from profile: BotProfile,
        session: AgentSessionState
    ) async throws -> GitHandoffPackage {
        package
    }
}

private actor FailingCleanupWorktreeManager: GitWorktreeManaging {
    let ownership: GitWorktreeOwnership

    init(ownership: GitWorktreeOwnership) {
        self.ownership = ownership
    }

    func prepareWorktree(
        for profile: BotProfile,
        startingPoint: String?,
        handoffID: UUID?
    ) async throws -> GitWorktreeOwnership {
        ownership
    }

    func makeHandoff(
        from profile: BotProfile,
        session: AgentSessionState
    ) async throws -> GitHandoffPackage {
        throw GitWorktreeError.commandFailed("No handoff expected.")
    }

    func worktreeIsDirty(_ ownership: GitWorktreeOwnership) async throws -> Bool {
        false
    }

    func removeWorktree(
        _ ownership: GitWorktreeOwnership,
        force: Bool
    ) async throws {
        throw GitWorktreeError.commandFailed("Simulated cleanup failure.")
    }
}

private actor UnremovableWorktreeManager: GitWorktreeManaging {
    let ownership: GitWorktreeOwnership
    private(set) var removeCount = 0

    init(ownership: GitWorktreeOwnership) {
        self.ownership = ownership
    }

    func prepareWorktree(
        for profile: BotProfile,
        startingPoint: String?,
        handoffID: UUID?
    ) async throws -> GitWorktreeOwnership {
        ownership
    }

    func makeHandoff(
        from profile: BotProfile,
        session: AgentSessionState
    ) async throws -> GitHandoffPackage {
        throw GitWorktreeError.commandFailed("No handoff expected.")
    }

    func worktreeIsDirty(_ ownership: GitWorktreeOwnership) async throws -> Bool {
        throw GitWorktreeError.conflictingWorktree(
            "The worktree is on a different branch."
        )
    }

    func removeWorktree(
        _ ownership: GitWorktreeOwnership,
        force: Bool
    ) async throws {
        removeCount += 1
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

private func managedWorkflowFixture() -> (
    manager: BotProfile,
    builder: BotProfile,
    reviewer: BotProfile,
    publisher: BotProfile,
    team: ManagerTeamConfiguration,
    profiles: [BotProfile]
) {
    let builder = BotProfile(
        name: "Builder",
        provider: .claude,
        role: .builder,
        instructions: "Implement.",
        workingDirectory: "/tmp/project"
    )
    let reviewer = BotProfile(
        name: "Reviewer",
        provider: .codex,
        role: .reviewer,
        instructions: "Review.",
        workingDirectory: "/tmp/project"
    )
    let publisher = BotProfile(
        name: "Documenter",
        provider: .claude,
        role: .publisher,
        instructions: "Document.",
        workingDirectory: "/tmp/project"
    )
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
        workingDirectory: "/tmp/project",
        managerTeam: team
    )
    return (
        manager,
        builder,
        reviewer,
        publisher,
        team,
        [manager, builder, reviewer, publisher]
    )
}

private actor RecoveredApprovalRuntime: AgentRuntime {
    private(set) var builderDispatchCount = 0

    func start(
        profile: BotProfile,
        resumeThreadID: String?
    ) async -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            continuation.yield(
                .sessionID(
                    resumeThreadID
                        ?? "recovered-\(profile.id.uuidString)"
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
        if profile.role == .builder {
            builderDispatchCount += 1
        }
        return AsyncStream { continuation in
            continuation.yield(.status(.working))
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
private struct ManagedWorkflowHarness {
    let directory: URL
    let managerID: UUID
    let ownership: GitWorktreeOwnership
    let runtime: OrchestrationRecordingRuntime
    let model: AppModel
}

@MainActor
private func makeManagedWorkflowHarness(
    reviewerResponses: [String] = [],
    reviewerResponseBlocks: [[String]]? = nil
) throws -> ManagedWorkflowHarness {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "bl00p-managed-fixture-\(UUID().uuidString)",
            isDirectory: true
        )
    let builderID = UUID()
    let reviewerID = UUID()
    let publisherID = UUID()
    let managerID = UUID()
    let ownership = GitWorktreeOwnership(
        ownerProfileID: builderID,
        repositoryPath: "/tmp/project",
        worktreePath: "/tmp/.bl00p-worktrees/project-builder",
        branch: "bl00p/managed-fixture",
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
        taskContext: "Speed up orchestration",
        testStatus: .passed,
        testSummary: "`swift test` — passed",
        workingTreeSummary: "Clean"
    )
    var firstRevisionPackage = package
    firstRevisionPackage.id = UUID()
    firstRevisionPackage.headRevision = "789abc"
    firstRevisionPackage.testEvidenceAt = .distantFuture
    var secondRevisionPackage = firstRevisionPackage
    secondRevisionPackage.id = UUID()
    secondRevisionPackage.headRevision = "fedcba"
    let team = ManagerTeamConfiguration(
        builderProfileID: builderID,
        reviewerProfileID: reviewerID,
        publisherProfileID: publisherID
    )
    let profiles = [
        BotProfile(
            id: managerID,
            name: "Manager",
            provider: .codex,
            role: .manager,
            instructions: "Coordinate.",
            workingDirectory: "/tmp/project",
            managerTeam: team
        ),
        BotProfile(
            id: builderID,
            name: "Builder",
            provider: .claude,
            role: .builder,
            instructions: "Build.",
            workingDirectory: "/tmp/project"
        ),
        BotProfile(
            id: reviewerID,
            name: "Reviewer",
            provider: .codex,
            role: .reviewer,
            instructions: "Review.",
            workingDirectory: "/tmp/project"
        ),
        BotProfile(
            id: publisherID,
            name: "Publisher",
            provider: .claude,
            role: .publisher,
            instructions: "Publish.",
            workingDirectory: "/tmp/project"
        )
    ]
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    try store.saveFixture(
        PersistedAppState(
            profiles: profiles,
            sessions: Dictionary(
                uniqueKeysWithValues: profiles.map {
                    ($0.id, AgentSessionState())
                }
            ),
            selectedBotID: managerID
        )
    )
    let runtime: OrchestrationRecordingRuntime
    if let reviewerResponseBlocks {
        runtime = OrchestrationRecordingRuntime(
            reviewerResponseBlocks: reviewerResponseBlocks
        )
    } else {
        runtime = OrchestrationRecordingRuntime(
            reviewerResponses: reviewerResponses
        )
    }
    let model = AppModel(
        runtime: runtime,
        worktrees: StubWorktreeManager(
            packages: [
                package,
                firstRevisionPackage,
                secondRevisionPackage
            ],
            preparedOwnership: ownership
        ),
        store: store
    )
    return ManagedWorkflowHarness(
        directory: directory,
        managerID: managerID,
        ownership: ownership,
        runtime: runtime,
        model: model
    )
}

@MainActor
private func runManagedWorkflow(
    _ harness: ManagedWorkflowHarness
) async throws {
    harness.model.send("Speed up orchestration", to: harness.managerID)
    for _ in 0..<100
        where harness.model.session(for: harness.managerID).status
            != .needsApproval {
        try await Task.sleep(for: .milliseconds(10))
    }
    let approval = try #require(
        harness.model.session(for: harness.managerID).entries.last(where: {
            $0.kind == .approval && $0.approvalState == .pending
        })
    )
    harness.model.resolveApproval(
        approval.id,
        approved: true,
        for: harness.managerID
    )
    for _ in 0..<200
        where harness.model.workflow(for: harness.managerID)?.stage
            != .completed {
        try await Task.sleep(for: .milliseconds(10))
    }
}

private let orchestrationImplementationPlan = """
## Implementation plan

1. Persist the approved plan unchanged.
2. Cover the [Builder handoff](https://example.com/builder-handoff).

Verification:
- Run the Swift test suite.
"""

private func taggedField(_ name: String, in message: String) -> String? {
    let opening = "<\(name)>\n"
    let closing = "\n</\(name)>"
    guard let openingRange = message.range(of: opening),
          let closingRange = message.range(
              of: closing,
              range: openingRange.upperBound..<message.endIndex
          ) else {
        return nil
    }
    return String(message[openingRange.upperBound..<closingRange.lowerBound])
}

private actor OrchestrationRecordingRuntime: AgentRuntime {
    struct Call: Sendable {
        let role: AgentRole
        let message: String
        let workingDirectory: String
    }

    private(set) var calls: [Call] = []
    private(set) var approvalResolutionCount = 0
    private(set) var assistantEntryIDs: [UUID] = []
    private var roleResponseCounts: [AgentRole: Int] = [:]
    private let reviewerResponses: [[String]]
    private let managerPlanningResponses: [String]

    init(
        reviewerResponses: [String] = [
            """
            Review finding: add a regression test.
            BL00P_REVIEW_DISPOSITION: changesRequested
            """,
            """
            Review clean. Ready to publish.
            BL00P_REVIEW_DISPOSITION: clean
            """
        ],
        managerPlanningResponses: [String] = [
            "Implement the feature with persistence and tests.",
            "Revised plan: implement the feature with restoration coverage."
        ]
    ) {
        self.reviewerResponses = reviewerResponses
            .map { [$0] }
        self.managerPlanningResponses = managerPlanningResponses
    }

    init(
        reviewerResponseBlocks: [[String]],
        managerPlanningResponses: [String] = [
            "Implement the feature with persistence and tests.",
            "Revised plan: implement the feature with restoration coverage."
        ]
    ) {
        self.reviewerResponses = reviewerResponseBlocks
        self.managerPlanningResponses = managerPlanningResponses
    }

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
        calls.append(
            .init(
                role: profile.role,
                message: message,
                workingDirectory: profile.runtimeWorkingDirectory
            )
        )
        let count = roleResponseCounts[profile.role, default: 0]
        roleResponseCounts[profile.role] = count + 1

        let responses: [String]
        switch profile.role {
        case .manager:
            if message.contains("planning phase") {
                responses = [
                    managerPlanningResponses.indices.contains(count)
                        ? managerPlanningResponses[count]
                        : managerPlanningResponses.last ?? ""
                ]
            } else {
                responses = [
                    "Complete: [draft PR](https://github.com/suttree/bl00p/pull/99)"
                ]
            }
        case .builder:
            responses = [
                count == 0
                    ? "Implementation committed and tests passed."
                    : "Review finding fixed, committed, and tests passed."
            ]
        case .reviewer:
            responses = reviewerResponses[
                min(count, reviewerResponses.count - 1)
            ]
        case .publisher:
            responses = [
                "Documentation committed. Draft PR: https://github.com/suttree/bl00p/pull/99"
            ]
        }

        let assistantEntries = responses
            .filter { !$0.isEmpty }
            .map { TimelineEntry(kind: .assistant, text: $0) }
        assistantEntryIDs.append(contentsOf: assistantEntries.map(\.id))
        return AsyncStream { continuation in
            continuation.yield(.status(.working))
            for assistantEntry in assistantEntries {
                continuation.yield(.entry(assistantEntry))
            }
            let hasStructuredReview = responses.contains {
                ReviewDisposition.parse(from: $0) != nil
            }
            continuation.yield(
                .status(
                    profile.role == .reviewer && hasStructuredReview
                        ? .needsAnswer
                        : .completed
                )
            )
            if profile.role == .reviewer {
                continuation.yield(
                    .entry(
                        .init(
                            kind: .assistant,
                            text: "Unrelated reviewer follow-up"
                        )
                    )
                )
            }
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

private actor BuilderStatusStubRuntime: AgentRuntime {
    let builderFinalStatus: AgentStatus
    let builderResponseText: String
    let blockedActionDetail: String?
    private(set) var calls: [AgentRole] = []

    init(
        builderFinalStatus: AgentStatus,
        builderResponseText: String = "Implementation committed and tests passed.",
        blockedActionDetail: String? = nil
    ) {
        self.builderFinalStatus = builderFinalStatus
        self.builderResponseText = builderResponseText
        self.blockedActionDetail = blockedActionDetail
    }

    func start(
        profile: BotProfile,
        resumeThreadID: String?
    ) async -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            continuation.yield(
                .sessionID(resumeThreadID ?? "session-\(profile.id.uuidString)")
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
        calls.append(profile.role)
        let responseText =
            profile.role == .builder
                ? builderResponseText
                : "Acknowledged."
        return AsyncStream { continuation in
            continuation.yield(.status(.working))
            continuation.yield(
                .entry(.init(kind: .assistant, text: responseText))
            )
            guard profile.role == .builder else {
                // Non-builder roles (e.g. the Reviewer) are left mid-turn,
                // deliberately never reaching a terminal status. These tests
                // only assert on the handoff that reached them, not on what
                // an automated review would do next — settling that turn
                // would cascade the fully-autonomous pipeline (revision or
                // publishing) past the state under test.
                return
            }
            if let blockedActionDetail {
                continuation.yield(
                    .entry(
                        .init(
                            kind: .question,
                            title: "Some actions were blocked",
                            text: "Claude could not run one or more required actions.",
                            detail: blockedActionDetail
                        )
                    )
                )
            }
            continuation.yield(.status(builderFinalStatus))
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

/// Simulates a Builder that ends its first turn `.blocked`, then reaches a
/// second terminal status purely via an approval resolution rather than a
/// new explicit chat message — the self-healing retry path.
private actor RetryableBuilderRuntime: AgentRuntime {
    private(set) var calls: [AgentRole] = []

    func start(
        profile: BotProfile,
        resumeThreadID: String?
    ) async -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            continuation.yield(
                .sessionID(resumeThreadID ?? "session-\(profile.id.uuidString)")
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
        calls.append(profile.role)
        let responseText =
            profile.role == .builder
                ? "Working on it, but a required action was blocked."
                : "Acknowledged."
        return AsyncStream { continuation in
            continuation.yield(.status(.working))
            continuation.yield(
                .entry(.init(kind: .assistant, text: responseText))
            )
            guard profile.role == .builder else {
                // Non-builder roles (e.g. the Reviewer) are left mid-turn,
                // deliberately never reaching a terminal status. This test
                // only asserts on the handoff that reached them, not on what
                // an automated review would do next — settling that turn
                // would cascade the fully-autonomous pipeline (revision or
                // publishing) past the state under test.
                return
            }
            continuation.yield(
                .entry(
                    .init(
                        kind: .question,
                        title: "Some actions were blocked",
                        text: "Claude could not run one or more required actions.",
                        detail: "• git commit -m \"Ship the feature\""
                    )
                )
            )
            continuation.yield(.status(.blocked))
            continuation.finish()
        }
    }

    func resolveApproval(
        entryID: UUID,
        approved: Bool,
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent> {
        // Deliberately reports another mid-retry approval request before the
        // final status, rather than `.working`, so this exercises the new
        // awaitingBuilderHandoffRetry re-check specifically rather than the
        // pre-existing "always resume on .working" exception.
        AsyncStream { continuation in
            continuation.yield(.status(.needsApproval))
            continuation.yield(
                .entry(
                    .init(
                        kind: .assistant,
                        text: "The action is approved; work is committed and tests passed."
                    )
                )
            )
            continuation.yield(.status(.blocked))
            continuation.finish()
        }
    }

    func stop(profile: BotProfile) async {}
}

/// The Builder's first turn ends blocked with a test-related denial; its
/// second turn (a fresh explicit send) also ends blocked but records no
/// denial of its own. Used to prove a stale denial from an earlier turn
/// cannot be reused to justify a caveat on a later, unrelated turn.
private actor TwoTurnBuilderRuntime: AgentRuntime {
    private(set) var calls: [AgentRole] = []
    private var builderRespondCount = 0

    func start(
        profile: BotProfile,
        resumeThreadID: String?
    ) async -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            continuation.yield(
                .sessionID(resumeThreadID ?? "session-\(profile.id.uuidString)")
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
        calls.append(profile.role)
        guard profile.role == .builder else {
            return AsyncStream { continuation in
                continuation.yield(.status(.working))
                continuation.yield(
                    .entry(.init(kind: .assistant, text: "Acknowledged."))
                )
                continuation.yield(.status(.completed))
                continuation.finish()
            }
        }
        builderRespondCount += 1
        let isFirstBuilderTurn = builderRespondCount == 1
        return AsyncStream { continuation in
            continuation.yield(.status(.working))
            continuation.yield(
                .entry(.init(kind: .assistant, text: "Working on it."))
            )
            if isFirstBuilderTurn {
                continuation.yield(
                    .entry(
                        .init(
                            kind: .question,
                            title: "Some actions were blocked",
                            text: "Claude could not run one or more required actions.",
                            detail: "• swift test"
                        )
                    )
                )
            }
            continuation.yield(.status(.blocked))
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

private actor SuspendedWorkflowRuntime: AgentRuntime {
    struct Call: Sendable {
        let role: AgentRole
        let message: String
        let workingDirectory: String
    }

    private(set) var calls: [Call] = []

    func start(
        profile: BotProfile,
        resumeThreadID: String?
    ) async -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            continuation.yield(
                .sessionID(
                    resumeThreadID
                        ?? "suspended-\(profile.id.uuidString)"
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
        calls.append(
            .init(
                role: profile.role,
                message: message,
                workingDirectory: profile.runtimeWorkingDirectory
            )
        )
        return AsyncStream { continuation in
            continuation.yield(.status(.working))
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

private actor BlockingWorkflowRuntime: AgentRuntime {
    private(set) var responseStarted = false
    private var responseContinuation:
        CheckedContinuation<AsyncStream<AgentEvent>, Never>?

    func start(
        profile: BotProfile,
        resumeThreadID: String?
    ) async -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            continuation.yield(
                .sessionID(
                    resumeThreadID
                        ?? "blocked-(profile.id.uuidString)"
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
        responseStarted = true
        return await withCheckedContinuation { continuation in
            responseContinuation = continuation
        }
    }

    func release() {
        responseContinuation?.resume(
            returning: AsyncStream { $0.finish() }
        )
        responseContinuation = nil
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

private actor SessionRecordingRuntime: AgentRuntime {
    private(set) var respondedSessionIDs: [UUID] = []
    private(set) var respondedDirectories: [UUID: String] = [:]

    func start(
        profile: BotProfile,
        resumeThreadID: String?
    ) async -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            continuation.yield(
                .sessionID(resumeThreadID ?? "session-\(profile.id.uuidString)")
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
        respondedSessionIDs.append(profile.id)
        respondedDirectories[profile.id] = profile.workingDirectory
        return AsyncStream { continuation in
            continuation.yield(
                .entry(
                    .init(
                        kind: .assistant,
                        text: "\(profile.id.uuidString): \(message)"
                    )
                )
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

private actor LateEventRuntime: AgentRuntime {
    private var continuation: AsyncStream<AgentEvent>.Continuation?
    private(set) var didStartResponse = false

    func start(
        profile: BotProfile,
        resumeThreadID: String?
    ) async -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            continuation.yield(.sessionID("late-\(profile.id.uuidString)"))
            continuation.yield(.status(.needsAnswer))
            continuation.finish()
        }
    }

    func respond(
        to message: String,
        attachments: [ImageAttachment],
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent> {
        let pair = AsyncStream.makeStream(of: AgentEvent.self)
        continuation = pair.continuation
        didStartResponse = true
        pair.continuation.yield(.status(.working))
        return pair.stream
    }

    func resolveApproval(
        entryID: UUID,
        approved: Bool,
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent> {
        AsyncStream { $0.finish() }
    }

    func stop(profile: BotProfile) async {}

    func emitLateEvent() {
        continuation?.yield(.entry(.init(kind: .assistant, text: "Too late")))
        continuation?.yield(.status(.completed))
        continuation?.finish()
        continuation = nil
    }
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

#if os(macOS)
@MainActor
#endif
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
