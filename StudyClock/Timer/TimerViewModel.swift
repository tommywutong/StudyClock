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
        return tasks.reduce(0) { total, task in
            total + snapshot.elapsed(taskID: task.id, on: day, calendar: calendar, now: now)
        }
    }

    func historyDays(now: Date = .now) -> [StudyDaySummary] {
        guard let store else { return [] }
        do {
            return try store.historyDays(through: now, calendar: calendar).map { day in
                let total = tasks.reduce(0) { partial, task in
                    partial + snapshot.elapsed(taskID: task.id, on: day, calendar: calendar, now: now)
                }
                let target = tasks.reduce(0) { partial, task in
                    partial + TimeInterval(task.dailyGoalSeconds)
                }
                return StudyDaySummary(date: day, total: total, target: target)
            }
        } catch {
            errorMessage = error.localizedDescription
            return []
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
            tasks = try store.tasks()
            snapshot = try store.snapshot(now: now, calendar: calendar)
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