import AppIntents
import SwiftUI
import WidgetKit

struct StudyClockWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> StudyTimerWidgetEntryState {
        StudyTimerWidgetEntryFactory.unavailable(now: .now)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (StudyTimerWidgetEntryState) -> Void
    ) {
        Task { @MainActor in
            let now = Date()
            let calendar = Calendar.current

            do {
                let state = try StudyStore.makeWidgetStore().widgetState(now: now, calendar: calendar)
                completion(state.makeEntry(calendar: calendar))
            } catch {
                completion(StudyTimerWidgetEntryFactory.unavailable(now: now))
            }
        }
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<StudyTimerWidgetEntryState>) -> Void
    ) {
        Task { @MainActor in
            let now = Date()
            let calendar = Calendar.current

            do {
                let state = try StudyStore.makeWidgetStore().widgetState(now: now, calendar: calendar)
                let entry = state.makeEntry(calendar: calendar)
                completion(Timeline(
                    entries: [entry],
                    policy: .after(state.nextRefreshDate(calendar: calendar))))
            } catch {
                let entry = StudyTimerWidgetEntryFactory.unavailable(now: now)
                let refreshDate = Calendar.current.date(byAdding: .hour, value: 1, to: .now)!
                completion(Timeline(entries: [entry], policy: .after(refreshDate)))
            }
        }
    }
}

struct StudyClockWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    let entry: StudyTimerWidgetEntryState

    var body: some View {
        Group {
            if let message = entry.statusMessage {
                errorView(message)
            } else if entry.usesEmptyState {
                emptyView
            } else if family == .systemMedium {
                mediumView
            } else {
                smallView
            }
        }
        .invalidatableContent()
    }

    @ViewBuilder
    private var elapsedView: some View {
        if entry.isRunning, let reference = entry.elapsedReferenceDate {
            runningElapsedText(from: reference)
        } else {
            Text(format(entry.displayedTask?.elapsed ?? entry.totalElapsed))
                .monospacedDigit()
        }
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                if entry.isRunning {
                    Circle()
                        .fill(.green)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                }

                Text(entry.isRunning ? "今日学习 · 正在计时" : "今日学习 · 已暂停")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text("今日 \(format(entry.totalElapsed))")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 7) {
                ForEach(Array(entry.displayTasks.prefix(3).enumerated()), id: \.element.id) { index, task in
                    StudyClockWidgetTimerCard(
                        task: task,
                        isPrimary: index == 0,
                        isRunning: entry.isRunning && task.id == entry.displayedTaskID,
                        elapsedReferenceDate: task.id == entry.displayedTaskID ? entry.elapsedReferenceDate : nil)
                    .frame(minWidth: index == 0 ? 108 : 72, maxWidth: index == 0 ? .infinity : 88)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let task = entry.displayedTask {
                Text(entry.isRunning ? "正在计时" : "最近任务")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(task.name)
                    .font(.headline)
                    .lineLimit(1)

                elapsedView
                    .font(.title2)
                    .layoutPriority(1)

                toggleButton(for: task)
            } else {
                Text("今日总计")
                    .font(.headline)

                elapsedView
                    .font(.title2)
                    .layoutPriority(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("当前没有计时任务")
                .font(.headline)

            Text("今日总计 \(format(entry.totalElapsed))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.headline)

            Link("打开 App", destination: Self.dashboardURL)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func toggleButton(for task: StudyTimerWidgetTask) -> some View {
        Button(intent: ToggleStudyTimerIntent(taskID: task.id.uuidString)) {
            Text(entry.isRunning ? "暂停" : "继续")
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.borderedProminent)
        .tint(entry.isRunning ? .orange : .secondary)
        .controlSize(.small)
        .accessibilityLabel(entry.isRunning ? "暂停 \(task.name)" : "继续 \(task.name)")
    }

    private func format(_ elapsed: TimeInterval) -> String {
        StudyTimerWidgetElapsedTimeFormatter.string(for: elapsed)
    }

    @ViewBuilder
    private func runningElapsedText(from reference: Date) -> some View {
        Text(timerInterval: reference...Date.distantFuture, countsDown: false, showsHours: true)
            .monospacedDigit()
    }

    private static let dashboardURL = URL(string: "studyclock://dashboard")!

}

private struct StudyClockWidgetTimerCard: View {
    let task: StudyTimerWidgetTask
    let isPrimary: Bool
    let isRunning: Bool
    let elapsedReferenceDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(task.name, systemImage: isRunning ? "circle.fill" : "pause.fill")
                .font(.caption2)
                .foregroundStyle(isRunning ? .green : .secondary)
                .lineLimit(1)

            elapsed
                .font(isPrimary ? .title3.weight(.bold) : .headline.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.7)

            Text(isRunning ? "正在计时" : "已暂停")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button(intent: ToggleStudyTimerIntent(taskID: task.id.uuidString)) {
                Text(actionTitle)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.borderedProminent)
            .tint(isRunning ? .blue : .gray)
            .controlSize(.mini)
            .accessibilityLabel("\(actionTitle) \(task.name)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var elapsed: some View {
        if isRunning, let elapsedReferenceDate {
            Text(timerInterval: elapsedReferenceDate...Date.distantFuture, countsDown: false, showsHours: true)
        } else {
            Text(StudyTimerWidgetElapsedTimeFormatter.string(for: task.elapsed))
        }
    }

    private var actionTitle: String {
        if isRunning { return "暂停" }
        return isPrimary ? "继续" : "开始"
    }
}

struct StudyClockWidget: Widget {
    let kind = StudyStore.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StudyClockWidgetProvider()) { entry in
            StudyClockWidgetEntryView(entry: entry)
                .widgetURL(URL(string: "studyclock://dashboard"))
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("学习计时")
        .description("显示今天的学习计时进度。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private enum StudyClockWidgetPreview {
    static let tasks = [
        StudyTimerWidgetTask(id: UUID(), name: "算法", elapsed: 5_400, target: 7_200),
        StudyTimerWidgetTask(id: UUID(), name: "八股", elapsed: 3_600, target: 10_800),
        StudyTimerWidgetTask(id: UUID(), name: "项目整理", elapsed: 1_800, target: 7_200)
    ]

    static var active: StudyTimerWidgetEntryState {
        let now = Date()
        return StudyTimerWidgetEntryState(
            date: now,
            tasks: tasks,
            displayedTaskID: tasks[0].id,
            isRunning: true,
            elapsedReferenceDate: now.addingTimeInterval(-5_400),
            totalElapsed: tasks.reduce(0) { $0 + $1.elapsed },
            statusMessage: nil)
    }

    static var paused: StudyTimerWidgetEntryState {
        StudyTimerWidgetEntryState(
            date: .now,
            tasks: tasks,
            displayedTaskID: tasks[1].id,
            isRunning: false,
            elapsedReferenceDate: nil,
            totalElapsed: tasks.reduce(0) { $0 + $1.elapsed },
            statusMessage: nil)
    }

    static var empty: StudyTimerWidgetEntryState {
        StudyTimerWidgetEntryState(
            date: .now,
            tasks: [],
            displayedTaskID: nil,
            isRunning: false,
            elapsedReferenceDate: nil,
            totalElapsed: 0,
            statusMessage: nil)
    }
}

#Preview(as: .systemSmall) {
    StudyClockWidget()
} timeline: {
    StudyClockWidgetPreview.active
    StudyClockWidgetPreview.paused
    StudyClockWidgetPreview.empty
}

#Preview(as: .systemMedium) {
    StudyClockWidget()
} timeline: {
    StudyClockWidgetPreview.active
    StudyClockWidgetPreview.paused
    StudyClockWidgetPreview.empty
}
