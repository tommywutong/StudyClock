import Foundation

enum StudyStatisticsPeriod: Int, CaseIterable, Identifiable, Sendable, Equatable {
    case sevenDays = 7
    case fifteenDays = 15
    case thirtyDays = 30

    var id: Int { rawValue }
    var dayCount: Int { rawValue }
}

struct StudyStatisticsTaskInput: Equatable, Sendable {
    let id: UUID
    let name: String
    let dailyGoalSeconds: Int
    let sortOrder: Int
}

struct StudyStatisticsTaskSummary: Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let elapsed: TimeInterval
    let previousElapsed: TimeInterval
    let elapsedChange: TimeInterval
    let elapsedRelativeChange: Double?
    let share: Double?
    let averageDailyElapsed: TimeInterval
    let goalElapsed: TimeInterval
    let goalCompletionRate: Double?
    let previousGoalCompletionRate: Double?
    let goalCompletionChangePercentagePoints: Double?
    let goalAttainmentDays: Int?
    let previousGoalAttainmentDays: Int?
}

struct StudyStatisticsReport: Equatable, Sendable {
    let period: StudyStatisticsPeriod
    let periodStart: Date
    let previousPeriodStart: Date
    let periodEnd: Date
    let hasHistory: Bool
    let elapsed: TimeInterval
    let previousElapsed: TimeInterval
    let elapsedChange: TimeInterval
    let elapsedRelativeChange: Double?
    let goalElapsed: TimeInterval
    let goalCompletionRate: Double?
    let previousGoalCompletionRate: Double?
    let goalCompletionChangePercentagePoints: Double?
    let tasks: [StudyStatisticsTaskSummary]
}

enum StudyStatisticsCalculator {
    private struct TaskTotals {
        let task: StudyStatisticsTaskInput
        let elapsed: TimeInterval
        let attainmentDays: Int
        let previousElapsed: TimeInterval
        let previousAttainmentDays: Int
    }

    static func calculate(
        tasks: [StudyStatisticsTaskInput],
        snapshot: TimerSnapshot,
        period: StudyStatisticsPeriod,
        now: Date,
        calendar: Calendar
    ) -> StudyStatisticsReport {
        let periodEnd = calendar.startOfDay(for: now)
        let dayCount = period.dayCount
        guard let periodStart = calendar.date(byAdding: .day, value: -dayCount, to: periodEnd),
              let previousPeriodStart = calendar.date(
                  byAdding: .day, value: -(2 * dayCount), to: periodEnd) else {
            preconditionFailure("Calendar could not derive statistics period boundaries")
        }

        let orderedTasks = tasks.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        var taskTotals: [TaskTotals] = []
        taskTotals.reserveCapacity(orderedTasks.count)
        var elapsed: TimeInterval = 0
        var previousElapsed: TimeInterval = 0
        var goalElapsed: TimeInterval = 0
        var goalActualElapsed: TimeInterval = 0
        var previousGoalActualElapsed: TimeInterval = 0

        for task in orderedTasks {
            let current = elapsedAndAttainmentDays(
                task: task,
                start: periodStart,
                end: periodEnd,
                snapshot: snapshot,
                now: now,
                calendar: calendar)
            let previous = elapsedAndAttainmentDays(
                task: task,
                start: previousPeriodStart,
                end: periodStart,
                snapshot: snapshot,
                now: now,
                calendar: calendar)

            elapsed += current.elapsed
            previousElapsed += previous.elapsed
            if task.dailyGoalSeconds > 0 {
                let taskGoalElapsed = TimeInterval(task.dailyGoalSeconds) * TimeInterval(dayCount)
                goalElapsed += taskGoalElapsed
                goalActualElapsed += current.elapsed
                previousGoalActualElapsed += previous.elapsed
            }
            taskTotals.append(TaskTotals(
                task: task,
                elapsed: current.elapsed,
                attainmentDays: current.attainmentDays,
                previousElapsed: previous.elapsed,
                previousAttainmentDays: previous.attainmentDays))
        }

        let goalCompletionRate = goalElapsed > 0 ? goalActualElapsed / goalElapsed : nil
        let previousGoalCompletionRate = goalElapsed > 0
            ? previousGoalActualElapsed / goalElapsed
            : nil
        let goalCompletionChangePercentagePoints: Double? = {
            guard let goalCompletionRate, let previousGoalCompletionRate else { return nil }
            return (goalCompletionRate - previousGoalCompletionRate) * 100
        }()

        let summaries = taskTotals.map { totals in
            let taskGoalElapsed = totals.task.dailyGoalSeconds > 0
                ? TimeInterval(totals.task.dailyGoalSeconds) * TimeInterval(dayCount)
                : 0
            let taskGoalCompletionRate = taskGoalElapsed > 0
                ? totals.elapsed / taskGoalElapsed
                : nil
            let previousTaskGoalCompletionRate = taskGoalElapsed > 0
                ? totals.previousElapsed / taskGoalElapsed
                : nil
            let taskGoalCompletionChangePercentagePoints: Double? = {
                guard let taskGoalCompletionRate, let previousTaskGoalCompletionRate else { return nil }
                return (taskGoalCompletionRate - previousTaskGoalCompletionRate) * 100
            }()
            let elapsedChange = totals.elapsed - totals.previousElapsed

            return StudyStatisticsTaskSummary(
                id: totals.task.id,
                name: totals.task.name,
                elapsed: totals.elapsed,
                previousElapsed: totals.previousElapsed,
                elapsedChange: elapsedChange,
                elapsedRelativeChange: totals.previousElapsed > 0
                    ? elapsedChange / totals.previousElapsed
                    : nil,
                share: elapsed > 0 ? totals.elapsed / elapsed : nil,
                averageDailyElapsed: totals.elapsed / TimeInterval(dayCount),
                goalElapsed: taskGoalElapsed,
                goalCompletionRate: taskGoalCompletionRate,
                previousGoalCompletionRate: previousTaskGoalCompletionRate,
                goalCompletionChangePercentagePoints: taskGoalCompletionChangePercentagePoints,
                goalAttainmentDays: totals.task.dailyGoalSeconds > 0 ? totals.attainmentDays : nil,
                previousGoalAttainmentDays: totals.task.dailyGoalSeconds > 0
                    ? totals.previousAttainmentDays
                    : nil)
        }

        let elapsedChange = elapsed - previousElapsed
        return StudyStatisticsReport(
            period: period,
            periodStart: periodStart,
            previousPeriodStart: previousPeriodStart,
            periodEnd: periodEnd,
            hasHistory: !snapshot.intervals.isEmpty || snapshot.activeTaskID != nil,
            elapsed: elapsed,
            previousElapsed: previousElapsed,
            elapsedChange: elapsedChange,
            elapsedRelativeChange: previousElapsed > 0
                ? elapsedChange / previousElapsed
                : nil,
            goalElapsed: goalElapsed,
            goalCompletionRate: goalCompletionRate,
            previousGoalCompletionRate: previousGoalCompletionRate,
            goalCompletionChangePercentagePoints: goalCompletionChangePercentagePoints,
            tasks: summaries)
    }

    private static func elapsedAndAttainmentDays(
        task: StudyStatisticsTaskInput,
        start: Date,
        end: Date,
        snapshot: TimerSnapshot,
        now: Date,
        calendar: Calendar
    ) -> (elapsed: TimeInterval, attainmentDays: Int) {
        var elapsed: TimeInterval = 0
        var attainmentDays = 0
        var day = start
        let dailyGoal = TimeInterval(task.dailyGoalSeconds)

        while day < end {
            let dayElapsed = snapshot.elapsed(
                taskID: task.id, on: day, calendar: calendar, now: now)
            elapsed += dayElapsed
            if task.dailyGoalSeconds > 0, dayElapsed >= dailyGoal {
                attainmentDays += 1
            }

            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day), nextDay > day else {
                preconditionFailure("Calendar could not advance a statistics day")
            }
            day = nextDay
        }

        return (elapsed, attainmentDays)
    }
}
