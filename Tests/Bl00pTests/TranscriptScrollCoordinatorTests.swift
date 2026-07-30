import Foundation
import Testing
@testable import Bl00p

@Test
func transcriptScrollStartsAtLatestForNonEmptySession() throws {
    var state = TranscriptScrollCoordinator()
    let sessionID = UUID()

    state.reset(for: sessionID, hasContent: true)

    let requestID = try #require(state.scheduledScrollRequestID)
    #expect(state.isFollowingLatest)
    #expect(!state.isNearBottom)
    #expect(state.shouldPerformScroll(
        requestID: requestID,
        for: sessionID
    ))
}

@Test
func transcriptScrollCoalescesAppendsAndStreamedMutations() throws {
    var state = TranscriptScrollCoordinator()
    let sessionID = UUID()
    state.reset(for: sessionID, hasContent: true)
    let initialRequest = try #require(state.scheduledScrollRequestID)

    state.contentChanged(for: sessionID)
    state.contentChanged(for: sessionID)

    #expect(state.scheduledScrollRequestID == initialRequest)
    state.didPerformScroll(requestID: initialRequest)
    state.contentChanged(for: sessionID)
    #expect(state.scheduledScrollRequestID != initialRequest)
}

@Test
func transcriptScrollUsesNearBottomTolerance() {
    var state = TranscriptScrollCoordinator()
    let sessionID = UUID()
    state.reset(for: sessionID, hasContent: true)

    state.viewportChanged(
        distanceToBottom:
            TranscriptScrollCoordinator.nearBottomTolerance,
        userInitiated: false
    )

    #expect(state.isNearBottom)
    #expect(state.isFollowingLatest)
}

@Test
func transcriptLayoutGrowthRepinsWhileFollowing() throws {
    var state = TranscriptScrollCoordinator()
    let sessionID = UUID()
    state.reset(for: sessionID, hasContent: true)
    let initialRequest = try #require(state.scheduledScrollRequestID)
    state.didPerformScroll(requestID: initialRequest)
    state.viewportChanged(distanceToBottom: 0, userInitiated: false)

    state.viewportChanged(distanceToBottom: 160, userInitiated: false)

    #expect(state.isFollowingLatest)
    #expect(state.scheduledScrollRequestID != nil)
}

@Test
func transcriptScrollHoldsDeliberateHistoryBrowsingDuringUpdates() {
    var state = TranscriptScrollCoordinator()
    let sessionID = UUID()
    state.reset(for: sessionID, hasContent: true)
    state.viewportChanged(distanceToBottom: 0, userInitiated: false)

    state.viewportChanged(distanceToBottom: 240, userInitiated: true)
    let requestAfterBrowsing = state.scrollRequestID
    state.contentChanged(for: sessionID)

    #expect(!state.isFollowingLatest)
    #expect(!state.isNearBottom)
    #expect(state.showsJumpToLatest)
    #expect(state.scheduledScrollRequestID == nil)
    #expect(state.scrollRequestID == requestAfterBrowsing)
}

@Test
func transcriptScrollIgnoresSmallBottomEdgeDrags() throws {
    var state = TranscriptScrollCoordinator()
    let sessionID = UUID()
    state.reset(for: sessionID, hasContent: true)
    let requestID = try #require(state.scheduledScrollRequestID)
    state.didPerformScroll(requestID: requestID)

    state.userDraggedTowardHistory(
        distance: TranscriptScrollCoordinator.nearBottomTolerance
    )

    #expect(state.isFollowingLatest)
    #expect(state.isNearBottom)
    #expect(!state.showsJumpToLatest)
}

@Test
func transcriptScrollHoldsAfterDeliberateHistoryDrag() throws {
    var state = TranscriptScrollCoordinator()
    let sessionID = UUID()
    state.reset(for: sessionID, hasContent: true)
    let requestID = try #require(state.scheduledScrollRequestID)
    state.didPerformScroll(requestID: requestID)

    state.userDraggedTowardHistory(
        distance: TranscriptScrollCoordinator.nearBottomTolerance + 1
    )

    #expect(!state.isFollowingLatest)
    #expect(!state.isNearBottom)
    #expect(state.showsJumpToLatest)
}

@Test
func transcriptScrollResumesWhenUserReturnsNearBottom() {
    var state = TranscriptScrollCoordinator()
    let sessionID = UUID()
    state.reset(for: sessionID, hasContent: true)
    state.viewportChanged(distanceToBottom: 300, userInitiated: true)

    state.viewportChanged(distanceToBottom: 20, userInitiated: true)

    #expect(state.isFollowingLatest)
    #expect(state.isNearBottom)
    #expect(!state.showsJumpToLatest)
}

@Test
func transcriptJumpToLatestResumesFollowing() throws {
    var state = TranscriptScrollCoordinator()
    let sessionID = UUID()
    state.reset(for: sessionID, hasContent: true)
    state.userBrowsedHistory()

    state.jumpToLatest(for: sessionID)

    let requestID = try #require(state.scheduledScrollRequestID)
    #expect(state.isFollowingLatest)
    #expect(state.shouldPerformScroll(
        requestID: requestID,
        for: sessionID
    ))
}

@Test
func transcriptSendResumesFollowingBeforeEntryAppend() {
    var state = TranscriptScrollCoordinator()
    let sessionID = UUID()
    state.reset(for: sessionID, hasContent: true)
    state.userBrowsedHistory()

    state.userSentMessage(in: sessionID)

    #expect(state.isFollowingLatest)
    #expect(state.scheduledScrollRequestID != nil)
}

@Test
func transcriptSessionResetCancelsStaleScrollRequest() throws {
    var state = TranscriptScrollCoordinator()
    let firstSessionID = UUID()
    let secondSessionID = UUID()
    state.reset(for: firstSessionID, hasContent: true)
    let staleRequestID = try #require(state.scheduledScrollRequestID)
    state.userBrowsedHistory()

    state.reset(for: secondSessionID, hasContent: true)

    #expect(state.sessionID == secondSessionID)
    #expect(state.isFollowingLatest)
    #expect(!state.shouldPerformScroll(
        requestID: staleRequestID,
        for: firstSessionID
    ))
    #expect(state.scheduledScrollRequestID != staleRequestID)
}
