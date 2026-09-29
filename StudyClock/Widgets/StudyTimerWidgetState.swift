import Foundation
import WidgetKit

struct StudyTimerWidgetTask: Equatable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let elapsed: TimeInterval
    let target: TimeInterval
}

struct StudyTimerWidgetState: Equatable, Sendable {
    let tasks: [StudyTimerWidgetTask]
    let activeTaskID: UUID?
    let activeStartedAt: Date?
    let lastTouchedTaskID: UUID?
    let now: Date
    let statusMessage: String?
}

struct StudyTimerWidgetEntryState: TimelineEntry, Equatable {
    let date: Date
    let tasks: [StudyTimerWidgetTask]
    let displayedTaskID: UUID?
    let isRunning: Bool
    let elapsedReferenceDate: Date?
    let totalElapsed: TimeInterval
    let statusMessage: String?
}

extension StudyTimerWidgetEntryState {
    var displayedTask: StudyTimerWidgetTask? {
        displayedTaskID.flatMap { taskID in
            tasks.first { $0.id == taskID }
        }
    }

    var usesEmptyState: Bool {
        statusMessage == nil && displayedTask == nil
    }

    var displayTasks: [StudyTimerWidgetTask] {
        guard let displayedTask else { return tasks }
        return [displayedTask] + tasks.filter { $0.id != displayedTask.id }
    }
}

enum StudyTimerWidgetEntryFactory {
    static func unavailable(now: Date) -> StudyTimerWidgetEntryState {
        StudyTimerWidgetEntryState(
            date: now,
            tasks: [],
            displayedTaskID: nil,
            isRunning: false,
            elapsedReferenceDate: nil,
            totalElapsed: 0,
            statusMessage: "无法读取学习计时，请打开 App")
    }
}

enum StudyTimerWidgetElapsedTimeFormatter {
    static func string(for elapsed: TimeInterval) -> String {
        guard elapsed.isFinite, elapsed > 0 else { return "00:00:00" }

        let totalSeconds = Int(elapsed)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds / 60) % 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

extension StudyTimerWidgetState {
    func makeEntry(calendar: Calendar) -> StudyTimerWidgetEntryState {
        let activeTask = activeTaskID.flatMap { taskID in
            tasks.first { $0.id == taskID }
        }
        let isRunning = activeTask != nil && activeStartedAt != nil
        let elapsedReferenceDate = activeTask.flatMap { task in
            activeStartedAt == nil ? nil : now.addingTimeInterval(-task.elapsed)
        }

        return StudyTimerWidgetEntryState(
            date: now,
            tasks: tasks,
            displayedTaskID: activeTaskID ?? lastTouchedTaskID,
            isRunning: isRunning,
            elapsedReferenceDate: elapsedReferenceDate,
            totalElapsed: tasks.reduce(0) { $0 + $1.elapsed },
            statusMessage: statusMessage)
    }

    func nextRefreshDate(calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
    }
}
