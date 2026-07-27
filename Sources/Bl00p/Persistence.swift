import Foundation

protocol PersistenceScheduling: Sendable {
    func sleep(for delay: Duration) async
}

struct ContinuousPersistenceScheduler: PersistenceScheduling {
    func sleep(for delay: Duration) async {
        try? await Task.sleep(for: delay)
    }
}

protocol PersistedStateWriting: Sendable {
    func write(_ state: PersistedAppState) async
}

actor FilePersistedStateWriter: PersistedStateWriting {
    private let fileURL: URL?

    init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    func write(_ state: PersistedAppState) async {
        guard let fileURL else { return }
        let startedAt = ContinuousClock.now

        do {
            let data = try JSONEncoder.compactState.encode(state)
            let fileManager = FileManager.default
            let directory = fileURL.deletingLastPathComponent()
            let backupURL = directory.appendingPathComponent(
                "\(fileURL.lastPathComponent).bak"
            )
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: fileURL.path) {
                let previousData = try Data(contentsOf: fileURL)
                try previousData.write(to: backupURL, options: .atomic)
            }
            try data.write(to: fileURL, options: .atomic)
            PerformanceMetrics.record(
                name: .persistence,
                duration: startedAt.duration(to: .now)
            )
        } catch {
            // Persistence failure should not interrupt an active coding session.
        }
    }
}

actor AppStatePersistenceQueue {
    private struct PendingState: Sendable {
        let revision: UInt64
        let state: PersistedAppState
    }

    private let writer: any PersistedStateWriting
    private let scheduler: any PersistenceScheduling
    private let coalescingDelay: Duration
    private var pending: PendingState?
    private var latestRevision: UInt64 = 0
    private var writtenRevision: UInt64 = 0
    private var scheduledTask: Task<Void, Never>?
    private var isWriting = false
    private var urgentWriteRequested = false
    private var writeWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        writer: any PersistedStateWriting,
        scheduler: any PersistenceScheduling,
        coalescingDelay: Duration
    ) {
        self.writer = writer
        self.scheduler = scheduler
        self.coalescingDelay = coalescingDelay
    }

    func enqueue(_ state: PersistedAppState, revision: UInt64) {
        guard revision >= latestRevision else { return }
        latestRevision = revision
        pending = PendingState(revision: revision, state: state)
        scheduleWrite()
    }

    func flush(_ state: PersistedAppState, revision: UInt64) async {
        if revision >= latestRevision {
            latestRevision = revision
            pending = PendingState(revision: revision, state: state)
        }
        await flushPending()
    }

    func flushPending() async {
        scheduledTask?.cancel()
        scheduledTask = nil
        urgentWriteRequested = true

        if isWriting {
            await withCheckedContinuation { continuation in
                writeWaiters.append(continuation)
            }
            if writtenRevision < latestRevision {
                await flushPending()
            }
            return
        }

        await writePending()
    }

    private func scheduleWrite() {
        scheduledTask?.cancel()
        let scheduler = scheduler
        let delay = coalescingDelay
        scheduledTask = Task { [weak self] in
            await scheduler.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.scheduledWriteFired()
        }
    }

    private func scheduledWriteFired() async {
        scheduledTask = nil
        guard !isWriting else { return }
        await writePending()
    }

    private func writePending() async {
        guard !isWriting else { return }
        isWriting = true

        repeat {
            guard let next = pending else { break }
            pending = nil
            await writer.write(next.state)
            writtenRevision = max(writtenRevision, next.revision)
        } while urgentWriteRequested && pending != nil

        urgentWriteRequested = false
        isWriting = false
        let waiters = writeWaiters
        writeWaiters.removeAll()
        waiters.forEach { $0.resume() }

        if pending != nil {
            scheduleWrite()
        }
    }
}

extension JSONEncoder {
    static var compactState: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
