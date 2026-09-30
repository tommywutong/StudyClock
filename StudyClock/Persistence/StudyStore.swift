import Foundation
import SwiftData

enum StudyStoreLocation {
    case legacyDefault
    case appGroup(URL)
    case explicit(URL)
}

enum StudyStoreError: LocalizedError {
    case requiresAppLaunch
    case appGroupUnavailable

    var errorDescription: String? {
        switch self {
        case .requiresAppLaunch:
            "请先打开 StudyClock 以迁移学习记录。"
        case .appGroupUnavailable:
            "无法访问 StudyClock 的共享存储。"
        }
    }
}

@MainActor
final class StudyStore {
    static let appGroupIdentifier = "group.com.tommywu.StudyClock"
    static let widgetKind = "StudyClockWidget"
    static let widgetDataDidChangeNotification = Notification.Name(
        "com.tommywu.StudyClock.widgetDataDidChange")
    static let widgetStatusMessageKey = "StudyClockWidget.statusMessage"

    private static let migrationVersion = 1
    private static let migrationVersionKey = "StudyClock.sharedStoreMigrationVersion"

    private let context: ModelContext

    private static let defaultTasks: [(UUID, String, Int)] = [
        (UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!, "八股", 10_800),
        (UUID(uuidString: "A0000000-0000-4000-8000-000000000002")!, "算法", 7_200),
        (UUID(uuidString: "A0000000-0000-4000-8000-000000000003")!, "项目整理", 7_200)
    ]

    init(container: ModelContainer) {
        context = ModelContext(container)
    }

    static func makeInMemory() throws -> StudyStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("StudyClock-\(UUID().uuidString).store")
        return try makeStore(at: .explicit(url), inMemory: true)
    }

    static func makePersistent(at url: URL) throws -> StudyStore {
        try makeStore(at: .explicit(url))
    }

    static func makeApplicationStore() throws -> StudyStore {
        let shared = try makeStore(at: .appGroup(appGroupStoreURL()))
        let defaults = try appGroupDefaults()

        if defaults.object(forKey: migrationVersionKey) == nil {
            let legacy = try makeStore(at: .legacyDefault)
            try migrateLegacyDataIfNeeded(from: legacy, to: shared)
            defaults.set(migrationVersion, forKey: migrationVersionKey)
        }

        return shared
    }

    static func makeWidgetStore() throws -> StudyStore {
        let defaults = try appGroupDefaults()
        guard defaults.integer(forKey: migrationVersionKey) == migrationVersion else {
            throw StudyStoreError.requiresAppLaunch
        }
        return try makeStore(at: .appGroup(appGroupStoreURL()))
    }

    static func migrateLegacyDataIfNeeded(from legacy: StudyStore, to shared: StudyStore) throws {
        var sharedTasksByID: [UUID: StudyTaskRecord] = [:]
        for task in try shared.tasks() {
            sharedTasksByID[task.id] = task
        }

        for legacyTask in try legacy.tasks() {
            if let sharedTask = sharedTasksByID[legacyTask.id] {
                sharedTask.name = legacyTask.name
                sharedTask.dailyGoalSeconds = legacyTask.dailyGoalSeconds
                sharedTask.sortOrder = legacyTask.sortOrder
            } else {
                shared.context.insert(StudyTaskRecord(
                    id: legacyTask.id,
                    name: legacyTask.name,
                    dailyGoalSeconds: legacyTask.dailyGoalSeconds,
                    sortOrder: legacyTask.sortOrder))
            }
        }
        try shared.context.save()

        var sharedActionIDs = Set(try shared.actionRecords().map(\.id))
        for legacyAction in try legacy.actionRecords() where sharedActionIDs.insert(legacyAction.id).inserted {
            shared.context.insert(TimerActionRecord(
                id: legacyAction.id,
                kind: legacyAction.kind,
                taskID: legacyAction.taskID,
                happenedAt: legacyAction.happenedAt,
                deviceID: legacyAction.deviceID,
                observedActionID: legacyAction.observedActionID))
        }
        try shared.context.save()
    }

    func seedDefaultsIfNeeded() throws {
        let existingIDs = Set(try context.fetch(FetchDescriptor<StudyTaskRecord>()).map(\.id))
        for (index, task) in Self.defaultTasks.enumerated() where !existingIDs.contains(task.0) {
            context.insert(StudyTaskRecord(
                id: task.0, name: task.1, dailyGoalSeconds: task.2, sortOrder: index))
        }
        try context.save()
    }

    func tasks() throws -> [StudyTaskRecord] {
        let descriptor = FetchDescriptor<StudyTaskRecord>(
            sortBy: [SortDescriptor(\StudyTaskRecord.sortOrder), SortDescriptor(\StudyTaskRecord.id)])
        return try context.fetch(descriptor)
    }

    func start(taskID: UUID, at date: Date = .now) throws {
        try append(.start, taskID: taskID, at: date, device: "local")
    }

    func pause(taskID: UUID, at date: Date = .now) throws {
        try append(.pause, taskID: taskID, at: date, device: "local")
    }

    func toggle(taskID: UUID, at date: Date = .now) throws {
        let currentSnapshot = try snapshot(now: date)
        let kind: TimerActionValue.Kind = currentSnapshot.activeTaskID == taskID ? .pause : .start
        try append(kind, taskID: taskID, at: date, device: "local")
    }

    func snapshot(now _: Date = .now, calendar _: Calendar = .current) throws -> TimerSnapshot {
        TimerReducer.reduce(try actionRecords().compactMap(\.actionValue))
    }

    func widgetState(
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> StudyTimerWidgetState {
        let orderedTasks = try tasks()
        let actions = try actionRecords()
        let currentSnapshot = TimerReducer.reduce(actions.compactMap(\.actionValue))
        let day = calendar.startOfDay(for: now)

        return StudyTimerWidgetState(
            tasks: orderedTasks.map { task in
                StudyTimerWidgetTask(
                    id: task.id,
                    name: task.name,
                    elapsed: currentSnapshot.elapsed(
                        taskID: task.id, on: day, calendar: calendar, now: now),
                    target: TimeInterval(task.dailyGoalSeconds))
            },
            activeTaskID: currentSnapshot.activeTaskID,
            activeStartedAt: currentSnapshot.activeStartedAt,
            lastTouchedTaskID: lastTouchedTaskID(in: actions),
            now: now,
            statusMessage: Self.widgetStatusMessage())
    }

    func lastTouchedTaskID() throws -> UUID? {
        lastTouchedTaskID(in: try actionRecords())
    }

    func progress(for task: StudyTaskRecord, day: Date, now: Date = .now, calendar: Calendar = .current) throws -> TaskProgress {
        let elapsed = try snapshot(now: now, calendar: calendar).elapsed(
            taskID: task.id, on: day, calendar: calendar, now: now)
        return TaskProgress(elapsed: elapsed, target: TimeInterval(task.dailyGoalSeconds))
    }

    func totalElapsed(on day: Date, now: Date = .now, calendar: Calendar = .current) throws -> TimeInterval {
        let snapshot = try snapshot(now: now, calendar: calendar)
        return try tasks().reduce(0) { total, task in
            total + snapshot.elapsed(taskID: task.id, on: day, calendar: calendar, now: now)
        }
    }

    func historyDays(through date: Date = .now, calendar: Calendar = .current) throws -> [Date] {
        let actionRecords = try actionRecords()
        let today = calendar.startOfDay(for: date)
        guard let earliest = actionRecords.map(\.happenedAt).min() else { return [] }
        let firstDay = calendar.startOfDay(for: earliest)
        var days: [Date] = []
        var cursor = today
        while cursor >= firstDay {
            days.append(cursor)
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return days
    }

    func updateTask(id: UUID, name: String, dailyGoalSeconds: Int) throws {
        let descriptor = FetchDescriptor<StudyTaskRecord>(predicate: #Predicate { $0.id == id })
        guard let task = try context.fetch(descriptor).first else { return }
        task.name = name
        task.dailyGoalSeconds = max(dailyGoalSeconds, 0)
        try context.save()
    }

    private static func makeStore(
        at location: StudyStoreLocation,
        inMemory: Bool = false
    ) throws -> StudyStore {
        switch location {
        case .legacyDefault:
            let configuration = ModelConfiguration(
                schema: Schema([StudyTaskRecord.self, TimerActionRecord.self]),
                cloudKitDatabase: .none)
            return StudyStore(container: try makeContainer(configuration: configuration))

        case .appGroup(let url):
            return StudyStore(container: try makeContainer(at: url, inMemory: inMemory))

        case .explicit(let url):
            return StudyStore(container: try makeContainer(at: url, inMemory: inMemory))
        }
    }

    private static func makeContainer(at url: URL, inMemory: Bool = false) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(
                schema: Schema([StudyTaskRecord.self, TimerActionRecord.self]),
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(
                nil,
                schema: Schema([StudyTaskRecord.self, TimerActionRecord.self]),
                url: url,
                cloudKitDatabase: .none)
        }
        return try makeContainer(configuration: configuration)
    }

    private static func makeContainer(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(
            for: StudyTaskRecord.self, TimerActionRecord.self,
            configurations: configuration)
    }

    private static func appGroupStoreURL() throws -> URL {
        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw StudyStoreError.appGroupUnavailable
        }

        let directory = containerURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("StudyClock.store")
    }

    private static func appGroupDefaults() throws -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            throw StudyStoreError.appGroupUnavailable
        }
        return defaults
    }

    private static func widgetStatusMessage() -> String? {
        UserDefaults(suiteName: appGroupIdentifier)?
            .string(forKey: widgetStatusMessageKey)
    }

    private func append(
        _ kind: TimerActionValue.Kind,
        taskID: UUID,
        at date: Date,
        device: String
    ) throws {
        let action = TimerActionValue(
            id: UUID(),
            kind: kind,
            taskID: taskID,
            happenedAt: date,
            deviceID: device,
            observedActionID: try latestActionID())
        context.insert(TimerActionRecord(action: action))
        try context.save()
    }

    private func actionRecords() throws -> [TimerActionRecord] {
        try context.fetch(FetchDescriptor<TimerActionRecord>())
    }

    private func lastTouchedTaskID(in actions: [TimerActionRecord]) -> UUID? {
        TimerReducer.acceptedActions(actions.compactMap(\.actionValue)).last?.taskID
    }

    private func latestActionID() throws -> UUID? {
        latestAction(in: try actionRecords())?.id
    }

    private func latestAction(in actions: [TimerActionRecord]) -> TimerActionRecord? {
        actions.max { lhs, rhs in
            if lhs.happenedAt != rhs.happenedAt {
                return lhs.happenedAt < rhs.happenedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
