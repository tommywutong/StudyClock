# StudyClock 统计页实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 App 主仪表盘增加统计入口与分项优先统计页，呈现最近 7 / 15 / 30 个完整本地日的学习投入、目标估算和相邻周期对比，通知中心 Widget 保持不变。

**Architecture:** 用纯值输入和 `StudyStatisticsCalculator` 从现有 `TimerSnapshot` 按 Calendar 日边界聚合当前、上一周期和目标指标；`TimerViewModel` 负责将持久化任务映射到输入。独立 SwiftUI 统计页仅在出现、周期切换或计时快照 / 任务值变化时更新，不放进主仪表盘逐秒 `TimelineView` 的计算闭包。

**Tech Stack:** Swift 5 language mode、SwiftUI、Observation、Foundation Calendar、Swift Testing、现有 Xcode filesystem-synchronized groups。

**Spec:** `docs/superpowers/specs/2026-10-01-study-statistics-design.md`

## Global Constraints

- 统计窗口为最近 N 个**完整本地日**，不包含今天，N ∈ {7, 15, 30}。
- 上一周期是紧邻当前周期之前的 N 个完整本地日；区间使用半开语义。
- 日期边界通过 `Calendar` 计算，不以固定秒数换算日期。
- 周期目标使用当前 `dailyGoalSeconds` 回算，并向用户明确标为估算；不得添加目标历史或 SwiftData schema。
- 当前每日目标 ≤ 0 时，该任务目标完成率与达标天数为 nil / 不适用；总体目标完成率只统计有正目标的任务，全部任务均无正目标时总体目标为 nil / 显示“未设目标”。
- 当前周期占比在总时长为 0 时返回 nil / 显示“—”，不计算 `0 / 0`。
- Widget 布局、数据 DTO、Timeline 策略和 `ToggleStudyTimerIntent` 不改。
- 统计页聚合不挂到逐秒 `TimelineView` 更新路径。
- **不要 commit 或 push，除非 TommyWu 后续明确要求。**

## Review Focus

1. 本地午夜和 DST 变更：两个周期严格相邻、完整日窗口长度按 Calendar 日期数计算；由 Task 1 的窗口与 DST 测试覆盖。
2. 跨午夜计时：同一事件在本地午夜前后按日切片且窗口外时间不混入；由 Task 1 的跨日测试覆盖。
3. 零目标任务：时长仍进入总时长和占比，但不抬高总体目标完成率，也不报告目标达标天数；由 Task 1 的目标测试覆盖。
4. 目标进度超过 100% / 周期时长为零：数字保留真实比例，进度条限于 100%；零总时长时占比为 nil；由 Task 1 的数值边界测试及 Task 3 的呈现实现覆盖。
5. 前周期基线为零 / 无历史：不输出 Infinity、NaN 或伪造环比百分比；由 Task 1 的比较和空历史测试覆盖。

---

## 文件与职责

- Create `StudyClock/Domain/StudyStatistics.swift`: period enum、统计纯值输入 / 输出和 Calculator。
- Widget target 的同步目录源码成员关系保持不变；仅 App 使用的 `StudyClock/Domain/StudyStatistics.swift` 与 `StudyClock/Views/StudyStatisticsView.swift` 必须不出现在 Widget 的 `StudyClockWidgetExtension.SwiftFileList` 中。
- Modify `StudyClock/Timer/TimerViewModel.swift`: 通过现有 `tasks` 与 `snapshot` 暴露确定性的统计查询，不让 SwiftUI 直接读取 SwiftData 模型以外的数据。
- Create `StudyClock/Views/StudyStatisticsView.swift`: 周期选择、总体摘要、分项档案、估算说明、空值和空历史状态。
- Modify `StudyClock/Views/TimerDashboardView.swift`: 在“历史”旁增加“统计”入口，并用一个有标识的 sheet destination 展示既有历史页或统计页。
- Modify `StudyClockTests/StudyClockTests.swift`: 聚合器和 ViewModel 映射行为的永久单元测试。
- Modify `StudyClockUITests/StudyClockUITests.swift`: 验证主界面可以打开统计页及切换周期。
- Modify `README.md`: 记录统计页功能、周期 / 目标估算口径及 Widget 范围。

## Task 1: 实现纯值统计聚合与日期 / 数值单元测试

**Files:**
- Create: `StudyClock/Domain/StudyStatistics.swift`
- Test: `StudyClockTests/StudyClockTests.swift`

**Interfaces:**
- Consumes: existing `TimerSnapshot.elapsed(taskID:on:calendar:now:)`, `TimerInterval`, `StudyTaskRecord` field meanings.
- Produces: `StudyStatisticsPeriod`, `StudyStatisticsTaskInput`, `StudyStatisticsTaskSummary`, `StudyStatisticsReport`, `StudyStatisticsCalculator.calculate(...)` used by Tasks 2–3.

### Required value contract

```swift
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
    static func calculate(
        tasks: [StudyStatisticsTaskInput],
        snapshot: TimerSnapshot,
        period: StudyStatisticsPeriod,
        now: Date,
        calendar: Calendar
    ) -> StudyStatisticsReport
}
```

All percentages in result values are ratios (`0.25 == 25%`) except the explicitly named `goalCompletionChangePercentagePoints`, which is a percentage-point difference (`25 == 25 pp`). A zero previous duration produces `elapsedRelativeChange == nil`; the view chooses “上期无投入” or “无变化” using both period values.

- [x] **Step 1: Add failing tests for complete, adjacent local-day windows and exclusive today**

Add the Swift Testing case and `makeDate` helper below inside the existing `StudyClockTests` struct. Use its fixed Gregorian UTC calendar and `now = 2025-01-15 12:00 UTC`; build a snapshot containing a one-hour interval on Jan 14, a two-hour interval on Jan 7, and an interval starting at today’s local midnight. Assert exact boundaries, current / previous duration, absolute / relative change, and exclusion of the interval on today.

```swift
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
```

- [x] **Step 2: Run the focused test to confirm the calculator API is missing**

Run:

```bash
xcodebuild test -project StudyClock.xcodeproj -scheme StudyClock \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:StudyClockTests/statisticsUseAdjacentCompleteLocalDayWindows
```

Expected RED: Swift compiler reports missing `StudyStatisticsCalculator` / result types. A test compile failure from missing production API is the intended red state; resolve any test-fixture compile error before proceeding.

- [x] **Step 3: Add the remaining behavior tests before implementing the calculator**

Append these deterministic tests to `StudyClockTests.swift`; each assertion checks a concrete boundary or result:

```swift
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
```

Keep fixtures isolated, UTC except the DST test, and use explicit `Calendar` values.

- [x] **Step 4: Run the added calculator tests to confirm they fail for missing API**

Run:

```bash
xcodebuild test -project StudyClock.xcodeproj -scheme StudyClock \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:StudyClockTests/statisticsUseAdjacentCompleteLocalDayWindows \
  -only-testing:StudyClockTests/statisticsSplitCrossMidnightIntervalsAndCountZeroDaysInAverage \
  -only-testing:StudyClockTests/statisticsUseCalendarDayBoundariesAcrossDaylightSavingTime \
  -only-testing:StudyClockTests/statisticsUseAllConfiguredWindowLengths \
  -only-testing:StudyClockTests/statisticsKeepNoGoalTimeInShareButExcludeItFromGoalCompletion \
  -only-testing:StudyClockTests/statisticsMarkOverallGoalNotSetWhenNoTaskHasAPositiveGoal \
  -only-testing:StudyClockTests/statisticsOrderTaskSummariesBySortOrder \
  -only-testing:StudyClockTests/statisticsRepresentZeroComparisonBaselineWithoutNonFiniteValues \
  -only-testing:StudyClockTests/statisticsRepresentEmptyHistoryWithoutNaNOrInfinity \
  -only-testing:StudyClockTests/statisticsCountAnActiveTodayTimerAsHistoryButExcludeToday \
  -only-testing:StudyClockTests/statisticsRepresentTwoZeroPeriodsWithOlderHistoryWithoutRelativeChange \
  -only-testing:StudyClockTests/statisticsKeepActualCompletionAboveOneWhileProgressCanBeClampedByTheView
```

Expected RED: production symbols do not yet exist; all test files and test methods compile otherwise.

- [x] **Step 5: Implement `StudyStatisticsCalculator` with half-open Calendar windows**

Compute `periodEnd = calendar.startOfDay(for: now)`, `periodStart = calendar.date(byAdding: .day, value: -period.dayCount, to: periodEnd)`, and `previousPeriodStart = calendar.date(byAdding: .day, value: -(2 * period.dayCount), to: periodEnd)`. Use `guard let` and `preconditionFailure` if Calendar cannot derive a required boundary; never substitute fixed seconds.

Iterate the current `[periodStart, periodEnd)` and prior `[previousPeriodStart, periodStart)` windows by advancing one Calendar day at a time. At each day, add `snapshot.elapsed(taskID: task.id, on: day, calendar: calendar, now: now)`; fail the invariant if Calendar cannot advance. Sort output by `sortOrder`, then `id.uuidString` as a deterministic tie-break. Compute `elapsedChange = elapsed - previousElapsed`, `elapsedRelativeChange = elapsedChange / previousElapsed` only when the previous total is positive, and current `averageDailyElapsed = elapsed / N`.

For each task with `dailyGoalSeconds > 0`, set `goalElapsed = TimeInterval(dailyGoalSeconds) * TimeInterval(N)`, compute current and prior completion rates against that same current-goal estimate, and count days meeting the current daily goal. For `dailyGoalSeconds <= 0`, set `goalElapsed` to 0 and return nil rates and attainment-day counts; still include elapsed time in overall duration and share. Return nil share when overall current elapsed is zero. The report's elapsed totals include every task; overall current/prior goal actuals and goal denominators include only positive-goal tasks. Overall goal rate and percentage-point change are nil if no positive goal exists; otherwise compute `(currentRate - previousRate) * 100` for the percentage-point change. Set `hasHistory` when `snapshot.intervals` is non-empty or `snapshot.activeTaskID` is non-nil. With no prior elapsed, leave relative change nil so the view distinguishes “上期无投入” from “无变化” using both totals.

- [x] **Step 6: Keep the calculator out of Widget target membership**

本工程中，把 `Domain/StudyStatistics.swift` 加入 Widget target 的 `membershipExceptions` 会使 Xcode 将此 App-only 计算器编译进 `StudyClockWidgetExtension`。保持该列表及 Widget 源码成员关系不变；Step 7 的 Widget target 构建须确认生成的 `StudyClockWidgetExtension.SwiftFileList` 不含计算器。

- [x] **Step 7: Run all focused calculator tests and check both app and Widget target builds**

Run the Task 1 test command above; expected: every test passes. Then run:

```bash
xcodebuild build -project StudyClock.xcodeproj -scheme StudyClock \
  -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: StudyClock App and Widget Extension compile. The statistics source is App-only; Widget source membership is unchanged.

## Task 2: Expose statistics through `TimerViewModel`

**Files:**
- Modify: `StudyClock/Timer/TimerViewModel.swift`
- Test: `StudyClockTests/StudyClockTests.swift`

**Interfaces:**
- Consumes: Task 1's `StudyStatisticsTaskInput`, `StudyStatisticsPeriod`, `StudyStatisticsReport`, `StudyStatisticsCalculator.calculate`.
- Produces: `TimerViewModel.studyStatistics(for:now:calendar:) -> StudyStatisticsReport`.

- [x] **Step 1: Add a failing ViewModel integration test**

Create an in-memory `StudyStore`, initialize the existing `TimerViewModel(store:)`, write deterministic events through the same store, reload at fixed `now`, and assert the public summary:

```swift
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
```

This exercises the real ViewModel mapping and existing `StudyStore` persistence path, not a mock of the forwarder.

- [x] **Step 2: Run the focused test and confirm the new API is missing**

Run:

```bash
xcodebuild test -project StudyClock.xcodeproj -scheme StudyClock \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:StudyClockTests/viewModelStatisticsMapsPersistedTasksAndSnapshot
```

Expected RED: `TimerViewModel` has no `studyStatistics(for:now:calendar:)` method.

- [x] **Step 3: Add the minimal ViewModel adapter**

Map the already ordered tasks to the pure `StudyStatisticsTaskInput` values and call the calculator with `snapshot`, `period`, `now`, and the caller-supplied `calendar`. Do not fetch a second store snapshot or expose `StudyTaskRecord` to SwiftUI statistics views.

- [x] **Step 4: Run the integration test and full unit suite**

Run the focused test above, then:

```bash
xcodebuild test -project StudyClock.xcodeproj -scheme StudyClock \
  -destination 'platform=macOS,arch=arm64' -only-testing:StudyClockTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: the new adapter test and the existing unit suite pass.

## Task 3: Add the App statistics page and dashboard entry

**Files:**
- Create: `StudyClock/Views/StudyStatisticsView.swift`
- Modify: `StudyClock/Views/TimerDashboardView.swift`
- Modify: `StudyClock/Timer/TimerViewModel.swift`: expose pure `StudyStatisticsTaskInput` values for change observation and reuse them in the calculator adapter.
- Test: `StudyClockUITests/StudyClockUITests.swift`

**Interfaces:**
- Consumes: `TimerViewModel.studyStatistics(for:now:calendar:)` and `StudyStatisticsReport` from Tasks 1–2.
- Produces: App-only sheet page and stable accessibility labels `查看学习统计`, `statistics-period-7`, `statistics-period-15`, and `statistics-period-30`.

- [x] **Step 1: Add a failing UI test for the entry, all periods, and close behavior**

Add this test using the existing `XCUIApplication` launch pattern:

```swift
@MainActor
func testStatisticsPageOpensAndChangesPeriod() throws {
    let app = XCUIApplication()
    app.launch()

    let statisticsButton = app.buttons["查看学习统计"]
    XCTAssertTrue(statisticsButton.waitForExistence(timeout: 5))
    statisticsButton.tap()

    let period7Button = app.buttons["statistics-period-7"]
    XCTAssertTrue(period7Button.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["近 7 天"].waitForExistence(timeout: 5))

    let period15Button = app.buttons["statistics-period-15"]
    XCTAssertTrue(period15Button.waitForExistence(timeout: 5))
    period15Button.tap()
    XCTAssertTrue(app.staticTexts["近 15 天"].waitForExistence(timeout: 5))

    let period30Button = app.buttons["statistics-period-30"]
    XCTAssertTrue(period30Button.waitForExistence(timeout: 5))
    period30Button.tap()
    XCTAssertTrue(app.staticTexts["近 30 天"].waitForExistence(timeout: 5))

    let closeButton = app.buttons["关闭学习统计"]
    XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
    closeButton.tap()
    XCTAssertTrue(statisticsButton.waitForExistence(timeout: 5))
}
```

Do not assert incidental sample durations or persisted user-data contents.

- [x] **Step 2: Attempt focused UI test; record automation startup failure if it occurs**

Run:

```bash
xcodebuild test -project StudyClock.xcodeproj -scheme StudyClock \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:StudyClockUITests/StudyClockUITests/testStatisticsPageOpensAndChangesPeriod
```

Expected RED: the app has no `查看学习统计` button. If the UI-test runner fails before launching the app, record that environment failure separately; do not change the test to a weaker assertion.
Execution note: the pre-implementation attempt timed out while enabling automation mode; the post-implementation runner hung before establishing a connection. Neither run executed assertions. The unchanged test and exact result are recorded in `.superpowers/sdd/2026-10-01-study-statistics/progress.md`.

- [x] **Step 3: Implement the statistics view with explicit refresh triggers**

Build `StudyStatisticsView` as a `NavigationStack` containing a `ScrollView`, a three-button period selector, one overall summary section, and task cards in report order. Show current-period total and goal completion, elapsed absolute / relative changes, and goal-completion percentage-point change. Each task card shows elapsed, share (or “—”), average/day, target/rate or “未设目标”, current and prior attainment days and their difference, elapsed difference and relative change, goal-completion percentage-point difference, and a `ProgressView` capped to `0...1` while displaying the uncapped integer percentage. When previous elapsed is zero, show “上期无投入” for positive current elapsed or “无变化” when both periods are zero; never render an infinite percentage. Use the existing Chinese duration formatter. Show a distinct no-history empty state; when any history exists but both selected periods are empty, keep task cards with zero values and current targets. Always show the current-target estimation caveat.

Store `selectedPeriod` and the displayed report in private `@State`. Refresh the report on first appearance, period changes, snapshot changes and task identity/name/goal/order changes. Do not put the calculator call in a `TimelineView` closure and do not add a timer to the statistics page.

- [x] **Step 4: Keep the new view out of Widget target membership**

Do not add `Views/StudyStatisticsView.swift` to the Widget target's `membershipExceptions`. Keep Widget source membership unchanged. Once the file exists, verify its generated `StudyClockWidgetExtension.SwiftFileList` omits the view.

- [x] **Step 5: Replace the history-only sheet flag with one identified destination**

In `TimerDashboardView`, replace `showingHistory` with one optional `DashboardSheet: String, Identifiable` selection with `.history` and `.statistics`. Preserve the existing history button label, `HistoryView` arguments, and frame; add the statistics toolbar button with accessibility label. Present the selected page in one `.sheet(item:)` outside the `TimelineView` content closure, giving the statistics page a suitable minimum frame. `MenuBarView` reuses `TimerDashboardView`, so the shared toolbar route appears there too; keep the same ViewModel and behavior rather than introducing a second statistics data source.

- [ ] **Step 6: Run the focused UI test, then smoke-run the App surface**

Run the focused UI test from Step 2. If the macOS automation runner starts, require both entry and period-selector assertions to pass. Then launch the built App on macOS, open the statistics entry, switch 7 → 15 → 30, close it, and open History to verify both routes still work. If UI automation initialization times out before launch, report that exact limit and perform the App smoke interaction manually; do not claim UI-test success.
Execution note: direct and Xcode-launched Apps produced black screenshots with no accessible window; `GetConsoleOutput` reported `Accessibility: Not vending elements because elementWindow(25) is lower than shield(2001)`. Device Interaction has no macOS target. Statistics and History routes remain unverified in a visible macOS session; see the SDD progress ledger.

## Task 4: Update user documentation and complete regression verification

**Files:**
- Modify: `README.md`
- Verify: `StudyClockTests`, `StudyClockUITests`, App and Widget build outputs, `git diff --check`.

- [x] **Step 1: Compare the existing README with the approved design before editing**

Review the feature, data-boundary, project-structure, and design-record sections. Confirm the README currently documents history but not the statistics page, and carry forward this acceptance checklist to Step 2: App-only entry; 7 / 15 / 30 complete local days; comparison with the adjacent prior period; per-task shares and goal metrics; current-goal estimate caveat; unchanged Widget scope. Documentation review is direct inspection; do not add a test whose only purpose is checking prose.

- [x] **Step 2: Update README feature and data-boundary sections**

Add one concise feature bullet for the App statistics page; explain complete-day windows, adjacent-period comparison, and the current-goal estimate under data behavior; and revise “no analytics” to distinguish local statistics from absent remote analytics. Keep Widget behavior unchanged and App Group storage local. Add the approved design and plan documents to the existing design-record links.

- [x] **Step 3: Run the unit suite, focused UI tests, and final checks**

Run:

```bash
xcodebuild test -project StudyClock.xcodeproj -scheme StudyClock \
  -destination 'platform=macOS,arch=arm64' -only-testing:StudyClockTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

xcodebuild test -project StudyClock.xcodeproj -scheme StudyClock \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:StudyClockUITests/StudyClockUITests/testStatisticsPageOpensAndChangesPeriod \
  -only-testing:StudyClockUITests/StudyClockUITests/testHistoryCanBeClosed

git diff --check
git diff --no-index --check /dev/null docs/superpowers/specs/2026-10-01-study-statistics-design.md
git diff --no-index --check /dev/null docs/superpowers/plans/2026-10-01-study-statistics.md
```

Expected: 0 unit-test failures, both focused UI tests pass when macOS UI automation initializes, and no whitespace errors. Build the App and Widget Extension; verify the Widget target does not compile `StudyStatistics.swift` or `StudyStatisticsView.swift`. Confirm `StudyClockWidget.swift`, `StudyTimerWidgetState.swift`, and `ToggleStudyTimerIntent.swift` are unchanged.
The `--no-index` checks compare untracked documentation against `/dev/null`; Git may return status 1 because the files differ. Treat whitespace diagnostics, not that expected diff status, as the pass/fail signal.
Execution note: `StudyClockTests`, App / Widget builds, and whitespace checks passed. Both focused UI test commands ended before assertions because the macOS test runner could not establish its control session; direct signed and unsigned App launches exposed no window, so Task 3 Step 6 remains unverified. Exact results are in the SDD progress ledger.

- [x] **Step 4: Review final scope and leave all changes uncommitted**

Inspect `git diff --stat` and the changed-file list. Expected product changes are limited to the statistics domain / ViewModel / view / dashboard / tests / README, alongside the accepted design and plan documents. `project.pbxproj` and Widget source files remain unchanged. Do not commit or push unless TommyWu asks.
