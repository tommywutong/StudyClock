import SwiftUI

struct TimerDashboardView: View {
    let viewModel: TimerViewModel
    @State private var showingHistory = false

    var body: some View {
        Group {
            if let initializationError = viewModel.initializationError {
                ContentUnavailableView(
                    "无法初始化学习计时",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(initializationError))
                    .navigationTitle("钟")
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            TimerHero(
                                taskName: viewModel.activeTask?.name,
                                elapsed: activeElapsed(now: context.date))

                            VStack(spacing: 10) {
                                ForEach(viewModel.tasks, id: \.id) { task in
                                    TaskTimerRow(
                                        name: task.name,
                                        progress: viewModel.progress(for: task, now: context.date),
                                        isRunning: viewModel.snapshot.activeTaskID == task.id
                                    ) {
                                        viewModel.toggle(taskID: task.id)
                                    }
                                }
                            }

                            HStack {
                                Label("今日总计", systemImage: "sum")
                                Spacer()
                                Text(format(viewModel.totalElapsed(now: context.date)))
                                    .monospacedDigit()
                                    .fontWeight(.semibold)
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        }
                        .padding()
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity)
                    }
                    .navigationTitle("钟")
                    .toolbar {
                        ToolbarItem(placement: .automatic) {
                            Button("历史", systemImage: "clock.arrow.circlepath") {
                                showingHistory = true
                            }
                            .accessibilityLabel("查看学习历史")
                        }
                    }
                }
                .sheet(isPresented: $showingHistory) {
                    HistoryView(viewModel: viewModel, now: .now)
                        .frame(minWidth: 340, minHeight: 360)
                }
            }
        }
        .alert("计时操作失败", isPresented: errorBinding) {
            Button("确定") { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "未知错误")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.dismissError() } })
    }

    private func activeElapsed(now: Date) -> TimeInterval {
        guard let task = viewModel.activeTask else { return 0 }
        return viewModel.progress(for: task, now: now).elapsed
    }

    private func format(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", value / 3_600, (value / 60) % 60, value % 60)
    }
}

private struct TimerHero: View {
    let taskName: String?
    let elapsed: TimeInterval

    var body: some View {
        VStack(spacing: 12) {
            Label(taskName ?? "当前没有计时任务", systemImage: taskName == nil ? "pause.circle" : "play.circle.fill")
                .font(.headline)
                .foregroundStyle(taskName == nil ? Color.secondary : Color.accentColor)
            FlipClockView(
                seconds: elapsed,
                label: taskName.map { "\($0) 今日累计" } ?? "当前没有运行中的任务")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
    }
}