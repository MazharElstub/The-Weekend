import Foundation
import Supabase

enum SyncOperationType: String, Codable {
    case upsertEvent
    case deleteEvent
    case setProtection
    case upsertGoal
    case appendAudit
}

enum SyncState: String, Codable {
    case pending
    case retrying
    case synced
}

struct PendingSyncOperation: Identifiable, Codable, Hashable {
    var id: String
    var type: SyncOperationType
    var entityId: String
    var createdAt: Date
    var attemptCount: Int
    var nextAttemptAt: Date

    var event: WeekendEvent?
    var protectionWeekKey: String?
    var protectionEnabled: Bool?
    var goal: MonthlyGoal?
    var auditEntry: AuditEntry?

    init(
        id: String = UUID().uuidString,
        type: SyncOperationType,
        entityId: String,
        createdAt: Date = Date(),
        attemptCount: Int = 0,
        nextAttemptAt: Date = Date(),
        event: WeekendEvent? = nil,
        protectionWeekKey: String? = nil,
        protectionEnabled: Bool? = nil,
        goal: MonthlyGoal? = nil,
        auditEntry: AuditEntry? = nil
    ) {
        self.id = id
        self.type = type
        self.entityId = entityId
        self.createdAt = createdAt
        self.attemptCount = attemptCount
        self.nextAttemptAt = nextAttemptAt
        self.event = event
        self.protectionWeekKey = protectionWeekKey
        self.protectionEnabled = protectionEnabled
        self.goal = goal
        self.auditEntry = auditEntry
    }
}

struct SyncReplayResult {
    var remainingOperations: [PendingSyncOperation]
    var syncStates: [String: SyncState]
    var lastErrorMessage: String?
}

final class SyncEngine {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func flush(
        operations: [PendingSyncOperation],
        userId: String,
        supabase: SupabaseClient,
        now: Date = Date()
    ) async -> SyncReplayResult {
        guard !operations.isEmpty else {
            return SyncReplayResult(remainingOperations: [], syncStates: [:], lastErrorMessage: nil)
        }

        var remaining: [PendingSyncOperation] = []
        var states: [String: SyncState] = [:]
        var lastErrorMessage: String?

        for var operation in operations {
            guard operation.nextAttemptAt <= now else {
                remaining.append(operation)
                continue
            }

            do {
                try await replay(operation: operation, userId: userId, supabase: supabase)
                states[operation.entityId] = .synced
            } catch {
                operation.attemptCount += 1
                let nextDelay = min(pow(2.0, Double(operation.attemptCount)) * 15.0, 3600.0)
                operation.nextAttemptAt = now.addingTimeInterval(nextDelay)
                remaining.append(operation)
                states[operation.entityId] = .retrying
                lastErrorMessage = error.localizedDescription
            }
        }

        return SyncReplayResult(
            remainingOperations: remaining,
            syncStates: states,
            lastErrorMessage: lastErrorMessage
        )
    }

    private func replay(
        operation: PendingSyncOperation,
        userId: String,
        supabase: SupabaseClient
    ) async throws {
        switch operation.type {
        case .upsertEvent:
            guard let event = operation.event else { return }
            try await upsertEvent(event: event, userId: userId, supabase: supabase)

        case .deleteEvent:
            try await supabase
                .from("weekend_events")
                .delete()
                .eq("id", value: operation.entityId)
                .eq("user_id", value: userId)
                .execute()

        case .setProtection:
            guard let weekendKey = operation.protectionWeekKey,
                  let enabled = operation.protectionEnabled else { return }
            if enabled {
                let payload = NewWeekendProtection(weekendKey: weekendKey, userId: userId)
                _ = try await supabase
                    .from("weekend_protections")
                    .delete()
                    .eq("weekend_key", value: weekendKey)
                    .eq("user_id", value: userId)
                    .execute()
                try await supabase
                    .from("weekend_protections")
                    .insert(payload)
                    .execute()
            } else {
                try await supabase
                    .from("weekend_protections")
                    .delete()
                    .eq("weekend_key", value: weekendKey)
                    .eq("user_id", value: userId)
                    .execute()
            }

        case .upsertGoal:
            guard let goal = operation.goal else { return }
            let payload = MonthlyGoalPayload(goal: goal)
            _ = try await supabase
                .from("monthly_goals")
                .delete()
                .eq("user_id", value: userId)
                .eq("month_key", value: goal.monthKey)
                .execute()
            try await supabase
                .from("monthly_goals")
                .insert(payload)
                .execute()

        case .appendAudit:
            guard let entry = operation.auditEntry else { return }
            let payload = AuditPayload(entry: entry, userId: userId)
            try await supabase
                .from("event_audit_logs")
                .insert(payload)
                .execute()
        }
    }

    private func upsertEvent(
        event: WeekendEvent,
        userId: String,
        supabase: SupabaseClient
    ) async throws {
        let remoteRows: [EventSyncMetadata] = try await supabase
            .from("weekend_events")
            .select("id,client_updated_at")
            .eq("id", value: event.id)
            .eq("user_id", value: userId)
            .limit(1)
            .execute()
            .value

        if let remote = remoteRows.first,
           let remoteUpdatedAt = remote.clientUpdatedAt,
           let localUpdatedAt = event.clientUpdatedAt,
           remoteUpdatedAt > localUpdatedAt {
            return
        }

        if remoteRows.isEmpty {
            let payload = NewWeekendEventSyncPayload(event: event, userId: userId)
            try await supabase
                .from("weekend_events")
                .insert(payload)
                .execute()
        } else {
            let payload = UpdateWeekendEventSyncPayload(event: event)
            try await supabase
                .from("weekend_events")
                .update(payload)
                .eq("id", value: event.id)
                .eq("user_id", value: userId)
                .execute()
        }
    }
}

private struct EventSyncMetadata: Decodable {
    let id: String
    let clientUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case clientUpdatedAt = "client_updated_at"
    }
}

private struct NewWeekendEventSyncPayload: Encodable {
    let id: String
    let title: String
    let type: String
    let weekendKey: String
    let days: [String]
    let startTime: String
    let endTime: String
    let userId: String
    let status: String
    let completedAt: String?
    let cancelledAt: String?
    let clientUpdatedAt: String
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case type
        case weekendKey = "weekend_key"
        case days
        case startTime = "start_time"
        case endTime = "end_time"
        case userId = "user_id"
        case status
        case completedAt = "completed_at"
        case cancelledAt = "cancelled_at"
        case clientUpdatedAt = "client_updated_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(event: WeekendEvent, userId: String) {
        id = event.id
        title = event.title
        type = event.type
        weekendKey = event.weekendKey
        days = event.days
        startTime = event.startTime
        endTime = event.endTime
        self.userId = userId
        status = event.status
        completedAt = SyncDateFormatter.isoString(from: event.completedAt)
        cancelledAt = SyncDateFormatter.isoString(from: event.cancelledAt)
        clientUpdatedAt = SyncDateFormatter.isoString(from: event.clientUpdatedAt ?? Date()) ?? SyncDateFormatter.isoString(from: Date()) ?? ""
        createdAt = SyncDateFormatter.isoString(from: event.createdAt ?? Date()) ?? SyncDateFormatter.isoString(from: Date()) ?? ""
        updatedAt = SyncDateFormatter.isoString(from: event.updatedAt ?? Date()) ?? SyncDateFormatter.isoString(from: Date()) ?? ""
        deletedAt = SyncDateFormatter.isoString(from: event.deletedAt)
    }
}

private struct UpdateWeekendEventSyncPayload: Encodable {
    let title: String
    let type: String
    let weekendKey: String
    let days: [String]
    let startTime: String
    let endTime: String
    let status: String
    let completedAt: String?
    let cancelledAt: String?
    let clientUpdatedAt: String
    let updatedAt: String
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case title
        case type
        case weekendKey = "weekend_key"
        case days
        case startTime = "start_time"
        case endTime = "end_time"
        case status
        case completedAt = "completed_at"
        case cancelledAt = "cancelled_at"
        case clientUpdatedAt = "client_updated_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(event: WeekendEvent) {
        title = event.title
        type = event.type
        weekendKey = event.weekendKey
        days = event.days
        startTime = event.startTime
        endTime = event.endTime
        status = event.status
        completedAt = SyncDateFormatter.isoString(from: event.completedAt)
        cancelledAt = SyncDateFormatter.isoString(from: event.cancelledAt)
        clientUpdatedAt = SyncDateFormatter.isoString(from: event.clientUpdatedAt ?? Date()) ?? SyncDateFormatter.isoString(from: Date()) ?? ""
        updatedAt = SyncDateFormatter.isoString(from: event.updatedAt ?? Date()) ?? SyncDateFormatter.isoString(from: Date()) ?? ""
        deletedAt = SyncDateFormatter.isoString(from: event.deletedAt)
    }
}

private struct MonthlyGoalPayload: Encodable {
    let id: String
    let userId: String
    let monthKey: String
    let plannedTarget: Int
    let completedTarget: Int
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case monthKey = "month_key"
        case plannedTarget = "planned_target"
        case completedTarget = "completed_target"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(goal: MonthlyGoal) {
        id = goal.id
        userId = goal.userId
        monthKey = goal.monthKey
        plannedTarget = goal.plannedTarget
        completedTarget = goal.completedTarget
        createdAt = SyncDateFormatter.isoString(from: goal.createdAt) ?? SyncDateFormatter.isoString(from: Date()) ?? ""
        updatedAt = SyncDateFormatter.isoString(from: goal.updatedAt) ?? SyncDateFormatter.isoString(from: Date()) ?? ""
    }
}

private struct AuditPayload: Encodable {
    let id: String
    let userId: String
    let action: String
    let entityType: String
    let entityId: String
    let payload: [String: String]
    let occurredAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case action
        case entityType = "entity_type"
        case entityId = "entity_id"
        case payload
        case occurredAt = "occurred_at"
    }

    init(entry: AuditEntry, userId: String) {
        id = entry.id
        self.userId = userId
        action = entry.action
        entityType = entry.entityType.rawValue
        entityId = entry.entityId
        payload = entry.payload
        occurredAt = SyncDateFormatter.isoString(from: entry.occurredAt) ?? SyncDateFormatter.isoString(from: Date()) ?? ""
    }
}

private enum SyncDateFormatter {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func isoString(from date: Date?) -> String? {
        guard let date else { return nil }
        return formatter.string(from: date)
    }
}
