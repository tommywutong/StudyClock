import SwiftUI

struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let initialName: String
    let initialGoalSeconds: Int
    let onSave: (String, Int) -> Void

    @State private var name: String
    @State private var hoursText: String
    @State private var minutesText: String

    init(
        title: String,
        initialName: String,
        initialGoalSeconds: Int,
        onSave: @escaping (String, Int) -> Void
    ) {
        self.title = title
        self.initialName = initialName
        self.initialGoalSeconds = initialGoalSeconds
        self.onSave = onSave

        let safeGoal = max(initialGoalSeconds, 0)
        _name = State(initialValue: initialName)
        _hoursText = State(initialValue: String(safeGoal / 3_600))
        _minutesText = State(initialValue: String((safeGoal % 3_600) / 60))
    }

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var goalSeconds: Int? {
        Self.goalSeconds(hours: hoursText, minutes: minutesText)
    }

    nonisolated static func goalSeconds(hours: String, minutes: String) -> Int? {
        guard let hours = Int(hours), hours >= 0,
              let minutes = Int(minutes), minutes >= 0 else { return nil }
        let hourSeconds = hours.multipliedReportingOverflow(by: 3_600)
        let minuteSeconds = minutes.multipliedReportingOverflow(by: 60)
        guard !hourSeconds.overflow, !minuteSeconds.overflow else { return nil }
        let total = hourSeconds.partialValue.addingReportingOverflow(minuteSeconds.partialValue)
        return total.overflow ? nil : total.partialValue
    }

    private var canSave: Bool {
        !normalizedName.isEmpty && goalSeconds != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("任务") {
                    TextField("任务名称", text: $name)
                        .accessibilityIdentifier("task-name")
                    if normalizedName.isEmpty {
                        Text("请输入任务名称")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("每日目标") {
                    HStack {
                        TextField("小时", text: $hoursText)
                            .frame(width: 64)
                            .accessibilityLabel("目标小时")
                            .accessibilityIdentifier("task-goal-hours")
                        Text("小时")
                        TextField("分钟", text: $minutesText)
                            .frame(width: 64)
                            .accessibilityLabel("目标分钟")
                            .accessibilityIdentifier("task-goal-minutes")
                        Text("分钟")
                    }
                    .accessibilityElement(children: .contain)
                    if goalSeconds == nil {
                        Text("请输入有效的非负目标时长")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard let goalSeconds else { return }
                        onSave(normalizedName, goalSeconds)
                        dismiss()
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("task-save")
                }
            }
        }
    }
}
