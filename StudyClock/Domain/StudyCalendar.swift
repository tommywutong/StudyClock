import Foundation

nonisolated enum StudyCalendarIntensity: Int, Equatable, Sendable {
    case empty = 0
    case light = 1
    case medium = 2
    case strong = 3
    case veryStrong = 4
}

nonisolated struct StudyCalendarTaskInput: Equatable, Sendable {
    let id: UUID
    let name: String
    let isArchived: Bool
    let sortOrder: Int
}

nonisolated struct StudyCalendarTaskSummary: Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let isArchived: Bool
    let elapsed: TimeInterval
}

nonisolated struct StudyCalendarDay: Equatable, Identifiable, Sendable {
    let date: Date
    let totalElapsed: TimeInterval
    let intensity: StudyCalendarIntensity
    let tasks: [StudyCalendarTaskSummary]

    var id: Date { date }
}

nonisolated struct StudyCalendarReport: Equatable, Sendable {
    let startDate: Date
    let endDate: Date
    let days: [StudyCalendarDay]
    let currentStreak: Int
    let longestVisibleStreak: Int

    func monthSections(calendar: Calendar) -> [StudyCalendarMonth] {
        let grouped = Dictionary(grouping: days) { day in
            calendar.dateInterval(of: .month, for: day.date)?.start ?? day.date
        }
        return grouped.keys.sorted().compactMap { monthStart in
            guard let days = grouped[monthStart], let firstDay = days.first else { return nil }
            let weekday = calendar.component(.weekday, from: firstDay.date)
            return StudyCalendarMonth(
                startDate: monthStart,
                days: days,
                leadingEmptyCount: (weekday - calendar.firstWeekday + 7) % 7)
        }
    }
}

nonisolated struct StudyCalendarMonth: Identifiable, Equatable, Sendable {
    let startDate: Date
    let days: [StudyCalendarDay]
    let leadingEmptyCount: Int

    var id: Date { startDate }
}

enum StudyCalendarCalculator {
    static func calculate(
        tasks: [StudyCalendarTaskInput],
        snapshot: TimerSnapshot,
        now: Date,
        calendar: Calendar,
        months: Int = 12
    ) -> StudyCalendarReport {
        let periodEnd = calendar.startOfDay(for: now)
        let startDate = calendar.date(byAdding: .month, value: -months, to: periodEnd) ?? periodEnd
        let orderedTasks = tasks.sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.id.uuidString < $1.id.uuidString
        }

        var days: [StudyCalendarDay] = []
        var cursor = startDate
        while cursor <= periodEnd {
            let taskSummaries = orderedTasks.map { task in
                StudyCalendarTaskSummary(
                    id: task.id,
                    name: task.name,
                    isArchived: task.isArchived,
                    elapsed: snapshot.elapsed(
                        taskID: task.id,
                        on: cursor,
                        calendar: calendar,
                        now: now))
            }
            let totalElapsed = taskSummaries.reduce(0) { $0 + $1.elapsed }
            days.append(StudyCalendarDay(
                date: cursor,
                totalElapsed: totalElapsed,
                intensity: intensity(for: totalElapsed),
                tasks: taskSummaries))

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        let earliestDate = earliestActivityDate(in: snapshot, calendar: calendar)
        let currentStreak = currentStreak(
            snapshot: snapshot,
            now: now,
            calendar: calendar,
            earliestDate: earliestDate)
        let longestVisibleStreak = longestStreak(in: days)

        return StudyCalendarReport(
            startDate: startDate,
            endDate: periodEnd,
            days: days,
            currentStreak: currentStreak,
            longestVisibleStreak: longestVisibleStreak)
    }

    // Clock-only refresh of the App's 12-month report. Metadata/snapshot changes use calculate.
    static func advancingToday(
        in report: StudyCalendarReport,
        snapshot: TimerSnapshot,
        now: Date,
        calendar: Calendar
    ) -> StudyCalendarReport {
        guard let previousDay = report.days.last else { return report }
        let today = calendar.startOfDay(for: now)
        if today != report.endDate {
            let tasks = previousDay.tasks.enumerated().map { index, task in
                StudyCalendarTaskInput(
                    id: task.id, name: task.name, isArchived: task.isArchived, sortOrder: index)
            }
            return calculate(tasks: tasks, snapshot: snapshot, now: now, calendar: calendar)
        }
        let tasks = previousDay.tasks.map { task in
            StudyCalendarTaskSummary(
                id: task.id, name: task.name, isArchived: task.isArchived,
                elapsed: snapshot.elapsed(taskID: task.id, on: today, calendar: calendar, now: now))
        }
        guard tasks != previousDay.tasks else { return report }
        let total = tasks.reduce(0) { $0 + $1.elapsed }
        var days = report.days
        days[days.count - 1] = StudyCalendarDay(
            date: today, totalElapsed: total, intensity: intensity(for: total), tasks: tasks)
        let activityChanged = (previousDay.totalElapsed > 0) != (total > 0)
        return StudyCalendarReport(
            startDate: report.startDate, endDate: today, days: days,
            currentStreak: activityChanged
                ? currentStreak(snapshot: snapshot, now: now, calendar: calendar,
                                earliestDate: earliestActivityDate(in: snapshot, calendar: calendar))
                : report.currentStreak,
            longestVisibleStreak: activityChanged ? longestStreak(in: days) : report.longestVisibleStreak)
    }

    private static func intensity(for totalElapsed: TimeInterval) -> StudyCalendarIntensity {
        switch totalElapsed {
        case ...0:
            return .empty
        case ..<1_800:
            return .light
        case ..<3_600:
            return .medium
        case ..<7_200:
            return .strong
        default:
            return .veryStrong
        }
    }

    private static func earliestActivityDate(
        in snapshot: TimerSnapshot,
        calendar: Calendar
    ) -> Date? {
        let intervalStart = snapshot.intervals.map(\.start).min()
        let activeStart = snapshot.activeStartedAt
        guard let earliest = [intervalStart, activeStart].compactMap({ $0 }).min() else {
            return nil
        }
        return calendar.startOfDay(for: earliest)
    }

    private static func currentStreak(
        snapshot: TimerSnapshot,
        now: Date,
        calendar: Calendar,
        earliestDate: Date?
    ) -> Int {
        guard let earliestDate else { return 0 }

        let today = calendar.startOfDay(for: now)
        let todayElapsed = snapshot.totalElapsed(on: today, calendar: calendar, now: now)
        var cursor = todayElapsed > 0
            ? today
            : calendar.date(byAdding: .day, value: -1, to: today)
        var streak = 0
        while let date = cursor, date >= earliestDate {
            if snapshot.totalElapsed(on: date, calendar: calendar, now: now) <= 0 {
                break
            }
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: date)
        }
        return streak
    }

    private static func longestStreak(in days: [StudyCalendarDay]) -> Int {
        var longest = 0
        var current = 0
        for day in days {
            if day.totalElapsed > 0 {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        return longest
    }
}

private extension TimerSnapshot {
    func totalElapsed(on day: Date, calendar: Calendar, now: Date) -> TimeInterval {
        var taskIDs = Set(intervals.map(\.taskID))
        if let activeTaskID {
            taskIDs.insert(activeTaskID)
        }
        return taskIDs.reduce(0) { total, taskID in
            total + elapsed(taskID: taskID, on: day, calendar: calendar, now: now)
        }
    }
}
