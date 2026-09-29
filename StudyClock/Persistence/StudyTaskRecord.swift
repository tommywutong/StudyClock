import Foundation
import SwiftData

@Model
final class StudyTaskRecord {
    var id: UUID
    var name: String
    var dailyGoalSeconds: Int
    var sortOrder: Int

    init(id: UUID, name: String, dailyGoalSeconds: Int, sortOrder: Int) {
        self.id = id
        self.name = name
        self.dailyGoalSeconds = dailyGoalSeconds
        self.sortOrder = sortOrder
    }
}

@Model
final class TimerActionRecord {
    var id: UUID
    var kind: String
    var taskID: UUID
    var happenedAt: Date
    var deviceID: String
    var observedActionID: UUID?

    convenience init(action: TimerActionValue) {
        self.init(
            id: action.id,
            kind: action.kind.rawValue,
            taskID: action.taskID,
            happenedAt: action.happenedAt,
            deviceID: action.deviceID,
            observedActionID: action.observedActionID)
    }

    init(
        id: UUID,
        kind: String,
        taskID: UUID,
        happenedAt: Date,
        deviceID: String,
        observedActionID: UUID?
    ) {
        self.id = id
        self.kind = kind
        self.taskID = taskID
        self.happenedAt = happenedAt
        self.deviceID = deviceID
        self.observedActionID = observedActionID
    }

    var actionValue: TimerActionValue? {
        guard let kind = TimerActionValue.Kind(rawValue: kind) else { return nil }
        return TimerActionValue(
            id: id, kind: kind, taskID: taskID, happenedAt: happenedAt,
            deviceID: deviceID, observedActionID: observedActionID)
    }
}