import Foundation

struct TranscriptScrollCoordinator {
    static let nearBottomTolerance = 80.0

    private(set) var sessionID: UUID?
    private(set) var isFollowingLatest = true
    private(set) var isNearBottom = false
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
        isAutomaticLayoutPending = hasContent
        cancelScheduledScroll()
        if hasContent {
            scheduleScroll()
        }
    }

    mutating func contentChanged(for sessionID: UUID) {
        guard self.sessionID == sessionID else {
            reset(for: sessionID, hasContent: true)
            return
        }
        guard isFollowingLatest else { return }

        isAutomaticLayoutPending = true
        scheduleScroll()
    }

    mutating func viewportChanged(
        distanceToBottom: Double,
        userInitiated: Bool
    ) {
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

    mutating func userBrowsedHistory() {
        isNearBottom = false
        holdPosition()
    }

    mutating func jumpToLatest(for sessionID: UUID) {
        if self.sessionID != sessionID {
            reset(for: sessionID, hasContent: true)
            return
        }
        resumeFollowing()
    }

    mutating func userSentMessage(in sessionID: UUID) {
        if self.sessionID != sessionID {
            reset(for: sessionID, hasContent: true)
            return
        }
        resumeFollowing()
    }

    func shouldPerformScroll(requestID: Int, for sessionID: UUID) -> Bool {
        self.sessionID == sessionID
            && isFollowingLatest
            && scheduledScrollRequestID == requestID
    }

    mutating func didPerformScroll(requestID: Int) {
        guard scheduledScrollRequestID == requestID else { return }
        scheduledScrollRequestID = nil
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
        guard scheduledScrollRequestID == nil else { return }
        scrollRequestID &+= 1
        scheduledScrollRequestID = scrollRequestID
    }

    private mutating func cancelScheduledScroll() {
        guard scheduledScrollRequestID != nil else { return }
        scrollRequestID &+= 1
        scheduledScrollRequestID = nil
    }
}
