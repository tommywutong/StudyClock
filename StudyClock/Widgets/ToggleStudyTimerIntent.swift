import AppIntents
import Foundation
import WidgetKit

struct ToggleStudyTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "切换学习计时"
    static let openAppWhenRun = false

    @Parameter(title: "任务 ID") var taskID: String

    init(taskID: String) {
        self.taskID = taskID
    }

    init() {
        taskID = ""
    }

    func perform() async throws -> some IntentResult {
        let taskID = taskID

        await MainActor.run {
            guard let taskID = UUID(uuidString: taskID) else {
                Self.writeWidgetStatus("无法更新计时，请打开 App 重试")
                WidgetCenter.shared.reloadTimelines(ofKind: StudyStore.widgetKind)
                return
            }

            do {
                let store = try StudyStore.makeWidgetStore()
                try store.toggle(taskID: taskID)
                Self.writeWidgetStatus(nil)
            } catch {
                Self.writeWidgetStatus("无法更新计时，请打开 App 重试")
            }

            WidgetCenter.shared.reloadTimelines(ofKind: StudyStore.widgetKind)
        }

        return .result()
    }

    @MainActor
    private static func writeWidgetStatus(_ message: String?) {
        guard let defaults = UserDefaults(suiteName: StudyStore.appGroupIdentifier) else { return }

        if let message {
            defaults.set(message, forKey: StudyStore.widgetStatusMessageKey)
        } else {
            defaults.removeObject(forKey: StudyStore.widgetStatusMessageKey)
        }
    }
}
