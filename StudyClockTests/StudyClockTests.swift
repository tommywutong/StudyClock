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
    @Test func taskLifecycleCreatesEditsReordersArchivesAndRestores() throws {
        let store = try StudyStore.makeInMemory()
        try store.seedDefaultsIfNeeded()

        let originalIDs = try store.tasks().map(\.id)
        let newID = try store.createTask(name: "英语", dailyGoalSeconds: 1_800)
        try store.updateTask(id: newID, name: "英语听力", dailyGoalSeconds: 2_400)
        try store.reorderTasks([newID] + originalIDs)

        try store.archiveTask(id: newID)

        #expect(try store.tasks().map(\.id).first == originalIDs.first)
        #expect(try store.tasks(includeArchived: true).first(where: { $0.id == newID })?.name == "英语听力")
        #expect(try store.tasks(includeArchived: true).first(where: { $0.id == newID })?.isArchived == true)

        try store.restoreTask(id: newID)
        #expect(try store.tasks().map(\.id).last == newID)
    }

    @MainActor
    @Test func taskMutationsTrimNamesNormalizeGoalsAndRejectInvalidOrdering() throws {
        let store = try StudyStore.makeInMemory()
        try store.seedDefaultsIfNeeded()

        let taskID = try store.createTask(name: "  英语  ", dailyGoalSeconds: -1)
        let task = try #require(store.tasks().first(where: { $0.id == taskID }))
        #expect(task.name == "英语")
        #expect(task.dailyGoalSeconds == 0)

        do {
            _ = try store.createTask(name: "   ", dailyGoalSeconds: 60)
            Issue.record("Expected an empty task name to be rejected")
        } catch let error as StudyStoreError {
            #expect(error == .invalidTaskName)
        }

        let activeIDs = try store.tasks().map(\.id)
        do {
            try store.reorderTasks([activeIDs[0], activeIDs[0]] + activeIDs.dropFirst())
            Issue.record("Expected duplicate task IDs to be rejected")
        } catch let error as StudyStoreError {
            #expect(error == .invalidTaskOrdering)
        }
    }

    @MainActor
    @Test func archivingRunningTaskIsRejectedAndArchivedTaskCannotReceiveTimerActions() throws {
        let store = try StudyStore.makeInMemory()
        try store.seedDefaultsIfNeeded()
        let task = try #require(store.tasks().first)
        let start = Date(timeIntervalSince1970: 1_000)

        func expectStoreError(_ expected: StudyStoreError, operation: () throws -> Void) {
            do {
                try operation()
                Issue.record("Expected \(expected), but the operation succeeded")
            } catch let error as StudyStoreError {
                #expect(error == expected)
            } catch {
                Issue.record("Expected \(expected), got \(error)")
            }
        }

        try store.start(taskID: task.id, at: start)
        expectStoreError(.activeTaskMustBePaused) {
            try store.archiveTask(id: task.id)
        }

        try store.pause(taskID: task.id, at: start.addingTimeInterval(60))
        try store.archiveTask(id: task.id)
        expectStoreError(.archivedTaskUnavailable) {
            try store.start(taskID: task.id, at: start.addingTimeInterval(120))
        }
        expectStoreError(.archivedTaskUnavailable) {
            try store.resetToday(taskID: task.id, at: start.addingTimeInterval(120))
        }
    }

    @MainActor
    @Test func archivedTaskHistoryRemainsInDailyTotalAndWidgetExcludesIt() throws {
        let store = try StudyStore.makeInMemory()
        try store.seedDefaultsIfNeeded()
        let task = try #require(store.tasks().first)
        let start = Date(timeIntervalSince1970: 32_400)
        let pause = start.addingTimeInterval(600)

        try store.start(taskID: task.id, at: start)
        try store.pause(taskID: task.id, at: pause)
        try store.archiveTask(id: task.id)

        #expect(try store.totalElapsed(on: start, now: pause, calendar: utcCalendar) == 600)
        #expect(try store.widgetState(now: pause, calendar: utcCalendar).tasks.contains(where: { $0.id == task.id }) == false)
    }

    @Test func calendarUsesTwelveCalendarMonthsIncludesTodayAndClassifiesIntensity() {
        let taskID = UUID()
        let now = makeDate(2025, 10, 5, hour: 12, calendar: utcCalendar)
        let snapshot = TimerReducer.reduce([
            .start(taskID, at: makeDate(2025, 10, 5, hour: 9, calendar: utcCalendar), device: "mac"),
            .pause(taskID, at: makeDate(2025, 10, 5, hour: 9, minute: 30, calendar: utcCalendar), device: "mac"),
            .start(taskID, at: makeDate(2024, 10, 5, hour: 9, calendar: utcCalendar), device: "mac"),
            .pause(taskID, at: makeDate(2024, 10, 5, hour: 9, minute: 30, calendar: utcCalendar), device: "mac")
        ])

        let report = StudyCalendarCalculator.calculate(
            tasks: [.init(id: taskID, name: "八股", isArchived: false, sortOrder: 0)],
            snapshot: snapshot,
            now: now,
            calendar: utcCalendar)

        #expect(report.startDate == makeDate(2024, 10, 5, calendar: utcCalendar))
        #expect(report.endDate == makeDate(2025, 10, 5, calendar: utcCalendar))
        #expect(report.days.first?.date == report.startDate)
        #expect(report.days.last?.date == report.endDate)
        #expect(report.days.last?.intensity == .medium)
        #expect(report.days.count == 366)
        #expect(report.days.contains(where: { $0.intensity == .empty }))
    }

    @Test func calendarStreakStartsYesterdayWhenTodayIsEmptyAndCanReachBeforeWindow() {
        let taskID = UUID()
        let now = makeDate(2025, 10, 5, hour: 12, calendar: utcCalendar)
        var actions: [TimerActionValue] = []
        for day in 0..<370 {
            let date = utcCalendar.date(byAdding: .day, value: -day - 1, to: utcCalendar.startOfDay(for: now))!
            actions += [
                .start(taskID, at: date.addingTimeInterval(3_600), device: "mac"),
                .pause(taskID, at: date.addingTimeInterval(3_660), device: "mac")
            ]
        }

        let report = StudyCalendarCalculator.calculate(
            tasks: [.init(id: taskID, name: "算法", isArchived: false, sortOrder: 0)],
            snapshot: TimerReducer.reduce(actions),
            now: now,
            calendar: utcCalendar)

        #expect(report.currentStreak == 370)
        #expect(report.longestVisibleStreak == 365)
    }

    @Test func calendarClassifiesExactIntensityBoundaries() {
        let taskID = UUID()
        let dates = [
            makeDate(2025, 1, 1, calendar: utcCalendar),
            makeDate(2025, 1, 2, calendar: utcCalendar),
            makeDate(2025, 1, 3, calendar: utcCalendar),
            makeDate(2025, 1, 4, calendar: utcCalendar)
        ]
        let durations: [TimeInterval] = [1_799, 1_800, 3_600, 7_200]
        var actions: [TimerActionValue] = []
        for (date, duration) in zip(dates, durations) {
            actions += [
                .start(taskID, at: date.addingTimeInterval(28_800), device: "mac"),
                .pause(taskID, at: date.addingTimeInterval(28_800 + duration), device: "mac")
            ]
        }

        let report = StudyCalendarCalculator.calculate(
            tasks: [.init(id: taskID, name: "算法", isArchived: false, sortOrder: 0)],
            snapshot: TimerReducer.reduce(actions),
            now: makeDate(2025, 1, 4, hour: 12, calendar: utcCalendar),
            calendar: utcCalendar)

        let intensities = dates.map { date in
            report.days.first(where: { utcCalendar.isDate($0.date, inSameDayAs: date) })?.intensity
        }
        #expect(intensities == [.light, .medium, .strong, .veryStrong])
    }

    @Test func calendarSplitsMidnightAndKeepsArchivedTaskDetails() {
        let regularTaskID = UUID()
        let archivedTaskID = UUID()
        let firstStart = makeDate(2025, 1, 1, hour: 23, minute: 59, calendar: utcCalendar)
        let firstPause = makeDate(2025, 1, 2, hour: 0, minute: 1, calendar: utcCalendar)
        let archivedStart = makeDate(2025, 1, 2, hour: 10, calendar: utcCalendar)
        let archivedPause = archivedStart.addingTimeInterval(60)
        let report = StudyCalendarCalculator.calculate(
            tasks: [
                .init(id: regularTaskID, name: "八股", isArchived: false, sortOrder: 0),
                .init(id: archivedTaskID, name: "旧项目", isArchived: true, sortOrder: 1)
            ],
            snapshot: TimerReducer.reduce([
                .start(regularTaskID, at: firstStart, device: "mac"),
                .pause(regularTaskID, at: firstPause, device: "mac"),
                .start(archivedTaskID, at: archivedStart, device: "mac"),
                .pause(archivedTaskID, at: archivedPause, device: "mac")
            ]),
            now: makeDate(2025, 1, 2, hour: 12, calendar: utcCalendar),
            calendar: utcCalendar)

        let firstDay = report.days.first { utcCalendar.isDate($0.date, inSameDayAs: firstStart) }
        let secondDay = report.days.first { utcCalendar.isDate($0.date, inSameDayAs: firstPause) }
        #expect(firstDay?.totalElapsed == 60)
        #expect(secondDay?.totalElapsed == 120)
        #expect(secondDay?.tasks.map(\.id) == [regularTaskID, archivedTaskID])
        #expect(secondDay?.tasks.last?.isArchived == true)
        #expect(secondDay?.tasks.last?.elapsed == 60)
    }

    @Test func calendarUsesCalendarDayBoundariesAcrossDaylightSavingTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let taskID = UUID()
        let snapshot = TimerReducer.reduce([
            .start(taskID, at: makeDate(2024, 3, 10, calendar: calendar), device: "mac"),
            .pause(taskID, at: makeDate(2024, 3, 11, calendar: calendar), device: "mac")
        ])

        let report = StudyCalendarCalculator.calculate(
            tasks: [.init(id: taskID, name: "DST", isArchived: false, sortOrder: 0)],
            snapshot: snapshot,
            now: makeDate(2024, 3, 12, hour: 12, calendar: calendar),
            calendar: calendar)

        let daylightSavingDay = report.days.first { calendar.isDate($0.date, inSameDayAs: makeDate(2024, 3, 10, calendar: calendar)) }
        #expect(abs((daylightSavingDay?.totalElapsed ?? 0) - (23 * 60 * 60)) < 0.001)
    }

    @Test func calendarMonthLayoutAlignsFirstVisibleDayToConfiguredWeekday() throws {
        var mondayCalendar = utcCalendar
        mondayCalendar.firstWeekday = 2
        let report = StudyCalendarCalculator.calculate(
            tasks: [],
            snapshot: TimerReducer.reduce([]),
            now: makeDate(2026, 10, 5, hour: 12, calendar: mondayCalendar),
            calendar: mondayCalendar)
        let months = report.monthSections(calendar: mondayCalendar)
        let firstMonth = try #require(months.first)
        let november = try #require(months.first {
            mondayCalendar.component(.month, from: $0.startDate) == 11
        })
        #expect(firstMonth.days.first?.date == makeDate(2025, 10, 5, calendar: mondayCalendar))
        #expect(firstMonth.leadingEmptyCount == 6)
        #expect(november.leadingEmptyCount == 5)
        #expect(months.flatMap(\.days).map(\.date) == report.days.map(\.date))

        var sundayCalendar = mondayCalendar
        sundayCalendar.firstWeekday = 1
        #expect(report.monthSections(calendar: sundayCalendar).first?.leadingEmptyCount == 0)
    }

    @Test func taskGoalInputHandlesValidMinutesAndRejectsInvalidOrOverflowingInput() {
        #expect(TaskEditorView.goalSeconds(hours: "1", minutes: "90") == 9_000)
        #expect(TaskEditorView.goalSeconds(hours: "0", minutes: "0") == 0)
        #expect(TaskEditorView.goalSeconds(hours: "-1", minutes: "0") == nil)
        #expect(TaskEditorView.goalSeconds(hours: "0", minutes: "-1") == nil)
        #expect(TaskEditorView.goalSeconds(hours: "", minutes: "0") == nil)
        #expect(TaskEditorView.goalSeconds(hours: "1.5", minutes: "0") == nil)
        #expect(TaskEditorView.goalSeconds(hours: String(Int.max), minutes: "0") == nil)
        #expect(TaskEditorView.goalSeconds(hours: "0", minutes: String(Int.max)) == nil)
        #expect(TaskEditorView.goalSeconds(hours: "1", minutes: String(Int.max / 60)) == nil)
    }

    @Test func durationFormattingHandlesFloatingPointGoalBoundaryAndPeriodTotals() throws {
        let goal = try #require(TaskEditorView.goalSeconds(hours: "0", minutes: "153722867280912930"))
        #expect(StudyDurationFormatting.hoursMinutes(TimeInterval(goal)) == "2562047788015215:30")
        #expect(StudyDurationFormatting.hoursMinutes(100_000_000_000_000_000_000) == "27777777777777776:46")
        #expect(StudyDurationFormatting.hoursMinutes(3_660) == "1:01")
        #expect(StudyDurationFormatting.hoursMinutes(-1) == "0:00")
        #expect(StudyDurationFormatting.hoursMinutes(.infinity) == "—")
        #expect(StudyDurationFormatting.hoursMinutes(.nan) == "—")
    }

    @Test func calendarClockRefreshAdvancesTodayAndRebuildsAcrossMidnight() throws {
        let taskID = UUID()
        let startedAt = makeDate(2025, 1, 2, hour: 9, calendar: utcCalendar)
        let snapshot = TimerSnapshot(
            intervals: [TimerInterval(
                taskID: taskID,
                start: makeDate(2025, 1, 1, hour: 9, calendar: utcCalendar),
                end: makeDate(2025, 1, 1, hour: 9, minute: 1, calendar: utcCalendar))],
            activeTaskID: taskID, activeStartedAt: startedAt, conflictingActionIDs: [])
        let original = StudyCalendarCalculator.calculate(
            tasks: [.init(id: taskID, name: "学习", isArchived: false, sortOrder: 0)],
            snapshot: snapshot, now: startedAt.addingTimeInterval(600), calendar: utcCalendar)
        let updated = StudyCalendarCalculator.advancingToday(
            in: original, snapshot: snapshot, now: startedAt.addingTimeInterval(1_800), calendar: utcCalendar)
        #expect(original.days.last?.totalElapsed == 600)
        #expect(updated.days.last?.totalElapsed == 1_800)
        #expect(updated.days.last?.intensity == .medium)
        #expect(updated.currentStreak == 2)
        #expect(updated.longestVisibleStreak == 2)
        #expect(updated.days.dropLast() == original.days.dropLast())

        let nextDay = StudyCalendarCalculator.advancingToday(
            in: updated, snapshot: snapshot,
            now: makeDate(2025, 1, 3, minute: 1, calendar: utcCalendar), calendar: utcCalendar)
        #expect(nextDay.endDate == makeDate(2025, 1, 3, calendar: utcCalendar))
        #expect(nextDay.startDate == makeDate(2024, 1, 3, calendar: utcCalendar))
        #expect(nextDay.days.last?.totalElapsed == 60)
        #expect(nextDay.days.first { $0.date == updated.endDate }?.totalElapsed == 54_000)
        #expect(nextDay.currentStreak == 3)
    }

    @MainActor
    @Test func viewModelTaskMutationsRefreshActiveAndHistoricalLists() throws {
        let reloader = RecordingWidgetReloader()
        let model = TimerViewModel(store: try StudyStore.makeInMemory(), reloader: reloader)
        let originalCount = model.tasks.count

        model.addTask(name: "英语", dailyGoalSeconds: 1_800)
        let newTask = try #require(model.tasks.last)
        model.updateTask(id: newTask.id, name: "英语听力", dailyGoalSeconds: 2_400)
        model.archiveTask(id: newTask.id)

        #expect(model.tasks.count == originalCount)
        #expect(model.historicalTasks.contains(where: { $0.id == newTask.id && $0.isArchived }))
        #expect(model.archivedTasks.map(\.id) == [newTask.id])
        #expect(reloader.reloadCount == 3)

        model.restoreTask(id: newTask.id)
        #expect(model.tasks.contains(where: { $0.id == newTask.id }))
        #expect(model.studyStatisticsTasks.contains {
            $0.id == newTask.id && $0.name == "英语听力" && $0.dailyGoalSeconds == 2_400
        })
    }

    @MainActor
    @Test func viewModelHistoricalStatisticsAndCalendarKeepArchivedTaskData() throws {
        let store = try StudyStore.makeInMemory()
        try store.seedDefaultsIfNeeded()
        let task = try #require(store.tasks().first)
        let startedAt = makeDate(2025, 1, 2, hour: 9, calendar: utcCalendar)
        let pausedAt = startedAt.addingTimeInterval(600)
        try store.start(taskID: task.id, at: startedAt)
        try store.pause(taskID: task.id, at: pausedAt)
        try store.archiveTask(id: task.id)

        let referenceDate = makeDate(2025, 1, 3, hour: 12, calendar: utcCalendar)
        let model = TimerViewModel(store: store)
        #expect(model.reload(now: referenceDate))

        let statistics = model.studyStatistics(
            for: .sevenDays,
            now: referenceDate,
            calendar: utcCalendar)
        #expect(statistics.tasks.contains { $0.id == task.id && $0.elapsed == 600 })
        #expect(statistics.tasks.first(where: { $0.id == task.id })?.isArchived == true)

        let calendarReport = model.studyCalendar(now: referenceDate, calendar: utcCalendar)
        let day = try #require(calendarReport.days.first { utcCalendar.isDate($0.date, inSameDayAs: startedAt) })
        #expect(day.tasks.first(where: { $0.id == task.id })?.isArchived == true)
        #expect(day.tasks.first(where: { $0.id == task.id })?.elapsed == 600)
    }

    @MainActor
    @Test func viewModelMovesActiveTasksAndPersistsSortOrder() throws {
        let reloader = RecordingWidgetReloader()
        let model = TimerViewModel(store: try StudyStore.makeInMemory(), reloader: reloader)
        let originalIDs = model.tasks.map(\.id)

        model.moveTasks(from: IndexSet(integer: 0), to: model.tasks.count)

        #expect(model.tasks.map(\.id) == Array(originalIDs.dropFirst()) + [originalIDs[0]])
        #expect(model.tasks.map(\.sortOrder) == Array(0..<originalIDs.count))
        #expect(reloader.reloadCount == 1)
    }

    @MainActor
    @Test func resettingActiveTaskClearsTodayStopsItAndPreservesPreviousDay() throws {
        let store = try StudyStore.makeInMemory()
        try store.seedDefaultsIfNeeded()
        let task = try #require(store.tasks().first)
        let startedAt = Date(timeIntervalSince1970: 86_300)
        let resetAt = Date(timeIntervalSince1970: 86_500)
        let previousDay = utcCalendar.startOfDay(for: startedAt)
        let resetDay = utcCalendar.startOfDay(for: resetAt)

        try store.start(taskID: task.id, at: startedAt)
        try store.resetToday(taskID: task.id, at: resetAt)

        let snapshot = try store.snapshot(now: resetAt, calendar: utcCalendar)
        #expect(snapshot.activeTaskID == nil)
        #expect(snapshot.elapsed(taskID: task.id, on: resetDay, calendar: utcCalendar, now: resetAt) == 0)
        #expect(snapshot.elapsed(taskID: task.id, on: previousDay, calendar: utcCalendar, now: resetAt) == 100)
    }

    @MainActor
    @Test func resettingInactiveTaskDoesNotStopAnotherRunningTask() throws {
        let store = try StudyStore.makeInMemory()
        try store.seedDefaultsIfNeeded()
        let tasks = try store.tasks()
        let runningTask = tasks[0]
        let resetTask = tasks[1]
        let resetStart = Date(timeIntervalSince1970: 1_000)
        let resetPause = Date(timeIntervalSince1970: 1_050)
        let runningStart = Date(timeIntervalSince1970: 1_100)
        let resetTime = Date(timeIntervalSince1970: 1_200)

        try store.start(taskID: resetTask.id, at: resetStart)
        try store.pause(taskID: resetTask.id, at: resetPause)
        try store.start(taskID: runningTask.id, at: runningStart)
        try store.resetToday(taskID: resetTask.id, at: resetTime)

        let snapshot = try store.snapshot(now: resetTime, calendar: utcCalendar)
        #expect(snapshot.activeTaskID == runningTask.id)
        #expect(snapshot.elapsed(taskID: resetTask.id, on: resetStart, calendar: utcCalendar, now: resetTime) == 0)
        #expect(snapshot.elapsed(taskID: runningTask.id, on: runningStart, calendar: utcCalendar, now: resetTime) == 100)
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

    @Test func mediumWidgetShowsCurrentTaskFirstAndReportsHiddenTasks() {
        let tasks = (0..<6).map { index in
            StudyTimerWidgetTask(id: UUID(), name: "任务\(index)", elapsed: 60, target: 3_600)
        }
        let current = tasks[4]
        let entry = StudyTimerWidgetEntryState(
            date: .now,
            tasks: tasks,
            displayedTaskID: current.id,
            isRunning: true,
            elapsedReferenceDate: .now,
            totalElapsed: 360,
            statusMessage: nil)

        #expect(entry.mediumDisplayTasks.map(\.id) == [current.id, tasks[0].id, tasks[1].id, tasks[2].id])
        #expect(entry.hiddenMediumTaskCount == 2)
        #expect(entry.tasks.map(\.id) == tasks.map(\.id))
        #expect(entry.totalElapsed == 360)
    }

    @Test func mediumWidgetPreservesOrderWithoutCurrentTaskAndHandlesCapacityBoundaries() {
        let tasks = (0..<4).map { index in
            StudyTimerWidgetTask(id: UUID(), name: "任务\(index)", elapsed: 60, target: 3_600)
        }
        for count in 0...tasks.count {
            let subset = Array(tasks.prefix(count))
            let entry = StudyTimerWidgetEntryState(
                date: .now,
                tasks: subset,
                displayedTaskID: nil,
                isRunning: false,
                elapsedReferenceDate: nil,
                totalElapsed: TimeInterval(count * 60),
                statusMessage: nil)
            #expect(entry.mediumDisplayTasks.map(\.id) == subset.map(\.id))
            #expect(entry.hiddenMediumTaskCount == 0)
            #expect(entry.usesMediumEmptyState == subset.isEmpty)
            #expect(entry.usesEmptyState)
        }
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
    @Test func statisticsUseAdjacentCompleteLocalDayWindows() {
        let taskID = UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!
        let snapshot = TimerSnapshot(
            intervals: [
                TimerInterval(taskID: taskID, start: makeDate(2025, 1, 14, hour: 8, calendar: utcCalendar), end: makeDate(2025, 1, 14, hour: 9, calendar: utcCalendar)),
                TimerInterval(taskID: taskID, start: makeDate(2025, 1, 7, hour: 8, calendar: utcCalendar), end: makeDate(2025, 1, 7, hour: 10, calendar: utcCalendar)),
                TimerInterval(taskID: taskID, start: makeDate(2025, 1, 15, hour: 0, calendar: utcCalendar), end: makeDate(2025, 1, 15, hour: 1, calendar: utcCalendar))
            ],
            activeTaskID: nil,
            activeStartedAt: nil,
            conflictingActionIDs: [])
        let report = StudyStatisticsCalculator.calculate(
            tasks: [.init(id: taskID, name: "八股", dailyGoalSeconds: 3_600, sortOrder: 0)],
            snapshot: snapshot,
            period: .sevenDays,
            now: makeDate(2025, 1, 15, hour: 12, calendar: utcCalendar),
            calendar: utcCalendar)

        #expect(report.periodStart == makeDate(2025, 1, 8, calendar: utcCalendar))
        #expect(report.previousPeriodStart == makeDate(2025, 1, 1, calendar: utcCalendar))
        #expect(report.periodEnd == makeDate(2025, 1, 15, calendar: utcCalendar))
        #expect(report.elapsed == 3_600)
        #expect(report.previousElapsed == 7_200)
        #expect(report.elapsedChange == -3_600)
        #expect(report.elapsedRelativeChange == -0.5)
        #expect(report.goalCompletionRate == 1.0 / 7.0)
        #expect(report.previousGoalCompletionRate == 2.0 / 7.0)
        #expect(report.goalCompletionChangePercentagePoints.map { abs($0 + 100.0 / 7.0) < 0.000_001 } == true)
    }

    @Test func statisticsSplitCrossMidnightIntervalsAndCountZeroDaysInAverage() {
        let taskID = UUID()
        let snapshot = TimerSnapshot(
            intervals: [TimerInterval(
                taskID: taskID,
                start: makeDate(2025, 1, 7, hour: 23, minute: 30, calendar: utcCalendar),
                end: makeDate(2025, 1, 8, hour: 1, calendar: utcCalendar)
            )],
            activeTaskID: nil,
            activeStartedAt: nil,
            conflictingActionIDs: [])
        let report = StudyStatisticsCalculator.calculate(
            tasks: [.init(id: taskID, name: "八股", dailyGoalSeconds: 3_600, sortOrder: 0)],
            snapshot: snapshot,
            period: .sevenDays,
            now: makeDate(2025, 1, 15, hour: 12, calendar: utcCalendar),
            calendar: utcCalendar)

        #expect(report.elapsed == 3_600)
        #expect(report.previousElapsed == 1_800)
        #expect(report.tasks[0].averageDailyElapsed == 3_600.0 / 7.0)
        #expect(report.tasks[0].goalAttainmentDays == 1)
        #expect(report.tasks[0].previousGoalAttainmentDays == 0)
    }

    @Test func statisticsUseCalendarDayBoundariesAcrossDaylightSavingTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let taskID = UUID()
        let snapshot = TimerSnapshot(
            intervals: [TimerInterval(
                taskID: taskID,
                start: makeDate(2024, 3, 10, calendar: calendar),
                end: makeDate(2024, 3, 11, calendar: calendar)
            )],
            activeTaskID: nil,
            activeStartedAt: nil,
            conflictingActionIDs: [])
        let report = StudyStatisticsCalculator.calculate(
            tasks: [.init(id: taskID, name: "DST", dailyGoalSeconds: 0, sortOrder: 0)],
            snapshot: snapshot,
            period: .sevenDays,
            now: makeDate(2024, 3, 12, hour: 12, calendar: calendar),
            calendar: calendar)

        #expect(report.elapsed == 23 * 60 * 60)
        #expect(report.periodEnd == makeDate(2024, 3, 12, calendar: calendar))
    }

    @Test func statisticsUseAllConfiguredWindowLengths() {
        let snapshot = TimerSnapshot(
            intervals: [],
            activeTaskID: nil,
            activeStartedAt: nil,
            conflictingActionIDs: [])
        let now = makeDate(2025, 1, 15, hour: 12, calendar: utcCalendar)
        let cases: [(StudyStatisticsPeriod, Date, Date)] = [
            (.sevenDays, makeDate(2025, 1, 8, calendar: utcCalendar), makeDate(2025, 1, 1, calendar: utcCalendar)),
            (.fifteenDays, makeDate(2024, 12, 31, calendar: utcCalendar), makeDate(2024, 12, 16, calendar: utcCalendar)),
            (.thirtyDays, makeDate(2024, 12, 16, calendar: utcCalendar), makeDate(2024, 11, 16, calendar: utcCalendar))
        ]

        for (period, expectedStart, expectedPreviousStart) in cases {
            let report = StudyStatisticsCalculator.calculate(
                tasks: [], snapshot: snapshot, period: period, now: now, calendar: utcCalendar)

            #expect(report.periodStart == expectedStart)
            #expect(report.previousPeriodStart == expectedPreviousStart)
            #expect(report.periodEnd == makeDate(2025, 1, 15, calendar: utcCalendar))
        }
    }

    @Test func statisticsKeepNoGoalTimeInShareButExcludeItFromGoalCompletion() {
        let goalTaskID = UUID()
        let noGoalTaskID = UUID()
        let snapshot = TimerSnapshot(
            intervals: [
                TimerInterval(taskID: goalTaskID, start: makeDate(2025, 1, 14, hour: 8, calendar: utcCalendar), end: makeDate(2025, 1, 14, hour: 9, calendar: utcCalendar)),
                TimerInterval(taskID: noGoalTaskID, start: makeDate(2025, 1, 13, hour: 8, calendar: utcCalendar), end: makeDate(2025, 1, 13, hour: 10, calendar: utcCalendar))
            ],
            activeTaskID: nil,
            activeStartedAt: nil,
            conflictingActionIDs: [])
        let report = StudyStatisticsCalculator.calculate(
            tasks: [
                .init(id: goalTaskID, name: "目标任务", dailyGoalSeconds: 3_600, sortOrder: 0),
                .init(id: noGoalTaskID, name: "无目标", dailyGoalSeconds: 0, sortOrder: 1)
            ],
            snapshot: snapshot,
            period: .sevenDays,
            now: makeDate(2025, 1, 15, hour: 12, calendar: utcCalendar),
            calendar: utcCalendar)

        #expect(report.elapsed == 10_800)
        #expect(report.tasks[0].share.map { abs($0 - 1.0 / 3.0) < 0.000_001 } == true)
        #expect(report.tasks[1].share.map { abs($0 - 2.0 / 3.0) < 0.000_001 } == true)
        #expect(report.goalElapsed == 25_200)
        #expect(report.goalCompletionRate == 1.0 / 7.0)
        #expect(report.goalCompletionChangePercentagePoints.map { abs($0 - 100.0 / 7.0) < 0.000_001 } == true)
        #expect(report.tasks[0].previousGoalCompletionRate == 0)
        #expect(report.tasks[0].goalCompletionChangePercentagePoints.map { abs($0 - 100.0 / 7.0) < 0.000_001 } == true)
        #expect(report.tasks[1].goalCompletionRate == nil)
        #expect(report.tasks[1].goalAttainmentDays == nil)
    }

    @Test func statisticsMarkOverallGoalNotSetWhenNoTaskHasAPositiveGoal() {
        let taskID = UUID()
        let snapshot = TimerSnapshot(
            intervals: [TimerInterval(
                taskID: taskID,
                start: makeDate(2025, 1, 14, hour: 8, calendar: utcCalendar),
                end: makeDate(2025, 1, 14, hour: 9, calendar: utcCalendar)
            )],
            activeTaskID: nil,
            activeStartedAt: nil,
            conflictingActionIDs: [])
        let report = StudyStatisticsCalculator.calculate(
            tasks: [.init(id: taskID, name: "无目标", dailyGoalSeconds: 0, sortOrder: 0)],
            snapshot: snapshot,
            period: .sevenDays,
            now: makeDate(2025, 1, 15, hour: 12, calendar: utcCalendar),
            calendar: utcCalendar)

        #expect(report.elapsed == 3_600)
        #expect(report.goalElapsed == 0)
        #expect(report.goalCompletionRate == nil)
        #expect(report.tasks[0].goalCompletionRate == nil)
        #expect(report.tasks[0].goalAttainmentDays == nil)
    }

    @Test func statisticsOrderTaskSummariesBySortOrder() {
        let firstID = UUID()
        let secondID = UUID()
        let snapshot = TimerSnapshot(
            intervals: [],
            activeTaskID: nil,
            activeStartedAt: nil,
            conflictingActionIDs: [])
        let report = StudyStatisticsCalculator.calculate(
            tasks: [
                .init(id: secondID, name: "第二项", dailyGoalSeconds: 0, sortOrder: 1),
                .init(id: firstID, name: "第一项", dailyGoalSeconds: 0, sortOrder: 0)
            ],
            snapshot: snapshot,
            period: .sevenDays,
            now: makeDate(2025, 1, 15, hour: 12, calendar: utcCalendar),
            calendar: utcCalendar)

        #expect(report.tasks.map(\.name) == ["第一项", "第二项"])
    }

    @Test func statisticsRepresentZeroComparisonBaselineWithoutNonFiniteValues() {
        let taskID = UUID()
        let snapshot = TimerSnapshot(
            intervals: [TimerInterval(
                taskID: taskID,
                start: makeDate(2025, 1, 14, hour: 8, calendar: utcCalendar),
                end: makeDate(2025, 1, 14, hour: 9, calendar: utcCalendar)
            )],
            activeTaskID: nil,
            activeStartedAt: nil,
            conflictingActionIDs: [])
        let report = StudyStatisticsCalculator.calculate(
            tasks: [.init(id: taskID, name: "八股", dailyGoalSeconds: 3_600, sortOrder: 0)],
            snapshot: snapshot,
            period: .sevenDays,
            now: makeDate(2025, 1, 15, hour: 12, calendar: utcCalendar),
            calendar: utcCalendar)

        #expect(report.elapsed == 3_600)
        #expect(report.previousElapsed == 0)
        #expect(report.elapsedRelativeChange == nil)
        #expect(report.goalCompletionRate?.isFinite == true)
        #expect(report.previousGoalCompletionRate == 0)
    }

    @Test func statisticsRepresentEmptyHistoryWithoutNaNOrInfinity() {
        let taskID = UUID()
        let snapshot = TimerSnapshot(
            intervals: [],
            activeTaskID: nil,
            activeStartedAt: nil,
            conflictingActionIDs: [])
        let report = StudyStatisticsCalculator.calculate(
            tasks: [.init(id: taskID, name: "八股", dailyGoalSeconds: 3_600, sortOrder: 0)],
            snapshot: snapshot,
            period: .sevenDays,
            now: makeDate(2025, 1, 15, hour: 12, calendar: utcCalendar),
            calendar: utcCalendar)

        #expect(report.hasHistory == false)
        #expect(report.elapsed == 0)
        #expect(report.elapsedRelativeChange == nil)
        #expect(report.goalCompletionRate == 0)
        #expect(report.tasks[0].share == nil)
        #expect(report.tasks[0].goalCompletionRate == 0)
    }

    @Test func statisticsCountAnActiveTodayTimerAsHistoryButExcludeToday() {
        let taskID = UUID()
        let snapshot = TimerSnapshot(
            intervals: [],
            activeTaskID: taskID,
            activeStartedAt: makeDate(2025, 1, 15, hour: 8, calendar: utcCalendar),
            conflictingActionIDs: [])
        let report = StudyStatisticsCalculator.calculate(
            tasks: [.init(id: taskID, name: "八股", dailyGoalSeconds: 3_600, sortOrder: 0)],
            snapshot: snapshot,
            period: .sevenDays,
            now: makeDate(2025, 1, 15, hour: 12, calendar: utcCalendar),
            calendar: utcCalendar)

        #expect(report.hasHistory)
        #expect(report.elapsed == 0)
        #expect(report.previousElapsed == 0)
        #expect(report.tasks[0].share == nil)
    }

    @Test func statisticsRepresentTwoZeroPeriodsWithOlderHistoryWithoutRelativeChange() {
        let taskID = UUID()
        let snapshot = TimerSnapshot(
            intervals: [TimerInterval(
                taskID: taskID,
                start: makeDate(2024, 12, 20, hour: 8, calendar: utcCalendar),
                end: makeDate(2024, 12, 20, hour: 9, calendar: utcCalendar)
            )],
            activeTaskID: nil,
            activeStartedAt: nil,
            conflictingActionIDs: [])
        let report = StudyStatisticsCalculator.calculate(
            tasks: [.init(id: taskID, name: "八股", dailyGoalSeconds: 3_600, sortOrder: 0)],
            snapshot: snapshot,
            period: .sevenDays,
            now: makeDate(2025, 1, 15, hour: 12, calendar: utcCalendar),
            calendar: utcCalendar)

        #expect(report.hasHistory)
        #expect(report.elapsed == 0)
        #expect(report.previousElapsed == 0)
        #expect(report.elapsedRelativeChange == nil)
        #expect(report.tasks[0].share == nil)
    }

    @Test func statisticsKeepActualCompletionAboveOneWhileProgressCanBeClampedByTheView() {
        let taskID = UUID()
        let snapshot = TimerSnapshot(
            intervals: [TimerInterval(
                taskID: taskID,
                start: makeDate(2025, 1, 14, hour: 8, calendar: utcCalendar),
                end: makeDate(2025, 1, 14, hour: 16, calendar: utcCalendar)
            )],
            activeTaskID: nil,
            activeStartedAt: nil,
            conflictingActionIDs: [])
        let report = StudyStatisticsCalculator.calculate(
            tasks: [.init(id: taskID, name: "八股", dailyGoalSeconds: 3_600, sortOrder: 0)],
            snapshot: snapshot,
            period: .sevenDays,
            now: makeDate(2025, 1, 15, hour: 12, calendar: utcCalendar),
            calendar: utcCalendar)

        #expect(report.tasks[0].goalCompletionRate == 8.0 / 7.0)
        #expect((report.tasks[0].goalCompletionRate ?? 0) > 1)
    }

    @MainActor
    @Test func viewModelStatisticsMapsPersistedTasksAndSnapshot() throws {
        let store = try StudyStore.makeInMemory()
        let viewModel = TimerViewModel(store: store)
        let tasks = try store.tasks()
        let calendar = utcCalendar
        let now = makeDate(2025, 1, 15, hour: 12, calendar: calendar)
        try store.start(taskID: tasks[0].id, at: makeDate(2025, 1, 14, hour: 8, calendar: calendar))
        try store.pause(taskID: tasks[0].id, at: makeDate(2025, 1, 14, hour: 9, calendar: calendar))
        try store.start(taskID: tasks[1].id, at: makeDate(2025, 1, 7, hour: 8, calendar: calendar))
        try store.pause(taskID: tasks[1].id, at: makeDate(2025, 1, 7, hour: 10, calendar: calendar))
        #expect(viewModel.reload(now: now))

        let report = viewModel.studyStatistics(for: .sevenDays, now: now, calendar: calendar)
        #expect(report.elapsed == 3_600)
        #expect(report.previousElapsed == 7_200)
        #expect(report.elapsedChange == -3_600)
        #expect(report.elapsedRelativeChange == -0.5)
        #expect(report.tasks.map(\.name) == ["八股", "算法", "项目整理"])
        #expect(report.tasks[0].goalElapsed == 75_600)
    }

    private func makeDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 0,
        minute: Int = 0,
        calendar: Calendar
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = calendar.timeZone
        return calendar.date(from: components)!
    }
}

private final class RecordingWidgetReloader: StudyClockWidgetReloading {
    private(set) var reloadCount = 0

    func reloadTimelines() {
        reloadCount += 1
    }
}
