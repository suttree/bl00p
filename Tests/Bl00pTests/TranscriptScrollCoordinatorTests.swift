import Foundation
import Testing
@testable import Bl00p

@Test
func transcriptScrollStartsAtLatestForNonEmptySession() throws {
    var state = TranscriptScrollCoordinator()
    let sessionID = UUID()

    state.reset(for: sessionID, hasContent: true)
    #expect(state.scheduledScrollRequestID == nil)
    state.transcriptMounted(for: sessionID)

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
    state.transcriptMounted(for: sessionID)
    let initialRequest = try #require(state.scheduledScrollRequestID)

    state.contentChanged(for: sessionID)
    state.contentChanged(for: sessionID)

    #expect(state.scheduledScrollRequestID == initialRequest)
    state.didPerformScroll(requestID: initialRequest, for: sessionID)
    state.contentChanged(for: sessionID)
    #expect(state.scheduledScrollRequestID != initialRequest)
}

@Test
func transcriptScrollUsesNearBottomTolerance() {
    var state = TranscriptScrollCoordinator()
    let sessionID = UUID()
    state.reset(for: sessionID, hasContent: true)
    state.transcriptMounted(for: sessionID)

    state.viewportChanged(
        for: sessionID,
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
    state.transcriptMounted(for: sessionID)
    let initialRequest = try #require(state.scheduledScrollRequestID)
    state.didPerformScroll(requestID: initialRequest, for: sessionID)
    state.viewportChanged(
        for: sessionID,
        distanceToBottom: 0,
        userInitiated: false
    )

    state.viewportChanged(
        for: sessionID,
        distanceToBottom: 160,
        userInitiated: false
    )

    #expect(state.isFollowingLatest)
    #expect(state.scheduledScrollRequestID != nil)
}

@Test
func transcriptScrollHoldsDeliberateHistoryBrowsingDuringUpdates() {
    var state = TranscriptScrollCoordinator()
    let sessionID = UUID()
    state.reset(for: sessionID, hasContent: true)
    state.transcriptMounted(for: sessionID)
    state.viewportChanged(
        for: sessionID,
        distanceToBottom: 0,
        userInitiated: false
    )

    state.viewportChanged(
        for: sessionID,
        distanceToBottom: 240,
        userInitiated: true
    )
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
    state.transcriptMounted(for: sessionID)
    let requestID = try #require(state.scheduledScrollRequestID)
    state.didPerformScroll(requestID: requestID, for: sessionID)

    state.userDraggedTowardHistory(
        distance: TranscriptScrollCoordinator.nearBottomTolerance,
        in: sessionID
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
    state.transcriptMounted(for: sessionID)
    let requestID = try #require(state.scheduledScrollRequestID)
    state.didPerformScroll(requestID: requestID, for: sessionID)

    state.userDraggedTowardHistory(
        distance: TranscriptScrollCoordinator.nearBottomTolerance + 1,
        in: sessionID
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
    state.transcriptMounted(for: sessionID)
    state.viewportChanged(
        for: sessionID,
        distanceToBottom: 300,
        userInitiated: true
    )

    state.viewportChanged(
        for: sessionID,
        distanceToBottom: 20,
        userInitiated: true
    )

    #expect(state.isFollowingLatest)
    #expect(state.isNearBottom)
    #expect(!state.showsJumpToLatest)
}

@Test
func transcriptJumpToLatestResumesFollowing() throws {
    var state = TranscriptScrollCoordinator()
    let sessionID = UUID()
    state.reset(for: sessionID, hasContent: true)
    state.transcriptMounted(for: sessionID)
    state.userBrowsedHistory(in: sessionID)

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
    state.transcriptMounted(for: sessionID)
    state.userBrowsedHistory(in: sessionID)

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
    state.transcriptMounted(for: firstSessionID)
    let staleRequestID = try #require(state.scheduledScrollRequestID)
    state.userBrowsedHistory(in: firstSessionID)

    state.reset(for: secondSessionID, hasContent: true)
    state.transcriptMounted(for: secondSessionID)

    #expect(state.sessionID == secondSessionID)
    #expect(state.isFollowingLatest)
    #expect(!state.shouldPerformScroll(
        requestID: staleRequestID,
        for: firstSessionID
    ))
    #expect(state.scheduledScrollRequestID != staleRequestID)
}

@Test
func transcriptRapidSessionSwitchingOnlyPerformsLatestRequest() throws {
    var state = TranscriptScrollCoordinator()
    let firstSessionID = UUID()
    let secondSessionID = UUID()

    state.reset(for: firstSessionID, hasContent: true)
    state.transcriptMounted(for: firstSessionID)
    let firstRequestID = try #require(state.scheduledScrollRequestID)

    state.reset(for: secondSessionID, hasContent: true)
    state.transcriptMounted(for: secondSessionID)
    let secondRequestID = try #require(state.scheduledScrollRequestID)

    state.reset(for: firstSessionID, hasContent: true)
    #expect(state.scheduledScrollRequestID == nil)
    state.didPerformScroll(
        requestID: firstRequestID,
        for: firstSessionID
    )
    #expect(!state.isNearBottom)

    state.transcriptMounted(for: firstSessionID)
    let finalRequestID = try #require(state.scheduledScrollRequestID)

    #expect(finalRequestID != firstRequestID)
    #expect(finalRequestID != secondRequestID)
    #expect(!state.shouldPerformScroll(
        requestID: firstRequestID,
        for: firstSessionID
    ))
    #expect(!state.shouldPerformScroll(
        requestID: secondRequestID,
        for: secondSessionID
    ))
    #expect(state.shouldPerformScroll(
        requestID: finalRequestID,
        for: firstSessionID
    ))
}

@Test
func transcriptIgnoresStaleSessionCallbacks() throws {
    var state = TranscriptScrollCoordinator()
    let firstSessionID = UUID()
    let secondSessionID = UUID()

    state.reset(for: firstSessionID, hasContent: true)
    state.transcriptMounted(for: firstSessionID)
    let firstRequestID = try #require(state.scheduledScrollRequestID)

    state.reset(for: secondSessionID, hasContent: true)
    state.transcriptMounted(for: secondSessionID)
    let secondRequestID = try #require(state.scheduledScrollRequestID)
    state.didPerformScroll(
        requestID: secondRequestID,
        for: secondSessionID
    )

    state.viewportChanged(
        for: firstSessionID,
        distanceToBottom: 300,
        userInitiated: true
    )
    state.userDraggedTowardHistory(
        distance: TranscriptScrollCoordinator.nearBottomTolerance + 1,
        in: firstSessionID
    )
    state.contentChanged(for: firstSessionID)
    state.jumpToLatest(for: firstSessionID)
    state.userSentMessage(in: firstSessionID)
    state.didPerformScroll(
        requestID: firstRequestID,
        for: firstSessionID
    )
    state.transcriptUnmounted(for: firstSessionID)

    #expect(state.sessionID == secondSessionID)
    #expect(state.isTranscriptMounted)
    #expect(state.isFollowingLatest)
    #expect(state.isNearBottom)
    #expect(state.scheduledScrollRequestID == nil)
}

@Test
func emptyTranscriptMountDoesNotScheduleScroll() {
    var state = TranscriptScrollCoordinator()
    let sessionID = UUID()

    state.reset(for: sessionID, hasContent: false)
    state.transcriptMounted(for: sessionID)

    #expect(state.sessionID == sessionID)
    #expect(state.isTranscriptMounted)
    #expect(state.isFollowingLatest)
    #expect(state.isNearBottom)
    #expect(state.scheduledScrollRequestID == nil)
}
