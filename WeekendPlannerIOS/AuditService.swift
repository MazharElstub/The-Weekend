import Foundation

enum AuditEntityType: String, Codable {
    case event
    case protection
    case template
    case settings
    case goal
    case sync
}

struct AuditEntry: Identifiable, Codable, Hashable {
    let id: String
    let action: String
    let entityType: AuditEntityType
    let entityId: String
    let payload: [String: String]
    let occurredAt: Date
}

final class AuditService {
    private let retentionDays: Int

    init(retentionDays: Int = 30) {
        self.retentionDays = retentionDays
    }

    func createEntry(
        action: String,
        entityType: AuditEntityType,
        entityId: String,
        payload: [String: String],
        occurredAt: Date = Date()
    ) -> AuditEntry {
        AuditEntry(
            id: UUID().uuidString,
            action: action,
            entityType: entityType,
            entityId: entityId,
            payload: payload,
            occurredAt: occurredAt
        )
    }

    func trim(entries: [AuditEntry], referenceDate: Date = Date()) -> [AuditEntry] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: referenceDate) else {
            return entries.sorted { $0.occurredAt > $1.occurredAt }
        }

        return entries
            .filter { $0.occurredAt >= cutoff }
            .sorted { $0.occurredAt > $1.occurredAt }
    }
}
