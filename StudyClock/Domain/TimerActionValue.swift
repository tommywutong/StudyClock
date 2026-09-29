import Foundation

struct TimerActionValue: Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case start
        case pause
    }

    let id: UUID
    let kind: Kind
    let taskID: UUID
    let happenedAt: Date
    let deviceID: String
    let observedActionID: UUID?

    static func start(
        _ taskID: UUID,
        at happenedAt: Date,
        device: String,
        observedActionID: UUID? = nil,
        id: UUID = UUID()
    ) -> Self {
        Self(id: id, kind: .start, taskID: taskID, happenedAt: happenedAt,
             deviceID: device, observedActionID: observedActionID)
    }

    static func pause(
        _ taskID: UUID,
        at happenedAt: Date,
        device: String,
        observedActionID: UUID? = nil,
        id: UUID = UUID()
    ) -> Self {
        Self(id: id, kind: .pause, taskID: taskID, happenedAt: happenedAt,
             deviceID: device, observedActionID: observedActionID)
    }
}