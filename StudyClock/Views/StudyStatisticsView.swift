import SwiftUI

struct StudyStatisticsView: View {
    @Environment(\.dismiss) private var dismiss

    let viewModel: TimerViewModel

    @State private var selectedPeriod = StudyStatisticsPeriod.sevenDays
    @State private var report: StudyStatisticsReport? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("近 \(selectedPeriod.dayCount) 天")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)

                    periodSelector

                    if let report {
                        if report.hasHistory {
                            StudyStatisticsOverview(report: report)

                            ForEach(report.tasks) { task in
                                StudyStatisticsTaskCard(task: task)
                            }
                        } else {
                            ContentUnavailableView(
                                "还没有学习记录",
                                systemImage: "chart.bar",
                                description: Text("完成一次学习计时后，这里会汇总历史投入。"))
                                .frame(maxWidth: .infinity, minHeight: 180)
                        }
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 180)
                    }

                    Text("目标估算：历史周期按任务当前每日目标回算，不代表当时设定的目标。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("学习统计")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭学习统计")
                }
            }
        }
        .onAppear(perform: refreshReport)
        .onChange(of: selectedPeriod) { _, _ in refreshReport() }
        .onChange(of: viewModel.snapshot) { _, _ in refreshReport() }
        .onChange(of: viewModel.calendar) { _, _ in refreshReport() }
        .onChange(of: viewModel.studyStatisticsTasks) { _, _ in refreshReport() }
    }

    private var periodSelector: some View {
        HStack(spacing: 8) {
            ForEach(StudyStatisticsPeriod.allCases) { period in
                Button("近 \(period.dayCount) 天") {
                    selectedPeriod = period
                }
                .buttonStyle(.bordered)
                .tint(selectedPeriod == period ? Color.accentColor : Color.gray)
                .accessibilityAddTraits(selectedPeriod == period ? .isSelected : [])
                .accessibilityIdentifier("statistics-period-\(period.rawValue)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refreshReport() {
        report = viewModel.studyStatistics(
            for: selectedPeriod,
            now: .now,
            calendar: viewModel.calendar)
    }
}

private struct StudyStatisticsOverview: View {
    let report: StudyStatisticsReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("总体投入")
                .font(.headline)

            Text(StudyStatisticsFormatting.duration(report.elapsed))
                .font(.largeTitle.monospacedDigit().weight(.semibold))
                .accessibilityLabel("全部任务投入 \(StudyStatisticsFormatting.duration(report.elapsed))")

            metricRow(
                "目标完成率（有目标任务）",
                report.goalCompletionRate.map(StudyStatisticsFormatting.percentage) ?? "未设目标")
            metricRow(
                "时长变化",
                StudyStatisticsFormatting.elapsedComparison(
                    current: report.elapsed,
                    previous: report.previousElapsed,
                    change: report.elapsedChange,
                    relativeChange: report.elapsedRelativeChange))
            metricRow(
                "目标完成率变化",
                report.goalCompletionChangePercentagePoints
                    .map(StudyStatisticsFormatting.percentagePoints) ?? "未设目标")
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

private struct StudyStatisticsTaskCard: View {
    let task: StudyStatisticsTaskSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(task.name)
                .font(.headline)

            metricRow("周期投入", StudyStatisticsFormatting.duration(task.elapsed))
            metricRow(
                "占全部投入",
                task.share.map(StudyStatisticsFormatting.percentage) ?? "—")
            metricRow("日均投入", StudyStatisticsFormatting.duration(task.averageDailyElapsed))

            if let completionRate = task.goalCompletionRate {
                metricRow("周期目标", StudyStatisticsFormatting.duration(task.goalElapsed))
                metricRow("目标完成率", StudyStatisticsFormatting.percentage(completionRate))
                ProgressView(value: min(max(completionRate, 0), 1))
                    .accessibilityLabel("\(task.name) 目标完成进度")
                    .accessibilityValue(StudyStatisticsFormatting.percentage(completionRate))

                if let attainmentDays = task.goalAttainmentDays,
                   let previousAttainmentDays = task.previousGoalAttainmentDays {
                    metricRow(
                        "达标天数",
                        "\(attainmentDays) 天（上期 \(previousAttainmentDays) 天，变化 \(StudyStatisticsFormatting.signedDays(attainmentDays - previousAttainmentDays))）")
                }

                metricRow(
                    "目标完成率变化",
                    task.goalCompletionChangePercentagePoints
                        .map(StudyStatisticsFormatting.percentagePoints) ?? "—")
            } else {
                metricRow("周期目标", "未设目标")
                metricRow("目标完成率", "未设目标")
            }

            metricRow(
                "时长变化",
                StudyStatisticsFormatting.elapsedComparison(
                    current: task.elapsed,
                    previous: task.previousElapsed,
                    change: task.elapsedChange,
                    relativeChange: task.elapsedRelativeChange))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

private enum StudyStatisticsFormatting {
    nonisolated static func duration(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%d:%02d", value / 3_600, (value / 60) % 60)
    }

    nonisolated static func percentage(_ ratio: Double) -> String {
        String(format: "%.0f%%", ratio * 100)
    }

    nonisolated static func percentagePoints(_ points: Double) -> String {
        let rounded = Int(points.rounded())
        let sign = rounded > 0 ? "+" : ""
        return "\(sign)\(rounded) 个百分点"
    }

    nonisolated static func elapsedComparison(
        current: TimeInterval,
        previous: TimeInterval,
        change: TimeInterval,
        relativeChange: Double?
    ) -> String {
        guard previous > 0 else {
            return current > 0 ? "\(signedDuration(change)) · 上期无投入" : "无变化"
        }
        guard let relativeChange else { return signedDuration(change) }
        return "\(signedDuration(change)) · \(percentage(relativeChange))"
    }

    nonisolated static func signedDays(_ days: Int) -> String {
        let sign = days > 0 ? "+" : ""
        return "\(sign)\(days)"
    }

    nonisolated private static func signedDuration(_ seconds: TimeInterval) -> String {
        let sign = seconds > 0 ? "+" : seconds < 0 ? "−" : ""
        return "\(sign)\(duration(abs(seconds)))"
    }
}
