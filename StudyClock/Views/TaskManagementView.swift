import SwiftUI

struct TaskManagementView: View {
    @Environment(\.dismiss) private var dismiss

    let viewModel: TimerViewModel
    @State private var presentedEditor: TaskEditorPresentation?

    private struct TaskEditorPresentation: Identifiable {
        let id: UUID
        let taskID: UUID?
        let title: String
        let name: String
        let goalSeconds: Int
    }

    var body: some View {
        NavigationStack {
            List {
                Section("进行中") {
                    if viewModel.tasks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("还没有活动任务", systemImage: "tray")
                                .foregroundStyle(.secondary)
                            Button("添加任务", systemImage: "plus") {
                                presentNewTask()
                            }
                            .accessibilityIdentifier("task-add-empty")
                        }
                        .padding(.vertical, 8)
                    } else {
                        ForEach(viewModel.tasks, id: \.id) { task in
                            taskRow(task)
                        }
                        .onMove(perform: viewModel.moveTasks)
                    }
                }

                Section("已归档") {
                    if viewModel.archivedTasks.isEmpty {
                        Text("暂无已归档任务")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.archivedTasks, id: \.id) { task in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(task.name)
                                    Text(goalText(for: task.dailyGoalSeconds))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("恢复", systemImage: "arrow.uturn.backward") {
                                    viewModel.restoreTask(id: task.id)
                                }
                                .labelStyle(.titleAndIcon)
                                .accessibilityIdentifier("task-restore-\(task.id.uuidString)")
                            }
                        }
                    }
                }
            }
            .navigationTitle("管理学习任务")
            .accessibilityLabel("管理学习任务")
            .accessibilityIdentifier("task-management")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭任务管理")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("添加", systemImage: "plus") {
                        presentNewTask()
                    }
                    .accessibilityIdentifier("task-add")
                }
            }
            .alert("任务操作失败", isPresented: errorBinding) {
                Button("确定") { viewModel.dismissError() }
            } message: {
                Text(viewModel.errorMessage ?? "未知错误")
            }
            .sheet(item: $presentedEditor) { editor in
                TaskEditorView(
                    title: editor.title,
                    initialName: editor.name,
                    initialGoalSeconds: editor.goalSeconds) { name, goalSeconds in
                        if let taskID = editor.taskID {
                            viewModel.updateTask(
                                id: taskID,
                                name: name,
                                dailyGoalSeconds: goalSeconds)
                        } else {
                            viewModel.addTask(name: name, dailyGoalSeconds: goalSeconds)
                        }
                    }
                    .frame(minWidth: 360, minHeight: 280)
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.dismissError() } })
    }

    @ViewBuilder
    private func taskRow(_ task: StudyTaskRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(task.name)
                    .font(.headline)
                Text(goalText(for: task.dailyGoalSeconds))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("编辑", systemImage: "pencil") {
                presentedEditor = TaskEditorPresentation(
                    id: task.id,
                    taskID: task.id,
                    title: "编辑任务",
                    name: task.name,
                    goalSeconds: task.dailyGoalSeconds)
            }
            .labelStyle(.iconOnly)
            .accessibilityLabel("编辑\(task.name)")
            .accessibilityIdentifier("task-edit-\(task.id.uuidString)")
            Button("归档", systemImage: "archivebox") {
                viewModel.archiveTask(id: task.id)
            }
            .labelStyle(.iconOnly)
            .accessibilityLabel("归档\(task.name)")
            .accessibilityIdentifier("task-archive-\(task.id.uuidString)")
        }
    }

    private func presentNewTask() {
        presentedEditor = TaskEditorPresentation(
            id: UUID(),
            taskID: nil,
            title: "添加任务",
            name: "",
            goalSeconds: 0)
    }

    private func goalText(for seconds: Int) -> String {
        guard seconds > 0 else { return "未设置每日目标" }
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        if hours > 0, minutes > 0 {
            return "每日目标 \(hours) 小时 \(minutes) 分钟"
        }
        if hours > 0 {
            return "每日目标 \(hours) 小时"
        }
        return "每日目标 \(minutes) 分钟"
    }
}
