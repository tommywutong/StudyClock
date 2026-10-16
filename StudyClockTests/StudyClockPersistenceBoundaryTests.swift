import Foundation
import SwiftData
import Testing
@testable import StudyClock

@MainActor
struct StudyClockPersistenceBoundaryTests {
    @Test func upgradingPreArchiveSchemaPreservesTaskAndEvents() throws {
        let url = temporaryURL("legacy-schema")
        let taskID = UUID()
        let start = TimerActionValue.start(taskID, at: Date(timeIntervalSince1970: 1_000), device: "fixture")
        let pause = TimerActionValue.pause(taskID, at: Date(timeIntervalSince1970: 1_600), device: "fixture")
        try writeLegacyStore(url: url, taskID: taskID, actions: [start, pause])

        let store = try StudyStore.makePersistent(at: url)
        let task = try #require(store.tasks(includeArchived: true).first)
        #expect(task.id == taskID)
        #expect(task.name == "既有任务")
        #expect(task.dailyGoalSeconds == 2_400)
        #expect(task.sortOrder == 17)
        #expect(!task.isArchived)
        let snapshot = try store.snapshot()
        #expect(snapshot.intervals == [TimerInterval(taskID: taskID, start: start.happenedAt, end: pause.happenedAt)])
        let schema = Schema([StudyTaskRecord.self, TimerActionRecord.self])
        let configuration = ModelConfiguration(nil, schema: schema, url: url, cloudKitDatabase: .none)
        let reopened = try ModelContainer(for: schema, configurations: configuration)
        let records = try ModelContext(reopened).fetch(FetchDescriptor<TimerActionRecord>())
        #expect(Set(records.map(\.id)) == Set([start.id, pause.id]))
    }

    @Test(arguments: FailedMutation.allCases)
    func failedTaskSaveRestoresReadableTaskState(_ mutation: FailedMutation) throws {
        let url = temporaryURL("save-failure")
        let writable = try StudyStore.makePersistent(at: url)
        try writable.seedDefaultsIfNeeded()
        let taskID = try #require(writable.tasks().first?.id)
        if mutation == .restore { try writable.archiveTask(id: taskID) }
        let schema = Schema([StudyTaskRecord.self, TimerActionRecord.self])
        let configuration = ModelConfiguration(
            nil, schema: schema, url: url, allowsSave: false, cloudKitDatabase: .none)
        let store = StudyStore(container: try ModelContainer(for: schema, configurations: configuration))
        let task = try #require(store.tasks(includeArchived: true).first(where: { $0.id == taskID }))
        let before = try store.tasks(includeArchived: true).map(TaskMetadata.init)
        let orderedIDs = try store.tasks().map(\.id)
        var failed = false
        do {
            switch mutation {
            case .create:
                _ = try store.createTask(name: "失败请求", dailyGoalSeconds: 600)
            case .edit:
                try store.updateTask(id: task.id, name: "失败请求", dailyGoalSeconds: 600)
            case .archive:
                try store.archiveTask(id: task.id)
            case .restore:
                try store.restoreTask(id: task.id)
            case .reorder:
                try store.reorderTasks(Array(orderedIDs.reversed()))
            }
        } catch { failed = true }
        #expect(failed)
        let after = try store.tasks(includeArchived: true).map(TaskMetadata.init)
        #expect(after == before)
    }

    @Test func cachedStoreRejectsTimerActionAfterAnotherStoreArchivesTask() throws {
        let url = temporaryURL("stale-archive")
        let cachedStore = try StudyStore.makePersistent(at: url)
        try cachedStore.seedDefaultsIfNeeded()
        let task = try #require(cachedStore.tasks().first)
        try StudyStore.makePersistent(at: url).archiveTask(id: task.id)
        var rejected = false
        do {
            try cachedStore.start(taskID: task.id, at: Date(timeIntervalSince1970: 1_000))
        } catch StudyStoreError.archivedTaskUnavailable { rejected = true }
        #expect(rejected)
        #expect(try StudyStore.makePersistent(at: url).snapshot().activeTaskID == nil)
    }

    private func temporaryURL(_ label: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("StudyClock-boundary-\(label)-\(UUID()).store")
    }

    private func writeLegacyStore(url: URL, taskID: UUID, actions: [TimerActionValue]) throws {
        let schema = Schema([PreArchiveSchema.StudyTaskRecord.self, TimerActionRecord.self])
        let configuration = ModelConfiguration(nil, schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)
        context.insert(PreArchiveSchema.StudyTaskRecord(
            id: taskID, name: "既有任务", dailyGoalSeconds: 2_400, sortOrder: 17))
        for action in actions { context.insert(TimerActionRecord(action: action)) }
        try context.save()
    }

}

enum FailedMutation: CaseIterable, Sendable {
    case create, edit, archive, restore, reorder
}

private struct TaskMetadata: Equatable {
    let id: UUID
    let name: String
    let goal: Int
    let order: Int
    let archived: Bool

    init(_ task: StudyTaskRecord) {
        id = task.id
        name = task.name
        goal = task.dailyGoalSeconds
        order = task.sortOrder
        archived = task.isArchived
    }
}

private enum PreArchiveSchema {
    @Model
    final class StudyTaskRecord {
        var id: UUID
        var name: String
        var dailyGoalSeconds: Int
        var sortOrder: Int

        init(id: UUID, name: String, dailyGoalSeconds: Int, sortOrder: Int) {
            self.id = id
            self.name = name
            self.dailyGoalSeconds = dailyGoalSeconds
            self.sortOrder = sortOrder
        }
    }
}
