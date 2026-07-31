import Foundation

struct TranscriptScrollCoordinator {
    static let nearBottomTolerance = 80.0

    private(set) var sessionID: UUID?
    private(set) var isFollowingLatest = true
    private(set) var isNearBottom = false
    private(set) var isTranscriptMounted = false
    private(set) var scrollRequestID = 0
    private(set) var scheduledScrollRequestID: Int?

    private var isAutomaticLayoutPending = false

    var showsJumpToLatest: Bool {
        !isFollowingLatest
    }

    mutating func reset(for sessionID: UUID, hasContent: Bool) {
        self.sessionID = sessionID
        isFollowingLatest = true
        isNearBottom = !hasContent
        isTranscriptMounted = false
        isAutomaticLayoutPending = hasContent
        cancelScheduledScroll()
    }

    mutating func transcriptMounted(for sessionID: UUID) {
        guard self.sessionID == sessionID else { return }

        isTranscriptMounted = true
        if isFollowingLatest, isAutomaticLayoutPending {
            scheduleScroll()
        }
    }

    mutating func transcriptUnmounted(for sessionID: UUID) {
        guard self.sessionID == sessionID else { return }

        isTranscriptMounted = false
        cancelScheduledScroll()
    }

    mutating func contentChanged(for sessionID: UUID) {
        guard self.sessionID == sessionID else { return }
        guard isFollowingLatest else { return }

        isAutomaticLayoutPending = true
        scheduleScroll()
    }

    mutating func viewportChanged(
        for sessionID: UUID,
        distanceToBottom: Double,
        userInitiated: Bool
    ) {
        guard self.sessionID == sessionID, isTranscriptMounted else { return }

        let isNearBottom =
            distanceToBottom <= Self.nearBottomTolerance
        self.isNearBottom = isNearBottom

        if userInitiated {
            if isNearBottom {
                isFollowingLatest = true
                isAutomaticLayoutPending = false
                scheduledScrollRequestID = nil
            } else {
                holdPosition()
            }
            return
        }

        guard isFollowingLatest else { return }
        if isNearBottom {
            isAutomaticLayoutPending = false
        } else if !isAutomaticLayoutPending {
            isAutomaticLayoutPending = true
            scheduleScroll()
        } else if scheduledScrollRequestID == nil {
            scheduleScroll()
        }
    }

    mutating func userBrowsedHistory(in sessionID: UUID) {
        guard self.sessionID == sessionID, isTranscriptMounted else { return }

        isNearBottom = false
        holdPosition()
    }

    mutating func userDraggedTowardHistory(
        distance: Double,
        in sessionID: UUID
    ) {
        guard distance > Self.nearBottomTolerance else { return }
        userBrowsedHistory(in: sessionID)
    }

    mutating func jumpToLatest(for sessionID: UUID) {
        guard self.sessionID == sessionID else { return }
        resumeFollowing()
    }

    mutating func userSentMessage(in sessionID: UUID) {
        guard self.sessionID == sessionID else { return }
        resumeFollowing()
    }

    func shouldPerformScroll(requestID: Int, for sessionID: UUID) -> Bool {
        self.sessionID == sessionID
            && isFollowingLatest
            && scheduledScrollRequestID == requestID
    }

    mutating func didPerformScroll(requestID: Int, for sessionID: UUID) {
        guard self.sessionID == sessionID,
              scheduledScrollRequestID == requestID else { return }
        scheduledScrollRequestID = nil
        isNearBottom = true
        isAutomaticLayoutPending = false
    }

    private mutating func resumeFollowing() {
        isFollowingLatest = true
        isAutomaticLayoutPending = true
        scheduleScroll()
    }

    private mutating func holdPosition() {
        isFollowingLatest = false
        isAutomaticLayoutPending = false
        cancelScheduledScroll()
    }

    private mutating func scheduleScroll() {
        guard isTranscriptMounted,
              scheduledScrollRequestID == nil else { return }
        scrollRequestID &+= 1
        scheduledScrollRequestID = scrollRequestID
    }

    private mutating func cancelScheduledScroll() {
        guard scheduledScrollRequestID != nil else { return }
        scrollRequestID &+= 1
        scheduledScrollRequestID = nil
    }
}
