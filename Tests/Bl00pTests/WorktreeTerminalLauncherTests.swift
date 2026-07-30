import Foundation
import Testing
@testable import Bl00p

@Test
func terminalTargetPathPrefersWorktreeOverRepository() {
    let path = WorktreeTerminalLauncher.terminalTargetPath(
        worktreePath: "/tmp/worktree",
        repositoryPath: "/tmp/repo"
    )
    #expect(path == "/tmp/worktree")
}

@Test
func terminalTargetPathFallsBackToRepositoryWhenNoWorktree() {
    let path = WorktreeTerminalLauncher.terminalTargetPath(
        worktreePath: nil,
        repositoryPath: "/tmp/repo"
    )
    #expect(path == "/tmp/repo")
}

@Test
func terminalTargetPathIsNilWhenNothingIsSelected() {
    let path = WorktreeTerminalLauncher.terminalTargetPath(
        worktreePath: nil,
        repositoryPath: ""
    )
    #expect(path == nil)
}

@Test
func terminalTargetPathIgnoresEmptyWorktreePath() {
    let path = WorktreeTerminalLauncher.terminalTargetPath(
        worktreePath: "",
        repositoryPath: "/tmp/repo"
    )
    #expect(path == "/tmp/repo")
}
