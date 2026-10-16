import SwiftUI

struct StudyCalendarView: View {
    let viewModel: TimerViewModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var report: StudyCalendarReport?
    @State private var months: [StudyCalendarMonth] = []
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("学习日历")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)

                    if let report {
                        streakSummary(report)
                        intensityLegend
                        selectedDayDetails(report)
                            .id("calendar-selected-day")
                        calendarGrid
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 180)
                    }
                }
                .padding()
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: selectedDate) { _, _ in
                proxy.scrollTo("calendar-selected-day", anchor: .top)
            }
        }
        .accessibilityIdentifier("study-calendar")
        .onAppear(perform: refreshReport)
        .onChange(of: viewModel.snapshot) { _, _ in refreshReport() }
        .onChange(of: viewModel.studyStatisticsTasks) { _, _ in refreshReport() }
        .onChange(of: viewModel.calendar) { _, _ in refreshReport() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshReport() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            refreshReport()
        }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { break }
                refreshCurrentDay()
            }
        }
    }

    private func streakSummary(_ report: StudyCalendarReport) -> some View {
        HStack(spacing: 12) {
            streakCard(
                title: "当前连续学习",
                value: "\(report.currentStreak) 天",
                accessibilityLabel: "当前连续学习 \(report.currentStreak) 天")
            streakCard(
                title: "可见范围最长连续",
                value: "\(report.longestVisibleStreak) 天",
                accessibilityLabel: "可见范围最长连续 \(report.longestVisibleStreak) 天")
        }
    }

    private func streakCard(
        title: String,
        value: String,
        accessibilityLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var calendarGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(months) { month in
                VStack(alignment: .leading, spacing: 8) {
                    Text(monthTitle(month.startDate))
                        .font(.headline)

                    LazyVGrid(columns: gridColumns, spacing: 6) {
                        ForEach(weekdaySymbols, id: \.self) { symbol in
                            Text(symbol)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .accessibilityHidden(true)
                        }

                        ForEach(0..<month.leadingEmptyCount, id: \.self) { _ in
                            Color.clear
                                .frame(minHeight: 28)
                                .accessibilityHidden(true)
                        }

                        ForEach(month.days, id: \.date) { day in
                            StudyCalendarDayCell(
                                day: day,
                                calendar: viewModel.calendar,
                                isSelected: viewModel.calendar.isDate(
                                    day.date,
                                    inSameDayAs: selectedDate)) {
                                        selectedDate = day.date
                                    }
                        }
                    }
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 24), spacing: 6), count: 7)
    }

    private var weekdaySymbols: [String] {
        let symbols = viewModel.calendar.shortStandaloneWeekdaySymbols
        guard !symbols.isEmpty else { return [] }
        let firstIndex = min(max(viewModel.calendar.firstWeekday - 1, 0), symbols.count - 1)
        return Array(symbols[firstIndex...]) + Array(symbols[..<firstIndex])
    }


    private var intensityLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("投入强度")
                .font(.headline)
            HStack(spacing: 8) {
                legendItem(title: "无投入", intensity: .empty)
                legendItem(title: "< 30 分钟", intensity: .light)
                legendItem(title: "30–60 分钟", intensity: .medium)
                legendItem(title: "1–2 小时", intensity: .strong)
                legendItem(title: "≥ 2 小时", intensity: .veryStrong)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func legendItem(title: String, intensity: StudyCalendarIntensity) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color(for: intensity))
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption)
        }
    }

    @ViewBuilder
    private func selectedDayDetails(_ report: StudyCalendarReport) -> some View {
        if let day = report.days.first(where: {
            viewModel.calendar.isDate($0.date, inSameDayAs: selectedDate)
        }) {
            VStack(alignment: .leading, spacing: 10) {
                Text(formattedDate(day.date))
                    .font(.headline)
                Text("当天总计：\(duration(day.totalElapsed))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                let studiedTasks = day.tasks.filter { $0.elapsed > 0 }
                if studiedTasks.isEmpty {
                    Text("当天没有学习记录")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(studiedTasks) { task in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(task.name)
                            if task.isArchived {
                                Text("已归档")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Text(duration(task.elapsed))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func refreshReport() {
        applyReport(viewModel.studyCalendar(now: .now, calendar: viewModel.calendar))
    }

    private func refreshCurrentDay() {
        guard let previousReport = report else { refreshReport(); return }
        let updated = StudyCalendarCalculator.advancingToday(
            in: previousReport, snapshot: viewModel.snapshot, now: .now, calendar: viewModel.calendar)
        guard updated.endDate == previousReport.endDate else { applyReport(updated); return }
        guard let day = updated.days.last, day != previousReport.days.last,
              let monthIndex = months.indices.last else { return }
        report = updated
        let month = months[monthIndex]
        var monthDays = month.days
        monthDays[monthDays.count - 1] = day
        months[monthIndex] = StudyCalendarMonth(
            startDate: month.startDate, days: monthDays, leadingEmptyCount: month.leadingEmptyCount)
    }

    private func applyReport(_ newReport: StudyCalendarReport) {
        report = newReport
        months = newReport.monthSections(calendar: viewModel.calendar)
        guard !newReport.days.contains(where: {
            viewModel.calendar.isDate($0.date, inSameDayAs: selectedDate)
        }) else { return }
        selectedDate = newReport.endDate
    }

    private func monthTitle(_ date: Date) -> String {
        let components = viewModel.calendar.dateComponents([.year, .month], from: date)
        return "\(components.year ?? 0)年\(components.month ?? 0)月"
    }

    private func formattedDate(_ date: Date) -> String {
        let components = viewModel.calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)年\(components.month ?? 0)月\(components.day ?? 0)日"
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let remainingSeconds = totalSeconds % 60
        if hours > 0 {
            return "\(hours)小时\(minutes)分"
        }
        if minutes > 0 {
            return "\(minutes)分\(remainingSeconds)秒"
        }
        return "\(remainingSeconds)秒"
    }

    private func color(for intensity: StudyCalendarIntensity) -> Color {
        switch intensity {
        case .empty:
            return Color.secondary.opacity(0.14)
        case .light:
            return Color.green.opacity(0.30)
        case .medium:
            return Color.green.opacity(0.48)
        case .strong:
            return Color.green.opacity(0.68)
        case .veryStrong:
            return Color.green.opacity(0.88)
        }
    }
}

private struct StudyCalendarDayCell: View {
    let day: StudyCalendarDay
    let calendar: Calendar
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Text(String(calendar.component(.day, from: day.date)))
                .font(.caption2.monospacedDigit())
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(color(for: day.intensity), in: RoundedRectangle(cornerRadius: 5))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.accentColor, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("累计\(duration(day.totalElapsed))，\(intensityDescription(day.intensity))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityLabel: String {
        let components = calendar.dateComponents([.year, .month, .day], from: day.date)
        return "\(components.year ?? 0)年\(components.month ?? 0)月\(components.day ?? 0)日"
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        if hours > 0 {
            return "\(hours)小时\(minutes)分"
        }
        return "\(minutes)分"
    }

    private func intensityDescription(_ intensity: StudyCalendarIntensity) -> String {
        switch intensity {
        case .empty:
            return "无投入"
        case .light:
            return "少量投入"
        case .medium:
            return "中等投入"
        case .strong:
            return "较多投入"
        case .veryStrong:
            return "高强度投入"
        }
    }

    private func color(for intensity: StudyCalendarIntensity) -> Color {
        switch intensity {
        case .empty:
            return Color.secondary.opacity(0.14)
        case .light:
            return Color.green.opacity(0.30)
        case .medium:
            return Color.green.opacity(0.48)
        case .strong:
            return Color.green.opacity(0.68)
        case .veryStrong:
            return Color.green.opacity(0.88)
        }
    }
}
