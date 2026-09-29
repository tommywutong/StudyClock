import SwiftUI

struct TaskTimerRow: View {
    let name: String
    let progress: TaskProgress
    let isRunning: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: isRunning ? "timer" : "circle")
                .foregroundStyle(isRunning ? Color.accentColor : .secondary)
                .frame(width: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(name).font(.headline)
                    if isRunning {
                        Text("正在计时")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                }
                Text(progressText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(isRunning ? "暂停" : "开始", action: action)
                .buttonStyle(.borderedProminent)
                .tint(isRunning ? .orange : .accentColor)
                .accessibilityLabel(isRunning ? "暂停 \(name)" : "开始 \(name)")
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(name)
    }

    private var progressText: String {
        let elapsed = format(progress.elapsed)
        if progress.overtime > 0 { return "已学 \(elapsed) · 超额 \(format(progress.overtime))" }
        return "已学 \(elapsed) · 还差 \(format(progress.remaining))"
    }

    private func format(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%d:%02d", value / 3_600, (value / 60) % 60)
    }
}