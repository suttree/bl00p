import Foundation
import OSLog

enum PerformanceMetricName: String, Sendable {
    case workflowStage = "workflow_stage"
    case workflowTotal = "workflow_total"
    case runtimeLaunch = "runtime_launch"
    case timeToFirstOutput = "time_to_first_output"
    case turnCompletion = "turn_completion"
    case worktreePreparation = "worktree_preparation"
    case handoffPreparation = "handoff_preparation"
    case persistence
}

enum PerformanceMetrics {
    private static let logger = Logger(
        subsystem: "com.suttree.bl00p",
        category: "performance"
    )

    static func record(
        name: PerformanceMetricName,
        duration: Duration,
        profile: BotProfile? = nil,
        stage: ManagerWorkflowStage? = nil,
        coldStart: Bool? = nil
    ) {
        let milliseconds = durationMilliseconds(duration)
        let provider = profile?.provider.rawValue ?? "none"
        let role = profile?.role.rawValue ?? "none"
        let model = safeModelIdentifier(profile?.modelID)
        let stageName = stage?.rawValue ?? "none"
        let temperature = coldStart.map { $0 ? "cold" : "warm" } ?? "none"

        logger.info(
            "metric=\(name.rawValue, privacy: .public) duration_ms=\(milliseconds, privacy: .public) provider=\(provider, privacy: .public) model=\(model, privacy: .public) role=\(role, privacy: .public) stage=\(stageName, privacy: .public) start=\(temperature, privacy: .public)"
        )
    }

    private static func durationMilliseconds(_ duration: Duration) -> Int64 {
        let components = duration.components
        let seconds = components.seconds.multipliedReportingOverflow(by: 1_000)
        let attoseconds = components.attoseconds / 1_000_000_000_000_000
        return seconds.partialValue + Int64(attoseconds)
    }

    private static func safeModelIdentifier(_ modelID: String?) -> String {
        guard let modelID, !modelID.isEmpty else { return "default" }
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "._-")
        )
        guard modelID.count <= 64,
              modelID.unicodeScalars.allSatisfy(allowed.contains) else {
            return "custom"
        }
        return modelID
    }
}
