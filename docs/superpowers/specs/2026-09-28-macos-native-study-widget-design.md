# macOS 原生学习计时小组件设计

**日期：** 2026-09-28
**状态：** 等待 TommyWu 审阅
**范围：** 仅 macOS 通知中心原生 Widget；不做桌面悬浮窗、不接入 Vorssaint、不在本轮加入 iPhone Live Activity。

## 目标

把“钟”加入 macOS 通知中心的编辑面板，提供不占桌面的原生小组件。用户可一眼看到当前学习任务和当天投入，并在 Widget 内直接暂停或继续当前任务；主 App、菜单栏和 Widget 始终读取同一份计时事件。

## 非目标

- 不做桌面悬浮窗、菜单栏工具集或其他 Vorssaint 功能。
- 不在 Widget 中切换任务；任务切换仍在主 App 完成。
- 不为 Widget 实现逐秒翻页动画或通过每秒 Timeline 刷新模拟动画。
- 不添加 iOS 小组件、Live Activity 或灵动岛界面。

## 已确认的体验

### 中号 Widget（`systemMedium`）

- 顶部显示 `今日学习 · 正在计时` 或 `今日学习 · 已暂停`，右侧显示今日总累计。
- 主视觉保留三张横向任务卡，当前（暂停后为最近）任务固定在第一张并略宽；其余任务按既有展示顺序排列。
- 每张卡显示任务名、`HH:MM:SS` 累计、明确状态文本和直接开始 / 暂停 / 继续操作；不改变任务切换逻辑。
- 运行状态统一使用橙色状态点、文字、按钮色和轻量背景色；暂停状态使用系统次级灰色，状态文本不只依赖颜色表达。
- 当前任务的任务名与时长使用更高对比度；卡片只使用连续圆角和低对比背景层级，不使用侧边强调条或纵向主卡。
- 卡片区域深链到 App 主页面；每个操作按钮的无障碍名称带任务名。

### 小号 Widget（`systemSmall`）

- 只保留当前/最近任务、实时累计和 `暂停` / `继续`。
- 不显示三项进度，避免压缩后信息不可读。
- 无活动且没有可恢复任务时，显示“当前没有计时任务”和今日总计；无操作按钮，点击打开 App。

### 状态和边界

- “继续”恢复最近暂停的任务；最近任务由最近一条合法的计时事件确定。
- 若用户在主 App 中刚切换了任务而旧 Widget 仍可见，按钮意图在执行时以共享存储的最新快照为准：同一任务则暂停；无活动任务则启动该任务；有其他任务运行时，按当前 App 既有语义切换到目标任务。
- Widget 操作失败时不伪造成功状态：保留上次成功快照，下一次刷新显示可识别的“无法更新，打开 App 重试”状态。
- 跨午夜时，Widget 在下一个本地日开始时建立新 entry，使“今日累计”归零；系统实时递增只作用于当前日期的活动区间。

## 单一数据源与迁移

现状：`StudyStore.makeLocal()` 以默认位置创建 SwiftData `ModelContainer`；Widget Extension 运行在独立进程，不能共享该容器。

### 共享容器

1. 为 `StudyClock` 和 `StudyClockWidgetExtension` 添加同一个 App Group：`group.com.tommywu.StudyClock`。
2. 将持久化容器显式定位到该 App Group 的 Application Support URL；`StudyStore` 的 App、Widget 和 App Intent 构造路径一致。
3. 任务记录（`StudyTaskRecord`）和事件记录（`TimerActionRecord`）仍是唯一真相；不增加“Widget 专用快照”或另一套计时器状态。
4. 主 App 每次开始、暂停、切换或修改任务后请求 `WidgetCenter.reloadTimelines(ofKind:)`；Widget 的 App Intent 成功写入后也请求同一刷新。

### 一次性迁移

1. App 首次升级后在主进程打开旧默认 SwiftData 容器和新的 App Group 容器。
2. 按稳定 ID 导入：任务以任务 ID 覆盖共享容器中同 ID 的种子值；事件以事件 ID 去重导入。导入过程可重复执行，不会重复累计学习时间。
3. 导入成功后在 App Group `UserDefaults` 写入迁移版本；若在写标记前中断，下次继续导入，依靠 ID 去重收敛。
4. 迁移成功后所有读写只使用 App Group 容器；旧容器保留为只读回退源，不删除用户历史文件。
- 迁移或容器创建失败时，主 App 显示明确错误；Widget 显示不可用状态并提供打开 App 的入口，绝不静默创建一套空白数据替代历史。非计时的最近操作错误文本存入 App Group `UserDefaults`，成功读写后清除；它不参与计时状态或累计计算。

## Widget 数据模型与渲染

- 新建可跨 target 编译的 Widget 数据读取层，输出：任务列表、当前活动任务 ID、最近任务 ID、每日累计、每日目标、活动开始时间，以及来自 App Group `UserDefaults` 的最近刷新错误状态。
- `TimerSnapshot` 仍由 `TimerReducer` 从事件流生成；为 Widget 增加读取“最近合法任务”的查询，不让视图自行推断事件排序。
- 运行中任务的展示基准为 `referenceDate = entry.now - currentDayElapsed`；Widget 使用 SwiftUI 的 timer-style dynamic date 从该基准向上计时。这样已累计的时长和当前运行区间组成连续显示，但 Widget Extension 不需要逐秒执行。
- Timeline 只生成“现在”和“下一次本地午夜”所需 entry；状态变更由 `WidgetCenter` 主动重载。运行中的顶部总计使用与任务卡一致的 dynamic date；WidgetKit 的刷新预算不用于秒表走动。
- Widget 支持 `systemSmall` 与 `systemMedium`；仅在 macOS 上注册这些 family。本轮不暴露 iOS Widget family。

## 交互

### App Intent

- 新建 `ToggleStudyTimerIntent(taskID:)`，在 App 与 Widget Extension 两个 target 中编译。
- Intent 打开 App Group `StudyStore`，基于执行时快照追加与 `TimerViewModel.toggle` 等价的 start/pause 事件，完成存储后刷新 `StudyClockWidget` 的 Timeline，并在 macOS 通过跨进程通知让已打开的 App 重新读取共享快照。
- Intent 返回成功结果前必须完成写入。出现持久化错误时捕获错误，将可显示的错误状态写入 App Group `UserDefaults` 并返回，不将错误抛给 WidgetKit。
- 交互按钮采用 `Button(intent:)`；卡片导航采用 `widgetURL`，不把“打开 App”伪装成按钮行为。

## 代码组织

- `Persistence/StudyStore.swift`：App Group 容器创建、幂等迁移、Widget 所需读取和原子 toggle 入口。
- `Timer/TimerViewModel.swift`：成功改变状态后请求 Widget Timeline 刷新；监听 Widget 的 macOS 跨进程变更通知，并在 App 回到前台时重新读取共享快照；保持现有主界面 API。
- 新建跨 target 的 Widget 状态 DTO / 查询层：隔离 SwiftData 模型与 Widget 视图。
- 新建跨 target 的 `AppIntent`：共享 toggle 语义。
- `StudyClockWidget/StudyClockWidget.swift`：用真实 Provider、entry 和 A 布局替换 Xcode 模板中的 `Time:` / 😀；保留 Widget Bundle。
- Entitlements：App 与 Extension 各自声明同一 App Group；不变更任何线上服务或 CloudKit 配置。

## 验证

### 自动化

1. 迁移：含任务自定义和多段历史事件的旧容器迁入后，任务、今日累计、历史汇总和 active task 均一致；重复运行不产生重复事件。
2. Intent：运行中点击同任务产生 pause；暂停后点击最近任务产生 start；点击过期 entry 的不同任务遵循既有切换语义。
3. Entry 计算：运行中累计基准正确；暂停时固定；跨午夜 entry 重置当日累计；无历史状态正确。
4. 现有 `TimerReducer`、`StudyStore`、主 App UI 测试继续通过。

### 实机/模拟验证

1. macOS 构建成功后，从通知中心编辑面板添加“钟”的小号和中号 Widget。
2. 在主 App 开始算法计时，观察两种 Widget 的任务名、进度和系统 timer-style 累计同步；等待至少一分钟，确认数字递增但没有周期性数据写入。
3. 在 Widget 内暂停并继续，回到主 App 确认事件与累计一致；在主 App 切换任务后确认 Widget 重新加载。
4. 关闭并重启 App 后，再次验证 Widget 读取相同历史。
5. 执行一次旧数据迁移路径并确认没有历史丢失或重复累计。

## 风险与约束

- WidgetKit 独立运行且 Timeline 更新由系统调度；无法承诺自定义逐秒翻页动画。系统的 dynamic date 可提供秒级累计显示。
- Native Widget 的“暂停 / 继续”刷新不是 App 内视图绑定，点击后会经历 Intent 执行和 Timeline 重载；主状态区域使用 `invalidatableContent` 表示等待同步，不把尚未确认的状态变化显示为成功。
- App Group 改动会改变本地数据位置，因此必须先迁移、后切换，且旧数据不得删除。
- 此功能仅供本机运行，不引入账号、服务器同步、CloudKit 或生产配置改动。
