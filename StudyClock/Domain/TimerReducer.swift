import Foundation

enum TimerReducer {
    private struct ActiveTimer {
        let taskID: UUID
        let startedAt: Date
    }

    static func acceptedActions(_ actions: [TimerActionValue]) -> [TimerActionValue] {
        let uniqueActions = uniqueActions(in: actions)
        var active: ActiveTimer?
        var accepted: [TimerActionValue] = []

        for action in uniqueActions where apply(action, active: &active, recordingInterval: { _ in }) {
            accepted.append(action)
        }

        return accepted
    }

    static func reduce(_ actions: [TimerActionValue]) -> TimerSnapshot {
        let uniqueActions = uniqueActions(in: actions)

        var actionsByObservedID: [UUID: [TimerActionValue]] = [:]
        for action in uniqueActions {
            guard let observedActionID = action.observedActionID else { continue }
            actionsByObservedID[observedActionID, default: []].append(action)
        }

        var conflicts = Set<UUID>()
        for branch in actionsByObservedID.values {
            guard Set(branch.map(\.deviceID)).count > 1 else { continue }
            conflicts.formUnion(branch.map(\.id))
        }

        var active: ActiveTimer?
        var intervals: [TimerInterval] = []
        for action in uniqueActions {
            _ = apply(action, active: &active) { intervals.append($0) }
        }

        return TimerSnapshot(
            intervals: intervals,
            activeTaskID: active?.taskID,
            activeStartedAt: active?.startedAt,
            conflictingActionIDs: conflicts)
    }

    private static func uniqueActions(in actions: [TimerActionValue]) -> [TimerActionValue] {
        let ordered = actions.sorted(by: precedes)
        var seenIDs = Set<UUID>()
        return ordered.filter { seenIDs.insert($0.id).inserted }
    }

    private static func apply(
        _ action: TimerActionValue,
        active: inout ActiveTimer?,
        recordingInterval: (TimerInterval) -> Void
    ) -> Bool {
        switch action.kind {
        case .start:
            guard active?.taskID != action.taskID else { return false }
            if let current = active, action.happenedAt > current.startedAt {
                recordingInterval(TimerInterval(
                    taskID: current.taskID, start: current.startedAt, end: action.happenedAt))
            }
            active = ActiveTimer(taskID: action.taskID, startedAt: action.happenedAt)
            return true

        case .pause:
            guard let current = active, current.taskID == action.taskID else { return false }
            if action.happenedAt > current.startedAt {
                recordingInterval(TimerInterval(
                    taskID: current.taskID, start: current.startedAt, end: action.happenedAt))
            }
            active = nil
            return true
        }
    }

    nonisolated private static func precedes(_ lhs: TimerActionValue, _ rhs: TimerActionValue) -> Bool {
        if lhs.happenedAt != rhs.happenedAt { return lhs.happenedAt < rhs.happenedAt }
        if lhs.deviceID != rhs.deviceID { return lhs.deviceID < rhs.deviceID }
        if lhs.id != rhs.id { return lhs.id.uuidString < rhs.id.uuidString }
        if lhs.taskID != rhs.taskID { return lhs.taskID.uuidString < rhs.taskID.uuidString }
        return lhs.kind.rawValue < rhs.kind.rawValue
    }
}