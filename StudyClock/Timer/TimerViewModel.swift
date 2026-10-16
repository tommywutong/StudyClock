import Foundation
import Observation
#if canImport(WidgetKit)
import WidgetKit

protocol StudyClockWidgetReloading {
    func reloadTimelines()
}

struct StudyClockWidgetReloader: StudyClockWidgetReloading {
    func reloadTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: StudyStore.widgetKind)
    }
}
#endif

struct StudyDaySummary: Identifiable {
    let date: Date
    let total: TimeInterval
    let target: TimeInterval

    var id: Date { date }
}

@MainActor
@Observable
final class TimerViewModel {

    #if os(macOS)
    private var externalChangeObserver: NSObjectProtocol?
    #endif
    private let store: StudyStore?
    private let reloader: any StudyClockWidgetReloading

    private(set) var tasks: [StudyTaskRecord] = []
    private(set) var historicalTasks: [StudyTaskRecord] = []

    var archivedTasks: [StudyTaskRecord] {
        historicalTasks.filter(\.isArchived)
    }

    var studyStatisticsTasks: [StudyStatisticsTaskInput] {
        historicalTasks.map { task in
            StudyStatisticsTaskInput(
                id: task.id,
                name: task.name,
                dailyGoalSeconds: task.dailyGoalSeconds,
                sortOrder: task.sortOrder,
                isArchived: task.isArchived)
        }
    }
    private(set) var snapshot = TimerSnapshot(
        intervals: [], activeTaskID: nil, activeStartedAt: nil, conflictingActionIDs: [])
    private(set) var initializationError: String?
    private(set) var errorMessage: String?
    var calendar = Calendar.current

    init(
        makeApplicationStore: () throws -> StudyStore,
        reloader: (any StudyClockWidgetReloading)? = nil
    ) {
        self.reloader = reloader ?? StudyClockWidgetReloader()
        do {
            store = try makeApplicationStore()
        } catch {
            store = nil
            initializationError = error.localizedDescription
        }
        #if os(macOS)
        externalChangeObserver = DistributedNotificationCenter.default().addObserver(
            forName: StudyStore.widgetDataDidChangeNotification,
            object: nil,
            queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshFromExternalStore()
                }
            }
        #endif
        reload()
    }
    #if os(macOS)
    isolated deinit {
        if let externalChangeObserver {
            DistributedNotificationCenter.default().removeObserver(externalChangeObserver)
        }
    }
    #endif

    convenience init(
        store: StudyStore? = nil,
        reloader: (any StudyClockWidgetReloading)? = nil
    ) {
        self.init(makeApplicationStore: {
            if let store { return store }
            return try StudyStore.makeApplicationStore()
        }, reloader: reloader)
    }

    var activeTask: StudyTaskRecord? {
        guard let activeTaskID = snapshot.activeTaskID else { return nil }
        return tasks.first { $0.id == activeTaskID }
    }

    func toggle(taskID: UUID, at date: Date = .now) {
        guard let store else { return }
        do {
            try store.toggle(taskID: taskID, at: date)
            if reload(now: date) {
                reloader.reloadTimelines()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func progress(for task: StudyTaskRecord, now: Date) -> TaskProgress {
        let elapsed = snapshot.elapsed(
            taskID: task.id, on: calendar.startOfDay(for: now), calendar: calendar, now: now)
        return TaskProgress(elapsed: elapsed, target: TimeInterval(task.dailyGoalSeconds))
    }

    func totalElapsed(now: Date) -> TimeInterval {
        let day = calendar.startOfDay(for: now)
        return historicalTasks.reduce(0) { total, task in
            total + snapshot.elapsed(taskID: task.id, on: day, calendar: calendar, now: now)
        }
    }

    func historyDays(now: Date = .now) -> [StudyDaySummary] {
        guard let store else { return [] }
        do {
            return try store.historyDays(through: now, calendar: calendar).map { day in
                let total = historicalTasks.reduce(0) { partial, task in
                    partial + snapshot.elapsed(taskID: task.id, on: day, calendar: calendar, now: now)
                }
                let target = historicalTasks.reduce(0) { partial, task in
                    partial + TimeInterval(task.dailyGoalSeconds)
                }
                return StudyDaySummary(date: day, total: total, target: target)
            }
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func studyCalendar(now: Date, calendar: Calendar) -> StudyCalendarReport {
        StudyCalendarCalculator.calculate(
            tasks: historicalTasks.map { task in
                StudyCalendarTaskInput(
                    id: task.id,
                    name: task.name,
                    isArchived: task.isArchived,
                    sortOrder: task.sortOrder)
            },
            snapshot: snapshot,
            now: now,
            calendar: calendar)
    }

    func studyStatistics(
        for period: StudyStatisticsPeriod,
        now: Date,
        calendar: Calendar
    ) -> StudyStatisticsReport {
        return StudyStatisticsCalculator.calculate(
            tasks: studyStatisticsTasks,
            snapshot: snapshot,
            period: period,
            now: now,
            calendar: calendar)
    }

    func addTask(name: String, dailyGoalSeconds: Int) {
        guard let store else { return }
        do {
            _ = try store.createTask(name: name, dailyGoalSeconds: dailyGoalSeconds)
            if reload() {
                reloader.reloadTimelines()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func archiveTask(id: UUID) {
        guard let store else { return }
        do {
            try store.archiveTask(id: id)
            if reload() {
                reloader.reloadTimelines()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restoreTask(id: UUID) {
        guard let store else { return }
        do {
            try store.restoreTask(id: id)
            if reload() {
                reloader.reloadTimelines()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveTasks(from source: IndexSet, to destination: Int) {
        guard let store, !source.isEmpty else { return }
        var reorderedTasks = tasks
        let movedTasks = source.sorted().map { reorderedTasks[$0] }
        for index in source.sorted(by: >) {
            reorderedTasks.remove(at: index)
        }
        let adjustment = source.filter { $0 < destination }.count
        let insertionIndex = min(max(destination - adjustment, 0), reorderedTasks.count)
        reorderedTasks.insert(contentsOf: movedTasks, at: insertionIndex)

        do {
            try store.reorderTasks(reorderedTasks.map(\.id))
            if reload() {
                reloader.reloadTimelines()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateTask(id: UUID, name: String, dailyGoalSeconds: Int) {
        guard let store else { return }
        do {
            try store.updateTask(id: id, name: name, dailyGoalSeconds: dailyGoalSeconds)
            if reload() {
                reloader.reloadTimelines()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    @discardableResult
    func reload(now: Date = .now) -> Bool {
        calendar = Calendar.current
        guard let store else { return false }
        do {
            try store.seedDefaultsIfNeeded()
            let activeTasks = try store.tasks()
            let allTasks = try store.tasks(includeArchived: true)
            let currentSnapshot = try store.snapshot(now: now, calendar: calendar)
            tasks = activeTasks
            historicalTasks = allTasks
            snapshot = currentSnapshot
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func refreshFromExternalStore(now: Date = .now) -> Bool {
        reload(now: now)
    }
}