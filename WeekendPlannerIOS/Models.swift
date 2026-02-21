import Foundation
import Supabase
import UserNotifications
import EventKit
import SwiftUI
import os

enum PerformanceMetricKey: String, CaseIterable {
    case appBootstrap
    case foregroundActivation
    case localMutationCommit
    case addEvent
    case updateEvent
    case removeEvent
    case toggleProtection
    case flushPendingOperations
    case rescheduleNotifications
    case accountScreenOpen
}

struct PerformanceMetricSummary: Identifiable {
    let key: PerformanceMetricKey
    let count: Int
    let averageMs: Double
    let p95Ms: Double
    let maxMs: Double

    var id: String { key.rawValue }
}

struct PerformanceSnapshot {
    let generatedAt: Date
    let metrics: [PerformanceMetricSummary]

    static let empty = PerformanceSnapshot(generatedAt: Date(), metrics: [])
}

private struct PerformanceAggregate {
    private(set) var count: Int = 0
    private(set) var totalMs: Double = 0
    private(set) var maxMs: Double = 0
    private(set) var samples: [Double] = []
    private let sampleLimit = 256

    mutating func record(_ durationMs: Double) {
        count += 1
        totalMs += durationMs
        maxMs = max(maxMs, durationMs)
        samples.append(durationMs)
        if samples.count > sampleLimit {
            samples.removeFirst(samples.count - sampleLimit)
        }
    }

    var averageMs: Double {
        guard count > 0 else { return 0 }
        return totalMs / Double(count)
    }

    var p95Ms: Double {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        let index = min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))
        return sorted[index]
    }
}

final class PerformanceMonitor {
    static let shared = PerformanceMonitor()

    private let logger = Logger(subsystem: "WeekendPlannerIOS", category: "performance")
    private let signpostLog = OSLog(subsystem: "WeekendPlannerIOS", category: .pointsOfInterest)
    private let lock = NSLock()
    private var starts: [UUID: (metric: PerformanceMetricKey, startedAt: CFAbsoluteTime)] = [:]
    private var signpostIDs: [UUID: OSSignpostID] = [:]
    private var aggregates: [PerformanceMetricKey: PerformanceAggregate] = [:]

    func begin(_ metric: PerformanceMetricKey) -> UUID {
        let token = UUID()
        let signpostID = OSSignpostID(log: signpostLog)
        guard lock.try() else {
            return token
        }
        starts[token] = (metric, CFAbsoluteTimeGetCurrent())
        signpostIDs[token] = signpostID
        lock.unlock()
        os_signpost(
            .begin,
            log: signpostLog,
            name: "PerformanceInterval",
            signpostID: signpostID,
            "metric=%{public}s",
            metric.rawValue
        )
        return token
    }

    func end(_ token: UUID) {
        guard lock.try() else { return }
        guard let started = starts.removeValue(forKey: token) else {
            lock.unlock()
            return
        }
        let signpostID = signpostIDs.removeValue(forKey: token)
        lock.unlock()
        let elapsedMs = max(0, (CFAbsoluteTimeGetCurrent() - started.startedAt) * 1_000)
        if let signpostID {
            os_signpost(
                .end,
                log: signpostLog,
                name: "PerformanceInterval",
                signpostID: signpostID,
                "metric=%{public}s duration_ms=%{public}.2f",
                started.metric.rawValue,
                elapsedMs
            )
        }
        record(metric: started.metric, durationMs: elapsedMs)
    }

    func record(metric: PerformanceMetricKey, durationMs: Double) {
        guard lock.try() else { return }
        var aggregate = aggregates[metric] ?? PerformanceAggregate()
        aggregate.record(durationMs)
        aggregates[metric] = aggregate
        lock.unlock()
        #if DEBUG
        logger.debug("\(metric.rawValue, privacy: .public): \(durationMs, format: .fixed(precision: 2))ms")
        #endif
    }

    func snapshot() -> PerformanceSnapshot {
        guard lock.try() else {
            return .empty
        }
        let summaries = aggregates
            .map { key, aggregate in
                PerformanceMetricSummary(
                    key: key,
                    count: aggregate.count,
                    averageMs: aggregate.averageMs,
                    p95Ms: aggregate.p95Ms,
                    maxMs: aggregate.maxMs
                )
            }
            .sorted { $0.key.rawValue < $1.key.rawValue }
        lock.unlock()
        return PerformanceSnapshot(generatedAt: Date(), metrics: summaries)
    }
}

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

enum WeekendDay: String, Codable, CaseIterable, Hashable, Identifiable {
    case mon
    case tue
    case wed
    case thu
    case fri
    case sat
    case sun

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mon: return "Monday"
        case .tue: return "Tuesday"
        case .wed: return "Wednesday"
        case .thu: return "Thursday"
        case .fri: return "Friday"
        case .sat: return "Saturday"
        case .sun: return "Sunday"
        }
    }

    var shortLabel: String {
        switch self {
        case .mon: return "Mon"
        case .tue: return "Tue"
        case .wed: return "Wed"
        case .thu: return "Thu"
        case .fri: return "Fri"
        case .sat: return "Sat"
        case .sun: return "Sun"
        }
    }

    var calendarWeekday: Int {
        switch self {
        case .sun: return 1
        case .mon: return 2
        case .tue: return 3
        case .wed: return 4
        case .thu: return 5
        case .fri: return 6
        case .sat: return 7
        }
    }

    var naturalSortOrder: Int {
        switch self {
        case .mon: return 0
        case .tue: return 1
        case .wed: return 2
        case .thu: return 3
        case .fri: return 4
        case .sat: return 5
        case .sun: return 6
        }
    }

    // Weekend rows are anchored around Saturday, so Friday comes first.
    var plannerRowSortOrder: Int {
        switch self {
        case .fri: return 0
        case .sat: return 1
        case .sun: return 2
        case .mon: return 3
        case .tue: return 4
        case .wed: return 5
        case .thu: return 6
        }
    }

    var offsetFromSaturdayAnchor: Int {
        switch self {
        case .fri: return -1
        case .sat: return 0
        case .sun: return 1
        case .mon: return 2
        case .tue: return 3
        case .wed: return 4
        case .thu: return 5
        }
    }

    static func from(calendarWeekday: Int) -> WeekendDay? {
        switch calendarWeekday {
        case 1: return .sun
        case 2: return .mon
        case 3: return .tue
        case 4: return .wed
        case 5: return .thu
        case 6: return .fri
        case 7: return .sat
        default: return nil
        }
    }
}

enum PublicHolidayRegionPreference: String, Codable, CaseIterable, Identifiable {
    case automatic
    case none
    case us
    case uk

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return "Automatic (from region)"
        case .none: return "No public holidays"
        case .us: return "United States"
        case .uk: return "United Kingdom"
        }
    }
}

enum SupportedPublicHolidayRegion: String, Codable {
    case us
    case uk

    var label: String {
        switch self {
        case .us: return "US"
        case .uk: return "UK"
        }
    }
}

struct WeekendConfiguration: Codable, Equatable {
    var weekendDays: [WeekendDay]
    var includeFridayEvening: Bool
    var fridayEveningStartHour: Int
    var fridayEveningStartMinute: Int
    var includePublicHolidays: Bool
    var publicHolidayRegionPreference: PublicHolidayRegionPreference

    static let defaults = WeekendConfiguration(
        weekendDays: [.sat, .sun],
        includeFridayEvening: false,
        fridayEveningStartHour: 17,
        fridayEveningStartMinute: 0,
        includePublicHolidays: true,
        publicHolidayRegionPreference: .automatic
    )

    var normalizedWeekendDays: Set<WeekendDay> {
        var days = Set(weekendDays)
        if includeFridayEvening {
            days.insert(.fri)
        }
        return days
    }

    var fridayEveningStartLabel: String {
        let hour = min(max(fridayEveningStartHour, 0), 23)
        let minute = min(max(fridayEveningStartMinute, 0), 59)
        return String(format: "%02d:%02d", hour, minute)
    }

    mutating func normalize() {
        let uniqueDays = Set(weekendDays)
        let sorted = uniqueDays.sorted { $0.naturalSortOrder < $1.naturalSortOrder }
        weekendDays = sorted
        fridayEveningStartHour = min(max(fridayEveningStartHour, 0), 23)
        fridayEveningStartMinute = min(max(fridayEveningStartMinute, 0), 59)
        if weekendDays.isEmpty && !includeFridayEvening {
            weekendDays = [.sat, .sun]
        }
    }
}

struct AnnualLeaveDay: Identifiable, Codable, Hashable {
    let dateKey: String
    var note: String

    var id: String { dateKey }
}

struct PersonalReminder: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case reminder
        case birthday

        var id: String { rawValue }

        var label: String {
            switch self {
            case .reminder:
                return "Reminder"
            case .birthday:
                return "Birthday"
            }
        }

        var sortOrder: Int {
            switch self {
            case .birthday:
                return 0
            case .reminder:
                return 1
            }
        }
    }

    let id: String
    var title: String
    var kind: Kind
    var month: Int
    var day: Int
    var year: Int?
    var repeatsAnnually: Bool
    let createdAt: Date
}

struct PublicHolidayInfo: Codable, Hashable {
    let dateKey: String
    let name: String
    let region: SupportedPublicHolidayRegion
}

enum OffDayReason: Hashable {
    case weekend(day: WeekendDay)
    case fridayEveningStart(label: String)
    case publicHoliday(name: String, region: SupportedPublicHolidayRegion)
    case annualLeave(note: String)

    var label: String {
        switch self {
        case .weekend(let day):
            return "\(day.label) weekend day"
        case .fridayEveningStart(let label):
            return "Weekend starts at \(label)"
        case .publicHoliday(let name, let region):
            return "\(name) (\(region.label) public holiday)"
        case .annualLeave(let note):
            return note.isEmpty ? "Annual leave" : "Annual leave: \(note)"
        }
    }
}

struct OffDayOption: Identifiable, Hashable {
    let day: WeekendDay
    let date: Date
    let reasons: [OffDayReason]

    var id: String { day.rawValue }
}

enum ProtectionMode: String {
    case warn
    case block
}

enum AppTheme: String, CaseIterable {
    case system
    case light
    case dark

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AccountDeletionOwnershipMode: String, CaseIterable {
    case transfer
    case delete

    var label: String {
        switch self {
        case .transfer:
            return "Transfer owned shared calendars"
        case .delete:
            return "Delete owned shared calendars"
        }
    }
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
        self.startTime = Self.normalizedTimeString(startTime)
        self.endTime = Self.normalizedTimeString(endTime)
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
        startTime = Self.normalizedTimeString(try container.decode(String.self, forKey: .startTime))
        endTime = Self.normalizedTimeString(try container.decode(String.self, forKey: .endTime))
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

    private static func normalizedTimeString(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":")
        guard parts.count >= 2 else { return trimmed }

        let hour = max(0, min(23, Int(parts[0]) ?? 0))
        let minute = max(0, min(59, Int(parts[1]) ?? 0))
        return String(format: "%02d:%02d", hour, minute)
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
    var attributedCalendarIDs: [String]?
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
        attributedCalendarIDs: [String]? = nil,
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
        self.attributedCalendarIDs = attributedCalendarIDs
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
    var attributedCalendarIDs: [String]?
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
        attributedCalendarIDs: [String]? = nil,
        weekendKey: String,
        days: [String],
        startTime: String,
        endTime: String
    ) {
        self.title = title
        self.type = type
        self.calendarId = calendarId
        self.attributedCalendarIDs = attributedCalendarIDs
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
    var id: String { CalendarHelper.formatKey(saturday) }
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
    let id: String
    let name: String
    let ownerUserId: String
    let shareCode: String
    let maxMembers: Int

    enum CodingKeys: String, CodingKey {
        case id
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

struct UserNotice: Identifiable, Codable, Hashable {
    let id: String
    let userId: String
    let type: String
    let title: String
    let message: String
    let metadata: [String: String]
    let createdAt: Date
    var readAt: Date?

    var isUnread: Bool {
        readAt == nil
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case type
        case title
        case message
        case metadata
        case createdAt = "created_at"
        case readAt = "read_at"
    }

    init(
        id: String,
        userId: String,
        type: String,
        title: String,
        message: String,
        metadata: [String: String],
        createdAt: Date,
        readAt: Date?
    ) {
        self.id = id
        self.userId = userId
        self.type = type
        self.title = title
        self.message = message
        self.metadata = metadata
        self.createdAt = createdAt
        self.readAt = readAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        type = try container.decode(String.self, forKey: .type)
        title = try container.decode(String.self, forKey: .title)
        message = try container.decode(String.self, forKey: .message)
        metadata = (try? container.decode([String: String].self, forKey: .metadata)) ?? [:]
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        readAt = try container.decodeIfPresent(Date.self, forKey: .readAt)
    }
}

private struct DeleteAccountRPCParams: Encodable {
    let pOwnershipMode: String

    enum CodingKeys: String, CodingKey {
        case pOwnershipMode = "p_ownership_mode"
    }
}

struct DeleteAccountRPCResult: Decodable {
    let deletedUserId: String
    let transferredCalendarCount: Int
    let deletedCalendarCount: Int
    let noticesCreatedCount: Int

    enum CodingKeys: String, CodingKey {
        case deletedUserId = "deleted_user_id"
        case transferredCalendarCount = "transferred_calendar_count"
        case deletedCalendarCount = "deleted_calendar_count"
        case noticesCreatedCount = "notices_created_count"
    }
}

private struct MarkNoticeReadRPCParams: Encodable {
    let pNoticeId: String

    enum CodingKeys: String, CodingKey {
        case pNoticeId = "p_notice_id"
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

struct CountdownWindowContext {
    let windowStart: Date
    let windowEndExclusive: Date
    let workweekStart: Date
    let weekendStartLabel: String
}

struct EventCalendarAttribution: Codable, Hashable {
    let eventId: String
    let calendarId: String
    let userId: String?

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case calendarId = "calendar_id"
        case userId = "user_id"
    }
}

private struct NewEventCalendarAttribution: Encodable {
    let eventId: String
    let calendarId: String
    let userId: String

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case calendarId = "calendar_id"
        case userId = "user_id"
    }
}

struct ExternalCalendarSummary: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let sourceTitle: String
    let allowsWrites: Bool
    let colorHex: String
}

struct ExternalCalendarEvent: Identifiable, Codable, Hashable {
    let sourceCalendarID: String
    let sourceEventID: String
    let sourceCalendarTitle: String
    let sourceSourceTitle: String
    let title: String
    let startDate: Date
    let endDate: Date
    let allDay: Bool
    let lastModified: Date

    var id: String {
        "\(sourceCalendarID)|\(sourceEventID)"
    }
}

struct ImportedEventLink: Identifiable, Codable, Hashable {
    let weekendEventID: String
    let sourceCalendarID: String
    let sourceEventID: String
    var lastFingerprint: String
    var writable: Bool
    var isInformational: Bool

    enum CodingKeys: String, CodingKey {
        case weekendEventID
        case sourceCalendarID
        case sourceEventID
        case lastFingerprint
        case writable
        case isInformational
    }

    init(
        weekendEventID: String,
        sourceCalendarID: String,
        sourceEventID: String,
        lastFingerprint: String,
        writable: Bool,
        isInformational: Bool = false
    ) {
        self.weekendEventID = weekendEventID
        self.sourceCalendarID = sourceCalendarID
        self.sourceEventID = sourceEventID
        self.lastFingerprint = lastFingerprint
        self.writable = writable
        self.isInformational = isInformational
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weekendEventID = try container.decode(String.self, forKey: .weekendEventID)
        sourceCalendarID = try container.decode(String.self, forKey: .sourceCalendarID)
        sourceEventID = try container.decode(String.self, forKey: .sourceEventID)
        lastFingerprint = try container.decode(String.self, forKey: .lastFingerprint)
        writable = try container.decodeIfPresent(Bool.self, forKey: .writable) ?? false
        isInformational = try container.decodeIfPresent(Bool.self, forKey: .isInformational) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(weekendEventID, forKey: .weekendEventID)
        try container.encode(sourceCalendarID, forKey: .sourceCalendarID)
        try container.encode(sourceEventID, forKey: .sourceEventID)
        try container.encode(lastFingerprint, forKey: .lastFingerprint)
        try container.encode(writable, forKey: .writable)
        try container.encode(isInformational, forKey: .isInformational)
    }

    var id: String {
        "\(sourceCalendarID)|\(sourceEventID)"
    }
}

enum ImportConflictState: String, Codable {
    case none
    case pending
    case acknowledged
}

enum SyncTrigger: String, Codable {
    case initial
    case foreground
    case manual
    case eventStoreChange
}

struct CalendarImportSettings: Codable, Equatable {
    var isEnabled: Bool
    var selectedSourceCalendarIDs: [String]
    var lastSyncAt: Date?
    var syncWindowDaysPast: Int
    var syncWindowDaysFuture: Int

    static let defaults = CalendarImportSettings(
        isEnabled: false,
        selectedSourceCalendarIDs: [],
        lastSyncAt: nil,
        syncWindowDaysPast: 30,
        syncWindowDaysFuture: 120
    )
}

struct HolidayInfoPill: Identifiable, Hashable {
    enum Kind: Hashable {
        case publicHoliday
        case annualLeave
        case reminder
    }

    let id: String
    let label: String
    let kind: Kind
    let reminderEventID: String?
    let personalReminderID: String?
    let sourceEventKey: String?

    var isRemovableReminder: Bool {
        reminderEventID != nil || personalReminderID != nil
    }

    var isAnnualLeave: Bool {
        kind == .annualLeave
    }

    var isReminder: Bool {
        kind == .reminder
    }
}

struct SupplementalReminderLine: Identifiable, Hashable {
    let day: WeekendDay
    let date: Date
    let pills: [HolidayInfoPill]

    var id: String {
        "\(CalendarHelper.formatKey(date))-\(day.rawValue)"
    }
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
    @Published var events: [WeekendEvent] = [] {
        didSet {
            rebuildEventIndexes()
        }
    }
    @Published var protections: Set<String> = [] {
        didSet {
            rebuildStatusIndex()
        }
    }
    @Published var selectedTab: AppTab = .overview
    @Published var selectedMonthKey: String = "upcoming"
    @Published var isLoading = false
    @Published var authMessage: String?
    @Published var showAuthSplash = true
    @Published var showOnboarding = false
    @Published var showOnboardingChecklist = false
    @Published var appTheme: AppTheme = .system
    @Published var protectionMode: ProtectionMode = .warn
    @Published var weekendConfiguration: WeekendConfiguration = .defaults
    @Published var annualLeaveDays: [AnnualLeaveDay] = []
    @Published var personalReminders: [PersonalReminder] = []
    @Published var countdownTimeZoneIdentifier: String?
    @Published var calendars: [PlannerCalendar] = []
    @Published var selectedCalendarId: String?
    @Published var notificationPermissionState: NotificationPermissionState = .notDetermined
    @Published var notificationPreferences: NotificationPreferences = .defaults
    @Published var calendarPermissionState: CalendarPermissionState = .notDetermined
    @Published var availableExternalCalendars: [ExternalCalendarSummary] = [] {
        didSet {
            rebuildStatusIndex()
        }
    }
    @Published var calendarImportSettings: CalendarImportSettings = .defaults
    @Published var importedEventLinks: [ImportedEventLink] = [] {
        didSet {
            importedEventIDLookup = Set(importedEventLinks.map(\.weekendEventID))
            rebuildStatusIndex()
        }
    }
    @Published var importConflicts: [String: ImportConflictState] = [:] {
        didSet {
            rebuildPendingConflictIndex()
        }
    }
    @Published var planTemplates: [PlanTemplate] = []
    @Published var planTemplateBundles: [PlanTemplateBundle] = []
    @Published var quickAddChips: [QuickAddChip] = [] {
        didSet {
            rebuildTopQuickAddChipsCache()
        }
    }
    private var syncStates: [String: SyncState] = [:]
    private var pendingOperations: [PendingSyncOperation] = []
    private var auditEntries: [AuditEntry] = []
    @Published private(set) var pendingOperationCount = 0
    @Published private(set) var syncInProgress = false
    @Published private(set) var lastSyncErrorMessage: String?
    @Published var notices: [UserNotice] = []
    @Published var weekendNotes: [String: String] = [:]
    @Published var eventDescriptions: [String: String] = [:]
    @Published var eventCalendarAttributions: [String: [String]] = [:]
    @Published var pendingWeekendSelection: String?
    @Published var pendingAddPlanWeekendKey: String?
    @Published var pendingAddPlanBypassProtection = false
    @Published var pendingAddPlanInitialDate: Date?
    @Published var pendingSettingsPath: [SettingsDestination] = []
    private(set) var performanceSnapshot: PerformanceSnapshot = .empty

    private let supabase: SupabaseClient
    private let notificationService: NotificationService
    private let calendarService: CalendarService
    private let templateStore: PlanTemplateStore
    private let bundleStore: PlanTemplateBundleStore
    private let calendarExportStore: CalendarExportStore
    private let localCacheStore: LocalCacheStore
    private let persistenceCoordinator: PersistenceCoordinator
    private let syncEngine: SyncEngine
    private let auditService: AuditService
    private let reportService: ReportService
    private let performanceMonitor: PerformanceMonitor
    private var periodicSyncTask: Task<Void, Never>?
    private var eventStoreObservationTask: Task<Void, Never>?
    private var isReconcilingImportedEvents = false
    private var outboundEchoDebounceUntil: [String: Date] = [:]
    private var lastAutomaticImportReconcileAt: Date?
    private var importedEventIDLookup: Set<String> = []
    private var dismissedInformationalSourceKeys: Set<String> = []
    private var pendingEventOperationIDs: Set<String> = []
    private var hasRemoteEventAttributionsTable: Bool?
    private var eventsByWeekendKey: [String: [WeekendEvent]] = [:]
    private var statusByWeekendKey: [String: WeekendStatus] = [:]
    private var pendingConflictWeekendKeys: Set<String> = []
    private var annualLeaveLookup: [String: AnnualLeaveDay] = [:]
    private var publicHolidayLookupCache: [SupportedPublicHolidayRegion: [String: PublicHolidayInfo]] = [:]
    private var topQuickAddChipsCache: [QuickAddChip] = []
    private let informationalImportedSourceKeywords = [
        "holiday",
        "holidays",
        "birthday",
        "birthdays",
        "reminder",
        "reminders",
        "observance",
        "observances"
    ]
    private let informationalImportedTitleKeywords = [
        "goodfriday",
        "bankholiday",
        "mothersday",
        "motherday",
        "fathersday",
        "fatherday",
        "britishsummertime",
        "daylightsaving",
        "easter",
        "eastersunday",
        "eastermonday",
        "christmas",
        "boxingday",
        "newyears",
        "thanksgiving",
        "valentine",
        "halloween",
        "birthday"
    ]
    private var scheduledSyncFlushTask: Task<Void, Never>?
    private var scheduledNotificationRescheduleTask: Task<Void, Never>?
    private var scheduledCalendarExportTasks: [String: Task<Void, Never>] = [:]
    private var scheduledLinkedEventUpdateTasks: [String: Task<Void, Never>] = [:]
    private var lastNotificationRescheduleSignature: Int?
    private var lastPerformanceSnapshotRefreshAt: Date?
    private var lastForegroundHeavyRefreshAt: Date?
    private let bypassAuthSplashForUITests: Bool
    private let skipOnboardingForUITests: Bool
    private let forceOnboardingForUITests: Bool

    var unreadNoticeCount: Int {
        notices.filter(\.isUnread).count
    }

    var hasPendingOperations: Bool {
        pendingOperationCount > 0
    }

    var nextPendingSyncRetryLabel: String? {
        guard let nextAttemptAt = pendingOperations.map(\.nextAttemptAt).min() else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: nextAttemptAt, relativeTo: Date())
    }

    func recentAuditEntries(limit: Int = 12) -> [AuditEntry] {
        Array(auditEntries.prefix(max(limit, 0)))
    }

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
        static let notices = "notices_cache.json"
        static let weekendNotes = "weekend_notes_cache.json"
        static let eventDescriptions = "event_descriptions_cache.json"
        static let eventCalendarAttributions = "event_calendar_attributions_cache.json"
        static let importLinks = "import_links_cache.json"
        static let importSettings = "import_settings_cache.json"
        static let importConflicts = "import_conflicts_cache.json"
    }

    private enum SettingsStorageKey {
        static let weekendConfiguration = "weekend-config-v1"
        static let annualLeaveDays = "weekend-annual-leave-v1"
        static let personalReminders = "weekend-personal-reminders-v1"
        static let dismissedInformationalSourceKeysPrefix = "weekend-dismissed-informational-sources-v1"
        static let onboardingCompletedPrefix = "weekend-onboarding-completed-v1"
    }

    enum CacheScope: CaseIterable {
        case calendars
        case selectedCalendarId
        case events
        case protections
        case templates
        case templateBundles
        case quickAddChips
        case syncStates
        case syncQueue
        case audit
        case notices
        case weekendNotes
        case eventDescriptions
        case eventCalendarAttributions
        case importLinks
        case importSettings
        case importConflicts
    }

    init(
        notificationService: NotificationService = .shared,
        calendarService: CalendarService = .shared,
        templateStore: PlanTemplateStore = PlanTemplateStore(),
        bundleStore: PlanTemplateBundleStore = PlanTemplateBundleStore(),
        calendarExportStore: CalendarExportStore = CalendarExportStore(),
        localCacheStore: LocalCacheStore = .shared,
        persistenceCoordinator: PersistenceCoordinator = PersistenceCoordinator(),
        syncEngine: SyncEngine = SyncEngine(),
        auditService: AuditService = AuditService(),
        reportService: ReportService = ReportService(),
        performanceMonitor: PerformanceMonitor = .shared
    ) {
        let url = URL(string: "https://vvuxlpsekzohlwywahtq.supabase.co")!
        let key = "sb_publishable_oQir3Zr26EqEERQDzIztcg_TIwK2CBK"
        self.supabase = SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
        )
        self.notificationService = notificationService
        self.calendarService = calendarService
        self.templateStore = templateStore
        self.bundleStore = bundleStore
        self.calendarExportStore = calendarExportStore
        self.localCacheStore = localCacheStore
        self.persistenceCoordinator = persistenceCoordinator
        self.syncEngine = syncEngine
        self.auditService = auditService
        self.reportService = reportService
        self.performanceMonitor = performanceMonitor
        #if DEBUG
        let launchArguments = ProcessInfo.processInfo.arguments
        self.bypassAuthSplashForUITests = launchArguments.contains("--uitest-skip-auth-splash")
        self.forceOnboardingForUITests = launchArguments.contains("--uitest-show-onboarding")
        let explicitSkipOnboarding = launchArguments.contains("--uitest-skip-onboarding")
        self.skipOnboardingForUITests = !self.forceOnboardingForUITests && (explicitSkipOnboarding || self.bypassAuthSplashForUITests)
        #else
        self.bypassAuthSplashForUITests = false
        self.forceOnboardingForUITests = false
        self.skipOnboardingForUITests = false
        #endif
        self.appTheme = Self.loadAppTheme()
        self.weekendConfiguration = Self.loadWeekendConfiguration()
        self.weekendConfiguration.normalize()
        self.annualLeaveDays = Self.loadAnnualLeaveDays()
        self.personalReminders = Self.loadPersonalReminders()
        self.notificationPreferences = NotificationPreferences.load()
        self.calendars = localCacheStore.load([PlannerCalendar].self, fileName: CacheFile.calendars, fallback: [])
        self.selectedCalendarId = localCacheStore.load(String?.self, fileName: CacheFile.selectedCalendarId, fallback: nil)
        self.events = localCacheStore.load([WeekendEvent].self, fileName: CacheFile.events, fallback: [])
        self.protections = Set(localCacheStore.load([String].self, fileName: CacheFile.protections, fallback: []))
        self.calendarImportSettings = localCacheStore.load(
            CalendarImportSettings.self,
            fileName: CacheFile.importSettings,
            fallback: .defaults
        )
        self.importedEventLinks = localCacheStore.load([ImportedEventLink].self, fileName: CacheFile.importLinks, fallback: [])
        self.importedEventIDLookup = Set(self.importedEventLinks.map(\.weekendEventID))
        self.importConflicts = localCacheStore.load([String: ImportConflictState].self, fileName: CacheFile.importConflicts, fallback: [:])
        self.planTemplates = localCacheStore.load([PlanTemplate].self, fileName: CacheFile.templates, fallback: templateStore.load())
        self.planTemplateBundles = localCacheStore.load([PlanTemplateBundle].self, fileName: CacheFile.templateBundles, fallback: bundleStore.load())
        self.quickAddChips = localCacheStore.load([QuickAddChip].self, fileName: CacheFile.quickAddChips, fallback: [])
        self.syncStates = localCacheStore.load([String: SyncState].self, fileName: CacheFile.syncStates, fallback: [:])
        self.pendingOperations = localCacheStore.load([PendingSyncOperation].self, fileName: CacheFile.syncQueue, fallback: [])
        self.pendingEventOperationIDs = Set(
            self.pendingOperations.compactMap { operation in
                switch operation.type {
                case .upsertEvent, .deleteEvent:
                    return operation.entityId
                case .setProtection, .appendAudit, .unsupported:
                    return nil
                }
            }
        )
        self.notices = localCacheStore.load([UserNotice].self, fileName: CacheFile.notices, fallback: [])
        self.weekendNotes = localCacheStore.load([String: String].self, fileName: CacheFile.weekendNotes, fallback: [:])
        self.eventDescriptions = localCacheStore.load([String: String].self, fileName: CacheFile.eventDescriptions, fallback: [:])
        self.eventCalendarAttributions = localCacheStore.load(
            [String: [String]].self,
            fileName: CacheFile.eventCalendarAttributions,
            fallback: [:]
        )
        let cachedAudit = localCacheStore.load([AuditEntry].self, fileName: CacheFile.audit, fallback: [])
        self.auditEntries = auditService.trim(entries: cachedAudit)
        self.pendingOperationCount = self.pendingOperations.count
        rebuildEventIndexes()
        rebuildPendingConflictIndex()
        rebuildAnnualLeaveLookup()
        rebuildTopQuickAddChipsCache()
        performanceSnapshot = performanceMonitor.snapshot()
        if let raw = UserDefaults.standard.string(forKey: "weekend-protection-mode"),
           let mode = ProtectionMode(rawValue: raw) {
            self.protectionMode = mode
        }
        if let timeZoneIdentifier = UserDefaults.standard.string(forKey: "weekend-countdown-timezone-id"),
           TimeZone(identifier: timeZoneIdentifier) != nil {
            self.countdownTimeZoneIdentifier = timeZoneIdentifier
        } else {
            self.countdownTimeZoneIdentifier = nil
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
                await MainActor.run {
                    self.scheduleSyncFlush(reason: "periodic", immediate: true)
                }
            }
        }
        if bypassAuthSplashForUITests {
            showAuthSplash = false
            showOnboarding = forceOnboardingForUITests
            showOnboardingChecklist = false
        }
    }

    deinit {
        periodicSyncTask?.cancel()
        eventStoreObservationTask?.cancel()
        scheduledSyncFlushTask?.cancel()
        scheduledNotificationRescheduleTask?.cancel()
        for task in scheduledCalendarExportTasks.values {
            task.cancel()
        }
        for task in scheduledLinkedEventUpdateTasks.values {
            task.cancel()
        }
    }

    func handleAppDidBecomeActive() async {
        let token = performanceMonitor.begin(.foregroundActivation)
        defer {
            performanceMonitor.end(token)
            refreshPerformanceSnapshot()
        }

        await refreshNotificationPermissionState()
        await refreshCalendarPermissionState()
        await refreshNotices()

        let now = Date()
        let shouldRunHeavyWork: Bool
        if let lastForegroundHeavyRefreshAt {
            shouldRunHeavyWork = now.timeIntervalSince(lastForegroundHeavyRefreshAt) >= 90
        } else {
            shouldRunHeavyWork = true
        }

        if shouldRunHeavyWork {
            await refreshAvailableExternalCalendars()
            await reconcileImportedCalendarEvents(trigger: .foreground)
            lastForegroundHeavyRefreshAt = now
        }

        scheduleNotificationResync(reason: "foreground", immediate: true)
        scheduleSyncFlush(reason: "foreground", immediate: shouldRunHeavyWork)
    }

    func handleAppWillResignActive() {
        persistCaches(
            scopes: [
                .events,
                .eventDescriptions,
                .eventCalendarAttributions,
                .importLinks,
                .importConflicts,
                .syncQueue,
                .syncStates
            ],
            policy: .immediate
        )
        guard session != nil, !pendingOperations.isEmpty else { return }
        scheduleSyncFlush(reason: "background", immediate: true)
    }

    func bootstrap() async {
        let token = performanceMonitor.begin(.appBootstrap)
        defer {
            performanceMonitor.end(token)
            refreshPerformanceSnapshot()
        }

        if bypassAuthSplashForUITests {
            showAuthSplash = false
            showOnboarding = forceOnboardingForUITests
            showOnboardingChecklist = false
            await refreshNotificationPermissionState()
            await refreshCalendarPermissionState()
            await refreshAvailableExternalCalendars()
            await refreshNotices()
            scheduleNotificationResync(reason: "bootstrap-uitest", immediate: true)
            scheduleSyncFlush(reason: "bootstrap-uitest", immediate: true)
            return
        }
        do {
            self.session = try await supabase.auth.session
        } catch {
            self.session = nil
        }
        self.showAuthSplash = session == nil
        if session != nil {
            await loadAll()
            evaluateOnboardingPresentation()
        } else {
            showOnboarding = false
            showOnboardingChecklist = false
        }
        await refreshNotificationPermissionState()
        await refreshCalendarPermissionState()
        await refreshAvailableExternalCalendars()
        startEventStoreObservationIfNeeded()
        await runInitialCalendarImport()
        scheduleNotificationResync(reason: "bootstrap", immediate: true)
        scheduleSyncFlush(reason: "bootstrap", immediate: true)
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
            evaluateOnboardingPresentation()
            await refreshNotificationPermissionState()
            await refreshCalendarPermissionState()
            await refreshAvailableExternalCalendars()
            startEventStoreObservationIfNeeded()
            await runInitialCalendarImport()
            scheduleNotificationResync(reason: "signin", immediate: true)
            scheduleSyncFlush(reason: "signin", immediate: true)
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
        await resetToSignedOutState()
    }

    @discardableResult
    func deleteAccount(
        mode: AccountDeletionOwnershipMode,
        performRemoteDeletion: (@Sendable () async throws -> DeleteAccountRPCResult)? = nil
    ) async -> Bool {
        guard session != nil || performRemoteDeletion != nil else {
            authMessage = "No account is currently signed in."
            return false
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let result: DeleteAccountRPCResult
            if let performRemoteDeletion {
                result = try await performRemoteDeletion()
            } else {
                let params = DeleteAccountRPCParams(pOwnershipMode: mode.rawValue)
                result = try await supabase.rpc("delete_my_account", params: params).execute().value
            }

            await resetToSignedOutState()
            if result.deletedCalendarCount > 0 {
                authMessage = "Account deleted permanently. \(result.deletedCalendarCount) shared calendar(s) were removed and members were notified."
            } else {
                authMessage = "Account deleted permanently."
            }
            return true
        } catch {
            authMessage = "Could not delete account. \(error.localizedDescription)"
            return false
        }
    }

    func refreshNotices() async {
        guard session != nil else {
            notices = []
            persistCaches(scopes: [.notices])
            return
        }
        do {
            let fetched: [UserNotice] = try await supabase
                .from("user_notices")
                .select("id,user_id,type,title,message,metadata,created_at,read_at")
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value
            notices = fetched
            persistCaches(scopes: [.notices])
        } catch {
            // Keep the current notice snapshot if a refresh fails.
        }
    }

    func markNoticeRead(noticeId: String) async {
        guard let index = notices.firstIndex(where: { $0.id == noticeId }),
              notices[index].readAt == nil else { return }

        do {
            let params = MarkNoticeReadRPCParams(pNoticeId: noticeId)
            let _: Bool = try await supabase
                .rpc("mark_notice_read", params: params)
                .execute()
                .value
            notices[index].readAt = Date()
            persistCaches(scopes: [.notices])
        } catch {
            // Non-blocking; notices will refresh next time account settings opens.
        }
    }

    func markAllNoticesRead() async {
        let unreadIDs = notices
            .filter(\.isUnread)
            .map(\.id)
        guard !unreadIDs.isEmpty else { return }
        for noticeId in unreadIDs {
            await markNoticeRead(noticeId: noticeId)
        }
    }

    private func resetToSignedOutState() async {
        session = nil
        showAuthSplash = !bypassAuthSplashForUITests
        showOnboarding = false
        showOnboardingChecklist = false
        calendars = []
        selectedCalendarId = nil
        events = []
        protections = []
        planTemplates = templateStore.load()
        planTemplateBundles = []
        quickAddChips = []
        notices = []
        weekendNotes = [:]
        eventDescriptions = [:]
        eventCalendarAttributions = [:]
        availableExternalCalendars = []
        calendarImportSettings = .defaults
        importedEventLinks = []
        importConflicts = [:]
        pendingOperations = []
        syncStates = [:]
        auditEntries = []
        pendingEventOperationIDs = []
        pendingOperationCount = 0
        syncInProgress = false
        lastSyncErrorMessage = nil
        pendingWeekendSelection = nil
        pendingAddPlanWeekendKey = nil
        pendingAddPlanBypassProtection = false
        pendingAddPlanInitialDate = nil
        pendingSettingsPath = []
        lastAutomaticImportReconcileAt = nil
        lastForegroundHeavyRefreshAt = nil
        lastNotificationRescheduleSignature = nil
        lastPerformanceSnapshotRefreshAt = nil
        hasRemoteEventAttributionsTable = nil
        dismissedInformationalSourceKeys = []
        eventStoreObservationTask?.cancel()
        eventStoreObservationTask = nil
        scheduledSyncFlushTask?.cancel()
        scheduledNotificationRescheduleTask?.cancel()
        for task in scheduledCalendarExportTasks.values {
            task.cancel()
        }
        for task in scheduledLinkedEventUpdateTasks.values {
            task.cancel()
        }
        scheduledCalendarExportTasks = [:]
        scheduledLinkedEventUpdateTasks = [:]
        for scope in CacheScope.allCases {
            persistenceCoordinator.scheduleRemove(fileName: fileName(for: scope), policy: .immediate)
        }
        await refreshNotificationPermissionState()
        scheduleNotificationResync(reason: "signed-out", immediate: true)
        refreshPerformanceSnapshot()
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
        dismissedInformationalSourceKeys = loadDismissedInformationalSourceKeysForCurrentUser()
        await loadCalendars()
        await loadEvents()
        await loadProtections()
        await refreshNotices()
        scheduleSyncFlush(reason: "load-all", immediate: true)
        scheduleNotificationResync(reason: "load-all", immediate: true)
    }

    func switchCalendar(to calendarId: String) async {
        guard selectedCalendarId != calendarId else { return }
        selectedCalendarId = calendarId
        persistCaches(scopes: [.selectedCalendarId])
        await loadEvents()
        await loadProtections()
        await runInitialCalendarImport()
        scheduleNotificationResync(reason: "switch-calendar", immediate: true)
    }

    func createCalendar(name: String) async -> Bool {
        guard let session else { return false }
        let userId = normalizedUserId(for: session)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let calendarId = UUID().uuidString.lowercased()

        let payload = NewPlannerCalendar(
            id: calendarId,
            name: trimmed,
            ownerUserId: userId,
            shareCode: generateShareCode(),
            maxMembers: 5
        )

        do {
            _ = try await supabase
                .from("planner_calendars")
                .insert(payload)
                .execute()
            let membership = NewCalendarMembership(
                calendarId: calendarId,
                userId: userId,
                role: "owner"
            )
            _ = try await supabase
                .from("calendar_members")
                .insert(membership)
                .execute()
            await loadCalendars()
            if calendars.contains(where: { $0.id == calendarId }) {
                await switchCalendar(to: calendarId)
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
                persistCaches(scopes: [.calendars, .selectedCalendarId])
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
            persistCaches(scopes: [.calendars, .selectedCalendarId])
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
        let calendarId = UUID().uuidString.lowercased()
        let payload = NewPlannerCalendar(
            id: calendarId,
            name: "Personal",
            ownerUserId: userId,
            shareCode: generateShareCode(),
            maxMembers: 5
        )
        _ = try await supabase
            .from("planner_calendars")
            .insert(payload)
            .execute()
        let membership = NewCalendarMembership(
            calendarId: calendarId,
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
            pruneEventDescriptionsToActiveEvents()
            persistCaches(scopes: [.events, .eventDescriptions, .importLinks, .importConflicts])
            return
        }
        do {
            let primaryResponse: [WeekendEvent] = try await supabase
                .from("weekend_events")
                .select()
                .eq("calendar_id", value: selectedCalendarId)
                .order("weekend_key", ascending: true)
                .execute()
                .value

            let attributedEventIDs = await attributedEventIDs(for: selectedCalendarId)
            let primaryEventIDs = Set(primaryResponse.map(\.id))
            let attributedOnlyIDs = attributedEventIDs.filter { !primaryEventIDs.contains($0) }

            var attributedResponse: [WeekendEvent] = []
            if !attributedOnlyIDs.isEmpty {
                attributedResponse = try await supabase
                    .from("weekend_events")
                    .select()
                    .`in`("id", values: Array(attributedOnlyIDs))
                    .order("weekend_key", ascending: true)
                    .execute()
                    .value
            }

            var deduplicated: [String: WeekendEvent] = [:]
            for event in primaryResponse + attributedResponse {
                deduplicated[event.id] = event
            }

            let normalized = deduplicated.values.map { event in
                let localIdentifiers = calendarExportStore.identifiers(for: event.id)
                return event.withCalendarEventIdentifier(localIdentifiers.first ?? event.calendarEventIdentifier)
            }.filter { !$0.isSyncDeleted }
            let merged = mergedEventsForSelectedCalendar(
                remoteEvents: normalized,
                selectedCalendarId: selectedCalendarId,
                pendingOperations: pendingOperations
            )
            self.events = merged
            pruneEventDescriptionsToActiveEvents()
            pruneImportedMetadataToActiveEvents()
            calendarExportStore.pruneMappings(validEventIDs: Set(merged.map(\.id)))
            persistCaches(scopes: [.events, .eventDescriptions, .importLinks, .importConflicts])
        } catch {
            authMessage = error.localizedDescription
        }
    }

    func mergedEventsForSelectedCalendar(
        remoteEvents: [WeekendEvent],
        selectedCalendarId: String,
        pendingOperations: [PendingSyncOperation]
    ) -> [WeekendEvent] {
        var mergedByID = Dictionary(uniqueKeysWithValues: remoteEvents.map { ($0.id, $0) })

        for operation in pendingOperations {
            switch operation.type {
            case .upsertEvent:
                guard let event = operation.event else { continue }
                let targetCalendarID = event.calendarId ?? operation.calendarId
                if targetCalendarID == selectedCalendarId {
                    mergedByID[event.id] = event
                } else {
                    mergedByID.removeValue(forKey: operation.entityId)
                }
            case .deleteEvent:
                mergedByID.removeValue(forKey: operation.entityId)
            case .setProtection, .appendAudit, .unsupported:
                continue
            }
        }

        let merged = mergedByID.values.filter { !$0.isSyncDeleted }
        return sortedEvents(merged)
    }

    func loadProtections() async {
        guard session != nil else { return }
        guard let selectedCalendarId else {
            protections = []
            persistCaches(scopes: [.protections])
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
            persistCaches(scopes: [.protections])
        } catch {
            authMessage = error.localizedDescription
        }
    }

    func addEvent(
        _ draft: NewWeekendEvent,
        exportToCalendar: Bool = false,
        attributedCalendarIDs: Set<String>? = nil
    ) async -> Bool {
        let token = performanceMonitor.begin(.addEvent)
        defer {
            performanceMonitor.end(token)
            refreshPerformanceSnapshot()
        }
        guard let session else { return false }
        guard let selectedCalendarId else {
            authMessage = "Please select a calendar first."
            return false
        }
        let userId = normalizedUserId(for: session)
        let normalizedCalendarIDs = normalizedAttributionCalendarIDs(
            from: attributedCalendarIDs ?? Set(draft.attributedCalendarIDs ?? []),
            fallbackPrimary: draft.calendarId ?? selectedCalendarId
        )
        let primaryCalendarID = preferredPrimaryCalendarID(
            from: normalizedCalendarIDs,
            preferred: draft.calendarId ?? selectedCalendarId
        ) ?? selectedCalendarId
        let now = Date()
        let newEvent = WeekendEvent(
            id: draft.id ?? UUID().uuidString,
            title: draft.title,
            type: draft.type,
            calendarId: primaryCalendarID,
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

        let commitToken = performanceMonitor.begin(.localMutationCommit)
        events = sortedEvents(events + [newEvent])
        setLocalEventCalendarAttributions(eventId: newEvent.id, calendarIDs: Set(normalizedCalendarIDs))
        scheduleRemoteEventCalendarAttributionSync(
            eventId: newEvent.id,
            calendarIDs: Set(normalizedCalendarIDs),
            userId: userId
        )
        registerQuickAddUsage(from: newEvent)
        if exportToCalendar {
            scheduleCalendarExportSync(for: newEvent, enabled: true)
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
        persistCaches(scopes: [.events, .eventCalendarAttributions, .syncQueue, .syncStates], policy: .immediate)
        persistCaches(scopes: [.quickAddChips])
        performanceMonitor.end(commitToken)
        scheduleNotificationResync(reason: "event-add")
        scheduleSyncFlush(reason: "event-add")
        return true
    }

    func updateEvent(
        eventId: String,
        _ update: UpdateWeekendEvent,
        exportToCalendar: Bool,
        attributedCalendarIDs: Set<String>? = nil
    ) async -> Bool {
        let token = performanceMonitor.begin(.updateEvent)
        defer {
            performanceMonitor.end(token)
            refreshPerformanceSnapshot()
        }
        guard let index = events.firstIndex(where: { $0.id == eventId }) else { return false }
        guard let selectedCalendarId else {
            authMessage = "Please select a calendar first."
            return false
        }
        var updatedEvent = events[index]
        let currentAttributions = Set(eventCalendarIDs(for: eventId))
        let requestedAttributions = attributedCalendarIDs ?? Set(update.attributedCalendarIDs ?? [])
        let normalizedCalendarIDs = normalizedAttributionCalendarIDs(
            from: requestedAttributions.isEmpty ? currentAttributions : requestedAttributions,
            fallbackPrimary: update.calendarId ?? updatedEvent.calendarId ?? selectedCalendarId
        )
        let primaryCalendarID = preferredPrimaryCalendarID(
            from: normalizedCalendarIDs,
            preferred: update.calendarId ?? updatedEvent.calendarId ?? selectedCalendarId
        ) ?? selectedCalendarId
        let now = Date()
        let commitToken = performanceMonitor.begin(.localMutationCommit)
        updatedEvent.title = update.title
        updatedEvent.type = update.type
        updatedEvent.calendarId = primaryCalendarID
        updatedEvent.weekendKey = update.weekendKey
        updatedEvent.days = update.days.sorted()
        updatedEvent.startTime = update.startTime
        updatedEvent.endTime = update.endTime
        updatedEvent.clientUpdatedAt = now
        updatedEvent.updatedAt = now
        events[index] = updatedEvent
        setLocalEventCalendarAttributions(eventId: updatedEvent.id, calendarIDs: Set(normalizedCalendarIDs))
        if let session {
            scheduleRemoteEventCalendarAttributionSync(
                eventId: updatedEvent.id,
                calendarIDs: Set(normalizedCalendarIDs),
                userId: normalizedUserId(for: session)
            )
        }

        if !normalizedCalendarIDs.contains(selectedCalendarId) {
            events.removeAll { $0.id == updatedEvent.id }
        }
        events = sortedEvents(events)

        if exportToCalendar {
            scheduleCalendarExportSync(for: updatedEvent, enabled: true)
        } else {
            removeCalendarExports(forEventID: eventId)
        }
        if importedEventLinks.contains(where: { $0.weekendEventID == updatedEvent.id }) {
            scheduleLinkedEventUpdate(for: updatedEvent)
            updateConflictState(for: updatedEvent.id)
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
        persistCaches(
            scopes: [.events, .eventCalendarAttributions, .importLinks, .importConflicts, .syncQueue, .syncStates],
            policy: .immediate
        )
        performanceMonitor.end(commitToken)
        scheduleNotificationResync(reason: "event-update")
        scheduleSyncFlush(reason: "event-update")
        return true
    }

    func duplicateEvent(eventId: String, toWeekendKey: String, days: [WeekendDay]? = nil) async -> Bool {
        guard let event = events.first(where: { $0.id == eventId }),
              let session = session else { return false }
        let sourceDescription = eventDescriptions[event.id]
        let daySelection = (days?.isEmpty == false ? days : event.dayValues) ?? event.dayValues
        let duplicateDays = daySelection.sorted { $0.plannerRowSortOrder < $1.plannerRowSortOrder }
        let duplicateEventId = UUID().uuidString
        let payload = NewWeekendEvent(
            id: duplicateEventId,
            title: event.title,
            type: event.type,
            calendarId: event.calendarId ?? selectedCalendarId,
            attributedCalendarIDs: eventCalendarIDs(for: event.id),
            weekendKey: toWeekendKey,
            days: duplicateDays.map(\.rawValue),
            startTime: event.startTime,
            endTime: event.endTime,
            userId: normalizedUserId(for: session)
        )
        let added = await addEvent(
            payload,
            exportToCalendar: isEventExportedToCalendar(eventId: event.id),
            attributedCalendarIDs: Set(eventCalendarIDs(for: event.id))
        )
        if added, let sourceDescription {
            setEventDescription(for: duplicateEventId, description: sourceDescription)
        }
        return added
    }

    func removeEvent(_ event: WeekendEvent) async {
        let token = performanceMonitor.begin(.removeEvent)
        defer {
            performanceMonitor.end(token)
            refreshPerformanceSnapshot()
        }
        guard events.contains(where: { $0.id == event.id }) else { return }
        if let linkIndex = importedEventLinks.firstIndex(where: { $0.weekendEventID == event.id }) {
            let link = importedEventLinks[linkIndex]
            if link.writable {
                do {
                    try calendarService.deleteExternalEvent(link: link)
                    outboundEchoDebounceUntil[sourceKey(calendarID: link.sourceCalendarID, eventID: link.sourceEventID)] = Date().addingTimeInterval(8)
                    importedEventLinks.remove(at: linkIndex)
                } catch {
                    authMessage = "Couldn't update source calendar. \(error.localizedDescription)"
                }
            } else {
                authMessage = "Source calendar is read-only. This removal is local only."
            }
        }
        events.removeAll { $0.id == event.id }
        eventDescriptions.removeValue(forKey: event.id)
        eventCalendarAttributions.removeValue(forKey: event.id)
        scheduleRemoteEventCalendarAttributionRemoval(eventId: event.id)
        importConflicts.removeValue(forKey: event.id)
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
        persistCaches(
            scopes: [.events, .eventDescriptions, .eventCalendarAttributions, .importLinks, .importConflicts, .syncQueue, .syncStates],
            policy: .immediate
        )
        scheduleNotificationResync(reason: "event-remove")
        scheduleSyncFlush(reason: "event-remove")
    }

    func toggleProtection(weekendKey: String, removePlans: Bool) async {
        let token = performanceMonitor.begin(.toggleProtection)
        defer {
            performanceMonitor.end(token)
            refreshPerformanceSnapshot()
        }
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
            persistCaches(scopes: [.protections, .events, .syncQueue, .syncStates], policy: .immediate)
            persistCaches(scopes: [.audit])
            scheduleNotificationResync(reason: "protection-remove")
            scheduleSyncFlush(reason: "protection-remove")
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
        persistCaches(scopes: [.protections, .events, .syncQueue, .syncStates], policy: .immediate)
        persistCaches(scopes: [.audit])
        scheduleNotificationResync(reason: "protection-add")
        scheduleSyncFlush(reason: "protection-add")
    }

    private func normalizedUserId(for session: Session) -> String {
        session.user.id.uuidString.lowercased()
    }

    private func onboardingCompletedStorageKey(userId: String) -> String {
        let trimmed = userId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let effective = trimmed.isEmpty ? "anonymous" : trimmed
        return "\(SettingsStorageKey.onboardingCompletedPrefix)-\(effective)"
    }

    func isProtected(_ weekendKey: String) -> Bool {
        protections.contains(weekendKey)
    }

    func events(for weekendKey: String) -> [WeekendEvent] {
        eventsByWeekendKey[weekendKey] ?? []
    }

    func eventCalendarIDs(for eventId: String) -> [String] {
        if let attributed = eventCalendarAttributions[eventId], !attributed.isEmpty {
            return attributed
        }
        if let event = events.first(where: { $0.id == eventId }),
           let calendarId = event.calendarId {
            return [calendarId]
        }
        if let selectedCalendarId {
            return [selectedCalendarId]
        }
        return []
    }

    func weekendNote(for weekendKey: String) -> String {
        weekendNotes[weekendNoteStorageKey(for: weekendKey)] ?? ""
    }

    func hasWeekendNote(weekendKey: String) -> Bool {
        !weekendNote(for: weekendKey).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func setWeekendNote(weekendKey: String, note: String) {
        let key = weekendNoteStorageKey(for: weekendKey)
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            weekendNotes.removeValue(forKey: key)
        } else {
            weekendNotes[key] = trimmed
        }
        persistCaches(scopes: [.weekendNotes])
    }

    func eventDescription(for eventId: String) -> String {
        eventDescriptions[eventId] ?? ""
    }

    func setEventDescription(for eventId: String, description: String) {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            eventDescriptions.removeValue(forKey: eventId)
        } else {
            eventDescriptions[eventId] = trimmed
        }
        persistCaches(scopes: [.eventDescriptions])
    }

    func status(for weekendKey: String) -> WeekendStatus {
        if let cached = statusByWeekendKey[weekendKey] {
            return cached
        }
        if protections.contains(weekendKey) {
            return WeekendStatus(type: "protected", label: "Protected")
        }
        return WeekendStatus(type: "free", label: "Free")
    }

    func setTheme(_ theme: AppTheme) {
        appTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: "weekend-theme")
        switch theme {
        case .system:
            UserDefaults.standard.removeObject(forKey: "weekend-theme-dark")
        case .light:
            UserDefaults.standard.set(false, forKey: "weekend-theme-dark")
        case .dark:
            UserDefaults.standard.set(true, forKey: "weekend-theme-dark")
        }
    }

    func setProtectionMode(_ mode: ProtectionMode) {
        protectionMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "weekend-protection-mode")
    }

    var activeWeekendDays: [WeekendDay] {
        weekendConfiguration
            .normalizedWeekendDays
            .sorted { $0.naturalSortOrder < $1.naturalSortOrder }
    }

    var resolvedPublicHolidayRegion: SupportedPublicHolidayRegion? {
        switch weekendConfiguration.publicHolidayRegionPreference {
        case .none:
            return nil
        case .us:
            return .us
        case .uk:
            return .uk
        case .automatic:
            return inferredPublicHolidayRegionFromLocale()
        }
    }

    var publicHolidayRegionDisplayLabel: String {
        guard let region = resolvedPublicHolidayRegion else { return "None" }
        switch weekendConfiguration.publicHolidayRegionPreference {
        case .automatic:
            return "\(region.label) (Auto)"
        case .none:
            return "None"
        case .us, .uk:
            return region.label
        }
    }

    var offDaysSummaryLabel: String {
        let daySummary = activeWeekendDays.map(\.shortLabel).joined(separator: ", ")
        var parts: [String] = []
        if !daySummary.isEmpty {
            parts.append(daySummary)
        }
        if weekendConfiguration.includePublicHolidays {
            parts.append("Public holidays: \(publicHolidayRegionDisplayLabel)")
        }
        if !annualLeaveDays.isEmpty {
            parts.append("\(annualLeaveDays.count) annual leave")
        }
        if parts.isEmpty {
            return "No life schedule configured"
        }
        return parts.joined(separator: " • ")
    }

    func setWeekendDayEnabled(_ day: WeekendDay, isOn: Bool) {
        var updated = weekendConfiguration
        var selected = Set(updated.weekendDays)
        if isOn {
            selected.insert(day)
        } else {
            selected.remove(day)
        }

        if selected.isEmpty && !updated.includeFridayEvening {
            selected.insert(.sat)
            selected.insert(.sun)
        }

        updated.weekendDays = selected.sorted { $0.naturalSortOrder < $1.naturalSortOrder }
        weekendConfiguration = updated
        persistWeekendConfiguration()
        scheduleNotificationResync(reason: "weekend-config")
    }

    func setFridayEveningEnabled(_ enabled: Bool) {
        var updated = weekendConfiguration
        updated.includeFridayEvening = enabled
        if !enabled && updated.weekendDays.isEmpty {
            updated.weekendDays = [.sat, .sun]
        }
        weekendConfiguration = updated
        persistWeekendConfiguration()
        scheduleNotificationResync(reason: "weekend-config")
    }

    func setFridayEveningStartTime(_ date: Date) {
        let components = CalendarHelper.calendar.dateComponents([.hour, .minute], from: date)
        var updated = weekendConfiguration
        updated.fridayEveningStartHour = components.hour ?? 17
        updated.fridayEveningStartMinute = components.minute ?? 0
        weekendConfiguration = updated
        persistWeekendConfiguration()
        scheduleNotificationResync(reason: "weekend-config")
    }

    func setIncludePublicHolidays(_ enabled: Bool) {
        weekendConfiguration.includePublicHolidays = enabled
        persistWeekendConfiguration()
    }

    func setPublicHolidayRegionPreference(_ preference: PublicHolidayRegionPreference) {
        weekendConfiguration.publicHolidayRegionPreference = preference
        persistWeekendConfiguration()
    }

    func addAnnualLeaveDay(_ date: Date, note: String) {
        let normalizedDate = CalendarHelper.calendar.startOfDay(for: date)
        let dateKey = CalendarHelper.formatKey(normalizedDate)
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existingIndex = annualLeaveDays.firstIndex(where: { $0.dateKey == dateKey }) {
            annualLeaveDays[existingIndex].note = trimmed
        } else {
            annualLeaveDays.append(AnnualLeaveDay(dateKey: dateKey, note: trimmed))
        }
        persistAnnualLeaveDays()
    }

    func addAnnualLeaveRange(from startDate: Date, to endDate: Date, note: String) {
        let calendar = CalendarHelper.calendar
        let normalizedStart = calendar.startOfDay(for: min(startDate, endDate))
        let normalizedEnd = calendar.startOfDay(for: max(startDate, endDate))
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)

        var leaveByDateKey = Dictionary(uniqueKeysWithValues: annualLeaveDays.map { ($0.dateKey, $0) })
        var cursor = normalizedStart
        while cursor <= normalizedEnd {
            let dateKey = CalendarHelper.formatKey(cursor)
            if var existing = leaveByDateKey[dateKey] {
                existing.note = trimmed
                leaveByDateKey[dateKey] = existing
            } else {
                leaveByDateKey[dateKey] = AnnualLeaveDay(dateKey: dateKey, note: trimmed)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        annualLeaveDays = leaveByDateKey.values.sorted { $0.dateKey < $1.dateKey }
        persistAnnualLeaveDays()
    }

    func removeAnnualLeaveDay(_ dateKey: String) {
        annualLeaveDays.removeAll { $0.dateKey == dateKey }
        persistAnnualLeaveDays()
    }

    func addPersonalReminder(
        title: String,
        kind: PersonalReminder.Kind,
        date: Date,
        repeatsAnnually: Bool
    ) {
        let calendar = CalendarHelper.calendar
        let normalizedDate = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.year, .month, .day], from: normalizedDate)
        guard let month = components.month, let day = components.day else { return }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle = kind == .birthday ? "Birthday" : "Reminder"
        let normalizedTitle = trimmed.isEmpty ? fallbackTitle : trimmed
        let normalizedRepeating = kind == .birthday ? true : repeatsAnnually
        let reminder = PersonalReminder(
            id: UUID().uuidString.lowercased(),
            title: normalizedTitle,
            kind: kind,
            month: month,
            day: day,
            year: normalizedRepeating ? nil : components.year,
            repeatsAnnually: normalizedRepeating,
            createdAt: Date()
        )
        personalReminders.append(reminder)
        persistPersonalReminders()
    }

    func removePersonalReminder(_ reminderID: String) {
        personalReminders.removeAll { $0.id == reminderID }
        persistPersonalReminders()
    }

    private struct AnnualLeaveAssociationEntry {
        let date: Date
        let note: String
    }

    private var annualLeaveAssociationsByWeekendKey: [String: [WeekendDay: [AnnualLeaveAssociationEntry]]] {
        let calendar = CalendarHelper.calendar
        let sortedLeaves = annualLeaveDays
            .compactMap { leave -> AnnualLeaveAssociationEntry? in
                guard let date = CalendarHelper.parseKey(leave.dateKey) else { return nil }
                return AnnualLeaveAssociationEntry(
                    date: calendar.startOfDay(for: date),
                    note: leave.note
                )
            }
            .sorted { $0.date < $1.date }

        guard !sortedLeaves.isEmpty else { return [:] }

        var blocks: [[AnnualLeaveAssociationEntry]] = []
        var currentBlock: [AnnualLeaveAssociationEntry] = []

        for leave in sortedLeaves {
            if let previous = currentBlock.last {
                let delta = calendar.dateComponents([.day], from: previous.date, to: leave.date).day ?? 0
                if delta == 1 {
                    currentBlock.append(leave)
                } else {
                    blocks.append(currentBlock)
                    currentBlock = [leave]
                }
            } else {
                currentBlock = [leave]
            }
        }

        if !currentBlock.isEmpty {
            blocks.append(currentBlock)
        }

        var associations: [String: [WeekendDay: [AnnualLeaveAssociationEntry]]] = [:]
        for block in blocks {
            let dates = block.map(\.date)
            let weekendKey = associatedWeekendKey(forAnnualLeaveBlock: dates)
            for leave in block {
                guard let weekday = WeekendDay.from(
                    calendarWeekday: calendar.component(.weekday, from: leave.date)
                ) else { continue }
                associations[weekendKey, default: [:]][weekday, default: []].append(leave)
            }
        }

        for weekendKey in associations.keys {
            guard let days = associations[weekendKey]?.keys else { continue }
            for day in days {
                associations[weekendKey]?[day]?.sort { $0.date < $1.date }
            }
        }

        return associations
    }

    private var annualLeaveDateToAssociatedWeekendKey: [String: String] {
        var mapping: [String: String] = [:]
        for (weekendKey, days) in annualLeaveAssociationsByWeekendKey {
            for entries in days.values {
                for entry in entries {
                    mapping[CalendarHelper.formatKey(entry.date)] = weekendKey
                }
            }
        }
        return mapping
    }

    private func associatedWeekendKey(forAnnualLeaveBlock dates: [Date]) -> String {
        guard let first = dates.min() else {
            return CalendarHelper.nextUpcomingWeekendKey() ?? CalendarHelper.formatKey(Date())
        }

        let calendar = CalendarHelper.calendar
        let previousSaturday = saturdayOnOrBefore(first)
        let previousWeekendKey = CalendarHelper.formatKey(previousSaturday)
        let nextSaturday = calendar.date(byAdding: .day, value: 7, to: previousSaturday) ?? previousSaturday
        let nextWeekendKey = CalendarHelper.formatKey(nextSaturday)

        let adjacentToPrevious = blockIsAdjacentToWeekend(dates, weekendKey: previousWeekendKey)
        let adjacentToNext = blockIsAdjacentToWeekend(dates, weekendKey: nextWeekendKey)

        if adjacentToPrevious && !adjacentToNext {
            return previousWeekendKey
        }
        return nextWeekendKey
    }

    private func blockIsAdjacentToWeekend(_ dates: [Date], weekendKey: String) -> Bool {
        let calendar = CalendarHelper.calendar
        let weekendDays = weekendConfiguration.normalizedWeekendDays
        guard !weekendDays.isEmpty else { return false }

        for weekendDay in weekendDays {
            guard let weekendDate = CalendarHelper.dateForPlannerDay(weekendDay, weekendKey: weekendKey) else {
                continue
            }
            let normalizedWeekendDate = calendar.startOfDay(for: weekendDate)
            for date in dates {
                let delta = abs(calendar.dateComponents(
                    [.day],
                    from: normalizedWeekendDate,
                    to: calendar.startOfDay(for: date)
                ).day ?? .max)
                if delta <= 1 {
                    return true
                }
            }
        }
        return false
    }

    private func saturdayOnOrBefore(_ date: Date) -> Date {
        let calendar = CalendarHelper.calendar
        let normalized = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: normalized)
        let daysBack = weekday % 7
        return calendar.date(byAdding: .day, value: -daysBack, to: normalized) ?? normalized
    }

    func offDayReasons(for date: Date) -> [OffDayReason] {
        let normalized = CalendarHelper.calendar.startOfDay(for: date)
        let dateKey = CalendarHelper.formatKey(normalized)
        guard let weekday = WeekendDay.from(calendarWeekday: CalendarHelper.calendar.component(.weekday, from: normalized)) else {
            return []
        }

        var reasons: [OffDayReason] = []
        if weekendConfiguration.normalizedWeekendDays.contains(weekday) {
            reasons.append(.weekend(day: weekday))
            if weekday == .fri && weekendConfiguration.includeFridayEvening {
                reasons.append(.fridayEveningStart(label: weekendConfiguration.fridayEveningStartLabel))
            }
        }

        if weekendConfiguration.includePublicHolidays,
           let holiday = publicHolidayLookup()[dateKey] {
            reasons.append(.publicHoliday(name: holiday.name, region: holiday.region))
        }

        if let leave = annualLeaveLookup[dateKey] {
            reasons.append(.annualLeave(note: leave.note))
        }

        return reasons
    }

    func isOffDay(_ date: Date) -> Bool {
        !offDayReasons(for: date).isEmpty
    }

    func availableDisplayOffDayOptions(for weekendKey: String) -> [OffDayOption] {
        let calendar = CalendarHelper.calendar
        return WeekendDay.allCases
            .compactMap { day -> OffDayOption? in
                let reasons = displayOffDayReasons(for: weekendKey, day: day)
                guard !reasons.isEmpty else { return nil }
                guard let dayDate = plannerDisplayDate(for: weekendKey, day: day)
                    ?? CalendarHelper.dateForPlannerDay(day, weekendKey: weekendKey) else {
                    return nil
                }
                return OffDayOption(day: day, date: calendar.startOfDay(for: dayDate), reasons: reasons)
            }
            .sorted { lhs, rhs in
                let left = calendar.startOfDay(for: lhs.date)
                let right = calendar.startOfDay(for: rhs.date)
                if left == right {
                    return lhs.day.plannerRowSortOrder < rhs.day.plannerRowSortOrder
                }
                return left < right
            }
    }

    func visiblePlannerDays(for weekendKey: String, events: [WeekendEvent]) -> [WeekendDay] {
        let offDays = Set(
            WeekendDay.allCases.filter { !displayOffDayReasons(for: weekendKey, day: $0).isEmpty }
        )
        let eventDays = Set(events.flatMap(\.dayValues))
        return offDays.union(eventDays).sorted { lhs, rhs in
            let lhsDate = plannerDisplayDate(for: weekendKey, day: lhs)
            let rhsDate = plannerDisplayDate(for: weekendKey, day: rhs)
            switch (lhsDate, rhsDate) {
            case let (left?, right?) where left != right:
                return left < right
            default:
                return lhs.plannerRowSortOrder < rhs.plannerRowSortOrder
            }
        }
    }

    func plannerDisplayEvents(for weekendKey: String, day: WeekendDay, events: [WeekendEvent]) -> [WeekendEvent] {
        events
            .filter { $0.dayValues.contains(day) }
            .filter { !isInformationalImportedEvent($0) }
            .sorted { $0.startTime < $1.startTime }
    }

    func holidayInfoPills(for weekendKey: String, day: WeekendDay, events: [WeekendEvent]) -> [HolidayInfoPill] {
        var pills: [HolidayInfoPill] = []

        for reason in offDayReasons(for: weekendKey, day: day) {
            switch reason {
            case .publicHoliday(let name, _):
                pills.append(
                    HolidayInfoPill(
                        id: "public-holiday-\(name)",
                        label: name,
                        kind: .publicHoliday,
                        reminderEventID: nil,
                        personalReminderID: nil,
                        sourceEventKey: nil
                    )
                )
            case .annualLeave(let note):
                let label = note.isEmpty ? "Annual leave" : note
                pills.append(
                    HolidayInfoPill(
                        id: "annual-leave-\(label)",
                        label: label,
                        kind: .annualLeave,
                        reminderEventID: nil,
                        personalReminderID: nil,
                        sourceEventKey: nil
                    )
                )
            default:
                break
            }
        }

        if let dayDate = plannerDisplayDate(for: weekendKey, day: day)
            ?? CalendarHelper.dateForPlannerDay(day, weekendKey: weekendKey) {
            let personalReminderPills = personalReminders(on: dayDate).map { reminder in
                HolidayInfoPill(
                    id: "personal-reminder-\(reminder.id)",
                    label: personalReminderPillLabel(for: reminder),
                    kind: .reminder,
                    reminderEventID: nil,
                    personalReminderID: reminder.id,
                    sourceEventKey: nil
                )
            }
            pills.append(contentsOf: personalReminderPills)
        }

        let informationalImported = events
            .filter { $0.dayValues.contains(day) }
            .filter { isInformationalImportedEvent($0) }
            .map { event in
                HolidayInfoPill(
                    id: "imported-info-\(event.id)",
                    label: event.title,
                    kind: .reminder,
                    reminderEventID: event.id,
                    personalReminderID: nil,
                    sourceEventKey: sourceKeyForImportedEvent(eventID: event.id)
                )
            }
        pills.append(contentsOf: informationalImported)

        return deduplicatedInfoPills(pills)
    }

    func supplementalReminderLines(for weekendKey: String, events: [WeekendEvent]) -> [SupplementalReminderLine] {
        let calendar = CalendarHelper.calendar
        let primaryDays = Set(visiblePlannerDays(for: weekendKey, events: events))

        return WeekendDay.allCases
            .compactMap { day -> SupplementalReminderLine? in
                guard !primaryDays.contains(day) else { return nil }
                guard let dayDate = plannerDisplayDate(for: weekendKey, day: day)
                    ?? CalendarHelper.dateForPlannerDay(day, weekendKey: weekendKey) else {
                    return nil
                }
                let reminderPills = holidayInfoPills(for: weekendKey, day: day, events: events)
                    .filter(\.isReminder)
                guard !reminderPills.isEmpty else { return nil }
                return SupplementalReminderLine(
                    day: day,
                    date: calendar.startOfDay(for: dayDate),
                    pills: reminderPills
                )
            }
            .sorted { lhs, rhs in
                let leftDate = calendar.startOfDay(for: lhs.date)
                let rightDate = calendar.startOfDay(for: rhs.date)
                if leftDate == rightDate {
                    return lhs.day.plannerRowSortOrder < rhs.day.plannerRowSortOrder
                }
                return leftDate < rightDate
            }
    }

    func dismissHolidayInfoPill(_ pill: HolidayInfoPill) {
        if let personalReminderID = pill.personalReminderID {
            removePersonalReminder(personalReminderID)
            return
        }

        guard let reminderEventID = pill.reminderEventID else { return }
        guard let eventIndex = events.firstIndex(where: { $0.id == reminderEventID }) else {
            if let sourceEventKey = pill.sourceEventKey {
                dismissedInformationalSourceKeys.insert(sourceEventKey)
                persistDismissedInformationalSourceKeys()
            }
            return
        }

        let event = events[eventIndex]
        guard isInformationalImportedEvent(event) else { return }

        if let linkIndex = importedEventLinks.firstIndex(where: { $0.weekendEventID == event.id }) {
            let link = importedEventLinks[linkIndex]
            dismissedInformationalSourceKeys.insert(sourceKey(calendarID: link.sourceCalendarID, eventID: link.sourceEventID))
            importedEventLinks.remove(at: linkIndex)
        } else if let sourceEventKey = pill.sourceEventKey {
            dismissedInformationalSourceKeys.insert(sourceEventKey)
        }
        persistDismissedInformationalSourceKeys()

        events.remove(at: eventIndex)
        eventDescriptions.removeValue(forKey: event.id)
        eventCalendarAttributions.removeValue(forKey: event.id)
        scheduleRemoteEventCalendarAttributionRemoval(eventId: event.id)
        importConflicts.removeValue(forKey: event.id)
        removeCalendarExports(forEventID: event.id)

        enqueueOperation(
            PendingSyncOperation(
                type: .deleteEvent,
                entityId: event.id,
                calendarId: event.calendarId ?? selectedCalendarId
            )
        )
        persistCaches(
            scopes: [.events, .eventDescriptions, .eventCalendarAttributions, .importLinks, .importConflicts, .syncQueue, .syncStates],
            policy: .immediate
        )
        scheduleNotificationResync(reason: "dismiss-reminder-pill")
        scheduleSyncFlush(reason: "dismiss-reminder-pill")
    }

    func preferredOffDayDate(for weekendKey: String) -> Date? {
        let options = availableDisplayOffDayOptions(for: weekendKey)
        if let first = options.first {
            return first.date
        }
        return CalendarHelper.parseKey(weekendKey)
    }

    func nextFutureHolidayDate(referenceDate: Date = Date()) -> Date? {
        let calendar = CalendarHelper.calendar
        let planningRange = CalendarHelper.planningDateRange(referenceDate: referenceDate)
        var cursor = max(
            calendar.startOfDay(for: referenceDate),
            calendar.startOfDay(for: planningRange.lowerBound)
        )
        let upperBound = calendar.startOfDay(for: planningRange.upperBound)

        while cursor <= upperBound {
            if isOffDay(cursor) {
                return cursor
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return nil
    }

    func countdownWindowContext(referenceDate: Date = Date(), timeZone: TimeZone) -> CountdownWindowContext? {
        guard let seedOffDay = nextFutureHolidayDate(referenceDate: referenceDate) else {
            return nil
        }
        let weekendKey = plannerDisplayWeekKey(for: seedOffDay)
        guard let span = holidayDateSpan(for: weekendKey) else {
            return nil
        }

        var countdownCalendar = Calendar(identifier: .gregorian)
        countdownCalendar.timeZone = timeZone

        let sourceCalendar = CalendarHelper.calendar
        let startDay = sourceCalendar.startOfDay(for: span.lowerBound)
        let endDay = sourceCalendar.startOfDay(for: span.upperBound)
        let rebasedStartDay = rebasedStartOfDay(startDay, calendar: countdownCalendar)
        let rebasedEndDay = rebasedStartOfDay(endDay, calendar: countdownCalendar)
        guard let windowEndExclusive = countdownCalendar.date(byAdding: .day, value: 1, to: rebasedEndDay) else {
            return nil
        }

        let startWeekday = WeekendDay.from(
            calendarWeekday: sourceCalendar.component(.weekday, from: startDay)
        ) ?? .sat
        let weekendStart = countdownWindowStart(
            rebasedStartDay: rebasedStartDay,
            startDayInSourceCalendar: startDay,
            startWeekday: startWeekday,
            countdownCalendar: countdownCalendar
        )

        let weekday = countdownCalendar.component(.weekday, from: rebasedStartDay)
        let daysSinceMonday = (weekday + 5) % 7
        let workweekStart = countdownCalendar.date(
            byAdding: .day,
            value: -daysSinceMonday,
            to: rebasedStartDay
        ) ?? rebasedStartDay

        return CountdownWindowContext(
            windowStart: weekendStart,
            windowEndExclusive: windowEndExclusive,
            workweekStart: workweekStart,
            weekendStartLabel: startWeekday.shortLabel
        )
    }

    func holidayRangeLabel(for weekendKey: String) -> String {
        guard let span = holidayDateSpan(for: weekendKey) else {
            if let saturday = CalendarHelper.parseKey(weekendKey) {
                return CalendarHelper.formatWeekendLabel(saturday)
            }
            return weekendKey
        }
        return formattedHolidayRangeLabel(start: span.lowerBound, end: span.upperBound)
    }

    func holidayDateSpan(for weekendKey: String) -> ClosedRange<Date>? {
        let calendar = CalendarHelper.calendar
        let dates = displayOffDayDates(for: weekendKey)
        guard !dates.isEmpty else { return nil }

        var blocks: [[Date]] = []
        var currentBlock: [Date] = []

        for date in dates {
            if let last = currentBlock.last {
                let delta = calendar.dateComponents([.day], from: last, to: date).day ?? 0
                if delta == 1 {
                    currentBlock.append(date)
                } else {
                    blocks.append(currentBlock)
                    currentBlock = [date]
                }
            } else {
                currentBlock = [date]
            }
        }

        if !currentBlock.isEmpty {
            blocks.append(currentBlock)
        }

        guard !blocks.isEmpty else { return nil }
        let anchor = CalendarHelper.parseKey(weekendKey).map { calendar.startOfDay(for: $0) } ?? dates[0]

        let selectedBlock = blocks.min { lhs, rhs in
            distanceFromAnchor(anchor, to: lhs) < distanceFromAnchor(anchor, to: rhs)
        } ?? blocks[0]

        guard let start = selectedBlock.first, let end = selectedBlock.last else { return nil }
        return start...end
    }

    func offDayReasons(for weekendKey: String, day: WeekendDay) -> [OffDayReason] {
        displayOffDayReasons(for: weekendKey, day: day)
    }

    func plannerDisplayDate(for weekendKey: String, day: WeekendDay) -> Date? {
        displaySortDate(for: weekendKey, day: day)
    }

    func plannerDisplayWeekKey(for date: Date) -> String {
        let normalizedKey = CalendarHelper.formatKey(CalendarHelper.calendar.startOfDay(for: date))
        if let associatedWeekendKey = annualLeaveDateToAssociatedWeekendKey[normalizedKey] {
            return associatedWeekendKey
        }
        return CalendarHelper.plannerWeekKey(for: date)
    }

    func plannerDisplayDay(for date: Date, weekendKey: String) -> WeekendDay? {
        let normalizedKey = CalendarHelper.formatKey(CalendarHelper.calendar.startOfDay(for: date))
        let associated = annualLeaveAssociationsByWeekendKey[weekendKey] ?? [:]

        for (day, entries) in associated {
            if entries.contains(where: {
                CalendarHelper.formatKey(CalendarHelper.calendar.startOfDay(for: $0.date)) == normalizedKey
            }) {
                return day
            }
        }

        return CalendarHelper.plannerDay(for: date, weekendKey: weekendKey)
    }

    func intervals(for event: WeekendEvent) -> [DateInterval] {
        let calendar = CalendarHelper.calendar
        let sortedDays = event.dayValues.sorted { lhs, rhs in
            let left = plannerDisplayDate(for: event.weekendKey, day: lhs)
                ?? CalendarHelper.dateForPlannerDay(lhs, weekendKey: event.weekendKey)
            let right = plannerDisplayDate(for: event.weekendKey, day: rhs)
                ?? CalendarHelper.dateForPlannerDay(rhs, weekendKey: event.weekendKey)
            switch (left, right) {
            case let (l?, r?) where l != r:
                return l < r
            default:
                return lhs.plannerRowSortOrder < rhs.plannerRowSortOrder
            }
        }

        var intervals: [DateInterval] = []
        for day in sortedDays {
            guard let dayDate = plannerDisplayDate(for: event.weekendKey, day: day)
                ?? CalendarHelper.dateForPlannerDay(day, weekendKey: event.weekendKey) else {
                continue
            }

            if event.isAllDay {
                let start = calendar.startOfDay(for: dayDate)
                guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
                intervals.append(DateInterval(start: start, end: end))
                continue
            }

            guard let startTime = eventTimeComponents(from: event.startTime),
                  let endTime = eventTimeComponents(from: event.endTime),
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

    func isWeekendInPast(_ weekendKey: String, referenceDate: Date = Date()) -> Bool {
        let calendar = CalendarHelper.calendar
        guard let effectiveEnd = effectiveWeekendEndDate(for: weekendKey) else { return true }
        let effectiveEndStart = calendar.startOfDay(for: effectiveEnd)
        let todayStart = calendar.startOfDay(for: referenceDate)
        return effectiveEndStart < todayStart
    }

    func monthSelectionKey(for weekendKey: String, referenceDate: Date = Date()) -> String {
        guard let saturday = CalendarHelper.parseKey(weekendKey) else { return "upcoming" }
        if isWeekendInPast(weekendKey, referenceDate: referenceDate) {
            return "historical"
        }
        let calendar = CalendarHelper.calendar
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
        let planningYearSet = Set(CalendarHelper.planningYears(referenceDate: referenceDate))
        let weekendYear = calendar.component(.year, from: normalizedWeekend)
        guard planningYearSet.contains(weekendYear) else { return "upcoming" }
        return CalendarHelper.formatKey(normalizedWeekend)
    }

    private func effectiveWeekendEndDate(for weekendKey: String) -> Date? {
        let calendar = CalendarHelper.calendar
        guard let saturday = CalendarHelper.parseKey(weekendKey) else { return nil }
        let sunday = calendar.date(byAdding: .day, value: 1, to: saturday) ?? saturday
        let associatedDates = displayOffDayDates(for: weekendKey)
        if let latest = associatedDates.max() {
            return max(calendar.startOfDay(for: sunday), latest)
        }
        return calendar.startOfDay(for: sunday)
    }

    private func displayOffDayDates(for weekendKey: String) -> [Date] {
        let calendar = CalendarHelper.calendar
        var dateKeys: Set<String> = []

        for day in WeekendDay.allCases {
            guard let dayDate = CalendarHelper.dateForPlannerDay(day, weekendKey: weekendKey) else { continue }
            let nonAnnualLeaveReasons = offDayReasons(for: dayDate).filter {
                if case .annualLeave = $0 {
                    return false
                }
                return true
            }
            if !nonAnnualLeaveReasons.isEmpty {
                dateKeys.insert(CalendarHelper.formatKey(calendar.startOfDay(for: dayDate)))
            }
        }

        let associatedLeave = annualLeaveAssociationsByWeekendKey[weekendKey] ?? [:]
        for entries in associatedLeave.values {
            for leave in entries {
                dateKeys.insert(CalendarHelper.formatKey(calendar.startOfDay(for: leave.date)))
            }
        }

        return dateKeys
            .compactMap(CalendarHelper.parseKey)
            .map { calendar.startOfDay(for: $0) }
            .sorted()
    }

    private func displayOffDayReasons(for weekendKey: String, day: WeekendDay) -> [OffDayReason] {
        var reasons: [OffDayReason] = []
        if let date = CalendarHelper.dateForPlannerDay(day, weekendKey: weekendKey) {
            let nonAnnualLeave = offDayReasons(for: date).filter {
                if case .annualLeave = $0 {
                    return false
                }
                return true
            }
            reasons.append(contentsOf: nonAnnualLeave)
        }

        let associatedAnnualLeave = annualLeaveAssociationsByWeekendKey[weekendKey]?[day] ?? []
        reasons.append(contentsOf: associatedAnnualLeave.map { .annualLeave(note: $0.note) })

        return deduplicatedOffDayReasons(reasons)
    }

    private func personalReminderPillLabel(for reminder: PersonalReminder) -> String {
        let trimmedTitle = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
        switch reminder.kind {
        case .birthday:
            if trimmedTitle.isEmpty {
                return "Birthday"
            }
            let lowercased = trimmedTitle.lowercased()
            if lowercased.contains("birthday") {
                return trimmedTitle
            }
            return "Birthday: \(trimmedTitle)"
        case .reminder:
            return trimmedTitle.isEmpty ? "Reminder" : trimmedTitle
        }
    }

    private func personalReminders(on date: Date) -> [PersonalReminder] {
        let calendar = CalendarHelper.calendar
        let normalized = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.year, .month, .day], from: normalized)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return []
        }

        return personalReminders
            .filter { reminder in
                guard reminder.month == month, reminder.day == day else { return false }
                if reminder.repeatsAnnually {
                    return true
                }
                return reminder.year == year
            }
            .sorted { lhs, rhs in
                if lhs.kind.sortOrder != rhs.kind.sortOrder {
                    return lhs.kind.sortOrder < rhs.kind.sortOrder
                }
                let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                if titleOrder != .orderedSame {
                    return titleOrder == .orderedAscending
                }
                return lhs.id < rhs.id
            }
    }

    private func rebasedStartOfDay(_ sourceDate: Date, calendar: Calendar) -> Date {
        let sourceCalendar = CalendarHelper.calendar
        let components = sourceCalendar.dateComponents(
            [.year, .month, .day],
            from: sourceCalendar.startOfDay(for: sourceDate)
        )
        var rebased = DateComponents()
        rebased.calendar = calendar
        rebased.timeZone = calendar.timeZone
        rebased.year = components.year
        rebased.month = components.month
        rebased.day = components.day
        return calendar.date(from: rebased) ?? sourceCalendar.startOfDay(for: sourceDate)
    }

    private func countdownWindowStart(
        rebasedStartDay: Date,
        startDayInSourceCalendar: Date,
        startWeekday: WeekendDay,
        countdownCalendar: Calendar
    ) -> Date {
        guard startWeekday == .fri,
              weekendConfiguration.includeFridayEvening,
              !weekendConfiguration.weekendDays.contains(.fri),
              !hasFullDayFridayReason(on: startDayInSourceCalendar) else {
            return rebasedStartDay
        }

        return countdownCalendar.date(
            bySettingHour: weekendConfiguration.fridayEveningStartHour,
            minute: weekendConfiguration.fridayEveningStartMinute,
            second: 0,
            of: rebasedStartDay
        ) ?? rebasedStartDay
    }

    private func hasFullDayFridayReason(on date: Date) -> Bool {
        offDayReasons(for: date).contains { reason in
            switch reason {
            case .annualLeave, .publicHoliday:
                return true
            default:
                return false
            }
        }
    }

    private func displaySortDate(for weekendKey: String, day: WeekendDay) -> Date? {
        let calendar = CalendarHelper.calendar
        var candidates: [Date] = []

        if let canonical = CalendarHelper.dateForPlannerDay(day, weekendKey: weekendKey) {
            candidates.append(calendar.startOfDay(for: canonical))
        }

        let associatedAnnualLeave = annualLeaveAssociationsByWeekendKey[weekendKey]?[day] ?? []
        candidates.append(contentsOf: associatedAnnualLeave.map { calendar.startOfDay(for: $0.date) })

        return candidates.min()
    }

    private func eventTimeComponents(from value: String) -> (hour: Int, minute: Int)? {
        let parts = value.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return nil
        }
        return (hour, minute)
    }

    private func deduplicatedOffDayReasons(_ reasons: [OffDayReason]) -> [OffDayReason] {
        var seen: Set<OffDayReason> = []
        var ordered: [OffDayReason] = []
        for reason in reasons {
            if seen.insert(reason).inserted {
                ordered.append(reason)
            }
        }
        return ordered
    }

    private func distanceFromAnchor(_ anchor: Date, to block: [Date]) -> Int {
        guard let start = block.first, let end = block.last else { return .max }
        let calendar = CalendarHelper.calendar
        if anchor < start {
            return calendar.dateComponents([.day], from: anchor, to: start).day ?? .max
        }
        if anchor > end {
            return calendar.dateComponents([.day], from: end, to: anchor).day ?? .max
        }
        return 0
    }

    private func formattedHolidayRangeLabel(start: Date, end: Date) -> String {
        let calendar = CalendarHelper.calendar
        if calendar.isDate(start, inSameDayAs: end) {
            return "\(CalendarHelper.monthFormatter.string(from: start)) \(CalendarHelper.dayFormatter.string(from: start))"
        }
        if calendar.isDate(start, equalTo: end, toGranularity: .month) {
            return "\(CalendarHelper.monthFormatter.string(from: start)) \(CalendarHelper.dayFormatter.string(from: start))–\(CalendarHelper.dayFormatter.string(from: end))"
        }
        return "\(CalendarHelper.monthFormatter.string(from: start)) \(CalendarHelper.dayFormatter.string(from: start)) - \(CalendarHelper.monthFormatter.string(from: end)) \(CalendarHelper.dayFormatter.string(from: end))"
    }

    var countdownTimeZone: TimeZone {
        if let identifier = countdownTimeZoneIdentifier,
           let timeZone = TimeZone(identifier: identifier) {
            return timeZone
        }
        return .autoupdatingCurrent
    }

    var countdownTimeZoneDisplayName: String {
        if let identifier = countdownTimeZoneIdentifier,
           let timeZone = TimeZone(identifier: identifier) {
            return "\(localizedTimeZoneName(timeZone)) • \(gmtOffsetLabel(for: timeZone))"
        }
        let systemTimeZone = TimeZone.autoupdatingCurrent
        return "System (\(localizedTimeZoneName(systemTimeZone)))"
    }

    func setCountdownTimeZoneIdentifier(_ identifier: String?) {
        let trimmed = identifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            countdownTimeZoneIdentifier = nil
            UserDefaults.standard.removeObject(forKey: "weekend-countdown-timezone-id")
            return
        }
        guard TimeZone(identifier: trimmed) != nil else { return }
        countdownTimeZoneIdentifier = trimmed
        UserDefaults.standard.set(trimmed, forKey: "weekend-countdown-timezone-id")
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
            days: draft.days.sorted { $0.plannerRowSortOrder < $1.plannerRowSortOrder }.map(\.rawValue),
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
        persistCaches(scopes: [.templates])
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

    func starterFromLastWeekend(referenceDate: Date) -> WeekendEvent? {
        let referenceWeekendKey = CalendarHelper.plannerWeekKey(for: referenceDate)
        var bestMatch: WeekendEvent?
        for event in events {
            guard event.weekendKey < referenceWeekendKey else { continue }
            guard let currentBest = bestMatch else {
                bestMatch = event
                continue
            }
            if event.weekendKey > currentBest.weekendKey {
                bestMatch = event
            } else if event.weekendKey == currentBest.weekendKey, event.startTime < currentBest.startTime {
                bestMatch = event
            }
        }
        return bestMatch
    }

    func starterFromSameMonthLastYear(referenceDate: Date) -> WeekendEvent? {
        let referenceWeekendKey = CalendarHelper.plannerWeekKey(for: referenceDate)
        guard let referenceSaturday = CalendarHelper.parseKey(referenceWeekendKey),
              let targetDate = CalendarHelper.calendar.date(byAdding: .year, value: -1, to: referenceSaturday) else {
            return nil
        }
        let targetYear = CalendarHelper.calendar.component(.year, from: targetDate)
        let targetMonth = CalendarHelper.calendar.component(.month, from: targetDate)
        let targetPrefix = String(format: "%04d-%02d-", targetYear, targetMonth)
        var bestMatch: WeekendEvent?
        for event in events {
            guard event.weekendKey.hasPrefix(targetPrefix) else { continue }
            guard let currentBest = bestMatch else {
                bestMatch = event
                continue
            }
            if event.weekendKey > currentBest.weekendKey {
                bestMatch = event
            } else if event.weekendKey == currentBest.weekendKey, event.startTime < currentBest.startTime {
                bestMatch = event
            }
        }
        return bestMatch
    }

    func topQuickAddChips(limit: Int = 4) -> [QuickAddChip] {
        Array(topQuickAddChipsCache.prefix(limit))
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
        let requiredDays = weekendConfiguration.normalizedWeekendDays.isEmpty
            ? Set([WeekendDay.sat, WeekendDay.sun])
            : weekendConfiguration.normalizedWeekendDays
        if requiredDays.isSubset(of: coveredDays) {
            return .ready
        }
        return .partiallyPlanned
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
                calendarId: event.calendarId,
                attributedCalendarIDs: eventCalendarIDs(for: event.id),
                weekendKey: toWeekendKey,
                days: event.days,
                startTime: event.startTime,
                endTime: event.endTime,
                userId: userId
            )
            if await addEvent(
                payload,
                exportToCalendar: isEventExportedToCalendar(eventId: event.id),
                attributedCalendarIDs: Set(eventCalendarIDs(for: event.id))
            ) {
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
        if calendarPermissionState.canReadEvents {
            await refreshAvailableExternalCalendars()
        } else {
            availableExternalCalendars = []
        }
        startEventStoreObservationIfNeeded()
    }

    func requestCalendarPermissionIfNeeded() async {
        if calendarPermissionState == .notDetermined {
            calendarPermissionState = await calendarService.requestAccess()
        } else {
            await refreshCalendarPermissionState()
        }
        if calendarPermissionState.canReadEvents {
            await refreshAvailableExternalCalendars()
            startEventStoreObservationIfNeeded()
            await runInitialCalendarImport()
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

    func refreshAvailableExternalCalendars() async {
        guard calendarPermissionState.canReadEvents else {
            availableExternalCalendars = []
            return
        }
        let calendars = calendarService.listAvailableCalendars()
        availableExternalCalendars = calendars
        let availableIDs = Set(calendars.map(\.id))
        let selected = calendarImportSettings.selectedSourceCalendarIDs.filter { availableIDs.contains($0) }
        if selected != calendarImportSettings.selectedSourceCalendarIDs {
            calendarImportSettings.selectedSourceCalendarIDs = selected
            persistCaches(scopes: [.importSettings])
        }
    }

    func setCalendarImportEnabled(_ enabled: Bool) async {
        calendarImportSettings.isEnabled = enabled
        if enabled && calendarImportSettings.selectedSourceCalendarIDs.isEmpty {
            calendarImportSettings.selectedSourceCalendarIDs = availableExternalCalendars.map(\.id)
        }
        persistCaches(scopes: [.importSettings])
        startEventStoreObservationIfNeeded()
        if enabled {
            await runInitialCalendarImport()
        }
    }

    func toggleImportedSourceCalendar(_ calendarID: String) {
        if let index = calendarImportSettings.selectedSourceCalendarIDs.firstIndex(of: calendarID) {
            calendarImportSettings.selectedSourceCalendarIDs.remove(at: index)
        } else {
            calendarImportSettings.selectedSourceCalendarIDs.append(calendarID)
        }
        calendarImportSettings.selectedSourceCalendarIDs.sort()
        persistCaches(scopes: [.importSettings])
    }

    func isImportedSourceCalendarSelected(_ calendarID: String) -> Bool {
        calendarImportSettings.selectedSourceCalendarIDs.contains(calendarID)
    }

    func runInitialCalendarImport() async {
        guard calendarImportSettings.isEnabled else { return }
        await reconcileImportedCalendarEvents(trigger: .initial)
    }

    func reconcileImportedCalendarEvents(trigger: SyncTrigger) async {
        guard calendarImportSettings.isEnabled else { return }
        guard calendarPermissionState.canReadEvents else { return }
        guard session != nil else { return }
        guard await ensureImportSourceCalendarsSelectedIfNeeded() else { return }
        guard !isReconcilingImportedEvents else { return }
        if shouldThrottleAutomaticReconcile(trigger: trigger) { return }

        isReconcilingImportedEvents = true
        defer { isReconcilingImportedEvents = false }
        if trigger == .eventStoreChange || trigger == .foreground {
            lastAutomaticImportReconcileAt = Date()
        }

        pruneEchoDebounceEntries()

        let now = Date()
        let from = CalendarHelper.calendar.date(
            byAdding: .day,
            value: -max(1, calendarImportSettings.syncWindowDaysPast),
            to: now
        ) ?? now
        let to = CalendarHelper.calendar.date(
            byAdding: .day,
            value: max(1, calendarImportSettings.syncWindowDaysFuture),
            to: now
        ) ?? now

        do {
            let sourceEvents = calendarService.fetchEvents(
                calendarIDs: calendarImportSettings.selectedSourceCalendarIDs,
                from: from,
                to: to
            )
            let shouldSweepMissingSourceLinks = !sourceEvents.isEmpty || trigger == .manual
            var seenSourceKeys: Set<String> = []
            var localEventsChanged = false
            var didMutateImportMetadata = false
            var didEnqueueOperations = false
            var needsEventSort = false
            var conflictCandidateIDs: Set<String> = []
            let writableByCalendarID = Dictionary(uniqueKeysWithValues: availableExternalCalendars.map { ($0.id, $0.allowsWrites) })

            for sourceEvent in sourceEvents {
                guard let importedDraft = draftImportedEvent(from: sourceEvent) else { continue }
                let sourceKey = sourceKey(calendarID: sourceEvent.sourceCalendarID, eventID: sourceEvent.sourceEventID)
                seenSourceKeys.insert(sourceKey)
                let sourceFingerprint = importedDraft.fingerprint
                if importedDraft.isInformational, dismissedInformationalSourceKeys.contains(sourceKey) {
                    continue
                }

                if let linkIndex = importedEventLinks.firstIndex(where: {
                    $0.sourceCalendarID == sourceEvent.sourceCalendarID &&
                    $0.sourceEventID == sourceEvent.sourceEventID
                }) {
                    if importedEventLinks[linkIndex].isInformational != importedDraft.isInformational {
                        importedEventLinks[linkIndex].isInformational = importedDraft.isInformational
                        didMutateImportMetadata = true
                    }
                    if let existingIndex = events.firstIndex(where: { $0.id == importedEventLinks[linkIndex].weekendEventID }) {
                        let existing = events[existingIndex]
                        let localFingerprint = fingerprint(for: existing)
                        let linked = importedEventLinks[linkIndex]

                        if sourceFingerprint == linked.lastFingerprint {
                            if localFingerprint != linked.lastFingerprint, linked.writable {
                                if try await pushLinkedEventUpdate(existing, linkIndex: linkIndex, persistChanges: false) {
                                    didMutateImportMetadata = true
                                }
                            } else if localFingerprint != linked.lastFingerprint {
                                importConflicts[existing.id] = .pending
                                conflictCandidateIDs.insert(existing.id)
                                didMutateImportMetadata = true
                            }
                            continue
                        }

                        if localFingerprint != linked.lastFingerprint && localFingerprint != sourceFingerprint {
                            importConflicts[existing.id] = .pending
                            conflictCandidateIDs.insert(existing.id)
                            didMutateImportMetadata = true
                            continue
                        }

                        if shouldIgnoreInboundSourceChange(sourceKey: sourceKey) && sourceFingerprint == localFingerprint {
                            importedEventLinks[linkIndex].lastFingerprint = sourceFingerprint
                            continue
                        }

                        let merged = mergeImportedEvent(importedDraft.event, into: existing)
                        events[existingIndex] = merged
                        importedEventLinks[linkIndex].lastFingerprint = sourceFingerprint
                        enqueueOperation(
                            PendingSyncOperation(
                                type: .upsertEvent,
                                entityId: merged.id,
                                event: merged,
                                calendarId: merged.calendarId
                            ),
                            persistImmediately: false
                        )
                        didEnqueueOperations = true
                        conflictCandidateIDs.insert(merged.id)
                        localEventsChanged = true
                        didMutateImportMetadata = true
                    } else {
                        importedEventLinks.remove(at: linkIndex)
                        didMutateImportMetadata = true
                    }
                    continue
                }

                if let dedupedEventID = dedupedImportedEventID(
                    sourceCalendarID: sourceEvent.sourceCalendarID,
                    candidate: importedDraft.event
                ) {
                    let writable = writableByCalendarID[sourceEvent.sourceCalendarID] ?? false
                    importedEventLinks.append(
                        ImportedEventLink(
                            weekendEventID: dedupedEventID,
                            sourceCalendarID: sourceEvent.sourceCalendarID,
                            sourceEventID: sourceEvent.sourceEventID,
                            lastFingerprint: sourceFingerprint,
                            writable: writable,
                            isInformational: importedDraft.isInformational
                        )
                    )
                    conflictCandidateIDs.insert(dedupedEventID)
                    didMutateImportMetadata = true
                    continue
                }

                guard let session else { continue }
                let userId = normalizedUserId(for: session)
                let importedEventID = UUID().uuidString
                let created = WeekendEvent(
                    id: importedEventID,
                    title: importedDraft.event.title,
                    type: importedDraft.event.type,
                    calendarId: importTargetCalendarId(),
                    weekendKey: importedDraft.event.weekendKey,
                    days: importedDraft.event.days,
                    startTime: importedDraft.event.startTime,
                    endTime: importedDraft.event.endTime,
                    userId: userId,
                    calendarEventIdentifier: sourceEvent.sourceEventID,
                    status: WeekendEventStatus.planned.rawValue,
                    completedAt: nil,
                    cancelledAt: nil,
                    clientUpdatedAt: now,
                    updatedAt: now,
                    createdAt: now,
                    deletedAt: nil
                )
                events.append(created)
                needsEventSort = true
                let writable = writableByCalendarID[sourceEvent.sourceCalendarID] ?? false
                importedEventLinks.append(
                    ImportedEventLink(
                        weekendEventID: created.id,
                        sourceCalendarID: sourceEvent.sourceCalendarID,
                        sourceEventID: sourceEvent.sourceEventID,
                        lastFingerprint: sourceFingerprint,
                        writable: writable,
                        isInformational: importedDraft.isInformational
                    )
                )
                enqueueOperation(
                    PendingSyncOperation(
                        type: .upsertEvent,
                        entityId: created.id,
                        event: created,
                        calendarId: created.calendarId
                    ),
                    persistImmediately: false
                )
                didEnqueueOperations = true
                conflictCandidateIDs.insert(created.id)
                localEventsChanged = true
                didMutateImportMetadata = true
            }

            if shouldSweepMissingSourceLinks {
                let selectedSourceIDs = Set(calendarImportSettings.selectedSourceCalendarIDs)
                let importedLinkSnapshot = importedEventLinks.filter { selectedSourceIDs.contains($0.sourceCalendarID) }
                for link in importedLinkSnapshot {
                    let key = sourceKey(calendarID: link.sourceCalendarID, eventID: link.sourceEventID)
                    guard !seenSourceKeys.contains(key) else { continue }

                    guard let localIndex = events.firstIndex(where: { $0.id == link.weekendEventID }) else {
                        importedEventLinks.removeAll { $0.weekendEventID == link.weekendEventID }
                        didMutateImportMetadata = true
                        continue
                    }

                    let localEvent = events[localIndex]
                    if fingerprint(for: localEvent) == link.lastFingerprint {
                        events.remove(at: localIndex)
                        eventDescriptions.removeValue(forKey: localEvent.id)
                        importConflicts.removeValue(forKey: localEvent.id)
                        importedEventLinks.removeAll { $0.weekendEventID == localEvent.id }
                        enqueueOperation(
                            PendingSyncOperation(
                                type: .deleteEvent,
                                entityId: localEvent.id,
                                calendarId: localEvent.calendarId ?? selectedCalendarId
                            ),
                            persistImmediately: false
                        )
                        didEnqueueOperations = true
                        localEventsChanged = true
                        didMutateImportMetadata = true
                    } else {
                        importConflicts[localEvent.id] = .pending
                        conflictCandidateIDs.insert(localEvent.id)
                        didMutateImportMetadata = true
                    }
                }
            }

            if needsEventSort {
                events = sortedEvents(events)
            }
            for eventID in conflictCandidateIDs {
                updateConflictState(for: eventID)
            }

            let previousSyncAt = calendarImportSettings.lastSyncAt
            let syncTimestamp = Date()
            let shouldPersistHeartbeat: Bool
            if let previousSyncAt {
                shouldPersistHeartbeat = syncTimestamp.timeIntervalSince(previousSyncAt) >= 30
            } else {
                shouldPersistHeartbeat = true
            }
            if localEventsChanged || didMutateImportMetadata || didEnqueueOperations || shouldPersistHeartbeat {
                calendarImportSettings.lastSyncAt = syncTimestamp
                let persistencePolicy: PersistencePolicy = (localEventsChanged || didEnqueueOperations) ? .immediate : .debounced
                persistCaches(
                    scopes: [
                        .events,
                        .eventDescriptions,
                        .importLinks,
                        .importConflicts,
                        .importSettings,
                        .syncQueue,
                        .syncStates
                    ],
                    policy: persistencePolicy
                )
            }

            if localEventsChanged {
                scheduleNotificationResync(reason: "calendar-import")
            }
            if didEnqueueOperations {
                scheduleSyncFlush(reason: "calendar-import")
            }
        } catch {
            authMessage = "Calendar import failed. \(error.localizedDescription)"
        }
    }

    func acknowledgeConflict(eventId: String) {
        guard importConflicts[eventId] == .pending else { return }
        importConflicts[eventId] = .acknowledged
        persistCaches(scopes: [.importConflicts])
    }

    func importConflictState(for eventId: String) -> ImportConflictState {
        importConflicts[eventId] ?? .none
    }

    func isImportedEvent(_ eventId: String) -> Bool {
        importedEventIDLookup.contains(eventId)
    }

    func hasPendingImportConflict(weekendKey: String) -> Bool {
        pendingConflictWeekendKeys.contains(weekendKey)
    }

    var calendarImportLastSyncLabel: String {
        guard let lastSyncAt = calendarImportSettings.lastSyncAt else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lastSyncAt, relativeTo: Date())
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
        scheduleNotificationResync(reason: "notification-permission", immediate: true)
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
        scheduleNotificationResync(reason: "notification-preferences")
    }

    func rescheduleNotifications(force: Bool = false) async {
        let signature = notificationRescheduleSignature()
        if !force, signature == lastNotificationRescheduleSignature {
            return
        }
        let token = performanceMonitor.begin(.rescheduleNotifications)
        await notificationService.rescheduleNotifications(
            events: events,
            protections: protections,
            preferences: notificationPreferences,
            sessionIsActive: session != nil
        )
        lastNotificationRescheduleSignature = signature
        performanceMonitor.end(token)
        refreshPerformanceSnapshot()
    }

    func weeklyReportSnapshot(referenceDate: Date = Date()) -> WeeklyReportSnapshot {
        reportService.weeklyReportSnapshot(
            events: events,
            referenceDate: referenceDate
        )
    }

    func enqueueOperation(_ operation: PendingSyncOperation, persistImmediately: Bool = true) {
        pendingOperations.append(operation)
        pendingOperationCount = pendingOperations.count
        switch operation.type {
        case .upsertEvent, .deleteEvent:
            syncStates[operation.entityId] = .pending
            pendingEventOperationIDs.insert(operation.entityId)
        case .setProtection, .appendAudit, .unsupported:
            break
        }
        if persistImmediately {
            persistCaches(scopes: [.syncQueue, .syncStates], policy: .immediate)
        }
    }

    @discardableResult
    private func compactPendingOperations() -> Bool {
        guard pendingOperations.count > 1 else { return false }

        var passthroughOperations: [(Int, PendingSyncOperation)] = []
        var latestOperationByBucket: [String: (Int, PendingSyncOperation)] = [:]

        for (index, operation) in pendingOperations.enumerated() {
            guard let bucket = syncCompactionBucket(for: operation) else {
                passthroughOperations.append((index, operation))
                continue
            }
            latestOperationByBucket[bucket] = (index, operation)
        }

        let compacted = (passthroughOperations + latestOperationByBucket.values.map { $0 })
            .sorted { lhs, rhs in lhs.0 < rhs.0 }
            .map(\.1)

        guard compacted.count < pendingOperations.count else { return false }
        pendingOperations = compacted
        pendingOperationCount = compacted.count
        rebuildPendingOperationIndex()
        return true
    }

    private func syncCompactionBucket(for operation: PendingSyncOperation) -> String? {
        switch operation.type {
        case .upsertEvent, .deleteEvent:
            return "event:\(operation.entityId)"
        case .setProtection:
            let calendarId = operation.calendarId ?? "none"
            let weekendKey = operation.protectionWeekKey ?? operation.entityId
            return "protection:\(calendarId):\(weekendKey)"
        case .appendAudit, .unsupported:
            return nil
        }
    }

    func flushPendingOperations() async {
        let metricToken = performanceMonitor.begin(.flushPendingOperations)
        defer {
            performanceMonitor.end(metricToken)
            refreshPerformanceSnapshot()
        }
        if compactPendingOperations() {
            persistCaches(scopes: [.syncQueue], policy: .debounced)
        }
        guard let session, !pendingOperations.isEmpty, !syncInProgress else { return }
        syncInProgress = true
        defer { syncInProgress = false }

        let result = await syncEngine.flush(
            operations: pendingOperations,
            userId: normalizedUserId(for: session),
            supabase: supabase
        )
        pendingOperations = result.remainingOperations
        pendingOperationCount = pendingOperations.count
        rebuildPendingOperationIndex()
        for (entityId, syncState) in result.syncStates {
            syncStates[entityId] = syncState
        }
        if let lastErrorMessage = result.lastErrorMessage {
            authMessage = "Sync will retry: \(lastErrorMessage)"
            lastSyncErrorMessage = lastErrorMessage
        } else if pendingOperations.isEmpty {
            lastSyncErrorMessage = nil
        }
        persistCaches(scopes: [.syncQueue, .syncStates])
    }

    func syncState(for eventId: String) -> SyncState {
        let state = syncStates[eventId]
        if pendingEventOperationIDs.contains(eventId) {
            if state == .retrying {
                return .retrying
            }
            return .pending
        }
        return state ?? .synced
    }

    func forceRetryPendingOperations(reason: String = "manual-retry") {
        guard !pendingOperations.isEmpty else { return }
        let now = Date()
        var didUpdateRetryTime = false
        for index in pendingOperations.indices {
            if pendingOperations[index].nextAttemptAt > now {
                pendingOperations[index].nextAttemptAt = now
                didUpdateRetryTime = true
            }
        }
        if didUpdateRetryTime {
            persistCaches(scopes: [.syncQueue], policy: .immediate)
        }
        scheduledSyncFlushTask?.cancel()
        scheduledSyncFlushTask = nil
        scheduleSyncFlush(reason: reason, immediate: true)
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
        persistCaches(scopes: [.audit])
    }

    func consumePendingWeekendSelection() {
        pendingWeekendSelection = nil
    }

    func consumePendingAddPlanSelection() {
        pendingAddPlanWeekendKey = nil
        pendingAddPlanBypassProtection = false
        pendingAddPlanInitialDate = nil
    }

    func consumePendingSettingsPath() {
        pendingSettingsPath.removeAll()
    }

    func consumePendingSettingsDestination() {
        consumePendingSettingsPath()
    }

    func evaluateOnboardingPresentation(userIdOverride: String? = nil) {
        if forceOnboardingForUITests {
            showOnboardingChecklist = false
            showOnboarding = true
            return
        }
        if skipOnboardingForUITests || showAuthSplash {
            showOnboarding = false
            showOnboardingChecklist = false
            return
        }

        let userId = userIdOverride ?? session.map(normalizedUserId(for:))
        guard let userId else {
            showOnboarding = false
            showOnboardingChecklist = false
            return
        }

        showOnboardingChecklist = false
        showOnboarding = !hasCompletedOnboarding(userId: userId)
    }

    func hasCompletedOnboarding(for session: Session) -> Bool {
        hasCompletedOnboarding(userId: normalizedUserId(for: session))
    }

    func hasCompletedOnboarding(userId: String) -> Bool {
        UserDefaults.standard.bool(forKey: onboardingCompletedStorageKey(userId: userId))
    }

    func markOnboardingCompleted() {
        guard let session else { return }
        markOnboardingCompleted(userId: normalizedUserId(for: session))
    }

    func markOnboardingCompleted(userId: String) {
        UserDefaults.standard.set(true, forKey: onboardingCompletedStorageKey(userId: userId))
    }

    func completeOnboardingAndShowChecklist() {
        markOnboardingCompleted()
        showOnboarding = false
        showOnboardingChecklist = true
    }

    func closeOnboardingChecklist() {
        showOnboardingChecklist = false
    }

    func presentOnboardingFromSettings() {
        showOnboardingChecklist = false
        showOnboarding = true
    }

    func openSettingsPath(_ path: [SettingsDestination]) {
        selectedTab = .settings
        pendingSettingsPath = path
    }

    func openSettingsDestination(_ destination: SettingsDestination) {
        openSettingsPath([destination])
    }

    func openAdvancedDiagnosticsInSettings() {
        openSettingsPath([.dataPrivacy, .advancedDiagnostics])
    }

    func openOnboardingSettingsStep(_ destination: SettingsDestination) {
        showOnboardingChecklist = false
        openSettingsDestination(destination)
    }

    func openOnboardingAddPlanStep() {
        showOnboardingChecklist = false
        let initialDate = nextFutureHolidayDate() ?? Date()
        selectedTab = .weekend
        selectedMonthKey = monthSelectionKey(
            for: CalendarHelper.plannerWeekKey(for: initialDate)
        )
        pendingAddPlanWeekendKey = CalendarHelper.plannerWeekKey(for: initialDate)
        pendingAddPlanBypassProtection = false
        pendingAddPlanInitialDate = initialDate
    }

    private func handleNotificationRoute(_ routeAction: NotificationRouteAction) {
        switch routeAction {
        case .openWeekend(let weekendKey):
            selectedTab = .weekend
            selectedMonthKey = monthSelectionKey(for: weekendKey)
            pendingWeekendSelection = weekendKey
        case .addPlan(let weekendKey):
            selectedTab = .weekend
            selectedMonthKey = monthSelectionKey(for: weekendKey)
            pendingAddPlanWeekendKey = weekendKey
            pendingAddPlanBypassProtection = false
            pendingAddPlanInitialDate = nil
        }
    }

    private func scheduleLinkedEventUpdate(for event: WeekendEvent) {
        let eventID = event.id
        scheduledLinkedEventUpdateTasks[eventID]?.cancel()
        scheduledLinkedEventUpdateTasks[eventID] = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer { self.scheduledLinkedEventUpdateTasks[eventID] = nil }
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            guard let linkIndex = self.importedEventLinks.firstIndex(where: { $0.weekendEventID == eventID }) else { return }
            _ = try? await self.pushLinkedEventUpdate(event, linkIndex: linkIndex)
            self.updateConflictState(for: eventID)
        }
    }

    private func scheduleCalendarExportSync(for event: WeekendEvent, enabled: Bool) {
        let eventID = event.id
        scheduledCalendarExportTasks[eventID]?.cancel()
        scheduledCalendarExportTasks[eventID] = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer { self.scheduledCalendarExportTasks[eventID] = nil }
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            self.syncCalendarExport(for: event, enabled: enabled)
        }
    }

    private func syncCalendarExport(for event: WeekendEvent, enabled: Bool) {
        if !enabled {
            removeCalendarExports(forEventID: event.id)
            return
        }
        guard calendarPermissionState.canWriteEvents else { return }
        let intervals = intervals(for: event)
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
        scheduledCalendarExportTasks[eventID]?.cancel()
        let identifiers = calendarExportStore.identifiers(for: eventID)
        calendarExportStore.removeIdentifiers(for: eventID)
        updateInMemoryCalendarIdentifier(forEventID: eventID, identifier: nil)
        guard !identifiers.isEmpty else { return }
        scheduledCalendarExportTasks[eventID] = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer { self.scheduledCalendarExportTasks[eventID] = nil }
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            do {
                try self.calendarService.removeExportedEvents(identifiers: identifiers)
            } catch {
                self.authMessage = "Could not remove Apple Calendar event. \(error.localizedDescription)"
            }
        }
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
        persistCaches(scopes: [.quickAddChips])
    }

    private func weekendNoteStorageKey(for weekendKey: String) -> String {
        "\(selectedCalendarId ?? "local")|\(weekendKey)"
    }

    private func pruneEventDescriptionsToActiveEvents() {
        let activeEventIDs = Set(events.map(\.id))
        eventDescriptions = eventDescriptions.filter { activeEventIDs.contains($0.key) }
    }

    private func normalizedAttributionCalendarIDs(from input: Set<String>, fallbackPrimary: String?) -> [String] {
        let validCalendarIDs = Set(calendars.map(\.id))
        var normalized = input.filter { validCalendarIDs.contains($0) }
        if normalized.isEmpty,
           let fallbackPrimary,
           validCalendarIDs.contains(fallbackPrimary) {
            normalized.insert(fallbackPrimary)
        }
        if normalized.isEmpty,
           let selectedCalendarId,
           validCalendarIDs.contains(selectedCalendarId) {
            normalized.insert(selectedCalendarId)
        }
        if normalized.isEmpty, let first = calendars.first?.id {
            normalized.insert(first)
        }
        return normalized.sorted()
    }

    private func preferredPrimaryCalendarID(from calendarIDs: [String], preferred: String?) -> String? {
        if let preferred, calendarIDs.contains(preferred) {
            return preferred
        }
        if let selectedCalendarId, calendarIDs.contains(selectedCalendarId) {
            return selectedCalendarId
        }
        return calendarIDs.first
    }

    private func setLocalEventCalendarAttributions(eventId: String, calendarIDs: Set<String>) {
        let sortedIDs = calendarIDs.sorted()
        if sortedIDs.isEmpty {
            eventCalendarAttributions.removeValue(forKey: eventId)
        } else {
            eventCalendarAttributions[eventId] = sortedIDs
        }
    }

    private func attributedEventIDs(for calendarId: String) async -> Set<String> {
        let remoteRows = await fetchRemoteEventCalendarAttributions(for: calendarId)
        if hasRemoteEventAttributionsTable == true {
            for eventId in eventCalendarAttributions.keys {
                eventCalendarAttributions[eventId]?.removeAll { $0 == calendarId }
                if eventCalendarAttributions[eventId]?.isEmpty == true {
                    eventCalendarAttributions.removeValue(forKey: eventId)
                }
            }
            for row in remoteRows {
                var ids = Set(eventCalendarAttributions[row.eventId] ?? [])
                ids.insert(row.calendarId)
                eventCalendarAttributions[row.eventId] = ids.sorted()
            }
        }

        return Set(
            eventCalendarAttributions.compactMap { eventId, calendarIDs in
                calendarIDs.contains(calendarId) ? eventId : nil
            }
        )
    }

    private func fetchRemoteEventCalendarAttributions(for calendarId: String) async -> [EventCalendarAttribution] {
        if hasRemoteEventAttributionsTable == false {
            return []
        }
        do {
            let rows: [EventCalendarAttribution] = try await supabase
                .from("weekend_event_calendar_attributions")
                .select("event_id,calendar_id,user_id")
                .eq("calendar_id", value: calendarId)
                .execute()
                .value
            hasRemoteEventAttributionsTable = true
            return rows
        } catch {
            if isMissingRemoteAttributionTableError(error) {
                hasRemoteEventAttributionsTable = false
                return []
            }
            return []
        }
    }

    private func syncRemoteEventCalendarAttributions(eventId: String, calendarIDs: Set<String>, userId: String) async {
        if hasRemoteEventAttributionsTable == false {
            return
        }
        do {
            _ = try await supabase
                .from("weekend_event_calendar_attributions")
                .delete()
                .eq("event_id", value: eventId)
                .execute()

            let payloads = calendarIDs.map {
                NewEventCalendarAttribution(eventId: eventId, calendarId: $0, userId: userId)
            }
            if !payloads.isEmpty {
                try await supabase
                    .from("weekend_event_calendar_attributions")
                    .insert(payloads)
                    .execute()
            }
            hasRemoteEventAttributionsTable = true
        } catch {
            if isMissingRemoteAttributionTableError(error) {
                hasRemoteEventAttributionsTable = false
                return
            }
        }
    }

    private func removeRemoteEventCalendarAttributions(eventId: String) async {
        if hasRemoteEventAttributionsTable == false {
            return
        }
        do {
            _ = try await supabase
                .from("weekend_event_calendar_attributions")
                .delete()
                .eq("event_id", value: eventId)
                .execute()
            hasRemoteEventAttributionsTable = true
        } catch {
            if isMissingRemoteAttributionTableError(error) {
                hasRemoteEventAttributionsTable = false
            }
        }
    }

    private func isMissingRemoteAttributionTableError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("weekend_event_calendar_attributions") &&
            (message.contains("does not exist") || message.contains("42p01"))
    }

    private func localizedTimeZoneName(_ timeZone: TimeZone) -> String {
        timeZone.localizedName(for: .generic, locale: .current)
            ?? timeZone.identifier.replacingOccurrences(of: "_", with: " ")
    }

    private func gmtOffsetLabel(for timeZone: TimeZone) -> String {
        let seconds = timeZone.secondsFromGMT()
        let sign = seconds >= 0 ? "+" : "-"
        let absolute = abs(seconds)
        let hours = absolute / 3600
        let minutes = (absolute % 3600) / 60
        return String(format: "GMT%@%02d:%02d", sign, hours, minutes)
    }

    private func publicHolidayLookup() -> [String: PublicHolidayInfo] {
        guard weekendConfiguration.includePublicHolidays,
              let region = resolvedPublicHolidayRegion else {
            return [:]
        }

        if let cached = publicHolidayLookupCache[region] {
            return cached
        }

        let planningYears = CalendarHelper.planningYears(referenceDate: Date())
        let currentYear = CalendarHelper.currentPlanningYear()
        let lowerYear = (planningYears.first ?? currentYear) - 1
        let upperYear = (planningYears.last ?? currentYear) + 1
        let years = Array(lowerYear...upperYear)
        let holidays = PublicHolidayCalculator.holidays(
            for: years,
            region: region,
            calendar: CalendarHelper.calendar
        )
        let map = Dictionary(uniqueKeysWithValues: holidays.map { ($0.dateKey, $0) })
        publicHolidayLookupCache[region] = map
        return map
    }

    private func inferredPublicHolidayRegionFromLocale() -> SupportedPublicHolidayRegion? {
        let regionCode = Locale.autoupdatingCurrent.region?.identifier.uppercased() ?? ""
        switch regionCode {
        case "US":
            return .us
        case "GB", "UK":
            return .uk
        default:
            return nil
        }
    }

    private func startEventStoreObservationIfNeeded() {
        guard calendarImportSettings.isEnabled, calendarPermissionState.canReadEvents else {
            eventStoreObservationTask?.cancel()
            eventStoreObservationTask = nil
            return
        }
        if eventStoreObservationTask != nil {
            return
        }
        eventStoreObservationTask = Task { [weak self] in
            guard let self else { return }
            for await _ in calendarService.observeEventStoreChanges() {
                if Task.isCancelled { break }
                await reconcileImportedCalendarEvents(trigger: .eventStoreChange)
            }
        }
    }

    private func sourceKey(calendarID: String, eventID: String) -> String {
        "\(calendarID)|\(eventID)"
    }

    private func pruneEchoDebounceEntries() {
        let now = Date()
        outboundEchoDebounceUntil = outboundEchoDebounceUntil.filter { $0.value > now }
    }

    private func shouldIgnoreInboundSourceChange(sourceKey: String) -> Bool {
        guard let debounceUntil = outboundEchoDebounceUntil[sourceKey] else { return false }
        return debounceUntil > Date()
    }

    private func shouldThrottleAutomaticReconcile(trigger: SyncTrigger) -> Bool {
        guard trigger == .eventStoreChange || trigger == .foreground else { return false }
        guard let lastAutomaticImportReconcileAt else { return false }
        return Date().timeIntervalSince(lastAutomaticImportReconcileAt) < 60
    }

    private func ensureImportSourceCalendarsSelectedIfNeeded() async -> Bool {
        if !calendarImportSettings.selectedSourceCalendarIDs.isEmpty {
            return true
        }

        if availableExternalCalendars.isEmpty {
            await refreshAvailableExternalCalendars()
        }

        let availableIDs = availableExternalCalendars.map(\.id)
        guard !availableIDs.isEmpty else { return false }

        calendarImportSettings.selectedSourceCalendarIDs = availableIDs
        persistCaches(scopes: [.importSettings])
        return true
    }

    private func importTargetCalendarId() -> String? {
        guard let session else { return selectedCalendarId }
        let userId = normalizedUserId(for: session)

        if let selectedCalendarId,
           let selected = calendars.first(where: { $0.id == selectedCalendarId }),
           selected.ownerUserId.lowercased() == userId {
            return selectedCalendarId
        }

        if let personal = calendars.first(where: {
            $0.ownerUserId.lowercased() == userId &&
            $0.name.localizedCaseInsensitiveCompare("Personal") == .orderedSame
        }) {
            return personal.id
        }

        if let owned = calendars.first(where: { $0.ownerUserId.lowercased() == userId }) {
            return owned.id
        }

        return selectedCalendarId
    }

    private func draftImportedEvent(from sourceEvent: ExternalCalendarEvent) -> (event: WeekendEvent, fingerprint: String, isInformational: Bool)? {
        let calendar = CalendarHelper.calendar
        let sourceStart = sourceEvent.startDate
        let sourceEnd = max(sourceEvent.endDate, sourceEvent.startDate.addingTimeInterval(60))
        guard let intersection = CalendarHelper.weekendIntersection(start: sourceStart, end: sourceEnd) else {
            return nil
        }
        let days = intersection.days.map(\.rawValue)

        let spansMultipleDays = !calendar.isDate(sourceStart, inSameDayAs: sourceEnd.addingTimeInterval(-1)) || days.count > 1
        let shouldTreatAsAllDay = sourceEvent.allDay || spansMultipleDays
        let startTime = shouldTreatAsAllDay ? "00:00" : CalendarHelper.timeString(from: sourceStart)
        let endTime = shouldTreatAsAllDay ? "23:59" : CalendarHelper.timeString(from: sourceEnd)

        let draft = WeekendEvent(
            id: UUID().uuidString,
            title: sourceEvent.title,
            type: PlanType.plan.rawValue,
            calendarId: importTargetCalendarId(),
            weekendKey: intersection.weekendKey,
            days: days,
            startTime: startTime,
            endTime: endTime,
            userId: session.map(normalizedUserId(for:)) ?? "",
            calendarEventIdentifier: sourceEvent.sourceEventID,
            status: WeekendEventStatus.planned.rawValue,
            completedAt: nil,
            cancelledAt: nil,
            clientUpdatedAt: sourceEvent.lastModified,
            updatedAt: sourceEvent.lastModified,
            createdAt: sourceEvent.lastModified,
            deletedAt: nil
        )
        return (
            draft,
            fingerprint(for: draft),
            isInformationalImportedSourceEvent(sourceEvent)
        )
    }

    private func mergeImportedEvent(_ imported: WeekendEvent, into existing: WeekendEvent) -> WeekendEvent {
        var merged = existing
        merged.title = imported.title
        merged.type = imported.type
        merged.weekendKey = imported.weekendKey
        merged.days = imported.days
        merged.startTime = imported.startTime
        merged.endTime = imported.endTime
        merged.calendarEventIdentifier = imported.calendarEventIdentifier
        merged.clientUpdatedAt = Date()
        merged.updatedAt = Date()
        return merged
    }

    private func dedupedImportedEventID(sourceCalendarID: String, candidate: WeekendEvent) -> String? {
        let candidateFingerprint = fingerprint(for: candidate)

        for event in events {
            guard event.weekendKey == candidate.weekendKey else { continue }
            guard fingerprint(for: event) == candidateFingerprint else { continue }

            if let existingLink = importedEventLinks.first(where: { $0.weekendEventID == event.id }) {
                if existingLink.sourceCalendarID == sourceCalendarID {
                    return event.id
                }
                continue
            }
            return event.id
        }

        return nil
    }

    private func updateConflictState(for eventID: String) {
        guard let importedEvent = events.first(where: { $0.id == eventID }) else {
            importConflicts.removeValue(forKey: eventID)
            return
        }
        guard isImportedEvent(eventID) else {
            importConflicts.removeValue(forKey: eventID)
            return
        }
        guard !isInformationalImportedEvent(importedEvent) else {
            importConflicts.removeValue(forKey: eventID)
            return
        }

        let importedIntervals = intervals(for: importedEvent)
        guard !importedIntervals.isEmpty else {
            importConflicts.removeValue(forKey: eventID)
            return
        }

        let hasOverlap = events.contains { other in
            guard other.id != importedEvent.id else { return false }
            guard other.weekendKey == importedEvent.weekendKey else { return false }
            guard !isImportedEvent(other.id) else { return false }

            let otherIntervals = intervals(for: other)
            return importedIntervals.contains { importedInterval in
                otherIntervals.contains { otherInterval in
                    importedInterval.intersects(otherInterval)
                }
            }
        }

        if hasOverlap {
            if importConflicts[eventID] != .acknowledged {
                importConflicts[eventID] = .pending
            }
        } else {
            importConflicts.removeValue(forKey: eventID)
        }
    }

    private func pruneImportedMetadataToActiveEvents() {
        let activeIDs = Set(events.map(\.id))
        importedEventLinks = importedEventLinks.filter { activeIDs.contains($0.weekendEventID) }
        importConflicts = importConflicts.filter { activeIDs.contains($0.key) }
    }

    private func fingerprint(for event: WeekendEvent) -> String {
        let intervals = intervals(for: event)
        let start = intervals.first?.start.timeIntervalSince1970 ?? 0
        let end = intervals.last?.end.timeIntervalSince1970 ?? 0
        let title = event.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let dayKey = event.days.sorted().joined(separator: ",")
        return "\(title)|\(event.weekendKey)|\(dayKey)|\(event.startTime)|\(event.endTime)|\(Int(start))|\(Int(end))|\(event.isAllDay ? 1 : 0)"
    }

    private func isInformationalImportedEvent(_ event: WeekendEvent) -> Bool {
        guard event.isAllDay else { return false }
        guard event.planType == .plan else { return false }

        let title = normalizedInfoLabel(event.title)
        let hasInformationalTitleKeyword = informationalImportedTitleKeywords.contains(where: { title.contains($0) })
        let hasInformationalLifecycleWord = title.contains("begins") || title.contains("starts") || title.contains("observed")

        if let link = importedEventLinks.first(where: { $0.weekendEventID == event.id }) {
            if link.isInformational {
                return true
            }
            if let sourceCalendar = importedSourceCalendarSummary(forImportedEventID: event.id) {
                let sourceText = normalizedInfoLabel("\(sourceCalendar.title) \(sourceCalendar.sourceTitle)")
                if informationalImportedSourceKeywords.contains(where: { sourceText.contains($0) }) {
                    return true
                }
            }
            return hasInformationalTitleKeyword || hasInformationalLifecycleWord
        }

        return hasInformationalTitleKeyword || hasInformationalLifecycleWord
    }

    private func isInformationalImportedSourceEvent(_ sourceEvent: ExternalCalendarEvent) -> Bool {
        guard sourceEvent.allDay else { return false }

        let normalizedTitle = normalizedInfoLabel(sourceEvent.title)
        let hasTitleKeyword = informationalImportedTitleKeywords.contains(where: { normalizedTitle.contains($0) })
        let sourceContext = normalizedInfoLabel("\(sourceEvent.sourceCalendarTitle) \(sourceEvent.sourceSourceTitle)")
        let hasSourceKeyword = informationalImportedSourceKeywords.contains(where: { sourceContext.contains($0) })
        let hasLifecycleWord = normalizedTitle.contains("begins") || normalizedTitle.contains("starts") || normalizedTitle.contains("observed")
        return hasTitleKeyword || hasSourceKeyword || hasLifecycleWord
    }

    private func importedSourceCalendarSummary(forImportedEventID eventID: String) -> ExternalCalendarSummary? {
        guard let sourceCalendarID = importedEventLinks.first(where: { $0.weekendEventID == eventID })?.sourceCalendarID else {
            return nil
        }
        return availableExternalCalendars.first(where: { $0.id == sourceCalendarID })
    }

    private func sourceKeyForImportedEvent(eventID: String) -> String? {
        guard let link = importedEventLinks.first(where: { $0.weekendEventID == eventID }) else { return nil }
        return sourceKey(calendarID: link.sourceCalendarID, eventID: link.sourceEventID)
    }

    private func deduplicatedInfoPills(_ pills: [HolidayInfoPill]) -> [HolidayInfoPill] {
        var indexByNormalizedLabel: [String: Int] = [:]
        var result: [HolidayInfoPill] = []

        for pill in pills {
            let trimmedLabel = pill.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = normalizedInfoLabel(trimmedLabel)
            guard !normalized.isEmpty else { continue }

            let candidate = HolidayInfoPill(
                id: pill.id,
                label: trimmedLabel,
                kind: pill.kind,
                reminderEventID: pill.reminderEventID,
                personalReminderID: pill.personalReminderID,
                sourceEventKey: pill.sourceEventKey
            )

            if let existingIndex = indexByNormalizedLabel[normalized] {
                let existing = result[existingIndex]
                if !existing.isRemovableReminder && candidate.isRemovableReminder {
                    result[existingIndex] = candidate
                }
                continue
            }

            indexByNormalizedLabel[normalized] = result.count
            result.append(candidate)
        }
        return result
    }

    private func normalizedInfoLabel(_ value: String) -> String {
        let folded = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let normalizedScalars = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(normalizedScalars))
    }

    private func dismissedInformationalSourceStorageKey(for session: Session?) -> String {
        let userKey = session.map(normalizedUserId(for:)) ?? "anonymous"
        return "\(SettingsStorageKey.dismissedInformationalSourceKeysPrefix)-\(userKey)"
    }

    private func loadDismissedInformationalSourceKeysForCurrentUser() -> Set<String> {
        let key = dismissedInformationalSourceStorageKey(for: session)
        guard let stored = UserDefaults.standard.array(forKey: key) as? [String] else { return [] }
        return Set(stored)
    }

    private func persistDismissedInformationalSourceKeys() {
        let key = dismissedInformationalSourceStorageKey(for: session)
        let values = Array(dismissedInformationalSourceKeys).sorted()
        UserDefaults.standard.set(values, forKey: key)
    }

    @discardableResult
    private func pushLinkedEventUpdate(_ event: WeekendEvent, linkIndex: Int, persistChanges: Bool = true) async throws -> Bool {
        guard importedEventLinks.indices.contains(linkIndex) else { return false }
        let link = importedEventLinks[linkIndex]
        guard link.writable else {
            authMessage = "Source calendar is read-only. Local changes won't sync back."
            return false
        }

        do {
            try calendarService.upsertExternalEvent(
                link: link,
                from: event,
                intervals: intervals(for: event)
            )
            let updatedFingerprint = fingerprint(for: event)
            importedEventLinks[linkIndex].lastFingerprint = updatedFingerprint
            outboundEchoDebounceUntil[sourceKey(calendarID: link.sourceCalendarID, eventID: link.sourceEventID)] = Date().addingTimeInterval(8)
            if persistChanges {
                persistCaches(scopes: [.importLinks])
            }
            return true
        } catch {
            authMessage = "Couldn't sync back to source calendar. \(error.localizedDescription)"
            throw error
        }
    }

    private static func loadAppTheme() -> AppTheme {
        if let raw = UserDefaults.standard.string(forKey: "weekend-theme"),
           let theme = AppTheme(rawValue: raw) {
            return theme
        }
        if UserDefaults.standard.object(forKey: "weekend-theme-dark") != nil {
            return UserDefaults.standard.bool(forKey: "weekend-theme-dark") ? .dark : .light
        }
        return .system
    }

    private static func loadWeekendConfiguration() -> WeekendConfiguration {
        guard let data = UserDefaults.standard.data(forKey: SettingsStorageKey.weekendConfiguration),
              var decoded = try? JSONDecoder().decode(WeekendConfiguration.self, from: data) else {
            return .defaults
        }
        decoded.normalize()
        return decoded
    }

    private static func loadAnnualLeaveDays() -> [AnnualLeaveDay] {
        guard let data = UserDefaults.standard.data(forKey: SettingsStorageKey.annualLeaveDays),
              let decoded = try? JSONDecoder().decode([AnnualLeaveDay].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.dateKey < $1.dateKey }
    }

    private static func loadPersonalReminders() -> [PersonalReminder] {
        guard let data = UserDefaults.standard.data(forKey: SettingsStorageKey.personalReminders),
              let decoded = try? JSONDecoder().decode([PersonalReminder].self, from: data) else {
            return []
        }
        return sortedPersonalReminders(decoded)
    }

    private func persistWeekendConfiguration() {
        var normalized = weekendConfiguration
        normalized.normalize()
        weekendConfiguration = normalized
        publicHolidayLookupCache.removeAll()
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        UserDefaults.standard.set(data, forKey: SettingsStorageKey.weekendConfiguration)
    }

    private func persistAnnualLeaveDays() {
        annualLeaveDays = annualLeaveDays.sorted { $0.dateKey < $1.dateKey }
        rebuildAnnualLeaveLookup()
        guard let data = try? JSONEncoder().encode(annualLeaveDays) else { return }
        UserDefaults.standard.set(data, forKey: SettingsStorageKey.annualLeaveDays)
    }

    private func persistPersonalReminders() {
        personalReminders = Self.sortedPersonalReminders(personalReminders)
        guard let data = try? JSONEncoder().encode(personalReminders) else { return }
        UserDefaults.standard.set(data, forKey: SettingsStorageKey.personalReminders)
    }

    private func rebuildAnnualLeaveLookup() {
        annualLeaveLookup = Dictionary(uniqueKeysWithValues: annualLeaveDays.map { ($0.dateKey, $0) })
    }

    private static func sortedPersonalReminders(_ reminders: [PersonalReminder]) -> [PersonalReminder] {
        reminders.sorted { lhs, rhs in
            if lhs.repeatsAnnually != rhs.repeatsAnnually {
                return lhs.repeatsAnnually && !rhs.repeatsAnnually
            }
            if lhs.month != rhs.month {
                return lhs.month < rhs.month
            }
            if lhs.day != rhs.day {
                return lhs.day < rhs.day
            }
            let lhsYear = lhs.year ?? Int.max
            let rhsYear = rhs.year ?? Int.max
            if lhsYear != rhsYear {
                return lhsYear < rhsYear
            }
            if lhs.kind.sortOrder != rhs.kind.sortOrder {
                return lhs.kind.sortOrder < rhs.kind.sortOrder
            }
            let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if titleOrder != .orderedSame {
                return titleOrder == .orderedAscending
            }
            return lhs.id < rhs.id
        }
    }

    private func refreshPerformanceSnapshot(force: Bool = false) {
        let now = Date()
        if !force,
           let lastPerformanceSnapshotRefreshAt,
           now.timeIntervalSince(lastPerformanceSnapshotRefreshAt) < 1.5 {
            return
        }
        performanceSnapshot = performanceMonitor.snapshot()
        lastPerformanceSnapshotRefreshAt = now
    }

    func currentPerformanceSnapshot() -> PerformanceSnapshot {
        performanceSnapshot
    }

    @discardableResult
    func capturePerformanceSnapshot() -> PerformanceSnapshot {
        refreshPerformanceSnapshot(force: true)
        return performanceSnapshot
    }

    func scheduleSyncFlush(reason: String, immediate: Bool = false) {
        _ = reason
        guard session != nil, !pendingOperations.isEmpty else { return }
        if syncInProgress {
            return
        }
        if scheduledSyncFlushTask != nil {
            return
        }
        if compactPendingOperations() {
            persistCaches(scopes: [.syncQueue], policy: .debounced)
        }
        scheduledSyncFlushTask = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor in
                    self.scheduledSyncFlushTask = nil
                }
            }
            if !immediate {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
            }
            await self.flushPendingOperations()
        }
    }

    func scheduleNotificationResync(reason: String, immediate: Bool = false) {
        _ = reason
        if !immediate, scheduledNotificationRescheduleTask != nil {
            return
        }
        let signature = notificationRescheduleSignature()
        if !immediate, signature == lastNotificationRescheduleSignature {
            return
        }
        scheduledNotificationRescheduleTask?.cancel()
        scheduledNotificationRescheduleTask = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor in
                    self.scheduledNotificationRescheduleTask = nil
                }
            }
            if !immediate {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
            }
            await self.rescheduleNotifications(force: true)
        }
    }

    private func notificationRescheduleSignature() -> Int {
        var hasher = Hasher()
        hasher.combine(session != nil)
        hasher.combine(notificationPreferences.weeklySummaryEnabled)
        hasher.combine(notificationPreferences.weeklySummaryWeekday)
        hasher.combine(notificationPreferences.weeklySummaryHour)
        hasher.combine(notificationPreferences.weeklySummaryMinute)
        hasher.combine(notificationPreferences.planningNudgeEnabled)
        hasher.combine(notificationPreferences.planningNudgeWeekday)
        hasher.combine(notificationPreferences.planningNudgeHour)
        hasher.combine(notificationPreferences.planningNudgeMinute)
        hasher.combine(notificationPreferences.eventReminderEnabled)
        hasher.combine(notificationPreferences.eventLeadMinutes)
        hasher.combine(notificationPreferences.sundayWrapUpEnabled)
        hasher.combine(notificationPreferences.mondayRecapEnabled)
        hasher.combine(weekendConfiguration.includeFridayEvening)
        hasher.combine(weekendConfiguration.fridayEveningStartHour)
        hasher.combine(weekendConfiguration.fridayEveningStartMinute)
        hasher.combine(weekendConfiguration.includePublicHolidays)
        hasher.combine(weekendConfiguration.publicHolidayRegionPreference.rawValue)
        for day in weekendConfiguration.weekendDays.sorted(by: { $0.naturalSortOrder < $1.naturalSortOrder }) {
            hasher.combine(day.rawValue)
        }
        for leave in annualLeaveDays.sorted(by: { $0.dateKey < $1.dateKey }) {
            hasher.combine(leave.dateKey)
            hasher.combine(leave.note)
        }
        for key in protections.sorted() {
            hasher.combine(key)
        }
        for event in events {
            hasher.combine(event.id)
            hasher.combine(event.weekendKey)
            hasher.combine(event.status)
            hasher.combine(event.startTime)
            hasher.combine(event.endTime)
            hasher.combine(event.days.joined(separator: ","))
        }
        return hasher.finalize()
    }

    private func scheduleRemoteEventCalendarAttributionSync(eventId: String, calendarIDs: Set<String>, userId: String) {
        Task { [weak self] in
            guard let self else { return }
            await self.syncRemoteEventCalendarAttributions(eventId: eventId, calendarIDs: calendarIDs, userId: userId)
        }
    }

    private func scheduleRemoteEventCalendarAttributionRemoval(eventId: String) {
        Task { [weak self] in
            guard let self else { return }
            await self.removeRemoteEventCalendarAttributions(eventId: eventId)
        }
    }

    private func rebuildEventIndexes() {
        var grouped: [String: [WeekendEvent]] = [:]
        for event in events {
            grouped[event.weekendKey, default: []].append(event)
        }
        for weekendKey in grouped.keys {
            grouped[weekendKey]?.sort { lhs, rhs in
                if lhs.startTime == rhs.startTime {
                    return lhs.title < rhs.title
                }
                return lhs.startTime < rhs.startTime
            }
        }
        eventsByWeekendKey = grouped
        rebuildStatusIndex()
        rebuildPendingConflictIndex()
    }

    private func rebuildStatusIndex() {
        let allWeekends = Set(eventsByWeekendKey.keys).union(protections)
        var updated: [String: WeekendStatus] = [:]
        for weekendKey in allWeekends {
            let weekendEvents = (eventsByWeekendKey[weekendKey] ?? [])
                .filter { $0.lifecycleStatus == .planned }
                .filter { !isInformationalImportedEvent($0) }
            let hasTravel = weekendEvents.contains { $0.planType == .travel }
            let hasPlan = weekendEvents.contains { $0.planType == .plan }
            let isProtected = protections.contains(weekendKey)

            if hasTravel {
                updated[weekendKey] = WeekendStatus(type: "travel", label: "Travel plans")
            } else if hasPlan {
                updated[weekendKey] = WeekendStatus(type: "plan", label: "Local plans")
            } else if isProtected {
                updated[weekendKey] = WeekendStatus(type: "protected", label: "Protected")
            } else {
                updated[weekendKey] = WeekendStatus(type: "free", label: "Free")
            }
        }
        statusByWeekendKey = updated
    }

    private func rebuildPendingConflictIndex() {
        let pendingEventIDs = Set(
            importConflicts.compactMap { eventID, state in
                state == .pending ? eventID : nil
            }
        )
        var weekendKeys: Set<String> = []
        for (weekendKey, weekendEvents) in eventsByWeekendKey {
            if weekendEvents.contains(where: {
                pendingEventIDs.contains($0.id) && !isInformationalImportedEvent($0)
            }) {
                weekendKeys.insert(weekendKey)
            }
        }
        pendingConflictWeekendKeys = weekendKeys
    }

    private func rebuildTopQuickAddChipsCache() {
        topQuickAddChipsCache = quickAddChips
            .sorted { lhs, rhs in
                if lhs.usageCount == rhs.usageCount {
                    return lhs.lastUsedAt > rhs.lastUsedAt
                }
                return lhs.usageCount > rhs.usageCount
            }
            .prefix(12)
            .map { $0 }
    }

    private func rebuildPendingOperationIndex() {
        pendingEventOperationIDs = Set(
            pendingOperations.compactMap { operation in
                switch operation.type {
                case .upsertEvent, .deleteEvent:
                    return operation.entityId
                case .setProtection, .appendAudit, .unsupported:
                    return nil
                }
            }
        )
    }

    private func fileName(for scope: CacheScope) -> String {
        switch scope {
        case .calendars: return CacheFile.calendars
        case .selectedCalendarId: return CacheFile.selectedCalendarId
        case .events: return CacheFile.events
        case .protections: return CacheFile.protections
        case .templates: return CacheFile.templates
        case .templateBundles: return CacheFile.templateBundles
        case .quickAddChips: return CacheFile.quickAddChips
        case .syncStates: return CacheFile.syncStates
        case .syncQueue: return CacheFile.syncQueue
        case .audit: return CacheFile.audit
        case .notices: return CacheFile.notices
        case .weekendNotes: return CacheFile.weekendNotes
        case .eventDescriptions: return CacheFile.eventDescriptions
        case .eventCalendarAttributions: return CacheFile.eventCalendarAttributions
        case .importLinks: return CacheFile.importLinks
        case .importSettings: return CacheFile.importSettings
        case .importConflicts: return CacheFile.importConflicts
        }
    }

    private func persistCaches(
        scopes: [CacheScope] = CacheScope.allCases,
        policy: PersistencePolicy = .debounced
    ) {
        for scope in Set(scopes) {
            switch scope {
            case .calendars:
                persistenceCoordinator.scheduleSave(calendars, fileName: fileName(for: scope), policy: policy)
            case .selectedCalendarId:
                persistenceCoordinator.scheduleSave(selectedCalendarId, fileName: fileName(for: scope), policy: policy)
            case .events:
                persistenceCoordinator.scheduleSave(events, fileName: fileName(for: scope), policy: policy)
            case .protections:
                persistenceCoordinator.scheduleSave(Array(protections), fileName: fileName(for: scope), policy: policy)
            case .templates:
                persistenceCoordinator.scheduleSave(planTemplates, fileName: fileName(for: scope), policy: policy)
            case .templateBundles:
                persistenceCoordinator.scheduleSave(planTemplateBundles, fileName: fileName(for: scope), policy: policy)
            case .quickAddChips:
                persistenceCoordinator.scheduleSave(quickAddChips, fileName: fileName(for: scope), policy: policy)
            case .syncStates:
                persistenceCoordinator.scheduleSave(syncStates, fileName: fileName(for: scope), policy: policy)
            case .syncQueue:
                persistenceCoordinator.scheduleSave(pendingOperations, fileName: fileName(for: scope), policy: policy)
            case .audit:
                persistenceCoordinator.scheduleSave(auditEntries, fileName: fileName(for: scope), policy: policy)
            case .notices:
                persistenceCoordinator.scheduleSave(notices, fileName: fileName(for: scope), policy: policy)
            case .weekendNotes:
                persistenceCoordinator.scheduleSave(weekendNotes, fileName: fileName(for: scope), policy: policy)
            case .eventDescriptions:
                persistenceCoordinator.scheduleSave(eventDescriptions, fileName: fileName(for: scope), policy: policy)
            case .eventCalendarAttributions:
                persistenceCoordinator.scheduleSave(eventCalendarAttributions, fileName: fileName(for: scope), policy: policy)
            case .importLinks:
                persistenceCoordinator.scheduleSave(importedEventLinks, fileName: fileName(for: scope), policy: policy)
            case .importSettings:
                persistenceCoordinator.scheduleSave(calendarImportSettings, fileName: fileName(for: scope), policy: policy)
            case .importConflicts:
                persistenceCoordinator.scheduleSave(importConflicts, fileName: fileName(for: scope), policy: policy)
            }
        }
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

private struct PublicHolidayCalculator {
    static func holidays(
        for years: [Int],
        region: SupportedPublicHolidayRegion,
        calendar baseCalendar: Calendar
    ) -> [PublicHolidayInfo] {
        let uniqueYears = Array(Set(years)).sorted()
        var holidays: [PublicHolidayInfo] = []
        for year in uniqueYears {
            switch region {
            case .us:
                holidays.append(contentsOf: usHolidays(year: year, calendar: baseCalendar))
            case .uk:
                holidays.append(contentsOf: ukHolidays(year: year, calendar: baseCalendar))
            }
        }
        return holidays.sorted { $0.dateKey < $1.dateKey }
    }

    private static func usHolidays(year: Int, calendar baseCalendar: Calendar) -> [PublicHolidayInfo] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = baseCalendar.timeZone
        calendar.locale = baseCalendar.locale
        let fixed = [
            ("New Year's Day", month: 1, day: 1),
            ("Juneteenth National Independence Day", month: 6, day: 19),
            ("Independence Day", month: 7, day: 4),
            ("Veterans Day", month: 11, day: 11),
            ("Christmas Day", month: 12, day: 25)
        ]

        var holidays: [PublicHolidayInfo] = []

        for holiday in fixed {
            guard let date = date(year: year, month: holiday.month, day: holiday.day, calendar: calendar) else { continue }
            let observed = observedDateUS(for: date, calendar: calendar)
            let isObservedDifferent = !calendar.isDate(date, inSameDayAs: observed)
            let name = isObservedDifferent ? "\(holiday.0) (observed)" : holiday.0
            holidays.append(
                PublicHolidayInfo(
                    dateKey: CalendarHelper.formatKey(observed),
                    name: name,
                    region: .us
                )
            )
        }

        let variable: [(String, Date?)] = [
            ("Martin Luther King Jr. Day", nthWeekday(year: year, month: 1, weekday: 2, occurrence: 3, calendar: calendar)),
            ("Presidents' Day", nthWeekday(year: year, month: 2, weekday: 2, occurrence: 3, calendar: calendar)),
            ("Memorial Day", lastWeekday(year: year, month: 5, weekday: 2, calendar: calendar)),
            ("Labor Day", nthWeekday(year: year, month: 9, weekday: 2, occurrence: 1, calendar: calendar)),
            ("Columbus Day", nthWeekday(year: year, month: 10, weekday: 2, occurrence: 2, calendar: calendar)),
            ("Thanksgiving Day", nthWeekday(year: year, month: 11, weekday: 5, occurrence: 4, calendar: calendar))
        ]

        for (name, date) in variable {
            guard let date else { continue }
            holidays.append(
                PublicHolidayInfo(
                    dateKey: CalendarHelper.formatKey(date),
                    name: name,
                    region: .us
                )
            )
        }

        return deduplicated(holidays)
    }

    private static func ukHolidays(year: Int, calendar baseCalendar: Calendar) -> [PublicHolidayInfo] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = baseCalendar.timeZone
        calendar.locale = baseCalendar.locale

        var holidays: [PublicHolidayInfo] = []
        var occupiedDateKeys: Set<String> = []

        func addWeekdayHoliday(_ name: String, date: Date?) {
            guard let date else { return }
            let key = CalendarHelper.formatKey(date)
            holidays.append(PublicHolidayInfo(dateKey: key, name: name, region: .uk))
            occupiedDateKeys.insert(key)
        }

        func addSubstituteHoliday(_ name: String, date: Date?) {
            guard let date else { return }
            var candidate = date
            while isWeekend(candidate, calendar: calendar) || occupiedDateKeys.contains(CalendarHelper.formatKey(candidate)) {
                guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else { break }
                candidate = next
            }
            let key = CalendarHelper.formatKey(candidate)
            holidays.append(PublicHolidayInfo(dateKey: key, name: "\(name) (substitute day)", region: .uk))
            occupiedDateKeys.insert(key)
        }

        if let newYear = date(year: year, month: 1, day: 1, calendar: calendar) {
            if isWeekend(newYear, calendar: calendar) {
                addSubstituteHoliday("New Year's Day", date: newYear)
            } else {
                addWeekdayHoliday("New Year's Day", date: newYear)
            }
        }

        if let easterSunday = easterSunday(year: year, calendar: calendar) {
            let goodFriday = calendar.date(byAdding: .day, value: -2, to: easterSunday)
            let easterMonday = calendar.date(byAdding: .day, value: 1, to: easterSunday)
            addWeekdayHoliday("Good Friday", date: goodFriday)
            addWeekdayHoliday("Easter Monday", date: easterMonday)
        }

        addWeekdayHoliday(
            "Early May bank holiday",
            date: nthWeekday(year: year, month: 5, weekday: 2, occurrence: 1, calendar: calendar)
        )
        addWeekdayHoliday(
            "Spring bank holiday",
            date: lastWeekday(year: year, month: 5, weekday: 2, calendar: calendar)
        )
        addWeekdayHoliday(
            "Summer bank holiday",
            date: lastWeekday(year: year, month: 8, weekday: 2, calendar: calendar)
        )

        let fixedLateYear = [
            ("Christmas Day", month: 12, day: 25),
            ("Boxing Day", month: 12, day: 26)
        ]

        // First add fixed holidays that already land on weekdays.
        for item in fixedLateYear {
            guard let dayDate = date(year: year, month: item.month, day: item.day, calendar: calendar) else { continue }
            if !isWeekend(dayDate, calendar: calendar) {
                addWeekdayHoliday(item.0, date: dayDate)
            }
        }

        // Then add substitute days for weekend collisions, respecting occupied weekdays.
        for item in fixedLateYear {
            guard let dayDate = date(year: year, month: item.month, day: item.day, calendar: calendar) else { continue }
            if isWeekend(dayDate, calendar: calendar) {
                addSubstituteHoliday(item.0, date: dayDate)
            }
        }

        return deduplicated(holidays)
    }

    private static func deduplicated(_ holidays: [PublicHolidayInfo]) -> [PublicHolidayInfo] {
        var seen: Set<String> = []
        var result: [PublicHolidayInfo] = []
        for holiday in holidays.sorted(by: { $0.dateKey < $1.dateKey }) {
            let key = "\(holiday.region.rawValue)|\(holiday.dateKey)"
            if seen.insert(key).inserted {
                result.append(holiday)
            }
        }
        return result
    }

    private static func observedDateUS(for date: Date, calendar: Calendar) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        switch weekday {
        case 7:
            return calendar.date(byAdding: .day, value: -1, to: date) ?? date
        case 1:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        default:
            return date
        }
    }

    private static func isWeekend(_ date: Date, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    private static func date(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private static func nthWeekday(
        year: Int,
        month: Int,
        weekday: Int,
        occurrence: Int,
        calendar: Calendar
    ) -> Date? {
        guard occurrence >= 1 else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.weekday = weekday
        components.weekdayOrdinal = occurrence
        return calendar.date(from: components)
    }

    private static func lastWeekday(
        year: Int,
        month: Int,
        weekday: Int,
        calendar: Calendar
    ) -> Date? {
        guard let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let dayRange = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
            return nil
        }

        for day in dayRange.reversed() {
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { continue }
            if calendar.component(.weekday, from: date) == weekday {
                return date
            }
        }
        return nil
    }

    // Meeus/Jones/Butcher Gregorian algorithm.
    private static func easterSunday(year: Int, calendar: Calendar) -> Date? {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
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
    private static let monthOptionsCacheLock = NSLock()
    private static var monthOptionsCacheToken: String?
    private static var monthOptionsCache: [MonthOption] = []
    private static var monthsCacheToken: String?
    private static var monthsCache: [MonthOption] = []
    private static var pastWeekendsCacheToken: String?
    private static var pastWeekendsCache: [WeekendInfo] = []

    static func monthStart(for date: Date) -> Date {
        calendar.date(
            from: calendar.dateComponents([.year, .month], from: date)
        ) ?? date
    }

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

    static func plannerWeekKey(for date: Date) -> String {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let deltaToSaturday: Int
        switch weekday {
        case 7: // Saturday
            deltaToSaturday = 0
        case 1: // Sunday
            deltaToSaturday = -1
        case 2: // Monday
            deltaToSaturday = -2
        case 3: // Tuesday
            deltaToSaturday = -3
        case 4: // Wednesday
            deltaToSaturday = -4
        case 5: // Thursday
            deltaToSaturday = -5
        case 6: // Friday
            deltaToSaturday = 1
        default:
            deltaToSaturday = 0
        }
        let saturday = calendar.date(byAdding: .day, value: deltaToSaturday, to: startOfDay) ?? startOfDay
        return formatKey(saturday)
    }

    static func dateForPlannerDay(_ day: WeekendDay, weekendKey: String) -> Date? {
        guard let saturday = parseKey(weekendKey) else { return nil }
        return dateForWeekendDay(day, saturday: saturday).map { calendar.startOfDay(for: $0) }
    }

    static func plannerDay(for date: Date, weekendKey: String) -> WeekendDay? {
        let normalized = calendar.startOfDay(for: date)
        for day in WeekendDay.allCases {
            guard let candidate = dateForPlannerDay(day, weekendKey: weekendKey) else { continue }
            if calendar.isDate(candidate, inSameDayAs: normalized) {
                return day
            }
        }
        return nil
    }

    static func formatKey(_ date: Date) -> String {
        let components = calendar.dateComponents(in: calendar.timeZone, from: date)
        let year = components.year ?? 0
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func parseKey(_ key: String) -> Date? {
        let normalizedInput = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedKey: String
        if let separator = normalizedInput.firstIndex(of: "T") {
            normalizedKey = String(normalizedInput[..<separator])
        } else {
            normalizedKey = normalizedInput
        }
        let parts = normalizedKey.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return calendar.date(from: components)
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

    static func timeString(from date: Date) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return String(format: "%02d:%02d", hour, minute)
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
        let token = monthOptionsToken(for: date)
        monthOptionsCacheLock.lock()
        if monthsCacheToken == token {
            let cached = monthsCache
            monthOptionsCacheLock.unlock()
            return cached
        }
        monthOptionsCacheLock.unlock()

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

        monthOptionsCacheLock.lock()
        monthsCacheToken = token
        monthsCache = months
        monthOptionsCacheLock.unlock()
        return months
    }

    static func getMonthOptions(startingFrom date: Date = Date()) -> [MonthOption] {
        let token = monthOptionsToken(for: date)
        monthOptionsCacheLock.lock()
        if monthOptionsCacheToken == token {
            let cached = monthOptionsCache
            monthOptionsCacheLock.unlock()
            return cached
        }
        monthOptionsCacheLock.unlock()

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
        monthOptionsCacheLock.lock()
        monthOptionsCacheToken = token
        monthOptionsCache = options
        monthOptionsCacheLock.unlock()
        return options
    }

    private static func monthOptionsToken(for date: Date) -> String {
        let components = calendar.dateComponents(in: calendar.timeZone, from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return "\(year)-\(month)-\(day)|\(calendar.timeZone.identifier)|\(Locale.current.identifier)"
    }

    static func getPast12MonthWeekends(referenceDate: Date = Date()) -> [WeekendInfo] {
        let token = monthOptionsToken(for: referenceDate)
        monthOptionsCacheLock.lock()
        if pastWeekendsCacheToken == token {
            let cached = pastWeekendsCache
            monthOptionsCacheLock.unlock()
            return cached
        }
        monthOptionsCacheLock.unlock()

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

        let filtered = weekends.filter {
            $0.saturday >= rangeStart &&
            isWeekendInPast($0.saturday, referenceDate: referenceDate)
        }
        monthOptionsCacheLock.lock()
        pastWeekendsCacheToken = token
        pastWeekendsCache = filtered
        monthOptionsCacheLock.unlock()
        return filtered
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

    static func weekendIntersection(start: Date, end: Date) -> (weekendKey: String, days: [WeekendDay])? {
        let normalizedEnd = max(end, start.addingTimeInterval(60)).addingTimeInterval(-1)
        var cursor = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: normalizedEnd)
        var matchedWeekendKey: String?

        while cursor <= endDay {
            if let key = weekendKey(for: cursor) {
                matchedWeekendKey = key
                break
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        guard let matchedWeekendKey,
              let saturday = parseKey(matchedWeekendKey) else {
            return nil
        }

        let saturdayStart = calendar.startOfDay(for: saturday)
        let sundayStart = calendar.date(byAdding: .day, value: 1, to: saturdayStart) ?? saturdayStart
        let mondayStart = calendar.date(byAdding: .day, value: 2, to: saturdayStart) ?? sundayStart

        var days: [WeekendDay] = []
        if start < sundayStart && end > saturdayStart {
            days.append(.sat)
        }
        if start < mondayStart && end > sundayStart {
            days.append(.sun)
        }

        guard !days.isEmpty else { return nil }
        return (matchedWeekendKey, days)
    }

    static func intervals(for event: WeekendEvent) -> [DateInterval] {
        guard let saturday = parseKey(event.weekendKey) else { return [] }
        let days = event.dayValues.sorted { $0.plannerRowSortOrder < $1.plannerRowSortOrder }
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
        let sortedDays = days.sorted { $0.plannerRowSortOrder < $1.plannerRowSortOrder }
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
        calendar.date(byAdding: .day, value: day.offsetFromSaturdayAnchor, to: saturday)
    }

    private static func timeComponents(from value: String) -> (hour: Int, minute: Int)? {
        let parts = value.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else { return nil }
        return (hour, minute)
    }
}
