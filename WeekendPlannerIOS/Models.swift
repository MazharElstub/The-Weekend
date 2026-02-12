import Foundation
import Supabase
import UserNotifications
import EventKit

enum PlanType: String, Codable, CaseIterable {
    case plan
    case travel

    var label: String {
        switch self {
        case .plan: return "Local plans"
        case .travel: return "Travel plans"
        }
    }

    var accentHex: String {
        switch self {
        case .plan: return "#5F8FFF"
        case .travel: return "#FF7A5C"
        }
    }
}

enum WeekendDay: String, Codable, CaseIterable {
    case sat
    case sun

    var label: String {
        switch self {
        case .sat: return "Saturday"
        case .sun: return "Sunday"
        }
    }
}

enum ProtectionMode: String {
    case warn
    case block
}

enum WeekendEventStatus: String, Codable, CaseIterable {
    case planned
    case completed
    case cancelled
}

struct WeekendEvent: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var type: String
    var calendarId: String?
    var weekendKey: String
    var days: [String]
    var startTime: String
    var endTime: String
    var userId: String
    var calendarEventIdentifier: String?
    var status: String
    var completedAt: Date?
    var cancelledAt: Date?
    var clientUpdatedAt: Date?
    var updatedAt: Date?
    var createdAt: Date?
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case type
        case calendarId = "calendar_id"
        case weekendKey = "weekend_key"
        case days
        case startTime = "start_time"
        case endTime = "end_time"
        case userId = "user_id"
        case calendarEventIdentifier = "calendar_event_identifier"
        case status
        case completedAt = "completed_at"
        case cancelledAt = "cancelled_at"
        case clientUpdatedAt = "client_updated_at"
        case updatedAt = "updated_at"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
    }

    init(
        id: String,
        title: String,
        type: String,
        calendarId: String? = nil,
        weekendKey: String,
        days: [String],
        startTime: String,
        endTime: String,
        userId: String,
        calendarEventIdentifier: String?,
        status: String = WeekendEventStatus.planned.rawValue,
        completedAt: Date? = nil,
        cancelledAt: Date? = nil,
        clientUpdatedAt: Date? = nil,
        updatedAt: Date? = nil,
        createdAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.calendarId = calendarId
        self.weekendKey = weekendKey
        self.days = days
        self.startTime = startTime
        self.endTime = endTime
        self.userId = userId
        self.calendarEventIdentifier = calendarEventIdentifier
        self.status = status
        self.completedAt = completedAt
        self.cancelledAt = cancelledAt
        self.clientUpdatedAt = clientUpdatedAt
        self.updatedAt = updatedAt
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        type = try container.decode(String.self, forKey: .type)
        calendarId = try container.decodeIfPresent(String.self, forKey: .calendarId)
        weekendKey = try container.decode(String.self, forKey: .weekendKey)
        days = try container.decodeIfPresent([String].self, forKey: .days) ?? []
        startTime = try container.decode(String.self, forKey: .startTime)
        endTime = try container.decode(String.self, forKey: .endTime)
        userId = try container.decode(String.self, forKey: .userId)
        calendarEventIdentifier = try container.decodeIfPresent(String.self, forKey: .calendarEventIdentifier)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? WeekendEventStatus.planned.rawValue
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        cancelledAt = try container.decodeIfPresent(Date.self, forKey: .cancelledAt)
        clientUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .clientUpdatedAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(calendarId, forKey: .calendarId)
        try container.encode(weekendKey, forKey: .weekendKey)
        try container.encode(days, forKey: .days)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(endTime, forKey: .endTime)
        try container.encode(userId, forKey: .userId)
        try container.encodeIfPresent(calendarEventIdentifier, forKey: .calendarEventIdentifier)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(cancelledAt, forKey: .cancelledAt)
        try container.encodeIfPresent(clientUpdatedAt, forKey: .clientUpdatedAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }

    var planType: PlanType {
        PlanType(rawValue: type) ?? .plan
    }

    var dayValues: [WeekendDay] {
        days.compactMap { WeekendDay(rawValue: $0) }
    }

    var isAllDay: Bool {
        startTime == "00:00" && endTime == "23:59"
    }

    var lifecycleStatus: WeekendEventStatus {
        WeekendEventStatus(rawValue: status) ?? .planned
    }

    var isSyncDeleted: Bool {
        deletedAt != nil
    }

    func withCalendarEventIdentifier(_ identifier: String?) -> WeekendEvent {
        WeekendEvent(
            id: id,
            title: title,
            type: type,
            calendarId: calendarId,
            weekendKey: weekendKey,
            days: days,
            startTime: startTime,
            endTime: endTime,
            userId: userId,
            calendarEventIdentifier: identifier,
            status: status,
            completedAt: completedAt,
            cancelledAt: cancelledAt,
            clientUpdatedAt: clientUpdatedAt,
            updatedAt: updatedAt,
            createdAt: createdAt,
            deletedAt: deletedAt
        )
    }

    func withLifecycleStatus(_ newStatus: WeekendEventStatus, at date: Date) -> WeekendEvent {
        var copy = self
        copy.status = newStatus.rawValue
        switch newStatus {
        case .planned:
            copy.completedAt = nil
            copy.cancelledAt = nil
        case .completed:
            copy.completedAt = date
            copy.cancelledAt = nil
        case .cancelled:
            copy.completedAt = nil
            copy.cancelledAt = date
        }
        copy.clientUpdatedAt = date
        copy.updatedAt = date
        return copy
    }
}

struct WeekendProtection: Codable {
    let weekendKey: String
    let userId: String
    let calendarId: String?

    enum CodingKeys: String, CodingKey {
        case weekendKey = "weekend_key"
        case userId = "user_id"
        case calendarId = "calendar_id"
    }
}

struct NewWeekendProtection: Encodable {
    let weekendKey: String
    let userId: String
    let calendarId: String?

    enum CodingKeys: String, CodingKey {
        case weekendKey = "weekend_key"
        case userId = "user_id"
        case calendarId = "calendar_id"
    }
}

struct NewWeekendEvent: Encodable {
    let id: String?
    let title: String
    let type: String
    let calendarId: String?
    let weekendKey: String
    let days: [String]
    let startTime: String
    let endTime: String
    let userId: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case type
        case calendarId = "calendar_id"
        case weekendKey = "weekend_key"
        case days
        case startTime = "start_time"
        case endTime = "end_time"
        case userId = "user_id"
    }

    init(
        id: String? = nil,
        title: String,
        type: String,
        calendarId: String? = nil,
        weekendKey: String,
        days: [String],
        startTime: String,
        endTime: String,
        userId: String
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.calendarId = calendarId
        self.weekendKey = weekendKey
        self.days = days
        self.startTime = startTime
        self.endTime = endTime
        self.userId = userId
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(calendarId, forKey: .calendarId)
        try container.encode(weekendKey, forKey: .weekendKey)
        try container.encode(days, forKey: .days)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(endTime, forKey: .endTime)
        try container.encode(userId, forKey: .userId)
    }
}

struct UpdateWeekendEvent: Encodable {
    let title: String
    let type: String
    let calendarId: String?
    let weekendKey: String
    let days: [String]
    let startTime: String
    let endTime: String

    enum CodingKeys: String, CodingKey {
        case title
        case type
        case calendarId = "calendar_id"
        case weekendKey = "weekend_key"
        case days
        case startTime = "start_time"
        case endTime = "end_time"
    }

    init(
        title: String,
        type: String,
        calendarId: String? = nil,
        weekendKey: String,
        days: [String],
        startTime: String,
        endTime: String
    ) {
        self.title = title
        self.type = type
        self.calendarId = calendarId
        self.weekendKey = weekendKey
        self.days = days
        self.startTime = startTime
        self.endTime = endTime
    }
}

struct MonthOption: Identifiable, Hashable {
    let id = UUID()
    let key: String
    let title: String
    let shortLabel: String
    let subtitle: String
    let year: Int?
    let weekends: [WeekendInfo]
}

struct WeekendInfo: Identifiable, Hashable {
    let id = UUID()
    let saturday: Date
    let label: String
}

struct PlannerCalendar: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let ownerUserId: String
    let shareCode: String
    let maxMembers: Int
    var memberCount: Int
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case ownerUserId = "owner_user_id"
        case shareCode = "share_code"
        case maxMembers = "max_members"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case memberCount
    }

    init(
        id: String,
        name: String,
        ownerUserId: String,
        shareCode: String,
        maxMembers: Int,
        memberCount: Int,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.ownerUserId = ownerUserId
        self.shareCode = shareCode
        self.maxMembers = maxMembers
        self.memberCount = memberCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        ownerUserId = try container.decode(String.self, forKey: .ownerUserId)
        shareCode = try container.decode(String.self, forKey: .shareCode)
        maxMembers = try container.decodeIfPresent(Int.self, forKey: .maxMembers) ?? 5
        memberCount = try container.decodeIfPresent(Int.self, forKey: .memberCount) ?? 1
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

struct CalendarMembership: Codable {
    let id: String
    let calendarId: String
    let userId: String
    let role: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case calendarId = "calendar_id"
        case userId = "user_id"
        case role
        case createdAt = "created_at"
    }
}

struct NewPlannerCalendar: Encodable {
    let name: String
    let ownerUserId: String
    let shareCode: String
    let maxMembers: Int

    enum CodingKeys: String, CodingKey {
        case name
        case ownerUserId = "owner_user_id"
        case shareCode = "share_code"
        case maxMembers = "max_members"
    }
}

struct UpdatePlannerCalendarName: Encodable {
    let name: String
}

struct NewCalendarMembership: Encodable {
    let calendarId: String
    let userId: String
    let role: String

    enum CodingKeys: String, CodingKey {
        case calendarId = "calendar_id"
        case userId = "user_id"
        case role
    }
}

private struct CalendarMembershipCountRow: Decodable {
    let calendarId: String

    enum CodingKeys: String, CodingKey {
        case calendarId = "calendar_id"
    }
}

enum NotificationPermissionState: String {
    case notDetermined
    case authorized
    case denied
    case provisional

    init(status: UNAuthorizationStatus) {
        switch status {
        case .authorized: self = .authorized
        case .denied: self = .denied
        case .provisional: self = .provisional
        case .notDetermined: self = .notDetermined
        case .ephemeral: self = .authorized
        @unknown default: self = .notDetermined
        }
    }

    var canDeliverNotifications: Bool {
        self == .authorized || self == .provisional
    }

    var label: String {
        switch self {
        case .notDetermined: return "Not enabled"
        case .authorized: return "Enabled"
        case .denied: return "Blocked in iOS Settings"
        case .provisional: return "Quiet delivery enabled"
        }
    }
}

struct NotificationPreferences: Codable, Equatable {
    var weeklySummaryEnabled: Bool
    var weeklySummaryHour: Int
    var weeklySummaryMinute: Int
    var weeklySummaryWeekday: Int

    var planningNudgeEnabled: Bool
    var planningNudgeHour: Int
    var planningNudgeMinute: Int
    var planningNudgeWeekday: Int

    var eventReminderEnabled: Bool
    var eventLeadMinutes: Int
    var sundayWrapUpEnabled: Bool
    var mondayRecapEnabled: Bool

    static let defaults = NotificationPreferences(
        weeklySummaryEnabled: true,
        weeklySummaryHour: 18,
        weeklySummaryMinute: 0,
        weeklySummaryWeekday: 5, // Thursday
        planningNudgeEnabled: true,
        planningNudgeHour: 10,
        planningNudgeMinute: 0,
        planningNudgeWeekday: 6, // Friday
        eventReminderEnabled: true,
        eventLeadMinutes: 60,
        sundayWrapUpEnabled: true,
        mondayRecapEnabled: true
    )

    enum CodingKeys: String, CodingKey {
        case weeklySummaryEnabled
        case weeklySummaryHour
        case weeklySummaryMinute
        case weeklySummaryWeekday
        case planningNudgeEnabled
        case planningNudgeHour
        case planningNudgeMinute
        case planningNudgeWeekday
        case eventReminderEnabled
        case eventLeadMinutes
        case sundayWrapUpEnabled
        case mondayRecapEnabled
    }

    init(
        weeklySummaryEnabled: Bool,
        weeklySummaryHour: Int,
        weeklySummaryMinute: Int,
        weeklySummaryWeekday: Int,
        planningNudgeEnabled: Bool,
        planningNudgeHour: Int,
        planningNudgeMinute: Int,
        planningNudgeWeekday: Int,
        eventReminderEnabled: Bool,
        eventLeadMinutes: Int,
        sundayWrapUpEnabled: Bool,
        mondayRecapEnabled: Bool
    ) {
        self.weeklySummaryEnabled = weeklySummaryEnabled
        self.weeklySummaryHour = weeklySummaryHour
        self.weeklySummaryMinute = weeklySummaryMinute
        self.weeklySummaryWeekday = weeklySummaryWeekday
        self.planningNudgeEnabled = planningNudgeEnabled
        self.planningNudgeHour = planningNudgeHour
        self.planningNudgeMinute = planningNudgeMinute
        self.planningNudgeWeekday = planningNudgeWeekday
        self.eventReminderEnabled = eventReminderEnabled
        self.eventLeadMinutes = eventLeadMinutes
        self.sundayWrapUpEnabled = sundayWrapUpEnabled
        self.mondayRecapEnabled = mondayRecapEnabled
    }

    private static let storageKey = "weekend-notification-preferences"

    static func load() -> NotificationPreferences {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return defaults }
        guard let decoded = try? JSONDecoder().decode(NotificationPreferences.self, from: data) else { return defaults }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weeklySummaryEnabled = try container.decodeIfPresent(Bool.self, forKey: .weeklySummaryEnabled) ?? Self.defaults.weeklySummaryEnabled
        weeklySummaryHour = try container.decodeIfPresent(Int.self, forKey: .weeklySummaryHour) ?? Self.defaults.weeklySummaryHour
        weeklySummaryMinute = try container.decodeIfPresent(Int.self, forKey: .weeklySummaryMinute) ?? Self.defaults.weeklySummaryMinute
        weeklySummaryWeekday = try container.decodeIfPresent(Int.self, forKey: .weeklySummaryWeekday) ?? Self.defaults.weeklySummaryWeekday
        planningNudgeEnabled = try container.decodeIfPresent(Bool.self, forKey: .planningNudgeEnabled) ?? Self.defaults.planningNudgeEnabled
        planningNudgeHour = try container.decodeIfPresent(Int.self, forKey: .planningNudgeHour) ?? Self.defaults.planningNudgeHour
        planningNudgeMinute = try container.decodeIfPresent(Int.self, forKey: .planningNudgeMinute) ?? Self.defaults.planningNudgeMinute
        planningNudgeWeekday = try container.decodeIfPresent(Int.self, forKey: .planningNudgeWeekday) ?? Self.defaults.planningNudgeWeekday
        eventReminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .eventReminderEnabled) ?? Self.defaults.eventReminderEnabled
        eventLeadMinutes = try container.decodeIfPresent(Int.self, forKey: .eventLeadMinutes) ?? Self.defaults.eventLeadMinutes
        sundayWrapUpEnabled = try container.decodeIfPresent(Bool.self, forKey: .sundayWrapUpEnabled) ?? Self.defaults.sundayWrapUpEnabled
        mondayRecapEnabled = try container.decodeIfPresent(Bool.self, forKey: .mondayRecapEnabled) ?? Self.defaults.mondayRecapEnabled
    }
}

enum CalendarPermissionState: String {
    case notDetermined
    case fullAccess
    case writeOnly
    case denied
    case restricted

    init(status: EKAuthorizationStatus) {
        if #available(iOS 17.0, *) {
            switch status {
            case .notDetermined: self = .notDetermined
            case .restricted: self = .restricted
            case .denied: self = .denied
            case .writeOnly: self = .writeOnly
            case .fullAccess: self = .fullAccess
            case .authorized: self = .fullAccess
            @unknown default: self = .notDetermined
            }
        } else {
            switch status {
            case .notDetermined: self = .notDetermined
            case .restricted: self = .restricted
            case .denied: self = .denied
            case .authorized: self = .fullAccess
            case .fullAccess: self = .fullAccess
            case .writeOnly: self = .fullAccess
            @unknown default: self = .notDetermined
            }
        }
    }

    var canReadEvents: Bool {
        self == .fullAccess
    }

    var canWriteEvents: Bool {
        self == .fullAccess || self == .writeOnly
    }

    var label: String {
        switch self {
        case .notDetermined: return "Not enabled"
        case .fullAccess: return "Full access enabled"
        case .writeOnly: return "Write-only enabled"
        case .denied: return "Blocked in iOS Settings"
        case .restricted: return "Restricted by device settings"
        }
    }
}

struct CalendarConflict: Identifiable, Hashable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let calendarName: String
}

struct PlanTemplate: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let title: String
    let type: String
    let days: [String]
    let startTime: String
    let endTime: String
    let createdAt: Date

    var planType: PlanType {
        PlanType(rawValue: type) ?? .plan
    }

    var dayValues: Set<WeekendDay> {
        Set(days.compactMap { WeekendDay(rawValue: $0) })
    }

    var isAllDay: Bool {
        startTime == "00:00" && endTime == "23:59"
    }
}

struct PlanTemplateDraft {
    let title: String
    let type: PlanType
    let days: Set<WeekendDay>
    let allDay: Bool
    let startTime: String
    let endTime: String
}

struct PlanTemplateBundleItem: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let type: String
    let days: [String]
    let startTime: String
    let endTime: String
    let sortOrder: Int
}

struct PlanTemplateBundle: Identifiable, Codable, Hashable {
    let id: String
    let userId: String
    let name: String
    let items: [PlanTemplateBundleItem]
    let createdAt: Date
    let updatedAt: Date
}

struct QuickAddChip: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var type: String
    var days: [String]
    var startTime: String
    var endTime: String
    var usageCount: Int
    var lastUsedAt: Date

    var dayValues: [WeekendDay] {
        days.compactMap { WeekendDay(rawValue: $0) }
    }
}

enum WeekendReadinessState: String, Codable {
    case unplanned
    case partiallyPlanned
    case ready
    case protected

    var label: String {
        switch self {
        case .unplanned: return "Unplanned"
        case .partiallyPlanned: return "Partially planned"
        case .ready: return "Ready"
        case .protected: return "Protected"
        }
    }
}

final class PlanTemplateStore {
    private let storageKey = "weekend-plan-templates"

    func load() -> [PlanTemplate] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        guard let decoded = try? JSONDecoder().decode([PlanTemplate].self, from: data) else { return [] }
        return decoded.sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ templates: [PlanTemplate]) {
        guard let data = try? JSONEncoder().encode(templates) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

final class PlanTemplateBundleStore {
    private let storageKey = "weekend-plan-template-bundles"

    func load() -> [PlanTemplateBundle] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        guard let decoded = try? JSONDecoder().decode([PlanTemplateBundle].self, from: data) else { return [] }
        return decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ bundles: [PlanTemplateBundle]) {
        guard let data = try? JSONEncoder().encode(bundles) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

final class CalendarExportStore {
    private let storageKey = "weekend-calendar-export-identifiers"
    private var map: [String: [String]]

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            self.map = decoded
        } else {
            self.map = [:]
        }
    }

    func identifiers(for eventId: String) -> [String] {
        map[eventId] ?? []
    }

    func setIdentifiers(_ identifiers: [String], for eventId: String) {
        if identifiers.isEmpty {
            map.removeValue(forKey: eventId)
        } else {
            map[eventId] = identifiers
        }
        persist()
    }

    func removeIdentifiers(for eventId: String) {
        map.removeValue(forKey: eventId)
        persist()
    }

    func pruneMappings(validEventIDs: Set<String>) {
        map = map.filter { validEventIDs.contains($0.key) }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var session: Session?
    @Published var events: [WeekendEvent] = []
    @Published var protections: Set<String> = []
    @Published var selectedTab: AppTab = .overview
    @Published var selectedMonthKey: String = "upcoming"
    @Published var isLoading = false
    @Published var authMessage: String?
    @Published var showAuthSplash = true
    @Published var useDarkMode = false
    @Published var protectionMode: ProtectionMode = .warn
    @Published var calendars: [PlannerCalendar] = []
    @Published var selectedCalendarId: String?
    @Published var notificationPermissionState: NotificationPermissionState = .notDetermined
    @Published var notificationPreferences: NotificationPreferences = .defaults
    @Published var calendarPermissionState: CalendarPermissionState = .notDetermined
    @Published var planTemplates: [PlanTemplate] = []
    @Published var planTemplateBundles: [PlanTemplateBundle] = []
    @Published var quickAddChips: [QuickAddChip] = []
    @Published var syncStates: [String: SyncState] = [:]
    @Published var pendingOperations: [PendingSyncOperation] = []
    @Published var auditEntries: [AuditEntry] = []
    @Published var monthlyGoals: [MonthlyGoal] = []
    @Published var isSyncing = false
    @Published var pendingWeekendSelection: String?
    @Published var pendingAddPlanWeekendKey: String?
    @Published var pendingAddPlanBypassProtection = false

    private let supabase: SupabaseClient
    private let notificationService: NotificationService
    private let calendarService: CalendarService
    private let templateStore: PlanTemplateStore
    private let bundleStore: PlanTemplateBundleStore
    private let calendarExportStore: CalendarExportStore
    private let localCacheStore: LocalCacheStore
    private let syncEngine: SyncEngine
    private let auditService: AuditService
    private let goalService: GoalService
    private var periodicSyncTask: Task<Void, Never>?

    private enum CacheFile {
        static let calendars = "calendars_cache.json"
        static let selectedCalendarId = "selected_calendar_cache.json"
        static let events = "events_cache.json"
        static let protections = "protections_cache.json"
        static let templates = "templates_cache.json"
        static let templateBundles = "template_bundles_cache.json"
        static let quickAddChips = "quick_add_chips_cache.json"
        static let syncStates = "sync_states_cache.json"
        static let syncQueue = "sync_queue_cache.json"
        static let audit = "audit_cache.json"
        static let monthlyGoals = "monthly_goals_cache.json"
    }

    init(
        notificationService: NotificationService = .shared,
        calendarService: CalendarService = .shared,
        templateStore: PlanTemplateStore = PlanTemplateStore(),
        bundleStore: PlanTemplateBundleStore = PlanTemplateBundleStore(),
        calendarExportStore: CalendarExportStore = CalendarExportStore(),
        localCacheStore: LocalCacheStore = .shared,
        syncEngine: SyncEngine = SyncEngine(),
        auditService: AuditService = AuditService(),
        goalService: GoalService = GoalService()
    ) {
        let url = URL(string: "https://vvuxlpsekzohlwywahtq.supabase.co")!
        let key = "sb_publishable_oQir3Zr26EqEERQDzIztcg_TIwK2CBK"
        self.supabase = SupabaseClient(supabaseURL: url, supabaseKey: key)
        self.notificationService = notificationService
        self.calendarService = calendarService
        self.templateStore = templateStore
        self.bundleStore = bundleStore
        self.calendarExportStore = calendarExportStore
        self.localCacheStore = localCacheStore
        self.syncEngine = syncEngine
        self.auditService = auditService
        self.goalService = goalService
        self.useDarkMode = UserDefaults.standard.bool(forKey: "weekend-theme-dark")
        self.notificationPreferences = NotificationPreferences.load()
        self.calendars = localCacheStore.load([PlannerCalendar].self, fileName: CacheFile.calendars, fallback: [])
        self.selectedCalendarId = localCacheStore.load(String?.self, fileName: CacheFile.selectedCalendarId, fallback: nil)
        self.events = localCacheStore.load([WeekendEvent].self, fileName: CacheFile.events, fallback: [])
        self.protections = Set(localCacheStore.load([String].self, fileName: CacheFile.protections, fallback: []))
        self.planTemplates = localCacheStore.load([PlanTemplate].self, fileName: CacheFile.templates, fallback: templateStore.load())
        self.planTemplateBundles = localCacheStore.load([PlanTemplateBundle].self, fileName: CacheFile.templateBundles, fallback: bundleStore.load())
        self.quickAddChips = localCacheStore.load([QuickAddChip].self, fileName: CacheFile.quickAddChips, fallback: [])
        self.syncStates = localCacheStore.load([String: SyncState].self, fileName: CacheFile.syncStates, fallback: [:])
        self.pendingOperations = localCacheStore.load([PendingSyncOperation].self, fileName: CacheFile.syncQueue, fallback: [])
        self.monthlyGoals = localCacheStore.load([MonthlyGoal].self, fileName: CacheFile.monthlyGoals, fallback: [])
        let cachedAudit = localCacheStore.load([AuditEntry].self, fileName: CacheFile.audit, fallback: [])
        self.auditEntries = auditService.trim(entries: cachedAudit)
        if let raw = UserDefaults.standard.string(forKey: "weekend-protection-mode"),
           let mode = ProtectionMode(rawValue: raw) {
            self.protectionMode = mode
        }
        self.notificationService.setRouteHandler { [weak self] routeAction in
            Task { @MainActor in
                self?.handleNotificationRoute(routeAction)
            }
        }
        self.periodicSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard let self else { continue }
                await self.flushPendingOperations()
            }
        }
    }

    deinit {
        periodicSyncTask?.cancel()
    }

    func bootstrap() async {
        do {
            self.session = try await supabase.auth.session
        } catch {
            self.session = nil
        }
        self.showAuthSplash = session == nil
        if session != nil {
            await loadAll()
        }
        await refreshNotificationPermissionState()
        await refreshCalendarPermissionState()
        await rescheduleNotifications()
        await flushPendingOperations()
    }

    func signIn(email: String, password: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await signInWithRetry(email: email, password: password)
            session = try await supabase.auth.session
            showAuthSplash = false
            authMessage = nil
            await loadAll()
            await refreshNotificationPermissionState()
            await refreshCalendarPermissionState()
            await rescheduleNotifications()
            await flushPendingOperations()
        } catch {
            authMessage = authErrorMessage(from: error)
        }
    }

    func signUp(email: String, password: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await supabase.auth.signUp(email: email, password: password)
            authMessage = "Check your email to confirm your account."
        } catch {
            authMessage = authErrorMessage(from: error)
        }
    }

    func signOut() async {
        do {
            try await supabase.auth.signOut()
        } catch {
            authMessage = error.localizedDescription
        }
        session = nil
        showAuthSplash = true
        calendars = []
        selectedCalendarId = nil
        events = []
        protections = []
        monthlyGoals = []
        pendingOperations = []
        syncStates = [:]
        auditEntries = []
        pendingWeekendSelection = nil
        pendingAddPlanWeekendKey = nil
        localCacheStore.remove(fileName: CacheFile.calendars)
        localCacheStore.remove(fileName: CacheFile.selectedCalendarId)
        localCacheStore.remove(fileName: CacheFile.events)
        localCacheStore.remove(fileName: CacheFile.protections)
        localCacheStore.remove(fileName: CacheFile.syncQueue)
        localCacheStore.remove(fileName: CacheFile.syncStates)
        localCacheStore.remove(fileName: CacheFile.audit)
        localCacheStore.remove(fileName: CacheFile.monthlyGoals)
        await refreshNotificationPermissionState()
        await rescheduleNotifications()
    }

    private func signInWithRetry(email: String, password: String) async throws {
        var attempt = 0
        while true {
            do {
                _ = try await supabase.auth.signIn(email: email, password: password)
                return
            } catch {
                attempt += 1
                guard attempt < 3, shouldRetryAuth(error) else { throw error }
                let delayNs = UInt64(attempt) * 500_000_000
                try await Task.sleep(nanoseconds: delayNs)
            }
        }
    }

    private func shouldRetryAuth(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        let retryableCodes: Set<Int> = [
            NSURLErrorNetworkConnectionLost,
            NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost
        ]
        return retryableCodes.contains(nsError.code)
    }

    private func authErrorMessage(from error: Error) -> String {
        if shouldRetryAuth(error) {
            return "The network connection was lost. Please check simulator connectivity and try again."
        }
        return error.localizedDescription
    }

    func loadAll() async {
        await loadCalendars()
        await loadEvents()
        await loadProtections()
        await loadMonthlyGoals()
        await flushPendingOperations()
    }

    func switchCalendar(to calendarId: String) async {
        guard selectedCalendarId != calendarId else { return }
        selectedCalendarId = calendarId
        persistCaches()
        await loadEvents()
        await loadProtections()
        await rescheduleNotifications()
    }

    func createCalendar(name: String) async -> Bool {
        guard let session else { return false }
        let userId = normalizedUserId(for: session)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let payload = NewPlannerCalendar(
            name: trimmed,
            ownerUserId: userId,
            shareCode: generateShareCode(),
            maxMembers: 5
        )

        do {
            let created: [PlannerCalendar] = try await supabase
                .from("planner_calendars")
                .insert(payload)
                .select("id,name,owner_user_id,share_code,max_members,created_at,updated_at")
                .execute()
                .value
            guard let calendar = created.first else { return false }
            let membership = NewCalendarMembership(
                calendarId: calendar.id,
                userId: userId,
                role: "owner"
            )
            _ = try await supabase
                .from("calendar_members")
                .insert(membership)
                .execute()
            await loadCalendars()
            if calendars.contains(where: { $0.id == calendar.id }) {
                await switchCalendar(to: calendar.id)
            }
            return true
        } catch {
            authMessage = "Could not create calendar. \(error.localizedDescription)"
            return false
        }
    }

    func renameCalendar(calendarId: String, to newName: String) async -> Bool {
        guard session != nil else { return false }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            authMessage = "Calendar name cannot be empty."
            return false
        }

        if let existing = calendars.first(where: { $0.id == calendarId }),
           existing.name == trimmed {
            return true
        }

        let payload = UpdatePlannerCalendarName(name: trimmed)
        do {
            let updated: [PlannerCalendar] = try await supabase
                .from("planner_calendars")
                .update(payload)
                .eq("id", value: calendarId)
                .select("id,name,owner_user_id,share_code,max_members,created_at,updated_at")
                .limit(1)
                .execute()
                .value

            guard !updated.isEmpty else {
                authMessage = "Only the calendar owner can rename this calendar."
                return false
            }

            await loadCalendars()
            return true
        } catch {
            authMessage = "Could not rename calendar. \(error.localizedDescription)"
            return false
        }
    }

    func joinCalendar(shareCode: String) async -> Bool {
        guard let session else { return false }
        let userId = normalizedUserId(for: session)
        let normalizedCode = shareCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !normalizedCode.isEmpty else { return false }

        do {
            let calendarsByCode: [PlannerCalendar] = try await supabase
                .from("planner_calendars")
                .select("id,name,owner_user_id,share_code,max_members,created_at,updated_at")
                .eq("share_code", value: normalizedCode)
                .limit(1)
                .execute()
                .value
            guard let target = calendarsByCode.first else {
                authMessage = "No calendar found for code \(normalizedCode)."
                return false
            }

            let existingMemberships: [CalendarMembership] = try await supabase
                .from("calendar_members")
                .select("id,calendar_id,user_id,role,created_at")
                .eq("calendar_id", value: target.id)
                .execute()
                .value

            if existingMemberships.contains(where: { $0.userId == userId }) {
                await loadCalendars()
                await switchCalendar(to: target.id)
                return true
            }

            guard existingMemberships.count < target.maxMembers else {
                authMessage = "This calendar is full. A maximum of \(target.maxMembers) members is allowed."
                return false
            }

            let membership = NewCalendarMembership(
                calendarId: target.id,
                userId: userId,
                role: "member"
            )
            _ = try await supabase
                .from("calendar_members")
                .insert(membership)
                .execute()

            await loadCalendars()
            await switchCalendar(to: target.id)
            return true
        } catch {
            authMessage = "Could not join calendar. \(error.localizedDescription)"
            return false
        }
    }

    private func loadCalendars() async {
        guard let session else { return }
        let userId = normalizedUserId(for: session)
        do {
            var memberships = try await fetchMemberships(userId: userId)
            if memberships.isEmpty {
                try await ensurePersonalCalendar(userId: userId)
                memberships = try await fetchMemberships(userId: userId)
            }

            let calendarIDs = Array(Set(memberships.map(\.calendarId)))
            guard !calendarIDs.isEmpty else {
                calendars = []
                selectedCalendarId = nil
                persistCaches()
                return
            }

            let fetchedCalendars: [PlannerCalendar] = try await supabase
                .from("planner_calendars")
                .select("id,name,owner_user_id,share_code,max_members,created_at,updated_at")
                .`in`("id", values: calendarIDs)
                .order("created_at", ascending: true)
                .execute()
                .value

            let memberCounts = await fetchMemberCounts(calendarIDs: calendarIDs)
            calendars = fetchedCalendars
                .map { calendar in
                    var mutable = calendar
                    mutable.memberCount = memberCounts[calendar.id] ?? 1
                    return mutable
                }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            if let selectedCalendarId,
               calendars.contains(where: { $0.id == selectedCalendarId }) {
                // keep current selection
            } else {
                selectedCalendarId = calendars.first?.id
            }
            persistCaches()
        } catch {
            authMessage = "Could not load calendars. \(error.localizedDescription)"
        }
    }

    private func fetchMemberships(userId: String) async throws -> [CalendarMembership] {
        try await supabase
            .from("calendar_members")
            .select("id,calendar_id,user_id,role,created_at")
            .eq("user_id", value: userId)
            .execute()
            .value
    }

    private func ensurePersonalCalendar(userId: String) async throws {
        let payload = NewPlannerCalendar(
            name: "Personal",
            ownerUserId: userId,
            shareCode: generateShareCode(),
            maxMembers: 5
        )
        let created: [PlannerCalendar] = try await supabase
            .from("planner_calendars")
            .insert(payload)
            .select("id,name,owner_user_id,share_code,max_members,created_at,updated_at")
            .execute()
            .value

        guard let calendar = created.first else { return }
        let membership = NewCalendarMembership(
            calendarId: calendar.id,
            userId: userId,
            role: "owner"
        )
        _ = try await supabase
            .from("calendar_members")
            .insert(membership)
            .execute()
    }

    private func fetchMemberCounts(calendarIDs: [String]) async -> [String: Int] {
        guard !calendarIDs.isEmpty else { return [:] }
        do {
            let rows: [CalendarMembershipCountRow] = try await supabase
                .from("calendar_members")
                .select("calendar_id")
                .`in`("calendar_id", values: calendarIDs)
                .execute()
                .value
            return rows.reduce(into: [:]) { partialResult, row in
                partialResult[row.calendarId, default: 0] += 1
            }
        } catch {
            return [:]
        }
    }

    private func generateShareCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var result = ""
        for _ in 0..<8 {
            if let character = alphabet.randomElement() {
                result.append(character)
            }
        }
        return result
    }

    func loadEvents() async {
        guard session != nil else { return }
        guard let selectedCalendarId else {
            events = []
            persistCaches()
            return
        }
        do {
            let response: [WeekendEvent] = try await supabase
                .from("weekend_events")
                .select()
                .eq("calendar_id", value: selectedCalendarId)
                .order("weekend_key", ascending: true)
                .execute()
                .value
            let normalized = response.map { event in
                let localIdentifiers = calendarExportStore.identifiers(for: event.id)
                return event.withCalendarEventIdentifier(localIdentifiers.first ?? event.calendarEventIdentifier)
            }.filter { !$0.isSyncDeleted }
            self.events = sortedEvents(normalized)
            calendarExportStore.pruneMappings(validEventIDs: Set(normalized.map(\.id)))
            persistCaches()
        } catch {
            authMessage = error.localizedDescription
        }
    }

    func loadProtections() async {
        guard session != nil else { return }
        guard let selectedCalendarId else {
            protections = []
            persistCaches()
            return
        }
        do {
            let response: [WeekendProtection] = try await supabase
                .from("weekend_protections")
                .select("weekend_key,user_id,calendar_id")
                .eq("calendar_id", value: selectedCalendarId)
                .order("weekend_key", ascending: true)
                .execute()
                .value
            self.protections = Set(response.map { $0.weekendKey })
            persistCaches()
        } catch {
            authMessage = error.localizedDescription
        }
    }

    func loadMonthlyGoals() async {
        guard let session else { return }
        let userId = normalizedUserId(for: session)
        do {
            let response: [MonthlyGoal] = try await supabase
                .from("monthly_goals")
                .select("id,user_id,month_key,planned_target,completed_target,created_at,updated_at")
                .eq("user_id", value: userId)
                .execute()
                .value
            self.monthlyGoals = response
            persistCaches()
        } catch {
            // Keep local goals if remote fetch fails.
        }
    }

    func addEvent(_ draft: NewWeekendEvent, exportToCalendar: Bool = false) async -> Bool {
        guard let session else { return false }
        guard let selectedCalendarId else {
            authMessage = "Please select a calendar first."
            return false
        }
        let userId = normalizedUserId(for: session)
        let now = Date()
        let newEvent = WeekendEvent(
            id: draft.id ?? UUID().uuidString,
            title: draft.title,
            type: draft.type,
            calendarId: draft.calendarId ?? selectedCalendarId,
            weekendKey: draft.weekendKey,
            days: draft.days.sorted(),
            startTime: draft.startTime,
            endTime: draft.endTime,
            userId: userId,
            calendarEventIdentifier: nil,
            status: WeekendEventStatus.planned.rawValue,
            completedAt: nil,
            cancelledAt: nil,
            clientUpdatedAt: now,
            updatedAt: now,
            createdAt: now,
            deletedAt: nil
        )

        events = sortedEvents(events + [newEvent])
        registerQuickAddUsage(from: newEvent)
        if exportToCalendar {
            syncCalendarExport(for: newEvent, enabled: true)
        }
        recordAudit(
            action: "event.add",
            entityType: .event,
            entityId: newEvent.id,
            payload: [
                "weekendKey": newEvent.weekendKey,
                "type": newEvent.type,
                "status": newEvent.status
            ]
        )
        enqueueOperation(
            PendingSyncOperation(
                type: .upsertEvent,
                entityId: newEvent.id,
                event: newEvent,
                calendarId: newEvent.calendarId
            )
        )
        persistCaches()
        await rescheduleNotifications()
        await flushPendingOperations()
        return true
    }

    func updateEvent(eventId: String, _ update: UpdateWeekendEvent, exportToCalendar: Bool) async -> Bool {
        guard let index = events.firstIndex(where: { $0.id == eventId }) else { return false }
        guard let selectedCalendarId else {
            authMessage = "Please select a calendar first."
            return false
        }
        var updatedEvent = events[index]
        let now = Date()
        updatedEvent.title = update.title
        updatedEvent.type = update.type
        updatedEvent.calendarId = update.calendarId ?? selectedCalendarId
        updatedEvent.weekendKey = update.weekendKey
        updatedEvent.days = update.days.sorted()
        updatedEvent.startTime = update.startTime
        updatedEvent.endTime = update.endTime
        updatedEvent.clientUpdatedAt = now
        updatedEvent.updatedAt = now
        events[index] = updatedEvent
        events = sortedEvents(events)

        if exportToCalendar {
            syncCalendarExport(for: updatedEvent, enabled: true)
        } else {
            removeCalendarExports(forEventID: eventId)
        }
        recordAudit(
            action: "event.update",
            entityType: .event,
            entityId: updatedEvent.id,
            payload: [
                "weekendKey": updatedEvent.weekendKey,
                "type": updatedEvent.type,
                "status": updatedEvent.status
            ]
        )
        enqueueOperation(
            PendingSyncOperation(
                type: .upsertEvent,
                entityId: updatedEvent.id,
                event: updatedEvent,
                calendarId: updatedEvent.calendarId
            )
        )
        persistCaches()
        await rescheduleNotifications()
        await flushPendingOperations()
        return true
    }

    func moveEvent(eventId: String, toWeekendKey: String, days: [WeekendDay]? = nil) async -> Bool {
        guard let event = events.first(where: { $0.id == eventId }) else { return false }
        let daySelection = (days?.isEmpty == false ? days : event.dayValues) ?? event.dayValues
        let updatedDays = daySelection.sorted { $0.rawValue < $1.rawValue }
        let payload = UpdateWeekendEvent(
            title: event.title,
            type: event.type,
            calendarId: event.calendarId ?? selectedCalendarId,
            weekendKey: toWeekendKey,
            days: updatedDays.map(\.rawValue),
            startTime: event.startTime,
            endTime: event.endTime
        )
        return await updateEvent(
            eventId: event.id,
            payload,
            exportToCalendar: isEventExportedToCalendar(eventId: event.id)
        )
    }

    func duplicateEvent(eventId: String, toWeekendKey: String, days: [WeekendDay]? = nil) async -> Bool {
        guard let event = events.first(where: { $0.id == eventId }),
              let session = session else { return false }
        let daySelection = (days?.isEmpty == false ? days : event.dayValues) ?? event.dayValues
        let duplicateDays = daySelection.sorted { $0.rawValue < $1.rawValue }
        let payload = NewWeekendEvent(
            id: UUID().uuidString,
            title: event.title,
            type: event.type,
            calendarId: event.calendarId ?? selectedCalendarId,
            weekendKey: toWeekendKey,
            days: duplicateDays.map(\.rawValue),
            startTime: event.startTime,
            endTime: event.endTime,
            userId: normalizedUserId(for: session)
        )
        return await addEvent(payload, exportToCalendar: isEventExportedToCalendar(eventId: event.id))
    }

    func removeEvent(_ event: WeekendEvent) async {
        guard events.contains(where: { $0.id == event.id }) else { return }
        events.removeAll { $0.id == event.id }
        removeCalendarExports(forEventID: event.id)
        recordAudit(
            action: "event.remove",
            entityType: .event,
            entityId: event.id,
            payload: ["weekendKey": event.weekendKey]
        )
        enqueueOperation(
            PendingSyncOperation(
                type: .deleteEvent,
                entityId: event.id,
                calendarId: event.calendarId ?? selectedCalendarId
            )
        )
        persistCaches()
        await rescheduleNotifications()
        await flushPendingOperations()
    }

    func toggleProtection(weekendKey: String, removePlans: Bool) async {
        guard let selectedCalendarId else {
            authMessage = "Please select a calendar first."
            return
        }
        if protections.contains(weekendKey) {
            protections.remove(weekendKey)
            recordAudit(
                action: "protection.remove",
                entityType: .protection,
                entityId: weekendKey,
                payload: ["weekendKey": weekendKey]
            )
            enqueueOperation(
                PendingSyncOperation(
                    type: .setProtection,
                    entityId: weekendKey,
                    calendarId: selectedCalendarId,
                    protectionWeekKey: weekendKey,
                    protectionEnabled: false
                )
            )
            persistCaches()
            await rescheduleNotifications()
            await flushPendingOperations()
            return
        }

        if removePlans {
            let affectedEvents = events(for: weekendKey)
            for event in affectedEvents {
                events.removeAll { $0.id == event.id }
                removeCalendarExports(forEventID: event.id)
                enqueueOperation(
                    PendingSyncOperation(
                        type: .deleteEvent,
                        entityId: event.id,
                        calendarId: event.calendarId ?? selectedCalendarId
                    )
                )
            }
        }

        protections.insert(weekendKey)
        recordAudit(
            action: "protection.add",
            entityType: .protection,
            entityId: weekendKey,
            payload: [
                "weekendKey": weekendKey,
                "removedPlans": removePlans ? "true" : "false"
            ]
        )
        enqueueOperation(
            PendingSyncOperation(
                type: .setProtection,
                entityId: weekendKey,
                calendarId: selectedCalendarId,
                protectionWeekKey: weekendKey,
                protectionEnabled: true
            )
        )
        persistCaches()
        await rescheduleNotifications()
        await flushPendingOperations()
    }

    private func normalizedUserId(for session: Session) -> String {
        session.user.id.uuidString.lowercased()
    }

    func isProtected(_ weekendKey: String) -> Bool {
        protections.contains(weekendKey)
    }

    func events(for weekendKey: String) -> [WeekendEvent] {
        events
            .filter { $0.weekendKey == weekendKey }
            .sorted { lhs, rhs in
                if lhs.startTime == rhs.startTime {
                    return lhs.title < rhs.title
                }
                return lhs.startTime < rhs.startTime
            }
    }

    func status(for weekendKey: String) -> WeekendStatus {
        let weekendEvents = events
            .filter { $0.weekendKey == weekendKey && $0.lifecycleStatus == .planned }
        let hasTravel = weekendEvents.contains { $0.planType == .travel }
        let hasPlan = weekendEvents.contains { $0.planType == .plan }
        let isProtected = protections.contains(weekendKey)

        if hasTravel {
            return WeekendStatus(type: "travel", label: "Travel plans")
        }
        if hasPlan {
            return WeekendStatus(type: "plan", label: "Local plans")
        }
        if isProtected {
            return WeekendStatus(type: "protected", label: "Protected")
        }
        return WeekendStatus(type: "free", label: "Free")
    }

    func setTheme(_ isDark: Bool) {
        useDarkMode = isDark
        UserDefaults.standard.set(isDark, forKey: "weekend-theme-dark")
    }

    func setProtectionMode(_ mode: ProtectionMode) {
        protectionMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "weekend-protection-mode")
    }

    func saveTemplate(name: String, draft: PlanTemplateDraft) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedTitle.isEmpty, !draft.days.isEmpty else { return }

        let start = draft.allDay ? "00:00" : draft.startTime
        let end = draft.allDay ? "23:59" : draft.endTime
        let template = PlanTemplate(
            id: UUID().uuidString,
            name: trimmedName,
            title: trimmedTitle,
            type: draft.type.rawValue,
            days: draft.days.sorted { $0.rawValue < $1.rawValue }.map(\.rawValue),
            startTime: start,
            endTime: end,
            createdAt: Date()
        )
        var updatedTemplates = planTemplates
        updatedTemplates.insert(template, at: 0)
        if updatedTemplates.count > 30 {
            updatedTemplates = Array(updatedTemplates.prefix(30))
        }
        planTemplates = updatedTemplates
        templateStore.save(updatedTemplates)
        persistCaches()
        recordAudit(
            action: "template.save",
            entityType: .template,
            entityId: template.id,
            payload: ["name": trimmedName]
        )
    }

    func saveTemplate(from event: WeekendEvent, name: String? = nil) {
        saveTemplate(
            name: name ?? event.title,
            draft: PlanTemplateDraft(
                title: event.title,
                type: event.planType,
                days: Set(event.dayValues),
                allDay: event.isAllDay,
                startTime: event.startTime,
                endTime: event.endTime
            )
        )
    }

    func removeTemplate(_ template: PlanTemplate) {
        planTemplates.removeAll { $0.id == template.id }
        templateStore.save(planTemplates)
        persistCaches()
        recordAudit(
            action: "template.remove",
            entityType: .template,
            entityId: template.id,
            payload: ["name": template.name]
        )
    }

    func applyTemplate(_ template: PlanTemplate, to weekendKey: String, userId: String) -> NewWeekendEvent {
        NewWeekendEvent(
            title: template.title,
            type: template.type,
            weekendKey: weekendKey,
            days: template.days,
            startTime: template.startTime,
            endTime: template.endTime,
            userId: userId
        )
    }

    func starterFromLastWeekend(referenceDate: Date) -> WeekendEvent? {
        guard let referenceWeekendKey = CalendarHelper.weekendKey(for: referenceDate),
              let referenceSaturday = CalendarHelper.parseKey(referenceWeekendKey) else {
            return nil
        }
        return events
            .filter {
                guard let saturday = CalendarHelper.parseKey($0.weekendKey) else { return false }
                return saturday < referenceSaturday
            }
            .sorted { lhs, rhs in
                if lhs.weekendKey == rhs.weekendKey {
                    return lhs.startTime < rhs.startTime
                }
                return lhs.weekendKey > rhs.weekendKey
            }
            .first
    }

    func starterFromSameMonthLastYear(referenceDate: Date) -> WeekendEvent? {
        guard let referenceWeekendKey = CalendarHelper.weekendKey(for: referenceDate),
              let referenceSaturday = CalendarHelper.parseKey(referenceWeekendKey),
              let targetDate = CalendarHelper.calendar.date(byAdding: .year, value: -1, to: referenceSaturday) else {
            return nil
        }
        let targetYear = CalendarHelper.calendar.component(.year, from: targetDate)
        let targetMonth = CalendarHelper.calendar.component(.month, from: targetDate)
        return events
            .filter { event in
                guard let saturday = CalendarHelper.parseKey(event.weekendKey) else { return false }
                return CalendarHelper.calendar.component(.year, from: saturday) == targetYear &&
                    CalendarHelper.calendar.component(.month, from: saturday) == targetMonth
            }
            .sorted { lhs, rhs in
                if lhs.weekendKey == rhs.weekendKey {
                    return lhs.startTime < rhs.startTime
                }
                return lhs.weekendKey > rhs.weekendKey
            }
            .first
    }

    func saveTemplateBundleFromWeekend(weekendKey: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let weekendEvents = events(for: weekendKey)
        guard !weekendEvents.isEmpty else { return }
        let now = Date()
        let bundle = PlanTemplateBundle(
            id: UUID().uuidString,
            userId: session.map(normalizedUserId(for:)) ?? "",
            name: trimmed,
            items: weekendEvents.enumerated().map { index, event in
                PlanTemplateBundleItem(
                    id: UUID().uuidString,
                    title: event.title,
                    type: event.type,
                    days: event.days,
                    startTime: event.startTime,
                    endTime: event.endTime,
                    sortOrder: index
                )
            },
            createdAt: now,
            updatedAt: now
        )
        planTemplateBundles.insert(bundle, at: 0)
        if planTemplateBundles.count > 20 {
            planTemplateBundles = Array(planTemplateBundles.prefix(20))
        }
        bundleStore.save(planTemplateBundles)
        persistCaches()
        recordAudit(
            action: "template.bundle.save",
            entityType: .template,
            entityId: bundle.id,
            payload: ["name": trimmed, "weekendKey": weekendKey]
        )
    }

    func removeTemplateBundle(_ bundle: PlanTemplateBundle) {
        planTemplateBundles.removeAll { $0.id == bundle.id }
        bundleStore.save(planTemplateBundles)
        persistCaches()
        recordAudit(
            action: "template.bundle.remove",
            entityType: .template,
            entityId: bundle.id,
            payload: ["name": bundle.name]
        )
    }

    func applyTemplateBundle(bundleId: String, toWeekendKey weekendKey: String) async -> Int {
        guard let session,
              let bundle = planTemplateBundles.first(where: { $0.id == bundleId }) else { return 0 }
        let userId = normalizedUserId(for: session)
        var createdCount = 0
        for item in bundle.items.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let payload = NewWeekendEvent(
                id: UUID().uuidString,
                title: item.title,
                type: item.type,
                weekendKey: weekendKey,
                days: item.days,
                startTime: item.startTime,
                endTime: item.endTime,
                userId: userId
            )
            if await addEvent(payload) {
                createdCount += 1
            }
        }
        if createdCount > 0 {
            recordAudit(
                action: "template.bundle.apply",
                entityType: .template,
                entityId: bundle.id,
                payload: ["name": bundle.name, "count": String(createdCount)]
            )
        }
        return createdCount
    }

    func topQuickAddChips(limit: Int = 4) -> [QuickAddChip] {
        quickAddChips
            .sorted { lhs, rhs in
                if lhs.usageCount == rhs.usageCount {
                    return lhs.lastUsedAt > rhs.lastUsedAt
                }
                return lhs.usageCount > rhs.usageCount
            }
            .prefix(limit)
            .map { $0 }
    }

    func quickAdd(chip: QuickAddChip, toWeekendKey weekendKey: String) async -> Bool {
        guard let session else { return false }
        let payload = NewWeekendEvent(
            id: UUID().uuidString,
            title: chip.title,
            type: chip.type,
            weekendKey: weekendKey,
            days: chip.days,
            startTime: chip.startTime,
            endTime: chip.endTime,
            userId: normalizedUserId(for: session)
        )
        let success = await addEvent(payload)
        if success {
            incrementChipUsage(chipId: chip.id)
        }
        return success
    }

    func readiness(for weekendKey: String) -> WeekendReadinessState {
        if isProtected(weekendKey) {
            return .protected
        }
        let planned = events(for: weekendKey).filter { $0.lifecycleStatus == .planned }
        if planned.isEmpty {
            return .unplanned
        }
        let coveredDays = Set(planned.flatMap(\.dayValues))
        if coveredDays.contains(.sat) && coveredDays.contains(.sun) {
            return .ready
        }
        return .partiallyPlanned
    }

    func transitionEventStatus(eventId: String, to status: WeekendEventStatus) async -> Bool {
        guard let index = events.firstIndex(where: { $0.id == eventId }) else { return false }
        let now = Date()
        let updated = events[index].withLifecycleStatus(status, at: now)
        events[index] = updated
        events = sortedEvents(events)
        enqueueOperation(
            PendingSyncOperation(
                type: .upsertEvent,
                entityId: updated.id,
                event: updated
            )
        )
        recordAudit(
            action: "event.status.\(status.rawValue)",
            entityType: .event,
            entityId: updated.id,
            payload: ["status": status.rawValue, "weekendKey": updated.weekendKey]
        )
        persistCaches()
        await rescheduleNotifications()
        await flushPendingOperations()
        return true
    }

    func markEventCompleted(_ eventId: String) async -> Bool {
        await transitionEventStatus(eventId: eventId, to: .completed)
    }

    func markEventCancelled(_ eventId: String) async -> Bool {
        await transitionEventStatus(eventId: eventId, to: .cancelled)
    }

    func reopenEvent(_ eventId: String) async -> Bool {
        await transitionEventStatus(eventId: eventId, to: .planned)
    }

    func carryForwardIncompleteEvents(fromWeekendKey: String, toWeekendKey: String) async -> Int {
        guard !isProtected(toWeekendKey),
              let session else { return 0 }
        let source = events(for: fromWeekendKey).filter { $0.lifecycleStatus == .planned }
        guard !source.isEmpty else { return 0 }
        let userId = normalizedUserId(for: session)
        var created = 0

        for event in source {
            let duplicateExists = events(for: toWeekendKey).contains {
                $0.lifecycleStatus == .planned &&
                $0.title == event.title &&
                $0.type == event.type &&
                $0.startTime == event.startTime &&
                $0.endTime == event.endTime &&
                $0.days.sorted() == event.days.sorted()
            }
            if duplicateExists { continue }

            let payload = NewWeekendEvent(
                id: UUID().uuidString,
                title: event.title,
                type: event.type,
                weekendKey: toWeekendKey,
                days: event.days,
                startTime: event.startTime,
                endTime: event.endTime,
                userId: userId
            )
            if await addEvent(payload, exportToCalendar: isEventExportedToCalendar(eventId: event.id)) {
                created += 1
            }
        }

        if created > 0 {
            recordAudit(
                action: "event.carry_forward",
                entityType: .event,
                entityId: fromWeekendKey,
                payload: [
                    "fromWeekendKey": fromWeekendKey,
                    "toWeekendKey": toWeekendKey,
                    "count": String(created)
                ]
            )
        }
        return created
    }

    func isEventExportedToCalendar(eventId: String) -> Bool {
        !calendarExportStore.identifiers(for: eventId).isEmpty
    }

    func refreshCalendarPermissionState() async {
        calendarPermissionState = calendarService.permissionState()
    }

    func requestCalendarPermissionIfNeeded() async {
        if calendarPermissionState == .notDetermined {
            calendarPermissionState = await calendarService.requestAccess()
        } else {
            await refreshCalendarPermissionState()
        }
    }

    func calendarConflicts(for intervals: [DateInterval], ignoringEventID: String? = nil) async -> [CalendarConflict] {
        guard calendarPermissionState.canReadEvents else { return [] }
        let ignoredIdentifiers: Set<String>
        if let ignoringEventID {
            ignoredIdentifiers = Set(calendarExportStore.identifiers(for: ignoringEventID))
        } else {
            ignoredIdentifiers = []
        }
        return calendarService.conflicts(for: intervals, ignoringEventIdentifiers: ignoredIdentifiers)
    }

    func refreshNotificationPermissionState() async {
        notificationPermissionState = await notificationService.authorizationStatus()
    }

    func requestNotificationPermissionIfNeeded() async {
        if notificationPermissionState == .notDetermined {
            notificationPermissionState = await notificationService.requestAuthorization()
        } else {
            await refreshNotificationPermissionState()
        }
        await rescheduleNotifications()
    }

    func updateNotificationPreferences(_ update: (inout NotificationPreferences) -> Void) {
        var updated = notificationPreferences
        update(&updated)
        guard updated != notificationPreferences else { return }
        notificationPreferences = updated
        notificationPreferences.save()
        recordAudit(
            action: "settings.notifications.update",
            entityType: .settings,
            entityId: "notification-preferences",
            payload: [:]
        )
        Task { [weak self] in
            guard let self else { return }
            await self.rescheduleNotifications()
        }
    }

    func rescheduleNotifications() async {
        await notificationService.rescheduleNotifications(
            events: events,
            protections: protections,
            preferences: notificationPreferences,
            sessionIsActive: session != nil
        )
    }

    func setMonthlyGoal(monthKey: String, plannedTarget: Int, completedTarget: Int) {
        guard let session else { return }
        let userId = normalizedUserId(for: session)
        let safePlanned = max(0, plannedTarget)
        let safeCompleted = max(0, completedTarget)
        let now = Date()

        if let index = monthlyGoals.firstIndex(where: { $0.monthKey == monthKey }) {
            monthlyGoals[index].plannedTarget = safePlanned
            monthlyGoals[index].completedTarget = safeCompleted
            monthlyGoals[index].updatedAt = now
            monthlyGoals[index].userId = userId
        } else {
            monthlyGoals.append(
                MonthlyGoal(
                    id: UUID().uuidString,
                    userId: userId,
                    monthKey: monthKey,
                    plannedTarget: safePlanned,
                    completedTarget: safeCompleted,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }
        if let goal = monthlyGoals.first(where: { $0.monthKey == monthKey }) {
            enqueueOperation(
                PendingSyncOperation(
                    type: .upsertGoal,
                    entityId: monthKey,
                    goal: goal
                )
            )
        }
        persistCaches()
        recordAudit(
            action: "goal.set",
            entityType: .goal,
            entityId: monthKey,
            payload: [
                "plannedTarget": String(safePlanned),
                "completedTarget": String(safeCompleted)
            ]
        )
        Task { [weak self] in
            guard let self else { return }
            await self.flushPendingOperations()
        }
    }

    func weeklyReportSnapshot(referenceDate: Date = Date()) -> WeeklyReportSnapshot {
        goalService.weeklyReportSnapshot(
            events: events,
            goals: monthlyGoals,
            referenceDate: referenceDate
        )
    }

    func currentStreak(referenceDate: Date = Date()) -> Int {
        goalService.streakSnapshot(events: events, referenceDate: referenceDate).current
    }

    func enqueueOperation(_ operation: PendingSyncOperation) {
        pendingOperations.append(operation)
        switch operation.type {
        case .upsertEvent, .deleteEvent:
            syncStates[operation.entityId] = .pending
        case .setProtection, .upsertGoal, .appendAudit:
            break
        }
        persistCaches()
    }

    func flushPendingOperations() async {
        guard let session, !pendingOperations.isEmpty, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let result = await syncEngine.flush(
            operations: pendingOperations,
            userId: normalizedUserId(for: session),
            supabase: supabase
        )
        pendingOperations = result.remainingOperations
        for (entityId, syncState) in result.syncStates {
            syncStates[entityId] = syncState
        }
        if let lastErrorMessage = result.lastErrorMessage {
            authMessage = "Sync will retry: \(lastErrorMessage)"
        }
        persistCaches()
    }

    func syncState(for eventId: String) -> SyncState {
        syncStates[eventId] ?? .synced
    }

    func recordAudit(action: String, entityType: AuditEntityType, entityId: String, payload: [String: String]) {
        let entry = auditService.createEntry(
            action: action,
            entityType: entityType,
            entityId: entityId,
            payload: payload
        )
        auditEntries = auditService.trim(entries: [entry] + auditEntries)
        if session != nil {
            enqueueOperation(
                PendingSyncOperation(
                    type: .appendAudit,
                    entityId: entry.id,
                    auditEntry: entry
                )
            )
        }
        persistCaches()
    }

    func consumePendingWeekendSelection() {
        pendingWeekendSelection = nil
    }

    func consumePendingAddPlanSelection() {
        pendingAddPlanWeekendKey = nil
        pendingAddPlanBypassProtection = false
    }

    private func handleNotificationRoute(_ routeAction: NotificationRouteAction) {
        switch routeAction {
        case .openWeekend(let weekendKey):
            selectedTab = .weekend
            selectedMonthKey = CalendarHelper.monthSelectionKey(for: weekendKey)
            pendingWeekendSelection = weekendKey
        case .addPlan(let weekendKey):
            selectedTab = .weekend
            selectedMonthKey = CalendarHelper.monthSelectionKey(for: weekendKey)
            pendingAddPlanWeekendKey = weekendKey
            pendingAddPlanBypassProtection = false
        }
    }

    private func syncCalendarExport(for event: WeekendEvent, enabled: Bool) {
        if !enabled {
            removeCalendarExports(forEventID: event.id)
            return
        }
        guard calendarPermissionState.canWriteEvents else { return }
        let intervals = CalendarHelper.intervals(for: event)
        guard !intervals.isEmpty else { return }
        let existingIdentifiers = calendarExportStore.identifiers(for: event.id)
        do {
            let syncedIdentifiers = try calendarService.syncExportedEvents(
                title: event.title,
                planType: event.planType,
                intervals: intervals,
                existingIdentifiers: existingIdentifiers
            )
            calendarExportStore.setIdentifiers(syncedIdentifiers, for: event.id)
            updateInMemoryCalendarIdentifier(forEventID: event.id, identifier: syncedIdentifiers.first)
        } catch {
            authMessage = "Could not sync Apple Calendar. \(error.localizedDescription)"
        }
    }

    private func removeCalendarExports(forEventID eventID: String) {
        let identifiers = calendarExportStore.identifiers(for: eventID)
        guard !identifiers.isEmpty else {
            updateInMemoryCalendarIdentifier(forEventID: eventID, identifier: nil)
            return
        }
        do {
            try calendarService.removeExportedEvents(identifiers: identifiers)
        } catch {
            authMessage = "Could not remove Apple Calendar event. \(error.localizedDescription)"
        }
        calendarExportStore.removeIdentifiers(for: eventID)
        updateInMemoryCalendarIdentifier(forEventID: eventID, identifier: nil)
    }

    private func removeCalendarExports(forEventIDs eventIDs: [String]) {
        for eventID in eventIDs {
            removeCalendarExports(forEventID: eventID)
        }
    }

    private func updateInMemoryCalendarIdentifier(forEventID eventID: String, identifier: String?) {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        events[index].calendarEventIdentifier = identifier
    }

    private func sortedEvents(_ input: [WeekendEvent]) -> [WeekendEvent] {
        input.sorted { lhs, rhs in
            if lhs.weekendKey == rhs.weekendKey {
                if lhs.startTime == rhs.startTime {
                    return lhs.title < rhs.title
                }
                return lhs.startTime < rhs.startTime
            }
            return lhs.weekendKey < rhs.weekendKey
        }
    }

    private func registerQuickAddUsage(from event: WeekendEvent) {
        if let index = quickAddChips.firstIndex(where: {
            $0.title == event.title &&
            $0.type == event.type &&
            $0.days.sorted() == event.days.sorted() &&
            $0.startTime == event.startTime &&
            $0.endTime == event.endTime
        }) {
            quickAddChips[index].usageCount += 1
            quickAddChips[index].lastUsedAt = Date()
        } else {
            quickAddChips.append(
                QuickAddChip(
                    id: UUID().uuidString,
                    title: event.title,
                    type: event.type,
                    days: event.days.sorted(),
                    startTime: event.startTime,
                    endTime: event.endTime,
                    usageCount: 1,
                    lastUsedAt: Date()
                )
            )
        }
        quickAddChips = quickAddChips
            .sorted { lhs, rhs in
                if lhs.usageCount == rhs.usageCount {
                    return lhs.lastUsedAt > rhs.lastUsedAt
                }
                return lhs.usageCount > rhs.usageCount
            }
            .prefix(12)
            .map { $0 }
    }

    private func incrementChipUsage(chipId: String) {
        guard let index = quickAddChips.firstIndex(where: { $0.id == chipId }) else { return }
        quickAddChips[index].usageCount += 1
        quickAddChips[index].lastUsedAt = Date()
        persistCaches()
    }

    private func persistCaches() {
        localCacheStore.save(calendars, fileName: CacheFile.calendars)
        localCacheStore.save(selectedCalendarId, fileName: CacheFile.selectedCalendarId)
        localCacheStore.save(events, fileName: CacheFile.events)
        localCacheStore.save(Array(protections), fileName: CacheFile.protections)
        localCacheStore.save(planTemplates, fileName: CacheFile.templates)
        localCacheStore.save(planTemplateBundles, fileName: CacheFile.templateBundles)
        localCacheStore.save(quickAddChips, fileName: CacheFile.quickAddChips)
        localCacheStore.save(syncStates, fileName: CacheFile.syncStates)
        localCacheStore.save(pendingOperations, fileName: CacheFile.syncQueue)
        localCacheStore.save(auditEntries, fileName: CacheFile.audit)
        localCacheStore.save(monthlyGoals, fileName: CacheFile.monthlyGoals)
    }
}

enum AppTab: String, CaseIterable {
    case overview = "Dashboard"
    case weekend = "Planner"
    case settings = "Settings"
}

struct WeekendStatus {
    let type: String
    let label: String
}

struct CalendarHelper {
    static let calendar = Calendar.current
    static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()

    static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()

    static func weekendKey(for date: Date) -> String? {
        let weekday = calendar.component(.weekday, from: date)
        var saturday = date
        if weekday == 7 {
            return formatKey(date)
        }
        if weekday == 1 {
            saturday = calendar.date(byAdding: .day, value: -1, to: date) ?? date
            return formatKey(saturday)
        }
        return nil
    }

    static func formatKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func parseKey(_ key: String) -> Date? {
        let normalizedInput = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedKey: String
        if let separator = normalizedInput.firstIndex(of: "T") {
            normalizedKey = String(normalizedInput[..<separator])
        } else {
            normalizedKey = normalizedInput
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: normalizedKey)
    }

    static func formatWeekendLabel(_ saturday: Date) -> String {
        let sunday = calendar.date(byAdding: .day, value: 1, to: saturday) ?? saturday
        if calendar.isDate(saturday, equalTo: sunday, toGranularity: .month) {
            return "\(monthFormatter.string(from: saturday)) \(dayFormatter.string(from: saturday))–\(dayFormatter.string(from: sunday))"
        }
        return "\(monthFormatter.string(from: saturday)) \(dayFormatter.string(from: saturday)) - \(monthFormatter.string(from: sunday)) \(dayFormatter.string(from: sunday))"
    }

    static func isWeekendInPast(_ saturday: Date, referenceDate: Date = Date()) -> Bool {
        let sunday = calendar.date(byAdding: .day, value: 1, to: saturday) ?? saturday
        let sundayStart = calendar.startOfDay(for: sunday)
        let todayStart = calendar.startOfDay(for: referenceDate)
        return sundayStart < todayStart
    }

    static func remainingWeekends(in weekends: [WeekendInfo], referenceDate: Date = Date()) -> [WeekendInfo] {
        weekends.filter { !isWeekendInPast($0.saturday, referenceDate: referenceDate) }
    }

    static func hasRemainingWeekends(_ month: MonthOption, referenceDate: Date = Date()) -> Bool {
        month.weekends.contains { !isWeekendInPast($0.saturday, referenceDate: referenceDate) }
    }

    static func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func currentPlanningYear(referenceDate: Date = Date()) -> Int {
        calendar.component(.year, from: referenceDate)
    }

    static func planningYears(referenceDate: Date = Date()) -> [Int] {
        let currentYear = currentPlanningYear(referenceDate: referenceDate)
        return Array(currentYear...(currentYear + 3))
    }

    static func planningDateRange(referenceDate: Date = Date()) -> ClosedRange<Date> {
        let currentYear = currentPlanningYear(referenceDate: referenceDate)
        let lowerBound = calendar.date(from: DateComponents(year: currentYear, month: 1, day: 1)) ?? referenceDate
        let upperYear = currentYear + 3
        let upperDate = calendar.date(from: DateComponents(year: upperYear, month: 12, day: 31)) ?? referenceDate
        let upperBound = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: upperDate) ?? upperDate
        return lowerBound...upperBound
    }

    static func getMonths(startingFrom date: Date = Date()) -> [MonthOption] {
        var months: [MonthOption] = []
        let years = planningYears(referenceDate: date)

        for year in years {
            for month in 1...12 {
                guard let monthDate = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { continue }
                let weekends = getWeekends(for: monthDate)
                let option = MonthOption(
                    key: formatKey(monthDate),
                    title: monthYearFormatter.string(from: monthDate),
                    shortLabel: monthFormatter.string(from: monthDate),
                    subtitle: String(calendar.component(.year, from: monthDate)),
                    year: calendar.component(.year, from: monthDate),
                    weekends: weekends
                )
                months.append(option)
            }
        }

        return months
    }

    static func getMonthOptions(startingFrom date: Date = Date()) -> [MonthOption] {
        let months = getMonths(startingFrom: date)
        guard !months.isEmpty else { return [] }

        let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let currentMonthKey = formatKey(currentMonth)
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
        let nextMonthKey = formatKey(nextMonth)
        let current = months.first(where: { $0.key == currentMonthKey }) ?? months.first
        let next = months.first(where: { $0.key == nextMonthKey })

        let historicalRangeStart = calendar.date(byAdding: .month, value: -12, to: date) ?? date
        let historicalSubtitle = "\(monthFormatter.string(from: historicalRangeStart)) \(calendar.component(.year, from: historicalRangeStart)) – \(monthFormatter.string(from: date)) \(calendar.component(.year, from: date))"

        let upcomingLabel: String
        if let current, let next {
            upcomingLabel = "\(monthFormatter.string(from: CalendarHelper.parseKey(current.key) ?? date)) \(current.subtitle) – \(monthFormatter.string(from: CalendarHelper.parseKey(next.key) ?? date)) \(next.subtitle)"
        } else if let current {
            upcomingLabel = "\(monthFormatter.string(from: CalendarHelper.parseKey(current.key) ?? date)) \(current.subtitle)"
        } else {
            upcomingLabel = ""
        }

        var upcomingWeekends: [WeekendInfo] = []
        if let current {
            upcomingWeekends.append(contentsOf: current.weekends)
        }
        if let next {
            upcomingWeekends.append(contentsOf: next.weekends)
        }

        var options: [MonthOption] = [
            MonthOption(
                key: "upcoming",
                title: "Upcoming weekends",
                shortLabel: "Upcoming",
                subtitle: upcomingLabel,
                year: nil,
                weekends: upcomingWeekends
            ),
            MonthOption(
                key: "historical",
                title: "Historical weekends",
                shortLabel: "Historical",
                subtitle: historicalSubtitle,
                year: nil,
                weekends: getPast12MonthWeekends(referenceDate: date)
            )
        ]

        options.append(contentsOf: months)
        return options
    }

    static func getPast12MonthWeekends(referenceDate: Date = Date()) -> [WeekendInfo] {
        guard let rangeStart = calendar.date(byAdding: .month, value: -12, to: referenceDate) else { return [] }
        let rangeStartMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: rangeStart)
        ) ?? rangeStart
        let referenceMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: referenceDate)
        ) ?? referenceDate

        var weekends: [WeekendInfo] = []
        for offset in 0...12 {
            guard let monthDate = calendar.date(byAdding: .month, value: offset, to: rangeStartMonth) else { continue }
            guard monthDate <= referenceMonth else { break }
            weekends.append(contentsOf: getWeekends(for: monthDate))
        }

        return weekends.filter {
            $0.saturday >= rangeStart &&
            isWeekendInPast($0.saturday, referenceDate: referenceDate)
        }
    }

    static func getWeekends(for monthDate: Date) -> [WeekendInfo] {
        var weekends: [WeekendInfo] = []
        guard let range = calendar.range(of: .day, in: .month, for: monthDate) else { return [] }
        let year = calendar.component(.year, from: monthDate)
        let month = calendar.component(.month, from: monthDate)

        for day in range {
            if let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
               calendar.component(.weekday, from: date) == 7 {
                let label = formatWeekendLabel(date)
                weekends.append(WeekendInfo(saturday: date, label: label))
            }
        }

        return weekends
    }

    static func monthSelectionKey(for weekendKey: String, referenceDate: Date = Date()) -> String {
        guard let saturday = parseKey(weekendKey) else { return "upcoming" }
        if isWeekendInPast(saturday, referenceDate: referenceDate) {
            return "historical"
        }
        let normalizedReference = calendar.date(
            from: calendar.dateComponents([.year, .month], from: referenceDate)
        ) ?? referenceDate
        let normalizedWeekend = calendar.date(
            from: calendar.dateComponents([.year, .month], from: saturday)
        ) ?? saturday
        let monthDelta = calendar.dateComponents([.month], from: normalizedReference, to: normalizedWeekend).month ?? 0
        if monthDelta == 0 || monthDelta == 1 {
            return "upcoming"
        }
        let planningYearSet = Set(planningYears(referenceDate: referenceDate))
        let weekendYear = calendar.component(.year, from: normalizedWeekend)
        guard planningYearSet.contains(weekendYear) else { return "upcoming" }
        return formatKey(normalizedWeekend)
    }

    static func nextWeekendKey(after weekendKey: String) -> String? {
        guard let saturday = parseKey(weekendKey),
              let nextSaturday = calendar.date(byAdding: .day, value: 7, to: saturday) else {
            return nil
        }
        return formatKey(nextSaturday)
    }

    static func nextUpcomingWeekendKey(referenceDate: Date = Date()) -> String? {
        var cursor = calendar.startOfDay(for: referenceDate)
        for _ in 0..<14 {
            let weekday = calendar.component(.weekday, from: cursor)
            if weekday == 7 {
                return formatKey(cursor)
            }
            if weekday == 1,
               let saturday = calendar.date(byAdding: .day, value: -1, to: cursor) {
                return formatKey(saturday)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return nil
    }

    static func intervals(for event: WeekendEvent) -> [DateInterval] {
        guard let saturday = parseKey(event.weekendKey) else { return [] }
        let days = event.dayValues.sorted { $0.rawValue < $1.rawValue }
        var intervals: [DateInterval] = []

        for day in days {
            guard let dayDate = dateForWeekendDay(day, saturday: saturday) else { continue }
            if event.isAllDay {
                let start = calendar.startOfDay(for: dayDate)
                guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
                intervals.append(DateInterval(start: start, end: end))
                continue
            }
            guard let startTime = timeComponents(from: event.startTime),
                  let endTime = timeComponents(from: event.endTime),
                  let start = calendar.date(
                    bySettingHour: startTime.hour,
                    minute: startTime.minute,
                    second: 0,
                    of: dayDate
                  ),
                  let end = calendar.date(
                    bySettingHour: endTime.hour,
                    minute: endTime.minute,
                    second: 0,
                    of: dayDate
                  ),
                  end > start else { continue }
            intervals.append(DateInterval(start: start, end: end))
        }

        return intervals.sorted { $0.start < $1.start }
    }

    static func intervals(
        weekendKey: String,
        days: Set<WeekendDay>,
        allDay: Bool,
        startTime: Date,
        endTime: Date
    ) -> [DateInterval] {
        guard let saturday = parseKey(weekendKey) else { return [] }
        let sortedDays = days.sorted { $0.rawValue < $1.rawValue }
        var intervals: [DateInterval] = []
        let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
        let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)

        for day in sortedDays {
            guard let dayDate = dateForWeekendDay(day, saturday: saturday) else { continue }
            if allDay {
                let start = calendar.startOfDay(for: dayDate)
                guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
                intervals.append(DateInterval(start: start, end: end))
                continue
            }

            guard let startHour = startComponents.hour,
                  let startMinute = startComponents.minute,
                  let endHour = endComponents.hour,
                  let endMinute = endComponents.minute,
                  let start = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: dayDate),
                  let end = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: dayDate),
                  end > start else { continue }
            intervals.append(DateInterval(start: start, end: end))
        }

        return intervals.sorted { $0.start < $1.start }
    }

    private static func dateForWeekendDay(_ day: WeekendDay, saturday: Date) -> Date? {
        switch day {
        case .sat:
            return saturday
        case .sun:
            return calendar.date(byAdding: .day, value: 1, to: saturday)
        }
    }

    private static func timeComponents(from value: String) -> (hour: Int, minute: Int)? {
        let parts = value.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else { return nil }
        return (hour, minute)
    }
}
