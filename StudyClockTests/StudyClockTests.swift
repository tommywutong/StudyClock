//
//  StudyClockTests.swift
//  StudyClockTests
//
//  Created by 吴桐 on 2026/9/27.
//

import Foundation
import SwiftData
import Testing
@testable import StudyClock

struct StudyClockTests {
    private var utcCalendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func temporaryStoreURL(_ label: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "StudyClockTests-\(label)-\(UUID().uuidString).store")
    }

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    @Test func switchingTasksStopsPreviousAndKeepsEachDuration() {
        let taskA = UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!
        let taskB = UUID(uuidString: "B0000000-0000-4000-8000-000000000002")!
        let startA = Date(timeIntervalSince1970: 32_400)
        let startB = Date(timeIntervalSince1970: 34_200)
        let pauseB = Date(timeIntervalSince1970: 35_400)
        let now = Date(timeIntervalSince1970: 36_000)

        let snapshot = TimerReducer.reduce([
            .start(taskA, at: startA, device: "mac"),
            .start(taskB, at: startB, device: "mac"),
            .pause(taskB, at: pauseB, device: "mac")
        ])
        let day = calendar.startOfDay(for: startA)

        #expect(snapshot.elapsed(taskID: taskA, on: day, calendar: calendar, now: now) == 1_800)
        #expect(snapshot.elapsed(taskID: taskB, on: day, calendar: calendar, now: now) == 1_200)
        #expect(snapshot.activeTaskID == nil)
    }

    @Test func startingAlreadyActiveTaskDoesNotResetItsElapsedTime() {
        let task = UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!
        let start = Date(timeIntervalSince1970: 32_400)
        let repeatedStart = Date(timeIntervalSince1970: 33_000)
        let pause = Date(timeIntervalSince1970: 33_600)
        let calendar = self.calendar

        let snapshot = TimerReducer.reduce([
            .start(task, at: start, device: "mac"),
            .start(task, at: repeatedStart, device: "mac"),
            .pause(task, at: pause, device: "mac")
        ])

        #expect(snapshot.elapsed(taskID: task, on: calendar.startOfDay(for: start), calendar: calendar, now: pause) == 1_200)
    }

    @MainActor
    @Test func storeSeedsThreeTasksAndPersistsTimerActions() throws {
        let store = try StudyStore.makeInMemory()
        try store.seedDefaultsIfNeeded()
        let tasks = try store.tasks()

        #expect(tasks.map(\.name) == ["八股", "算法", "项目整理"])
        #expect(tasks.map(\.dailyGoalSeconds) == [10_800, 7_200, 7_200])

        let startA = Date(timeIntervalSince1970: 32_400)
        let startB = Date(timeIntervalSince1970: 34_200)
        let pauseB = Date(timeIntervalSince1970: 35_400)
        try store.start(taskID: tasks[0].id, at: startA)
        try store.start(taskID: tasks[1].id, at: startB)
        try store.pause(taskID: tasks[1].id, at: pauseB)

        let today = calendar.startOfDay(for: startA)
        let snapshot = try store.snapshot(now: Date(timeIntervalSince1970: 36_000), calendar: calendar)
        #expect(snapshot.elapsed(taskID: tasks[0].id, on: today, calendar: calendar, now: pauseB) == 1_800)
        #expect(snapshot.elapsed(taskID: tasks[1].id, on: today, calendar: calendar, now: pauseB) == 1_200)
        #expect(snapshot.activeTaskID == nil)
    }

    @MainActor
    @Test func emptyHistoryHasNoDays() throws {
        let store = try StudyStore.makeInMemory()
        try store.seedDefaultsIfNeeded()

        #expect(try store.historyDays(through: Date(timeIntervalSince1970: 36_000), calendar: calendar).isEmpty)
    }

    @MainActor
    @Test func historyIncludesEmptyLocalDaysBetweenSessions() throws {
        let store = try StudyStore.makeInMemory()
        try store.seedDefaultsIfNeeded()
        let task = try #require(store.tasks().first)
        let firstStart = Date(timeIntervalSince1970: 32_400)
        let firstPause = Date(timeIntervalSince1970: 33_000)
        let thirdStart = Date(timeIntervalSince1970: 205_200)
        let thirdPause = Date(timeIntervalSince1970: 205_800)
        try store.start(taskID: task.id, at: firstStart)
        try store.pause(taskID: task.id, at: firstPause)
        try store.start(taskID: task.id, at: thirdStart)
        try store.pause(taskID: task.id, at: thirdPause)

        let days = try store.historyDays(through: thirdPause, calendar: calendar)
        let emptyDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: firstStart))!

        #expect(days == [calendar.startOfDay(for: thirdStart), emptyDay, calendar.startOfDay(for: firstStart)])
        #expect(try store.progress(for: task, day: emptyDay, now: thirdPause, calendar: calendar).elapsed == 0)
    }

    @Test func sessionCrossingMidnightContributesToBothLocalDays() {
        let task = UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!
        let start = Date(timeIntervalSince1970: 86_340)
        let pause = Date(timeIntervalSince1970: 86_460)
        let calendar = self.calendar
        let snapshot = TimerReducer.reduce([
            .start(task, at: start, device: "mac"),
            .pause(task, at: pause, device: "mac")
        ])
        let firstDay = calendar.startOfDay(for: start)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: firstDay)!

        #expect(snapshot.elapsed(taskID: task, on: firstDay, calendar: calendar, now: pause) == 60)
        #expect(snapshot.elapsed(taskID: task, on: nextDay, calendar: calendar, now: pause) == 60)
    }

    @MainActor
    @Test func migrationCopiesHistoryOnceAndPreservesRunningTask() throws {
        let legacy = try StudyStore.makePersistent(at: temporaryStoreURL("legacy"))
        let shared = try StudyStore.makePersistent(at: temporaryStoreURL("shared"))
        try legacy.seedDefaultsIfNeeded()
        let tasks = try legacy.tasks()
        try legacy.updateTask(id: tasks[0].id, name: "系统设计", dailyGoalSeconds: 9_000)
        try legacy.start(taskID: tasks[0].id, at: Date(timeIntervalSince1970: 86_340))
        try legacy.pause(taskID: tasks[0].id, at: Date(timeIntervalSince1970: 86_460))
        try legacy.start(taskID: tasks[1].id, at: Date(timeIntervalSince1970: 86_500))

        let now = Date(timeIntervalSince1970: 86_600)
        let day = utcCalendar.startOfDay(for: now)
        try StudyStore.migrateLegacyDataIfNeeded(from: legacy, to: shared)
        let firstTotal = try shared.totalElapsed(on: day, now: now, calendar: utcCalendar)
        try StudyStore.migrateLegacyDataIfNeeded(from: legacy, to: shared)
        let secondTotal = try shared.totalElapsed(on: day, now: now, calendar: utcCalendar)

        let migratedTasks = try shared.tasks()
        let snapshot = try shared.snapshot(now: now, calendar: utcCalendar)
        #expect(migratedTasks[0].name == "系统设计")
        #expect(migratedTasks[0].dailyGoalSeconds == 9_000)
        #expect(migratedTasks[0].sortOrder == tasks[0].sortOrder)
        #expect(snapshot.activeTaskID == tasks[1].id)
        #expect(snapshot.elapsed(taskID: tasks[0].id, on: Date(timeIntervalSince1970: 0), calendar: utcCalendar, now: now) == 60)
        #expect(secondTotal == firstTotal)
    }

    @MainActor
    @Test func toggleUsesLatestStateForAnOutdatedWidgetTask() throws {
        let store = try StudyStore.makeInMemory()
        try store.seedDefaultsIfNeeded()
        let tasks = try store.tasks()
        try store.start(taskID: tasks[1].id, at: Date(timeIntervalSince1970: 1_000))
        try store.toggle(taskID: tasks[0].id, at: Date(timeIntervalSince1970: 1_100))
        #expect(try store.snapshot(now: Date(timeIntervalSince1970: 1_100), calendar: utcCalendar).activeTaskID == tasks[0].id)
    }

    @MainActor
    @Test func widgetStateReflectsTodayRunningTask() throws {
        let store = try StudyStore.makeInMemory()
        try store.seedDefaultsIfNeeded()
        let tasks = try store.tasks()
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let now = Date(timeIntervalSince1970: 1_100)
        try store.start(taskID: tasks[1].id, at: startedAt)

        let state = try store.widgetState(now: now, calendar: utcCalendar)

        #expect(state.tasks.map(\.id) == tasks.map(\.id))
        #expect(state.tasks[1].elapsed == 100)
        #expect(state.tasks[1].target == 7_200)
        #expect(state.activeTaskID == tasks[1].id)
        #expect(state.activeStartedAt == startedAt)
        #expect(state.lastTouchedTaskID == tasks[1].id)
        #expect(state.now == now)
    }

    @MainActor
    @Test func unavailableApplicationStoreKeepsInitializationErrorAndSkipsMutations() {
        let initializationError = StudyStoreError.appGroupUnavailable
        let model = TimerViewModel(makeApplicationStore: { throw initializationError })
        let taskID = UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!

        #expect(model.initializationError == initializationError.localizedDescription)
        model.reload(now: Date(timeIntervalSince1970: 1_000))
        model.toggle(taskID: taskID, at: Date(timeIntervalSince1970: 1_100))
        model.updateTask(id: taskID, name: "不应写入", dailyGoalSeconds: 1)

        #expect(model.initializationError == initializationError.localizedDescription)
        #expect(model.errorMessage == nil)
        #expect(model.tasks.isEmpty)
        #expect(model.snapshot.activeTaskID == nil)
    }

    @MainActor
    @Test func lastTouchedTaskIgnoresUnknownAndInvalidPause() throws {
        let taskA = UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!
        let taskB = UUID(uuidString: "B0000000-0000-4000-8000-000000000002")!
        let url = temporaryStoreURL("last-touched")
        let configuration = SwiftData.ModelConfiguration(
            nil,
            schema: SwiftData.Schema([StudyTaskRecord.self, TimerActionRecord.self]),
            url: url,
            cloudKitDatabase: .none)
        let container = try SwiftData.ModelContainer(
            for: StudyTaskRecord.self, TimerActionRecord.self,
            configurations: configuration)
        let context = SwiftData.ModelContext(container)
        context.insert(StudyTaskRecord(id: taskA, name: "八股", dailyGoalSeconds: 3_600, sortOrder: 0))
        context.insert(StudyTaskRecord(id: taskB, name: "算法", dailyGoalSeconds: 3_600, sortOrder: 1))
        context.insert(TimerActionRecord(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
            kind: "start",
            taskID: taskA,
            happenedAt: Date(timeIntervalSince1970: 1_000),
            deviceID: "mac",
            observedActionID: nil))
        context.insert(TimerActionRecord(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000002")!,
            kind: "pause",
            taskID: taskB,
            happenedAt: Date(timeIntervalSince1970: 1_100),
            deviceID: "mac",
            observedActionID: nil))
        context.insert(TimerActionRecord(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000003")!,
            kind: "unknown",
            taskID: taskB,
            happenedAt: Date(timeIntervalSince1970: 1_200),
            deviceID: "mac",
            observedActionID: nil))
        try context.save()

        let store = try StudyStore.makePersistent(at: url)
        let state = try store.widgetState(now: Date(timeIntervalSince1970: 1_300), calendar: utcCalendar)

        #expect(try store.lastTouchedTaskID() == taskA)
        #expect(state.lastTouchedTaskID == taskA)
    }

    @Test func runningWidgetEntryUsesCumulativeElapsedReferenceDate() {
        let now = Date(timeIntervalSince1970: 10_000)
        let task = StudyTimerWidgetTask(id: UUID(), name: "算法", elapsed: 3_600, target: 7_200)
        let state = StudyTimerWidgetState(
            tasks: [task],
            activeTaskID: task.id,
            activeStartedAt: now.addingTimeInterval(-600),
            lastTouchedTaskID: task.id,
            now: now,
            statusMessage: nil)

        let entry = state.makeEntry(calendar: utcCalendar)

        #expect(entry.isRunning)
        #expect(entry.displayedTaskID == task.id)
        #expect(entry.elapsedReferenceDate == now.addingTimeInterval(-3_600))
        #expect(entry.totalElapsed == 3_600)
    }

    @Test func widgetEntryRefreshesAtNextLocalMidnight() {
        let now = Date(timeIntervalSince1970: 86_399)
        let state = StudyTimerWidgetState(
            tasks: [],
            activeTaskID: nil,
            activeStartedAt: nil,
            lastTouchedTaskID: nil,
            now: now,
            statusMessage: nil)

        #expect(state.nextRefreshDate(calendar: utcCalendar) == Date(timeIntervalSince1970: 86_400))
    }

    @Test func pausedWidgetEntryUsesLastTouchedTaskWithoutReferenceDate() {
        let task = StudyTimerWidgetTask(id: UUID(), name: "算法", elapsed: 3_600, target: 7_200)
        let state = StudyTimerWidgetState(
            tasks: [task],
            activeTaskID: nil,
            activeStartedAt: nil,
            lastTouchedTaskID: task.id,
            now: Date(timeIntervalSince1970: 10_000),
            statusMessage: "无法更新，打开 App 重试")

        let entry = state.makeEntry(calendar: utcCalendar)

        #expect(entry.displayedTaskID == task.id)
        #expect(!entry.isRunning)
        #expect(entry.elapsedReferenceDate == nil)
        #expect(entry.statusMessage == "无法更新，打开 App 重试")
    }

    @Test func emptyWidgetEntryHasNoDisplayedTaskOrReferenceDate() {
        let state = StudyTimerWidgetState(
            tasks: [],
            activeTaskID: nil,
            activeStartedAt: nil,
            lastTouchedTaskID: nil,
            now: Date(timeIntervalSince1970: 10_000),
            statusMessage: nil)

        let entry = state.makeEntry(calendar: utcCalendar)

        #expect(entry.displayedTaskID == nil)
        #expect(entry.elapsedReferenceDate == nil)
        #expect(entry.totalElapsed == 0)
    }

    @Test func idleWidgetEntryUsesTotalWithoutDisplayTask() {
        let tasks = [
            StudyTimerWidgetTask(id: UUID(), name: "八股", elapsed: 600, target: 3_600),
            StudyTimerWidgetTask(id: UUID(), name: "算法", elapsed: 900, target: 7_200)
        ]
        let state = StudyTimerWidgetState(
            tasks: tasks,
            activeTaskID: nil,
            activeStartedAt: nil,
            lastTouchedTaskID: nil,
            now: Date(timeIntervalSince1970: 10_000),
            statusMessage: nil)

        let entry = state.makeEntry(calendar: utcCalendar)

        #expect(entry.displayedTaskID == nil)
        #expect(entry.elapsedReferenceDate == nil)
        #expect(entry.totalElapsed == 1_500)
    }

    @Test func widgetDisplayTasksMovesCurrentTaskToTheFirstCard() {
        let first = StudyTimerWidgetTask(id: UUID(), name: "八股", elapsed: 600, target: 3_600)
        let current = StudyTimerWidgetTask(id: UUID(), name: "算法", elapsed: 900, target: 7_200)
        let third = StudyTimerWidgetTask(id: UUID(), name: "项目", elapsed: 300, target: 7_200)
        let entry = StudyTimerWidgetEntryState(
            date: .now,
            tasks: [first, current, third],
            displayedTaskID: current.id,
            isRunning: true,
            elapsedReferenceDate: .now,
            totalElapsed: 1_800,
            statusMessage: nil)

        #expect(entry.displayTasks.map(\.id) == [current.id, first.id, third.id])
    }

    @Test func widgetElapsedLabelsAlwaysUseHoursMinutesAndSeconds() {
        #expect(StudyTimerWidgetElapsedTimeFormatter.string(for: 0) == "00:00:00")
        #expect(StudyTimerWidgetElapsedTimeFormatter.string(for: 4.9) == "00:00:04")
        #expect(StudyTimerWidgetElapsedTimeFormatter.string(for: 3_660) == "01:01:00")
        #expect(StudyTimerWidgetElapsedTimeFormatter.string(for: 90_000) == "25:00:00")
    }

    @Test func widgetEntryWithoutDisplayTaskUsesEmptyState() {
        let task = StudyTimerWidgetTask(id: UUID(), name: "八股", elapsed: 600, target: 3_600)
        let state = StudyTimerWidgetState(
            tasks: [task],
            activeTaskID: nil,
            activeStartedAt: nil,
            lastTouchedTaskID: nil,
            now: Date(timeIntervalSince1970: 10_000),
            statusMessage: nil)

        #expect(state.makeEntry(calendar: utcCalendar).usesEmptyState)
        #expect(StudyTimerWidgetEntryFactory.unavailable(now: .now).usesEmptyState == false)
    }

    @Test func unavailableWidgetEntryExplainsHowToRecover() {
        let entry = StudyTimerWidgetEntryFactory.unavailable(now: Date(timeIntervalSince1970: 10_000))

        #expect(entry.statusMessage == "无法读取学习计时，请打开 App")
        #expect(entry.displayedTaskID == nil)
        #expect(entry.elapsedReferenceDate == nil)
        #expect(entry.tasks.isEmpty)
    }

    @MainActor
    @Test func externalStoreMutationRefreshesApplicationSnapshot() throws {
        let url = temporaryStoreURL("external-refresh")
        let appStore = try StudyStore.makePersistent(at: url)
        let viewModel = TimerViewModel(store: appStore)
        let task = try #require(viewModel.tasks.first)
        let start = Date(timeIntervalSince1970: 1_000)
        let pause = Date(timeIntervalSince1970: 1_060)

        try StudyStore.makePersistent(at: url).start(taskID: task.id, at: start)
        viewModel.refreshFromExternalStore(now: pause)

        #expect(viewModel.snapshot.activeTaskID == task.id)
        #expect(viewModel.snapshot.elapsed(
            taskID: task.id, on: start, calendar: utcCalendar, now: pause) == 60)

        try StudyStore.makePersistent(at: url).pause(taskID: task.id, at: pause)
        viewModel.refreshFromExternalStore(now: pause)

        #expect(viewModel.snapshot.activeTaskID == nil)
        #expect(viewModel.snapshot.elapsed(
            taskID: task.id, on: start, calendar: utcCalendar, now: pause) == 60)
    }

    @MainActor
    @Test func successfulTimerToggleReloadsWidgetTimeline() throws {
        let reloader = RecordingWidgetReloader()
        let viewModel = TimerViewModel(store: try StudyStore.makeInMemory(), reloader: reloader)
        let task = try #require(viewModel.tasks.first)

        viewModel.toggle(taskID: task.id, at: Date(timeIntervalSince1970: 1_000))

        #expect(reloader.reloadCount == 1)
    }
}

private final class RecordingWidgetReloader: StudyClockWidgetReloading {
    private(set) var reloadCount = 0

    func reloadTimelines() {
        reloadCount += 1
    }
}
