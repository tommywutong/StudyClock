import Foundation

struct TimerInterval: Equatable, Sendable {
    let taskID: UUID
    let start: Date
    let end: Date
}

struct TimerSnapshot: Equatable, Sendable {
    let intervals: [TimerInterval]
    let activeTaskID: UUID?
    let activeStartedAt: Date?
    let conflictingActionIDs: Set<UUID>

    func elapsed(
        taskID: UUID,
        on day: Date,
        calendar: Calendar,
        now: Date
    ) -> TimeInterval {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart),
              dayEnd > dayStart else {
            return 0
        }

        var total: TimeInterval = 0
        for interval in intervals where interval.taskID == taskID {
            total += intersectionDuration(
                interval.start, interval.end, with: dayStart, through: dayEnd)
        }

        if activeTaskID == taskID, let activeStartedAt {
            total += intersectionDuration(
                activeStartedAt, max(now, activeStartedAt),
                with: dayStart, through: dayEnd)
        }
        return max(total, 0)
    }

    private func intersectionDuration(
        _ start: Date,
        _ end: Date,
        with dayStart: Date,
        through dayEnd: Date
    ) -> TimeInterval {
        let intersectionStart = max(start, dayStart)
        let intersectionEnd = min(end, dayEnd)
        guard intersectionEnd > intersectionStart else { return 0 }
        return intersectionEnd.timeIntervalSince(intersectionStart)
    }
}