# StudyClock

一个面向学习准备阶段的多任务计时器。它借鉴棋钟的使用方式：创建多个独立任务，当前只运行一个任务，随时切换、暂停和继续，分别观察每个任务今天还投入了多少时间。

> 当前版本主要验证 macOS 本机运行和 macOS 通知中心 Widget。项目暂不依赖账号、服务器、CloudKit 或生产环境配置。

## 功能

- 三个相互独立的学习任务，可在任务之间切换计时
- 事件流记录开始、暂停和切换，避免直接覆盖累计时长
- 主 App、菜单栏入口和通知中心 Widget 读取同一份本地计时数据
- 中号 Widget 显示三张任务卡，可直接开始、暂停或继续任务
- 小号 Widget 显示当前或最近任务
- Widget 运行中的时间使用系统动态计时显示，不通过每秒写库或刷新 Timeline 实现
- Widget 操作后同步刷新已经打开的 App；App 回到前台时也会重新读取共享状态
- 学习历史按本地日期汇总，支持跨午夜区间计算
- 首次从旧默认 SwiftData 容器迁移到 App Group 共享容器时保留历史记录

## 运行要求

- macOS 14.0 或更高版本
- Xcode 27.0 或与当前工程设置兼容的较新 Xcode
- Apple Development 签名，用于在本机安装 App Group 和 Widget Extension

本机已验证环境：macOS 27、Xcode 27.0、Apple Silicon。

## 开始运行

1. 克隆仓库并打开工程：

   ```bash
   git clone https://github.com/tommywutong/StudyClock.git
   cd StudyClock
   open StudyClock.xcodeproj
   ```

2. 在 Xcode 中选择 `StudyClock` scheme 和当前 Mac 运行目标。
3. 运行 App。
4. 如需使用 Widget，在通知中心编辑面板添加“学习计时”小号或中号 Widget。
5. 首次运行主 App，等待共享存储迁移完成后再使用 Widget。

项目的 App 和 Widget Extension 使用相同的 App Group：

```text
group.com.tommywu.StudyClock
```

这是本地数据共享所需的 entitlement，不是网络服务凭据。

## 验证

### 本地签名测试

```bash
xcodebuild test \
  -project StudyClock.xcodeproj \
  -scheme StudyClock \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:StudyClockTests
```

### 无签名 CI 测试

CI 使用以下命令构建并运行单元测试，不需要开发者证书：

```bash
xcodebuild test \
  -project StudyClock.xcodeproj \
  -scheme StudyClock \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:StudyClockTests \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
```

`StudyClockUITests` 依赖 macOS UI 自动化环境，未纳入无签名 CI；Widget 的最终布局仍应在通知中心中人工确认。

## 数据与同步模型

App 和 Widget 不各自维护一套计时结果，而是共同读取 App Group 中的 SwiftData store：

```text
App / MenuBarExtra ─┐
                    ├─ App Group / Library/Application Support/StudyClock.store
Widget Intent ──────┘
```

计时动作保存为不可变事件，包含：

- `start` / `pause`
- 任务 ID
- 发生时间
- 设备来源
- 观察到的上一个动作 ID

`TimerReducer` 从事件流计算当前任务和累计区间。Widget Intent 写入共享 store 后：

1. 重载 Widget Timeline；
2. 在 macOS 发送跨进程变更通知；
3. 已打开的 App 重新读取快照；
4. App 回到前台时再次刷新，覆盖 App 在后台期间错过通知的情况。

正常刷新策略：状态变化立即触发重载；运行中的数字由系统动态计时更新；每日累计在本地午夜进入下一天；共享 store 暂时不可用时 Widget 每小时重试一次。

## 项目结构

```text
StudyClock/
├── Domain/                  # 事件值、Reducer、快照和进度计算
├── Persistence/             # SwiftData、App Group、迁移和共享查询
├── Timer/                   # 主 App 的计时状态与 Widget 刷新
├── Views/                   # 主 App 仪表盘、历史和任务行
├── Widgets/                 # Widget Intent 和跨 target DTO
├── Mac/                     # macOS 菜单栏入口
├── StudyClockApp.swift      # App scene 与前台刷新
├── StudyClockWidget/        # Widget Provider、Entry 和 SwiftUI 布局
├── StudyClockTests/         # Swift Testing 单元测试
└── docs/superpowers/        # 设计与实现记录
```

## 当前边界

- Widget 当前仅注册 macOS `systemSmall` 和 `systemMedium` family。
- Widget 内可以操作计时，但任务的完整排序和编辑仍在主 App 完成。
- 当前只保证本机 App Group 共享，不提供跨设备同步。
- 没有账号、云同步、CloudKit、统计服务或远程 API。
- 许可证尚未声明；在添加明确许可证前，不应默认拥有任意开源再分发权限。

## 设计记录

- [macOS Widget 设计说明](docs/superpowers/specs/2026-09-28-macos-native-study-widget-design.md)
- [macOS Widget 实现计划](docs/superpowers/plans/2026-09-28-macos-native-study-widget.md)

## 反馈

这是一个本机运行的面试准备辅助项目。欢迎通过 GitHub Issues 记录可复现的问题、系统版本、Xcode 版本和对应的操作步骤。
