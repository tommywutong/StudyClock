import SwiftUI

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss

    let viewModel: TimerViewModel
    let now: Date

    var body: some View {
        NavigationStack {
            let days = viewModel.historyDays(now: now)
            List(days) { day in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(day.date, format: .dateTime.year().month().day())
                            .font(.headline)
                        Text(day.date, format: .dateTime.weekday(.wide))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(format(day.total))
                            .font(.headline.monospacedDigit())
                        Text(progressText(for: day))
                            .font(.caption)
                            .foregroundStyle(day.total >= day.target ? .green : .secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(day.date.formatted(date: .long, time: .omitted))，\(format(day.total))，\(progressText(for: day))")
            }
            .overlay {
                if days.isEmpty {
                    ContentUnavailableView("还没有历史记录", systemImage: "clock.arrow.circlepath", description: Text("开始一次学习计时后，这里会保留每日累计。"))
                }
            }
            .navigationTitle("学习历史")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭学习历史")
                }
            }
        }
    }

    private func progressText(for day: StudyDaySummary) -> String {
        guard day.target > 0 else { return "无目标" }
        return "目标 \(format(day.target))"
    }

    private func format(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%d:%02d", value / 3_600, (value / 60) % 60)
    }
}
