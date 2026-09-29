import Foundation

struct TaskProgress: Equatable, Sendable {
    let elapsed: TimeInterval
    let target: TimeInterval

    var remaining: TimeInterval { max(target - elapsed, 0) }
    var overtime: TimeInterval { max(elapsed - target, 0) }
    var isComplete: Bool { elapsed >= target }
}