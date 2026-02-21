import Foundation

enum AuditEntityType: Codable, Hashable {
    case event
    case protection
    case template
    case settings
    case sync
    case unsupported

    var rawValue: String {
        switch self {
        case .event:
            return "event"
        case .protection:
            return "protection"
        case .template:
            return "template"
        case .settings:
            return "settings"
        case .sync:
            return "sync"
        case .unsupported:
            return "unsupported"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "event":
            self = .event
        case "protection":
            self = .protection
        case "template":
            self = .template
        case "settings":
            self = .settings
        case "sync":
            self = .sync
        default:
            self = .unsupported
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
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
