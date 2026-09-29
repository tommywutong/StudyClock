# macOS 原生学习计时小组件 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把“钟”的同一份本地学习计时状态安全地暴露为可暂停/继续的 macOS 通知中心原生小组件。

**Architecture:** App 与 Widget Extension 通过同一个 App Group SwiftData store 读取事件流；主 App 在首次启动时把旧默认 store 幂等导入共享 store。共享的 `StudyTimerWidgetState` 只读取事件流并生成 Widget entry；`ToggleStudyTimerIntent` 经同一 `StudyStore.toggle` 写入事件，再刷新 Timeline。Widget 用 dynamic-date timer 渲染运行中累计，不靠逐秒 Timeline。

**Tech Stack:** Swift 6、SwiftUI、SwiftData、WidgetKit、App Intents、Testing、Xcode macOS Widget Extension。

**Spec:** `docs/superpowers/specs/2026-09-28-macos-native-study-widget-design.md`

## Global Constraints

- 本轮仅支持 macOS `systemSmall` 和 `systemMedium` Widget；不做 iOS Widget、Live Activity、灵动岛、桌面悬浮窗或 Vorssaint 集成。
- 使用 App Group `group.com.tommywu.StudyClock`；App 与 Extension 必须读写同一份 SwiftData 事件记录。
- 旧默认 SwiftData store 迁移必须保留历史，按稳定 UUID 幂等去重，且不得删除旧文件。
- Widget 可以显示系统实时递增的时长，但不得以每秒 Timeline reload 或自定义翻页动画实现。
- Widget 内只有暂停/继续；任务切换仍在主 App 完成。
- 不写入密钥、Cookie、token；不改 CloudKit、服务器或生产环境配置；不 commit 或 push。
- 每次 start/pause/switch/updateTask 成功后刷新 `StudyClockWidget` Timeline；失败状态不参与计时计算。

## Review Focus

1. **升级后已有历史：** 旧 store 的自定义任务、跨午夜区间、运行中任务和事件 UUID 迁移一次且仅一次，重试不会双计时。
2. **过期 Widget entry：** 用户在 App 内切换任务后点旧 Widget 的按钮，Intent 基于最新共享快照追加正确 start/pause 事件。
3. **日期边界：** 23:59 开始、跨越本地午夜的活动在 Widget 到新一天后从 0 重新累计，而旧一天保持正确时长。
4. **运行时动态时长：** 已有累计加上活动区间的 reference date 连续递增；暂停 entry 的时间完全固定。
5. **共享容器故障：** App Group URL、store 或 Intent 写入失败时不创建空白替代数据、不报告假成功，Widget 有可打开 App 的错误状态。

---

## 文件结构与职责

| 路径 | 责任 |
|---|---|
| `StudyClock/StudyClock/Persistence/StudyStore.swift` | 默认/共享 store 的构造、幂等迁移、事件读取、原子 toggle、Widget 查询与失败状态。 |
| `StudyClock/StudyClock/Persistence/StudyTaskRecord.swift` | 保持现有 SwiftData schema；迁移时直接复制任务与事件字段。 |
| `StudyClock/StudyClock/Widgets/StudyTimerWidgetState.swift` | 跨 App/Extension 的值类型 DTO、entry 计算、下一本地午夜与实时计时 reference date。 |
| `StudyClock/StudyClock/Widgets/ToggleStudyTimerIntent.swift` | Widget `Button(intent:)` 的薄适配层；调用 store 的单一 toggle API。 |
| `StudyClock/StudyClock/Timer/TimerViewModel.swift` | 主 App 成功改变数据后刷新 Widget Timeline。 |
| `StudyClock/StudyClockWidget/StudyClockWidget.swift` | 真实 TimelineProvider、A 布局的小号/中号 UI、dynamic date、Link 与交互按钮。 |
| `StudyClock/StudyClock/StudyClock.entitlements` | App 的 App Group entitlement。 |
| `StudyClock/StudyClockWidget/StudyClockWidgetExtension.entitlements` | Extension 的相同 App Group entitlement。 |
| `StudyClock/StudyClockTests/StudyClockTests.swift` | 迁移、toggle、Widget state、日期边界回归测试。 |
| `StudyClock/StudyClock.xcodeproj/project.pbxproj` | 由 Xcode 项目编辑操作更新：target membership、Extension/App entitlements 和 source build phases。不要手工文本编辑。 |

`StudyStore.swift`、`StudyTaskRecord.swift`、`TimerActionValue.swift`、`TimerReducer.swift`、`TimerSnapshot.swift`、`TaskProgress.swift`、`StudyTimerWidgetState.swift` 与 `ToggleStudyTimerIntent.swift` 必须同时加入 **StudyClock** 与 **StudyClockWidgetExtension** target；不复制模型或 reducer 源码。

## Task 1: 共享 SwiftData 容器、幂等迁移与原子计时操作

**Files:**
- Create: `StudyClock/StudyClock/Widgets/StudyTimerWidgetState.swift`
- Modify: `StudyClock/StudyClock/Persistence/StudyStore.swift`
- Modify: `StudyClock/StudyClockTests/StudyClockTests.swift`
- Modify through Xcode target membership: `StudyClock/StudyClock/Persistence/StudyStore.swift`, `StudyClock/StudyClock/Persistence/StudyTaskRecord.swift`, `StudyClock/StudyClock/Domain/TimerActionValue.swift`, `StudyClock/StudyClock/Domain/TimerReducer.swift`, `StudyClock/StudyClock/Domain/TimerSnapshot.swift`, `StudyClock/StudyClock/Domain/TaskProgress.swift`, `StudyClock/StudyClock/Widgets/StudyTimerWidgetState.swift`

**Interfaces:**
- Consumes: `TimerReducer.reduce(_:) -> TimerSnapshot`, `TimerSnapshot.elapsed(taskID:on:calendar:now:)`, existing SwiftData models.
- Produces:
  ```swift
  enum StudyStoreLocation { case legacyDefault, appGroup(URL), explicit(URL) }

  @MainActor
  final class StudyStore {
      static let appGroupIdentifier = "group.com.tommywu.StudyClock"
      static let widgetKind = "StudyClockWidget"
      static func makeApplicationStore() throws -> StudyStore
      static func makeWidgetStore() throws -> StudyStore
      static func makePersistent(at url: URL) throws -> StudyStore
      static func migrateLegacyDataIfNeeded(from legacy: StudyStore, to shared: StudyStore) throws
      func toggle(taskID: UUID, at date: Date = .now) throws
      func widgetState(now: Date = .now, calendar: Calendar = .current) throws -> StudyTimerWidgetState
      func lastTouchedTaskID() throws -> UUID?
  }
  ```
- Invariants: every write uses `observedActionID` from the latest stored event; migrations insert an action only when its UUID does not already exist; status text is stored in App Group `UserDefaults` only and never used by `TimerReducer`.

- [ ] **Step 1: Write failing migration and toggle tests**

  Extend `StudyClockTests` with deterministic UTC tests using two temporary SQLite URLs. Add these helpers to the test type before the tests, then seed the legacy store, customize `tasks[0].name`, record a session crossing midnight and leave `tasks[1]` running. Assert import preserves task fields, active task and elapsed values; invoke import a second time and assert total elapsed is unchanged. Add the stale-entry toggle test below.

  ```swift
  private var utcCalendar: Calendar {
      var value = Calendar(identifier: .gregorian)
      value.timeZone = TimeZone(secondsFromGMT: 0)!
      return value
  }

  private func temporaryStoreURL(_ label: String) -> URL {
      FileManager.default.temporaryDirectory
          .appending(path: "StudyClockTests-\(label)-\(UUID().uuidString).store")
  }
  ```

  ```swift
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

      try StudyStore.migrateLegacyDataIfNeeded(from: legacy, to: shared)
      try StudyStore.migrateLegacyDataIfNeeded(from: legacy, to: shared)

      let migratedTasks = try shared.tasks()
      let snapshot = try shared.snapshot(now: Date(timeIntervalSince1970: 86_600), calendar: utcCalendar)
      #expect(migratedTasks[0].name == "系统设计")
      #expect(snapshot.activeTaskID == tasks[1].id)
      #expect(snapshot.elapsed(taskID: tasks[0].id, on: Date(timeIntervalSince1970: 0), calendar: utcCalendar, now: Date(timeIntervalSince1970: 86_600)) == 60)
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
  ```

- [ ] **Step 2: Run the two new tests and confirm they fail for missing APIs**

  Run with Xcode `RunSomeTests` against `StudyClockTests/migrationCopiesHistoryOnceAndPreservesRunningTask()` and `StudyClockTests/toggleUsesLatestStateForAnOutdatedWidgetTask()`.

  Expected: compilation failure because `makePersistent`, `migrateLegacyDataIfNeeded`, and `toggle` do not exist.

- [ ] **Step 3: Implement explicit container creation and migration**

  In `StudyStore`, centralize schema creation and create an explicit persistent URL factory:

  ```swift
  private static func makeContainer(at url: URL, inMemory: Bool = false) throws -> ModelContainer {
      let configuration = ModelConfiguration(
          url: url,
          isStoredInMemoryOnly: inMemory,
          cloudKitDatabase: .none)
      return try ModelContainer(
          for: StudyTaskRecord.self, TimerActionRecord.self,
          configurations: configuration)
  }

  static func makePersistent(at url: URL) throws -> StudyStore {
      try StudyStore(container: makeContainer(at: url))
  }
  ```

  `makeApplicationStore()` must resolve `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)`, append `Library/Application Support/StudyClock.store`, make the parent directory, open the shared container, open the unchanged legacy-default container only when the App Group migration version is absent, perform the idempotent import, then store migration version `1` in `UserDefaults(suiteName: appGroupIdentifier)`. `TimerViewModel` uses this factory. `makeWidgetStore()` opens only the shared URL and first verifies the same migration version; if the main App has never initialized the group, it throws a recognizable `StudyStoreError.requiresAppLaunch` instead of seeding an empty Widget database.

  Implement `migrateLegacyDataIfNeeded` as two UUID-keyed passes. Copy every legacy task’s ID/name/goal/sort order into the shared task with the same ID or insert it; fetch shared action IDs once, then insert only legacy actions whose ID is absent. Save once after each pass. Never delete either store.

- [ ] **Step 4: Implement one authoritative toggle and widget query**

  Add `toggle(taskID:at:)`, reuse `snapshot` at `date`, and append either a pause for the requested currently active task or a start for the requested task. Keep `start`/`pause` public for existing callers, but make all three use one private `append(_:device:)` path. Add `lastTouchedTaskID()` using the same `(happenedAt, id.uuidString)` ordering as `latestActionID()`.

  Define the value-only DTO in `StudyTimerWidgetState.swift`; it must not expose `@Model` objects:

  ```swift
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
  ```

  `widgetState(now:calendar:)` fetches ordered tasks once, obtains a single snapshot, calculates each task’s `elapsed` for `calendar.startOfDay(for: now)`, loads the non-timing status message from App Group `UserDefaults`, and returns a value snapshot.

- [ ] **Step 5: Re-run focused tests and existing persistence tests**

  Run the two new tests plus existing `storeSeedsThreeTasksAndPersistsTimerActions()` and `sessionCrossingMidnightContributesToBothLocalDays()` through Xcode `RunSomeTests`.

  Expected: all pass. Confirm the repeated migration assertion proves no doubled intervals.

## Task 2: Widget state-to-entry transformation and time-boundary tests

**Files:**
- Modify: `StudyClock/StudyClock/Widgets/StudyTimerWidgetState.swift`
- Modify: `StudyClock/StudyClockTests/StudyClockTests.swift`

**Interfaces:**
- Consumes: `StudyTimerWidgetState` from Task 1.
- Produces:
  ```swift
  struct StudyTimerWidgetEntryState: TimelineEntry, Equatable {
      let date: Date
      let tasks: [StudyTimerWidgetTask]
      let displayedTaskID: UUID?
      let isRunning: Bool
      let elapsedReferenceDate: Date?
      let totalElapsed: TimeInterval
      let statusMessage: String?
  }

  enum StudyTimerWidgetEntryFactory {
      static func unavailable(now: Date) -> StudyTimerWidgetEntryState
  }

  extension StudyTimerWidgetState {
      func makeEntry(calendar: Calendar) -> StudyTimerWidgetEntryState
      func nextRefreshDate(calendar: Calendar) -> Date
  }
  ```

- [ ] **Step 1: Write failing entry calculation tests**

  ```swift
  @Test func runningWidgetEntryUsesCumulativeElapsedReferenceDate() {
      let now = Date(timeIntervalSince1970: 10_000)
      let task = StudyTimerWidgetTask(id: UUID(), name: "算法", elapsed: 3_600, target: 7_200)
      let state = StudyTimerWidgetState(
          tasks: [task], activeTaskID: task.id, activeStartedAt: now.addingTimeInterval(-600),
          lastTouchedTaskID: task.id, now: now, statusMessage: nil)

      let entry = state.makeEntry(calendar: utcCalendar)
      #expect(entry.isRunning)
      #expect(entry.displayedTaskID == task.id)
      #expect(entry.elapsedReferenceDate == now.addingTimeInterval(-3_600))
  }

  @Test func widgetEntryRefreshesAtNextLocalMidnight() {
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(secondsFromGMT: 0)!
      let now = Date(timeIntervalSince1970: 86_399)
      let state = StudyTimerWidgetState(tasks: [], activeTaskID: nil, activeStartedAt: nil, lastTouchedTaskID: nil, now: now, statusMessage: nil)
      #expect(state.nextRefreshDate(calendar: calendar) == Date(timeIntervalSince1970: 86_400))
  }
  ```

- [ ] **Step 2: Run tests and verify missing entry APIs fail**

  Run the two named tests using Xcode `RunSomeTests`.

  Expected: compile failure because `StudyTimerWidgetEntryState`, `makeEntry`, and `nextRefreshDate` do not exist.

- [ ] **Step 3: Implement deterministic display-task and reference-date rules**

  `makeEntry` chooses `activeTaskID` when non-nil, otherwise `lastTouchedTaskID`; it sets `isRunning` only when both the active task and `activeStartedAt` exist. For an active display task, find its `elapsed` and set `elapsedReferenceDate = now.addingTimeInterval(-elapsed)`; otherwise set it to `nil`. `nextRefreshDate` returns `calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!`.

  Do not embed `TimerSnapshot`, SwiftData, `WidgetCenter`, or SwiftUI views in this file. This keeps date math testable in the app test target and ensures the same DTO builds in both targets.

- [ ] **Step 4: Add paused and empty-state tests**

  Add one test asserting a paused state displays `lastTouchedTaskID`, returns `isRunning == false`, and has `elapsedReferenceDate == nil`; add one test asserting an empty state has no display task and no reference date. These pin the Widget’s no-button condition.

- [ ] **Step 5: Run the full `StudyClockTests` target**

  Run Xcode `RunSomeTests` for all `StudyClockTests` tests.

  Expected: existing reducer/history behavior and all entry-state cases pass.

## Task 3: App Intent, Widget refresh orchestration, and App Group capabilities

**Files:**
- Create: `StudyClock/StudyClock/Widgets/ToggleStudyTimerIntent.swift`
- Modify: `StudyClock/StudyClock/Timer/TimerViewModel.swift`
- Create: `StudyClock/StudyClock/StudyClock.entitlements`
- Create: `StudyClock/StudyClockWidget/StudyClockWidgetExtension.entitlements`
- Modify through Xcode target membership: `StudyClock/StudyClock/Widgets/ToggleStudyTimerIntent.swift`
- Modify through Xcode target settings/capabilities: `StudyClock`, `StudyClockWidgetExtension`
- Modify: `StudyClock/StudyClockTests/StudyClockTests.swift`

**Interfaces:**
- Consumes: `StudyStore.makeWidgetStore()`, `StudyStore.toggle(taskID:at:)`, `StudyStore.widgetKind`.
- Produces:
  ```swift
  struct ToggleStudyTimerIntent: AppIntent {
      static let title: LocalizedStringResource = "切换学习计时"
      @Parameter(title: "任务 ID") var taskID: String
      init(taskID: String)
      init()
      func perform() async throws -> some IntentResult
  }
  ```

- [ ] **Step 1: Write the failing refresh-after-mutation test seam**

  Introduce a protocol only for the side effect:

  ```swift
  protocol StudyClockWidgetReloading {
      func reloadTimelines()
  }

  struct StudyClockWidgetReloader: StudyClockWidgetReloading {
      func reloadTimelines() { WidgetCenter.shared.reloadTimelines(ofKind: StudyStore.widgetKind) }
  }
  ```

  Make `TimerViewModel` receive `reloader: any StudyClockWidgetReloading = StudyClockWidgetReloader()` and test it with a counter fake:

  ```swift
  @MainActor
  @Test func successfulTimerToggleReloadsWidgetTimeline() throws {
      let reloader = RecordingWidgetReloader()
      let viewModel = TimerViewModel(store: try StudyStore.makeInMemory(), reloader: reloader)
      let task = try #require(viewModel.tasks.first)
      viewModel.toggle(taskID: task.id, at: Date(timeIntervalSince1970: 1_000))
      #expect(reloader.reloadCount == 1)
  }
  ```

- [ ] **Step 2: Run the test and verify it fails**

  Run `successfulTimerToggleReloadsWidgetTimeline()` with Xcode `RunSomeTests`.

  Expected: compile failure because `StudyClockWidgetReloading` and the `reloader` initializer argument are missing.

- [ ] **Step 3: Implement reload only after successful writes**

  Add the protocol and WidgetKit-backed implementation under `#if canImport(WidgetKit)`. Change `TimerViewModel`’s default store factory from `StudyStore.makeLocal()` to `StudyStore.makeApplicationStore()`. In `TimerViewModel.toggle` and `updateTask`, call `reloader.reloadTimelines()` only after the store write succeeds and `reload(now:)` has completed without an error. Do not request a timeline reload from `reload()` itself, history rendering, or `TimelineView` ticks.

- [ ] **Step 4: Implement the App Intent as a thin adapter**

  `ToggleStudyTimerIntent.perform()` parses `UUID(uuidString: taskID)`, then uses `await MainActor.run` to open `StudyStore.makeWidgetStore()` and call `toggle(taskID:)`. On success it clears the shared `widgetStatusMessage`, reloads `StudyClockWidget`, then returns `.result()`. On invalid UUID, a missing migration marker, or store error, it writes the short user-facing status `“无法更新计时，请打开 App 重试”` to App Group `UserDefaults`, reloads the Timeline, and returns `.result()` without modifying timer records.

  The intent’s `openAppWhenRun` remains `false`: it must perform real pause/continue work in the Widget process. Add `ToggleStudyTimerIntent.swift` to both app and extension targets.

- [ ] **Step 5: Add App Group capability and validate target membership**

  Create both entitlement plists with the exact group:

  ```xml
  <key>com.apple.security.application-groups</key>
  <array>
      <string>group.com.tommywu.StudyClock</string>
  </array>
  ```

  Use Xcode target build-setting/capability operations to set `CODE_SIGN_ENTITLEMENTS` to the matching plist for each target. Add all Task 1 shared source files and `ToggleStudyTimerIntent.swift` to the Widget Extension Compile Sources. Add the app URL type `studyclock` with `CFBundleURLSchemes = ["studyclock"]` to the **StudyClock** target using Xcode’s Info.plist editing tool, so `widgetURL(studyclock://dashboard)` launches the App. Then build the macOS app.

  Expected: `StudyClock` and `StudyClockWidgetExtension` compile without duplicate definitions, missing target membership, or missing App Group entitlement errors.

- [ ] **Step 6: Run the focused test and build**

  Run `successfulTimerToggleReloadsWidgetTimeline()` and the macOS `BuildProject` action.

  Expected: test passes; app and Widget Extension build successfully.

## Task 4: Replace the template Widget with the selected native A layout

**Files:**
- Modify: `StudyClock/StudyClockWidget/StudyClockWidget.swift`
- Modify: `StudyClock/StudyClockWidget/StudyClockWidgetBundle.swift`
- Modify: `StudyClock/StudyClockTests/StudyClockTests.swift` only if a view-independent entry formatting helper is needed

**Interfaces:**
- Consumes: `StudyStore.makeWidgetStore()`, `StudyTimerWidgetState.makeEntry(calendar:)`, `StudyTimerWidgetEntryState`, `ToggleStudyTimerIntent(taskID:)`.
- Produces: `StudyClockWidget` with kind `StudyStore.widgetKind`, `systemSmall` and `systemMedium` configurations.

- [ ] **Step 1: Write a failing unavailable-entry test**

  Keep provider error handling out of the view layer. Test the shared factory introduced in Task 2:

  ```swift
  @Test func unavailableWidgetEntryExplainsHowToRecover() {
      let entry = StudyTimerWidgetEntryFactory.unavailable(now: Date(timeIntervalSince1970: 10_000))
      #expect(entry.statusMessage == "无法读取学习计时，请打开 App")
      #expect(entry.displayedTaskID == nil)
      #expect(entry.elapsedReferenceDate == nil)
      #expect(entry.tasks.isEmpty)
  }
  ```

- [ ] **Step 2: Run the unavailable-entry test and confirm it fails**

  Run `unavailableWidgetEntryExplainsHowToRecover()` using Xcode `RunSomeTests`.

  Expected: compile failure because `StudyTimerWidgetEntryFactory.unavailable(now:)` is absent.

- [ ] **Step 3: Implement Provider and minimal Timeline**

  Replace `SimpleEntry`, 😀 placeholders and hourly entries with `StudyTimerWidgetEntryState`. Because `StudyStore` is `@MainActor`, `getSnapshot` and `getTimeline` wrap their load in `Task { @MainActor in ... }` before invoking the completion handler. On success, load `StudyStore.makeWidgetStore().widgetState(now:calendar:)`, generate one entry at `state.now`, and use `.after(state.nextRefreshDate(calendar:))`. On error, use `StudyTimerWidgetEntryFactory.unavailable(now:)` and `.after(Calendar.current.date(byAdding: .hour, value: 1, to: .now)!)`. The provider must not make periodic minute/second entries.

- [ ] **Step 4: Implement A layout for both widget families**

  Add a family switch inside the entry view:

  ```swift
  @ViewBuilder
  private var elapsedView: some View {
      if entry.isRunning, let reference = entry.elapsedReferenceDate {
          Text(reference, style: .timer)
              .monospacedDigit()
      } else {
          Text(format(entry.displayedTask?.elapsed ?? entry.totalElapsed))
              .monospacedDigit()
      }
  }
  ```

  - `systemMedium`: header with running/paused state; current/recent task, goal, `elapsedView`, green status dot while running; a single `Button(intent: ToggleStudyTimerIntent(taskID: task.id.uuidString))` labelled `暂停` or `继续`; ordered rows for all tasks with capped progress width `min(elapsed / max(target, 1), 1)` and monospaced `H:MM` labels.
  - `systemSmall`: current/recent task, `elapsedView`, one pause/continue button; omit progress rows.
  - Empty state: show “当前没有计时任务” and today’s total; no intent button.
  - Error state: show `statusMessage` and a `Link`/`widgetURL` to `studyclock://dashboard`; no action button.
  - Give the Widget root `widgetURL(URL(string: "studyclock://dashboard"))`, except interactive controls must retain their `Button(intent:)` behavior. Mark the dynamic task/time container with `invalidatableContent()`.
  - Use `.containerBackground(for: .widget)` and `configurationDisplayName("学习计时")`; do not use the template strings `My Widget`, `Time:`, or any emoji placeholder.

- [ ] **Step 5: Add and run entry view edge tests**

  Test Task 2’s empty and paused entry helpers plus Task 4’s unavailable entry factory. Run all `StudyClockTests` via Xcode `RunSomeTests`.

  Expected: all app-level logic passes. Do not add snapshot tests that merely assert labels or view hierarchy forwarding.

- [ ] **Step 6: Build and render Widget previews**

  Build the macOS project. Use Xcode preview rendering for `.systemSmall` and `.systemMedium` states covering active, paused and empty entries; inspect that the primary timer and action fit, the medium progress rows remain legible, and dynamic type does not truncate an action label.

## Task 5: End-to-end macOS Notification Center verification and cleanup

**Files:**
- Modify only if verification exposes a real defect: exact file from Tasks 1–4.
- Do not create permanent documentation beyond the approved spec and this plan.

**Interfaces:**
- Consumes: built `StudyClock.app` and `StudyClockWidgetExtension.appex`.
- Produces: a verified local `/Applications/钟.app` containing the Widget Extension.

- [ ] **Step 1: Build and install the macOS product**

  Select `My Mac`, run Xcode `BuildProject`, then replace `/Applications/钟.app` with the built product and verify its signature. Stop any old process before reopening so macOS loads the new Widget Extension bundle.

  Expected: the installed app contains `Contents/PlugIns/StudyClockWidgetExtension.appex` and launches successfully.

- [ ] **Step 2: Add both Widget sizes in Notification Center**

  Use macOS Notification Center’s edit interface to add “学习计时” once as `systemSmall` and once as `systemMedium`. This is required visual verification; a SwiftUI preview is not substitute evidence that macOS discovers the extension.

  Expected: neither card shows template `Time:` or 😀 content.

- [ ] **Step 3: Exercise running, pause, resume and stale-entry paths**

  Start 算法 in the App. Observe both Widgets show 算法 and a timer that increases over at least 60 seconds without a repeating store write. Tap pause in the medium Widget, return to App and verify the timer stopped. Tap continue in the small Widget, then change to 八股 in App and tap the previously visible 算法 Widget action; confirm reducer semantics make 算法 active again and close 八股’s running interval.

- [ ] **Step 4: Exercise persistence and migration safeguards**

  Quit and relaunch `/Applications/钟.app`; confirm Widget and App agree on the active/recent task and history. Run the targeted migration regression test once more. Confirm no old history disappeared and no interval doubled.

- [ ] **Step 5: Run final automated checks and remove temporary verification artifacts**

  Run all `StudyClockTests`, the existing `StudyClockUITests/testHistoryCanBeClosed()`, and a macOS `BuildProject`. Remove only throwaway test stores, screenshots, and device-session artifacts created during verification; retain no debug buttons, test-mode storage paths, or Xcode template Widget content.

  Expected: focused widget tests, existing timer tests, UI regression test and macOS build all pass; actual Notification Center shows and controls the installed Widget.

## Plan Self-Review

- **Spec coverage:** Tasks 1–3 cover App Group sharing, migration, single event source, stale interaction and App Intent. Task 2 covers dynamic timer and midnight math. Task 4 covers selected A visuals, sizes, accessibility and failure states. Task 5 covers discoverability, local install and real Notification Center interaction. No spec section lacks an implementation task.
- **Placeholder scan:** The only placeholder-keyword references are this self-review statement; no plan step contains an unresolved placeholder.
- **Type consistency:** `StudyTimerWidgetState` is created in Task 1 and transformed in Task 2. `StudyTimerWidgetEntryState` and `StudyTimerWidgetEntryFactory` are produced in Task 2 and consumed by Task 4. `StudyStore.toggle(taskID:at:)` is defined in Task 1 and consumed by Task 3. `StudyStore.makeApplicationStore()` is used only by the App; `StudyStore.makeWidgetStore()` is used only by the Widget/Intent. `StudyStore.widgetKind` is defined in Task 1 and used by Task 3/4.
- **Review Focus coverage:** migration/duplicate events: Task 1; stale widget action: Task 1; midnight and dynamic time: Task 2; App Group failure: Task 3 intent handling and Task 4 unavailable-entry test, then Task 5 manual verification.
