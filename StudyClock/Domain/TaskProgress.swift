import Foundation

struct TaskProgress: Equatable, Sendable {
    let elapsed: TimeInterval
    let target: TimeInterval

    var remaining: TimeInterval { max(target - elapsed, 0) }
    var overtime: TimeInterval { max(elapsed - target, 0) }
    var isComplete: Bool { elapsed >= target }
}

enum StudyDurationFormatting {
    nonisolated static func hoursMinutes(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "—" }
        let value = max(0, seconds.rounded(.down))
        let hours = (value / 3_600).rounded(.down)
        let minutes = Int(value.truncatingRemainder(dividingBy: 3_600) / 60)
        return String(format: "%.0f:%02d", hours, minutes)
    }
}