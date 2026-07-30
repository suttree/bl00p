import Testing
@testable import Bl00p

@Test
func closeWarningSaysCleanManagedWorktreeWillBeDeleted() {
    let message = SessionCloseWarningMessage.make(
        for: SessionCloseAssessment(
            isActive: false,
            hasDirtyWorktree: false,
            participatesInWorkflow: false,
            hasManagedWorktree: true
        )
    )

    #expect(
        message == """
        The local chat history will be deleted.

        The managed Git worktree will be deleted. Its Git branch is retained for recovery.
        """
    )
}

@Test
func closeWarningSaysDirtyManagedWorktreeWillBeDeleted() {
    let message = SessionCloseWarningMessage.make(
        for: SessionCloseAssessment(
            isActive: false,
            hasDirtyWorktree: true,
            participatesInWorkflow: false,
            hasManagedWorktree: true
        )
    )

    #expect(message.contains("The managed Git worktree will be deleted."))
    #expect(message.contains("Its Git branch is retained for recovery."))
    #expect(
        message.contains(
            "The worktree has uncommitted changes and will be removed."
        )
    )
}

@Test
func closeWarningSaysUnsafeManagedWorktreeWillRemainOnDisk() {
    let message = SessionCloseWarningMessage.make(
        for: SessionCloseAssessment(
            isActive: false,
            hasDirtyWorktree: false,
            participatesInWorkflow: false,
            hasManagedWorktree: true,
            leavesWorktreeOnDisk: true,
            worktreeWarning: "The registered worktree uses a different branch."
        )
    )

    #expect(!message.contains("worktree will be deleted"))
    #expect(
        message.contains(
            "The managed Git worktree cannot be safely removed automatically and will be left on disk."
        )
    )
    #expect(message.contains("Its Git branch is retained for recovery."))
    #expect(
        message.contains(
            "The registered worktree uses a different branch."
        )
    )
}

@Test
func closeWarningRetainsActiveAgentAndWorkflowWarnings() {
    let message = SessionCloseWarningMessage.make(
        for: SessionCloseAssessment(
            isActive: true,
            hasDirtyWorktree: true,
            participatesInWorkflow: true,
            hasManagedWorktree: true
        )
    )

    #expect(message.contains("The agent is active and will be stopped."))
    #expect(
        message.contains(
            "The worktree has uncommitted changes and will be removed."
        )
    )
    #expect(message.contains("Its managed workflow will be paused."))
}
