# 学习日历与自定义任务实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在保留现有计时事件和 App Group store 的前提下，增加可增删归档的自定义任务、每日目标和排序，增加最近 12 个月学习日历与连续学习日，并让中号 Widget 按可读空间动态展示活动任务。

**Architecture:** `StudyTaskRecord` 增加归档状态；`StudyStore` 负责任务生命周期和活动/历史查询边界；计时事件仍由 `TimerReducer` 与 `TimerSnapshot` 解释，不复制每日计时数据。新增纯值 `StudyCalendarCalculator` 从快照生成 12 个月日数据和 streak，`TimerViewModel` 向 SwiftUI 提供活动任务、历史任务和聚合结果；Widget 只读取未归档任务并在固定中号空间内按当前任务优先展示。

**Tech Stack:** Swift 5 language mode、SwiftUI、Observation、SwiftData、WidgetKit、App Intents、Swift Testing、XCTest UI tests、现有 Xcode filesystem-synchronized groups。

**Spec:** `docs/superpowers/specs/2026-10-05-study-calendar-dynamic-tasks-design.md`

## Global Constraints

- 新安装仍创建现有三项任务作为可编辑起始值；这三项不是任务数量上限。
- 升级已有安装时保留现有 task ID、任务配置和计时事件，不重置或复制已有任务。
- 每项任务支持名称、每日目标时长和排序调整。
- 归档而非物理删除：归档任务不再出现在计时和 Widget 操作列表中，但仍留在历史记录、日统计和热力图汇总中。
- 小号 Widget 保持现状；中号 Widget 不再固定只渲染前三张卡。中号空间不足时展示当前计时任务优先、其余按排序尽量放入；其余任务仍可在 App 中访问。本阶段不增加大号 Widget。
- 修改每日目标后，历史目标完成率继续按当前每日目标估算，并保留现有页面说明；本功能不记录目标变更历史。
- 重命名保留 task ID 和所有计时事件；历史显示使用该 task 当前名称，不复制历史名称快照。
- 热力图范围从今天向前 12 个本地日历月的对应日期起，包含今天；今天显示截至当前的部分日累计。
- 热力图颜色等级固定为：无投入、(0, 1800) 秒、[1800, 3600) 秒、[3600, 7200) 秒、≥7200 秒。
- 连续学习日以本地日累计时长大于 0 作为定义，不依赖每日目标；当前连续天数可以向可见窗口之前延伸。
- 日边界通过 `Calendar` 计算；跨午夜事件按本地日切片，DST 日不按固定 86,400 秒计算。
- 计时器、Widget 只使用未归档任务；历史、7 / 15 / 30 天统计和日历分项包含归档任务。
- 不增加 SwiftData 每日汇总副本、登录、网络同步、番茄钟、任务颜色、永久删除、历史名称快照或大号 Widget。
- 不修改用户未点名的生产配置、Cloudflare/D1/Vectorize；不写入 API key、Cookie、token。
- 实现期间不自动 commit、push、force-push 或改写历史；只有 TommyWu 后续明确要求时才执行 Git 发布。

## Review Focus

1. **旧 App Group store 的模型兼容性：** 新增 `isArchived` 后旧任务必须默认视为未归档，既有 UUID、名称、目标、排序和计时事件保持不变。由 Task 1 的持久化打开/迁移 smoke 与回归测试覆盖。
2. **活动任务归档边界：** 正在计时的任务不能被归档，归档任务不能被 start/pause/toggle/reset；归档历史仍计入总时长。由 Task 1 的任务生命周期测试覆盖。
3. **今天和连续学习日边界：** 今天有部分计时应进入日历；今天无计时时当前 streak 从昨天计算；连续区间可延伸到 12 个月窗口之前。由 Task 2 的日历计算器测试覆盖。
4. **本地日期与 DST：** 跨午夜时长必须切到两个本地日，DST 日使用 `Calendar` 日边界而不是固定秒数。由 Task 2 的跨午夜/DST 测试覆盖。
5. **Widget 空间与任务顺序：** 当前任务必须优先，剩余活动任务按排序填充固定可读容量，隐藏项数量明确提示；小号 Widget 行为不能回归。由 Task 5 的纯值 Widget 状态测试和 Task 6 的构建/人工 smoke 覆盖。

## 文件与职责地图

### 数据与领域

- Modify: `StudyClock/Persistence/StudyTaskRecord.swift` — 给 `StudyTaskRecord` 增加 `isArchived`，默认值为 `false`。
- Modify: `StudyClock/Persistence/StudyStore.swift` — 活动/历史任务查询、创建、编辑、排序、归档/恢复、归档任务操作保护；保留既有事件流。
- Create: `StudyClock/Domain/StudyCalendar.swift` — 日历日值类型、颜色强度、streak 和日分项纯值计算。
- Modify: `StudyClock/Domain/StudyStatistics.swift` — 统计输入包含归档任务，保留当前目标估算语义。

### App 状态与界面

- Modify: `StudyClock/Timer/TimerViewModel.swift` — 分离活动任务与历史任务，暴露任务生命周期操作和日历查询。
- Create: `StudyClock/Views/TaskManagementView.swift` — 活动/归档任务列表、新增、排序、归档/恢复入口。
- Create: `StudyClock/Views/TaskEditorView.swift` — 名称与每日目标编辑；目标以小时/分钟输入，持久化为秒。
- Modify: `StudyClock/Views/TimerDashboardView.swift` — 增加“管理任务”入口；仪表盘仍只显示活动任务。
- Modify: `StudyClock/Views/HistoryView.swift` — 日总计和目标汇总包含归档任务。
- Create: `StudyClock/Views/StudyCalendarView.swift` — 12 个月热力图、颜色图例、streak 摘要和选中日期详情。
- Modify: `StudyClock/Views/StudyStatisticsView.swift` — 在现有统计页增加“统计 / 学习日历”切换，并刷新归档任务数据。

### Widget、测试与文档

- Modify: `StudyClock/Widgets/StudyTimerWidgetState.swift` — 提供中号 Widget 的可读容量、隐藏任务数量和当前任务优先顺序。
- Modify: `StudyClockWidget/StudyClockWidget.swift` — 中号使用动态紧凑布局；小号保持现有布局和行为。
- Modify: `StudyClockTests/StudyClockTests.swift` — 任务生命周期、日历聚合、历史保留、Widget 展示状态回归。
- Modify: `StudyClockUITests/StudyClockUITests.swift` — 任务管理和学习日历入口/周期切换/返回路径。
- Modify: `README.md` — 任务管理、归档、热力图、streak 和 Widget 展示规则。
- Verify: `StudyClock.xcodeproj/project.pbxproj` — 新文件进入 App target；共享 Widget DTO 进入 App 与 Widget target；App-only 日历/任务视图不进入 Widget target。

---

### Task 1: 扩展任务模型与 StudyStore 生命周期

**Files:**
- Modify: `StudyClock/Persistence/StudyTaskRecord.swift`
- Modify: `StudyClock/Persistence/StudyStore.swift`
- Test: `StudyClockTests/StudyClockTests.swift`

**Interfaces:**
- Produces `StudyTaskRecord.isArchived: Bool`，默认 `false`。
- Produces `StudyStore.tasks(includeArchived: Bool = false) throws -> [StudyTaskRecord]`；默认只返回可计时任务，`true` 返回活动和归档任务。
- Produces `StudyStore.createTask(name: String, dailyGoalSeconds: Int) throws -> UUID`。
- Produces `StudyStore.updateTask(id: UUID, name: String, dailyGoalSeconds: Int) throws`; name is trimmed and must not be empty; negative goals are normalized to 0.
- Produces `StudyStore.reorderTasks(_ taskIDs: [UUID]) throws`，参数必须包含当前所有活动任务且不重复。
- Produces `StudyStore.archiveTask(id: UUID) throws`、`StudyStore.restoreTask(id: UUID) throws`。
- Existing `start`, `pause`, `toggle`, `resetToday`, `widgetState` only accept non-archived task IDs.

- [ ] **Step 1: 写任务生命周期的失败测试**

在 `StudyClockTests.swift` 增加以下行为测试；测试使用 `StudyStore.makeInMemory()`，不测试 SwiftData 内部拷贝：

```swift
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
```

- [ ] **Step 2: 运行失败测试确认缺少生命周期 API**

运行：

```bash
xcodebuild test \
  -project StudyClock.xcodeproj \
  -scheme StudyClock \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:StudyClockTests/taskLifecycleCreatesEditsReordersArchivesAndRestores \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected：编译失败，先因 `isArchived`、`createTask`、`archiveTask` 等新接口不存在而失败；不得用修改测试来绕过缺失生产 API。

- [ ] **Step 3: 实现模型字段和错误类型**

在 `StudyTaskRecord` 增加带默认值的字段，并保留现有初始化调用可编译：

```swift
@Model
final class StudyTaskRecord {
    var id: UUID
    var name: String
    var dailyGoalSeconds: Int
    var sortOrder: Int
    var isArchived: Bool

    init(
        id: UUID,
        name: String,
        dailyGoalSeconds: Int,
        sortOrder: Int,
        isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.dailyGoalSeconds = dailyGoalSeconds
        self.sortOrder = sortOrder
        self.isArchived = isArchived
    }
}
```

`StudyStoreError` conforms to `LocalizedError` and `Equatable`; add these cases:

```swift
enum StudyStoreError: LocalizedError, Equatable {
    case invalidTaskName
    case taskNotFound
    case activeTaskMustBePaused
    case archivedTaskUnavailable
    case invalidTaskOrdering
}
```

每个错误提供稳定中文描述；UI 直接显示 `localizedDescription`，不在 View 层重复判断字符串。

- [ ] **Step 4: 实现活动/历史查询和任务写操作**

`tasks(includeArchived:)` 分支使用两个明确的 `FetchDescriptor`，避免在 `#Predicate` 中捕获布尔参数：

```swift
func tasks(includeArchived: Bool = false) throws -> [StudyTaskRecord] {
    let sort = [
        SortDescriptor(\.sortOrder),
        SortDescriptor(\.id)
    ]
    if includeArchived {
        return try context.fetch(FetchDescriptor(sortBy: sort))
    }
    return try context.fetch(FetchDescriptor(
        predicate: #Predicate<StudyTaskRecord> { !$0.isArchived },
        sortBy: sort))
}
```

`seedDefaultsIfNeeded()` 和 `migrateLegacyDataIfNeeded` 必须用 `tasks(includeArchived: true)` 或直接全量 Fetch，防止归档的默认任务被重复创建。新任务的排序为当前活动任务最大 `sortOrder + 1`；新名称去除首尾空白；目标存储 `max(value, 0)`。

`reorderTasks(_:)` 先取活动任务 ID 集合，要求与输入集合完全一致，然后按输入顺序写入 `sortOrder = 0...`，一次 `context.save()` 完成。`archiveTask` 先验证任务存在且未归档，再读取最新 `snapshot`; 若 `activeTaskID == id` 抛出 `.activeTaskMustBePaused`，否则设置 `isArchived = true`。`restoreTask` 只把已存在任务设为未归档，并将它放到活动任务末尾。

`start`, `pause`, `toggle`, `resetToday` 在写事件前调用统一的 `activeTask(id:)` 校验；未知 ID 使用 `.taskNotFound`，已归档 ID 使用 `.archivedTaskUnavailable`。不改变事件流、`observedActionID` 或 reducer 语义。

- [ ] **Step 5: 保持历史总计包含归档任务，Widget 只取活动任务**

`totalElapsed(on:now:calendar:)`、`historyDays` 相关的 App 查询使用 `tasks(includeArchived: true)`；`widgetState` 使用默认 `tasks()`。`StudyStore` 的历史查询仍基于完整 `TimerActionRecord`，不删除归档任务的动作。

- [ ] **Step 6: 运行 Task 1 测试和现有持久化回归**

运行：

```bash
xcodebuild test \
  -project StudyClock.xcodeproj \
  -scheme StudyClock \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:StudyClockTests/taskLifecycleCreatesEditsReordersArchivesAndRestores \
  -only-testing:StudyClockTests/archivingRunningTaskIsRejectedAndArchivedTaskCannotReceiveTimerActions \
  -only-testing:StudyClockTests/archivedTaskHistoryRemainsInDailyTotalAndWidgetExcludesIt \
  -only-testing:StudyClockTests/storeSeedsThreeTasksAndPersistsTimerActions \
  -only-testing:StudyClockTests/migrationCopiesHistoryOnceAndPreservesRunningTask \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected：新增测试和原有任务/迁移测试全部通过；默认仍创建“八股”“算法”“项目整理”，但可继续新增第四项。

- [ ] **Step 7: 对已有持久化 store 做手工兼容 smoke**

使用当前已有 App Group store 启动新构建，不执行清库、不删除 `/Applications/钟.app` 数据；确认原三项名称、目标、历史和当前计时仍存在，且读取旧任务时 `isArchived == false`。如果旧 store 无法打开，停止后修复模型迁移，不以删除数据库规避问题。

---

### Task 2: 实现 StudyCalendar 纯值聚合器

**Files:**
- Create: `StudyClock/Domain/StudyCalendar.swift`
- Modify: `StudyClockTests/StudyClockTests.swift`

**Interfaces:**

```swift
enum StudyCalendarIntensity: Int, Equatable, Sendable {
    case empty = 0
    case light = 1
    case medium = 2
    case strong = 3
    case veryStrong = 4
}

struct StudyCalendarTaskInput: Equatable, Sendable {
    let id: UUID
    let name: String
    let isArchived: Bool
    let sortOrder: Int
}

struct StudyCalendarTaskSummary: Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let isArchived: Bool
    let elapsed: TimeInterval
}

struct StudyCalendarDay: Equatable, Identifiable, Sendable {
    let date: Date
    let totalElapsed: TimeInterval
    let intensity: StudyCalendarIntensity
    let tasks: [StudyCalendarTaskSummary]

    var id: Date { date }
}

struct StudyCalendarReport: Equatable, Sendable {
    let startDate: Date
    let endDate: Date
    let days: [StudyCalendarDay]
    let currentStreak: Int
    let longestVisibleStreak: Int
}

enum StudyCalendarCalculator {
    static func calculate(
        tasks: [StudyCalendarTaskInput],
        snapshot: TimerSnapshot,
        now: Date,
        calendar: Calendar,
        months: Int = 12
    ) -> StudyCalendarReport
}
```

- [ ] **Step 1: 写边界和 streak 失败测试**

增加固定 UTC 测试，覆盖今天、12 个月起点、颜色边界、今天无投入、窗口外 streak：

```swift
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
    #expect(report.days.last?.intensity == .light)
    #expect(report.days.count == 366)
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
```

另加：跨午夜区间在相邻日期各贡献 60 秒；洛杉矶 DST 春季日期按 Calendar 日边界切分；归档任务仍出现在选中日的 `tasks` 中；0 秒日为 `.empty` 且不计入 streak。

- [ ] **Step 2: 运行失败测试确认聚合器不存在**

运行：

```bash
xcodebuild test \
  -project StudyClock.xcodeproj \
  -scheme StudyClock \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:StudyClockTests/calendarUsesTwelveCalendarMonthsIncludesTodayAndClassifiesIntensity \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected：因 `StudyCalendarCalculator` 和相关值类型不存在而编译失败。

- [ ] **Step 3: 实现日期窗口和逐日聚合**

`periodEnd = calendar.startOfDay(for: now)`；`startDate = calendar.date(byAdding: .month, value: -months, to: periodEnd)!`。从 `startDate` 逐日通过 `calendar.date(byAdding: .day, value: 1, ...)` 生成闭区间 `[startDate, periodEnd]`。每个日值对按 `sortOrder` 排序的全部任务调用：

```swift
snapshot.elapsed(
    taskID: task.id,
    on: day,
    calendar: calendar,
    now: now)
```

今天的活动区间使用 `now` 截断；未来日期不生成。`totalElapsed` 是所有任务的和；强度严格使用 `0`, `1800`, `3600`, `7200` 边界，保证 1800 秒属于 `.medium`、3600 秒属于 `.strong`、7200 秒属于 `.veryStrong`。

- [ ] **Step 4: 实现当前 streak 和可见窗口最长 streak**

当前 streak 的起点是：今天总时长大于 0 则今天，否则昨天。向前逐日检查 `totalElapsed > 0`，直到遇到空日或早于快照中最早的有效开始/区间日期；这样今天无投入时从昨天算，且连续区间可超过可见 12 个月窗口。没有任何历史时返回 0。

最长 streak 只在 `report.days` 可见日期上计算连续非空日长度，不把窗口外日期并入可见最长值。

- [ ] **Step 5: 运行 Task 2 聚合测试和原统计测试**

运行：

```bash
xcodebuild test \
  -project StudyClock.xcodeproj \
  -scheme StudyClock \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:StudyClockTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected：日历新增测试、现有跨午夜/DST 测试、现有统计测试全部通过；不产生 NaN 或 Infinity。

---

### Task 3: 接入 ViewModel 和任务管理界面

**Files:**
- Modify: `StudyClock/Timer/TimerViewModel.swift`
- Create: `StudyClock/Views/TaskManagementView.swift`
- Create: `StudyClock/Views/TaskEditorView.swift`
- Modify: `StudyClock/Views/TimerDashboardView.swift`
- Modify: `StudyClock/Views/HistoryView.swift`
- Modify: `StudyClockTests/StudyClockTests.swift`

**Interfaces:**
- `TimerViewModel.tasks` 只包含活动任务，保留现有仪表盘调用方式。
- `TimerViewModel.historicalTasks` 包含活动和归档任务。
- `TimerViewModel.archivedTasks` 返回 `historicalTasks.filter(\.isArchived)`。
- `TimerViewModel.addTask(name: String, dailyGoalSeconds: Int)`。
- `TimerViewModel.moveTasks(from: IndexSet, to: Int)`。
- `TimerViewModel.archiveTask(id: UUID)`、`restoreTask(id: UUID)`。
- `TimerViewModel.studyCalendar(now: Date, calendar: Calendar) -> StudyCalendarReport`。
- `TimerViewModel.studyStatistics(...)` 改为使用 `historicalTasks` 映射，归档任务仍出现在统计结果。

- [ ] **Step 1: 写 ViewModel 任务操作失败测试**

增加：新增任务后 active 列表增加且 Widget reloader 只刷新一次；归档后从 `tasks` 消失但在 `historicalTasks` 保留；恢复后回到 active；更新名称和目标后统计输入反映新值；排序后 `sortOrder` 与数组一致。

示例：

```swift
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
    #expect(reloader.reloadCount == 3)

    model.restoreTask(id: newTask.id)
    #expect(model.tasks.contains(where: { $0.id == newTask.id }))
    #expect(model.studyStatisticsTasks.contains(where: { $0.id == newTask.id && $0.name == "英语听力" }))
}
```

- [ ] **Step 2: 运行失败测试确认 ViewModel API 缺少**

运行聚焦测试；Expected：`historicalTasks`、`addTask`、`archiveTask` 等符号不存在。

- [ ] **Step 3: 扩展 ViewModel reload 和 mutation 流程**

`reload` 同时读取：

```swift
tasks = try store.tasks()
historicalTasks = try store.tasks(includeArchived: true)
```

`studyStatisticsTasks` 和 `studyCalendar` 使用 `historicalTasks`；`totalElapsed` 与 `historyDays` 的汇总使用历史任务，确保归档后今日/历史总计不下降。`progress` 和 `activeTask` 继续使用活动任务。

每个成功写操作都执行 `reload(now:)`，成功后调用 `reloader.reloadTimelines()`；失败只写入 `errorMessage`，不修改内存列表。`moveTasks` 先基于活动任务数组应用 SwiftUI 的 `move(fromOffsets:toOffset:)`，再把新 ID 顺序交给 store。

- [ ] **Step 4: 实现任务编辑页**

`TaskEditorView` 只接受值和闭包，不读取 SwiftData：

```swift
struct TaskEditorView: View {
    let title: String
    let initialName: String
    let initialGoalSeconds: Int
    let onSave: (String, Int) -> Void
}
```

名称使用 `String` 文本框；每日目标使用小时和分钟两个非负数字输入框，保存时计算 `hours * 3_600 + minutes * 60`。编辑已有目标时从秒数拆分；当前项目默认目标均为整分钟。名称为空时禁用保存并显示“请输入任务名称”。保存后由 ViewModel 统一校验和持久化。

- [ ] **Step 5: 实现任务管理页和入口**

`TaskManagementView` 使用活动任务 `List`，支持 `.onMove`；每行提供编辑和归档操作。归档任务单独放在“已归档” section，提供恢复按钮。新增按钮打开空编辑页；编辑按钮传入当前名称和目标。活动任务为空时显示“还没有活动任务”和“添加任务”按钮。

为入口和 UI 测试设置稳定标识：

```swift
.accessibilityLabel("管理学习任务")
.accessibilityIdentifier("task-management")
.accessibilityIdentifier("task-add")
.accessibilityIdentifier("task-edit-\(task.id.uuidString)")
.accessibilityIdentifier("task-archive-\(task.id.uuidString)")
```

`TimerDashboardView` toolbar 增加“管理任务”；仪表盘的 `ForEach` 继续遍历活动 `viewModel.tasks`，不显示归档任务。

- [ ] **Step 6: 修改历史页和现有统计映射**

`HistoryView` 继续展示既有日期列表，但 ViewModel 的 `StudyDaySummary.total` 和 `target` 来自历史任务；归档任务今日已有投入时不能从总计中消失。`StudyStatisticsTaskInput` 增加带默认值的 `isArchived: Bool = false`，`StudyStatisticsTaskSummary` 同步保留该字段；统计卡片显示“已归档”辅助标记，但仍显示历史投入和当前目标估算。

- [ ] **Step 7: 运行 ViewModel、Store 和现有 UI 编译测试**

运行 `StudyClockTests` 全量。确认错误场景也通过：store 初始化失败时新增/编辑/归档不崩溃；空活动任务仍能打开管理页并新增任务；归档任务历史仍在统计中。

---

### Task 4: 接入学习日历 UI 和统计页切换

**Files:**
- Create: `StudyClock/Views/StudyCalendarView.swift`
- Modify: `StudyClock/Views/StudyStatisticsView.swift`
- Modify: `StudyClock/Domain/StudyStatistics.swift`
- Modify: `StudyClockUITests/StudyClockUITests.swift`

**Interfaces:**
- `StudyCalendarView` 接收 `TimerViewModel`，通过 `viewModel.studyCalendar(now:calendar:)` 获取值。
- `StudyStatisticsView` 内部 `StudyStatisticsSection` 取 `.statistics` / `.calendar`，初始为 `.statistics`。
- `StudyStatisticsView` 的周期切换、快照变化、任务变化和日历变化仍触发当前统计刷新。

- [ ] **Step 1: 写 UI 测试入口和切换失败测试**

在 UI 测试中增加：打开“查看学习统计”，找到 `statistics-section-calendar`，切换后验证“学习日历”“当前连续学习”存在；切回“统计”验证“总体投入”；关闭后回到仪表盘。先运行确认新标识不存在而失败。

- [ ] **Step 2: 实现统计页分段切换**

在现有 `StudyStatisticsView` 顶部增加 `.segmented` Picker：

```swift
Picker("统计视图", selection: $selectedSection) {
    Text("统计")
        .tag(StudyStatisticsSection.statistics)
        .accessibilityIdentifier("statistics-section-statistics")
    Text("学习日历")
        .tag(StudyStatisticsSection.calendar)
        .accessibilityIdentifier("statistics-section-calendar")
}
.pickerStyle(.segmented)
.accessibilityIdentifier("statistics-section-picker")
```

统计分支保留现有总体摘要、任务卡和 7/15/30 天按钮；数据源已由 Task 3 改为包含归档任务。目标估算说明保持原文，不改为历史真实目标。

- [ ] **Step 3: 实现热力图布局**

`StudyCalendarView` 展示：

1. `当前连续学习 N 天` 和 `可见范围最长连续 N 天`；
2. 月份标签和按 `calendar.firstWeekday` 对齐的 7 列网格；
3. 每个日期的颜色等级、日期 accessibility label 和选中状态；
4. 固定颜色图例：无投入、< 30 分钟、30–60 分钟、1–2 小时、≥ 2 小时；
5. 选中日期的总时长和分项任务列表，归档任务显示“已归档”。

使用 `ScrollView` 承载 12 个月网格；不把网格放入主仪表盘的逐秒 `TimelineView`。选中日期默认今天；无投入日期显示“当天没有学习记录”，不隐藏日期。

- [ ] **Step 4: 处理日期刷新和可访问性**

日历 view 在 `onAppear`、`viewModel.snapshot`、`viewModel.studyStatisticsTasks` 和 `viewModel.calendar` 变化时重新计算。每个日期按钮的 accessibility 内容包含完整日期、累计时长和强度，不只暴露颜色。当天运行中的计时通过现有 snapshot 计算，不单独写入日历存储。

- [ ] **Step 5: 运行 UI 测试和统计回归**

运行：

```bash
xcodebuild test \
  -project StudyClock.xcodeproj \
  -scheme StudyClock \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:StudyClockUITests/testStatisticsPageOpensCalendarAndReturnsToStatistics \
  -only-testing:StudyClockTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

如果当前 host 的 macOS UI automation 仍被 system shield 阻止，保留编译结果和失败原因，不把 UI 自动化失败误报为产品逻辑失败；同时使用 `StudyCalendarCalculator` 和 ViewModel 测试证明数据行为。

---

### Task 5: 让中号 Widget 动态展示活动任务

**Files:**
- Modify: `StudyClock/Widgets/StudyTimerWidgetState.swift`
- Modify: `StudyClockWidget/StudyClockWidget.swift`
- Modify: `StudyClockTests/StudyClockTests.swift`

**Interfaces:**
- Existing `displayTasks` 继续把当前任务移动到第一项。
- Add `static let mediumDisplayCapacity = 4` as the single tested layout constant.
- Add `mediumDisplayTasks: [StudyTimerWidgetTask]` returning `displayTasks.prefix(Self.mediumDisplayCapacity)`。
- Add `hiddenMediumTaskCount: Int` returning `max(tasks.count - mediumDisplayTasks.count, 0)`。

- [ ] **Step 1: 写 Widget 动态容量和顺序失败测试**

```swift
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
}
```

另加不超过 4 项时不隐藏、没有当前任务时保留 sortOrder、空任务返回空数组等断言；现有小号 entry 测试原样保留。

- [ ] **Step 2: 实现纯值容量和隐藏数量**

把容量集中放在 `StudyTimerWidgetEntryState`，不要在 SwiftUI body 中散落 `prefix(3)`。`displayTasks` 继续以当前任务优先；`mediumDisplayTasks` 只截断展示，不改变 `tasks` 原始数据或 totalElapsed。

- [ ] **Step 3: 实现中号紧凑布局**

将中号的三张大卡改为可读的紧凑双列网格，每项显示任务名、累计时间、运行状态和已有 start/pause/continue/reset 操作。使用 `entry.mediumDisplayTasks`；超过容量时在底部显示：

```swift
Text("还有 \(entry.hiddenMediumTaskCount) 项，打开 App 查看")
```

并通过已有 `studyclock://dashboard` Link 打开 App。当前任务保持第一项和运行高亮。小号分支不改动 `displayedTask`、按钮或文案。

- [ ] **Step 4: 确认归档任务不会进入 Widget**

Widget provider 继续使用 `StudyStore.widgetState` 的活动任务查询；对旧 Widget intent 的 stale task ID，Store 返回 `.archivedTaskUnavailable`，Intent 写入既有错误状态并 reload timeline。不要在 Widget DTO 中复制归档状态。

- [ ] **Step 5: 运行 Widget 状态测试和 App/Widget 编译**

运行 `StudyClockTests`，再执行：

```bash
xcodebuild build \
  -project StudyClock.xcodeproj \
  -scheme StudyClock \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

确认 `StudyTimerWidgetState.swift`、`ToggleStudyTimerIntent.swift`、`ResetStudyTimerIntent.swift` 同时能被 App/Widget 正确编译；TaskManagement、StudyCalendar 等 App-only 文件不进入 Widget target。

---

### Task 6: 文档、UI 测试和整体验证

**Files:**
- Modify: `README.md`
- Modify: `StudyClockUITests/StudyClockUITests.swift`
- Verify: `StudyClock.xcodeproj/project.pbxproj`

- [ ] **Step 1: 完善 UI 测试场景**

增加以下稳定路径：

```swift
@MainActor
func testTaskManagementCanAddTask() throws {
    let app = XCUIApplication()
    app.launch()

    app.buttons["管理学习任务"].tap()
    XCTAssertTrue(app.staticTexts["任务管理"].waitForExistence(timeout: 5))
    app.buttons["task-add"].tap()
    app.textFields["任务名称"].tap()
    app.textFields["任务名称"].typeText("英语听力")
    app.buttons["保存任务"].tap()
    XCTAssertTrue(app.staticTexts["英语听力"].waitForExistence(timeout: 5))
}

@MainActor
func testStatisticsPageOpensCalendarAndReturnsToStatistics() throws {
    let app = XCUIApplication()
    app.launch()
    app.buttons["查看学习统计"].tap()
    app.buttons["statistics-section-calendar"].tap()
    XCTAssertTrue(app.staticTexts["学习日历"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["当前连续学习"].waitForExistence(timeout: 5))
    app.buttons["statistics-section-statistics"].tap()
    XCTAssertTrue(app.staticTexts["总体投入"].waitForExistence(timeout: 5))
}
```

任务编辑页的名称、目标输入和归档操作使用固定 accessibility identifiers；不根据动态坐标点击。

- [ ] **Step 2: 更新 README**

补充：

- 任务可新增、改名、设置每日目标、排序、归档/恢复；默认三项只是起始值。
- 归档不删除历史，历史/统计/日历仍可见。
- 学习日历包含最近 12 个月、今天、实际投入颜色等级和 streak 定义。
- 中号 Widget 当前任务优先，空间不足时提示剩余任务并引导打开 App；小号 Widget 行为不变。
- 明确目标完成率仍按当前目标估算。

同步项目结构清单，加入 `StudyCalendar.swift`、`TaskManagementView.swift`、`TaskEditorView.swift`、`StudyCalendarView.swift`。

- [ ] **Step 3: 运行完整单元测试、UI 编译和 signed build**

依次运行：

```bash
xcodebuild test \
  -project StudyClock.xcodeproj \
  -scheme StudyClock \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:StudyClockTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

xcodebuild build \
  -project StudyClock.xcodeproj \
  -scheme StudyClock \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

xcodebuild build \
  -project StudyClock.xcodeproj \
  -scheme StudyClock \
  -destination 'platform=macOS,arch=arm64'
```

Expected：单元测试 `TEST SUCCEEDED`，无签名 App/Widget build 和正常签名 build 均 `BUILD SUCCEEDED`。

- [ ] **Step 4: 验证签名、target membership 和差异**

运行：

```bash
codesign --verify --deep --strict --verbose=2 \
  "$HOME/Library/Developer/Xcode/DerivedData/StudyClock-*/Build/Products/Debug/StudyClock.app"
git diff --check
git status --short
```

确认 App 嵌入 Widget Extension，Metadata 包含现有 toggle/reset intents；确认工作区只包含本计划涉及文件，不包含 `build/`、DerivedData、`.superpowers/` 或凭据。

- [ ] **Step 5: 进行可用表面 smoke 并准确报告限制**

安装并启动最新 signed App，确认：旧数据仍存在；任务管理可创建/编辑/归档/恢复；统计页可切换学习日历；归档任务不出现在计时列表但仍出现在历史/日历明细。尝试打开中号 Widget；如果当前 host 仍不支持 Widget Preview 或被 screen shield 阻止通知中心，记录为环境限制，不声称 Widget 视觉交互已验收。

## 交付边界

- 本计划完成后默认保持当前 feature branch 工作区，不自动 commit 或 push。
- 只有 TommyWu 明确要求 Git 发布时，才按 `clean-commit` 流程检查、提交和推送。
- 任何无法在当前 host 完成的通知中心视觉验证，都在最终报告中与单元测试、编译和本地 App smoke 分开列出。
