import Foundation
import EventKit

final class CalendarService {
    static let shared = CalendarService()

    private let eventStore: EKEventStore
    private let calendar: Calendar

    init(eventStore: EKEventStore = EKEventStore(), calendar: Calendar = .current) {
        self.eventStore = eventStore
        self.calendar = calendar
    }

    func permissionState() -> CalendarPermissionState {
        CalendarPermissionState(status: EKEventStore.authorizationStatus(for: .event))
    }

    func requestAccess() async -> CalendarPermissionState {
        _ = try? await eventStore.requestFullAccessToEvents()
        return permissionState()
    }

    func listAvailableCalendars() -> [ExternalCalendarSummary] {
        eventStore.calendars(for: .event)
            .map { calendar in
                ExternalCalendarSummary(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    sourceTitle: calendar.source.title,
                    allowsWrites: calendar.allowsContentModifications,
                    colorHex: hexColor(from: calendar.cgColor)
                )
            }
            .sorted { lhs, rhs in
                if lhs.sourceTitle == rhs.sourceTitle {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.sourceTitle.localizedCaseInsensitiveCompare(rhs.sourceTitle) == .orderedAscending
            }
    }

    func fetchEvents(calendarIDs: [String], from: Date, to: Date) -> [ExternalCalendarEvent] {
        guard !calendarIDs.isEmpty else { return [] }

        let calendars = eventStore.calendars(for: .event)
            .filter { calendarIDs.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }

        let predicate = eventStore.predicateForEvents(
            withStart: from,
            end: to,
            calendars: calendars
        )

        return eventStore.events(matching: predicate)
            .compactMap { event in
                guard let sourceEventID = event.eventIdentifier else { return nil }
                return ExternalCalendarEvent(
                    sourceCalendarID: event.calendar.calendarIdentifier,
                    sourceEventID: sourceEventID,
                    sourceCalendarTitle: event.calendar.title,
                    sourceSourceTitle: event.calendar.source.title,
                    title: event.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? event.title ?? "Calendar event"
                        : "Calendar event",
                    startDate: event.startDate,
                    endDate: event.endDate,
                    allDay: event.isAllDay,
                    lastModified: event.lastModifiedDate ?? event.startDate
                )
            }
            .sorted { lhs, rhs in
                if lhs.startDate == rhs.startDate {
                    return lhs.endDate < rhs.endDate
                }
                return lhs.startDate < rhs.startDate
            }
    }

    func upsertExternalEvent(
        link: ImportedEventLink,
        from event: WeekendEvent,
        intervals: [DateInterval]? = nil
    ) throws {
        let targetCalendar = eventStore.calendar(withIdentifier: link.sourceCalendarID)
        guard let targetCalendar else {
            throw CalendarSyncError.calendarNotFound
        }
        guard targetCalendar.allowsContentModifications else {
            throw CalendarSyncError.calendarReadOnly
        }

        let calendarInterval = externalWriteInterval(for: event, intervals: intervals)
        guard calendarInterval.end > calendarInterval.start else {
            throw CalendarSyncError.invalidInterval
        }

        let existing = eventStore.event(withIdentifier: link.sourceEventID)
        let ekEvent = existing ?? EKEvent(eventStore: eventStore)
        ekEvent.calendar = targetCalendar
        ekEvent.title = event.title
        ekEvent.notes = "Synced from The Weekend"
        ekEvent.startDate = calendarInterval.start
        ekEvent.endDate = calendarInterval.end
        ekEvent.isAllDay = event.isAllDay
        try eventStore.save(ekEvent, span: .thisEvent, commit: true)
    }

    func deleteExternalEvent(link: ImportedEventLink) throws {
        guard let targetCalendar = eventStore.calendar(withIdentifier: link.sourceCalendarID) else {
            throw CalendarSyncError.calendarNotFound
        }
        guard targetCalendar.allowsContentModifications else {
            throw CalendarSyncError.calendarReadOnly
        }
        guard let existing = eventStore.event(withIdentifier: link.sourceEventID) else {
            return
        }
        try eventStore.remove(existing, span: .thisEvent, commit: true)
    }

    func observeEventStoreChanges() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let center = NotificationCenter.default
            let token = center.addObserver(
                forName: .EKEventStoreChanged,
                object: eventStore,
                queue: nil
            ) { _ in
                continuation.yield(())
            }
            continuation.onTermination = { _ in
                center.removeObserver(token)
            }
        }
    }

    func conflicts(for intervals: [DateInterval], ignoringEventIdentifiers: Set<String> = []) -> [CalendarConflict] {
        guard !intervals.isEmpty else { return [] }

        var deduplicated: [String: CalendarConflict] = [:]

        for interval in intervals {
            let predicate = eventStore.predicateForEvents(
                withStart: interval.start,
                end: interval.end,
                calendars: nil
            )
            let matches = eventStore.events(matching: predicate)

            for event in matches {
                guard let eventID = event.eventIdentifier else { continue }
                guard !ignoringEventIdentifiers.contains(eventID) else { continue }
                guard event.endDate > interval.start && event.startDate < interval.end else { continue }

                deduplicated[eventID] = CalendarConflict(
                    id: eventID,
                    title: event.title?.isEmpty == false ? event.title ?? "Calendar event" : "Calendar event",
                    startDate: event.startDate,
                    endDate: event.endDate,
                    calendarName: event.calendar.title
                )
            }
        }

        return deduplicated.values.sorted { lhs, rhs in
            if lhs.startDate == rhs.startDate {
                return lhs.endDate < rhs.endDate
            }
            return lhs.startDate < rhs.startDate
        }
    }

    func syncExportedEvents(
        title: String,
        planType: PlanType,
        intervals: [DateInterval],
        existingIdentifiers: [String]
    ) throws -> [String] {
        guard let targetCalendar = eventStore.defaultCalendarForNewEvents else {
            return []
        }

        var savedIdentifiers: [String] = []

        for (index, interval) in intervals.enumerated() {
            let event: EKEvent
            if index < existingIdentifiers.count,
               let existing = eventStore.event(withIdentifier: existingIdentifiers[index]) {
                event = existing
            } else {
                event = EKEvent(eventStore: eventStore)
            }

            event.calendar = targetCalendar
            event.title = title
            event.notes = "Created from The Weekend • \(planType.label)"
            event.startDate = interval.start
            event.endDate = interval.end
            event.isAllDay = isAllDayInterval(interval)

            try eventStore.save(event, span: .thisEvent, commit: false)
            if let eventIdentifier = event.eventIdentifier {
                savedIdentifiers.append(eventIdentifier)
            }
        }

        if existingIdentifiers.count > intervals.count {
            for staleIdentifier in existingIdentifiers.dropFirst(intervals.count) {
                guard let staleEvent = eventStore.event(withIdentifier: staleIdentifier) else { continue }
                try eventStore.remove(staleEvent, span: .thisEvent, commit: false)
            }
        }

        try eventStore.commit()

        return savedIdentifiers
    }

    func removeExportedEvents(identifiers: [String]) throws {
        guard !identifiers.isEmpty else { return }
        for identifier in identifiers {
            guard let existing = eventStore.event(withIdentifier: identifier) else { continue }
            try eventStore.remove(existing, span: .thisEvent, commit: false)
        }
        try eventStore.commit()
    }

    private func isAllDayInterval(_ interval: DateInterval) -> Bool {
        let startOfDay = calendar.startOfDay(for: interval.start)
        let secondsInDay = 86_400.0
        return abs(interval.start.timeIntervalSince(startOfDay)) < 1 &&
            interval.duration >= secondsInDay - 1 &&
            interval.duration <= secondsInDay + 1
    }

    private func externalWriteInterval(for event: WeekendEvent, intervals: [DateInterval]? = nil) -> DateInterval {
        let resolvedIntervals = (intervals?.isEmpty == false ? intervals : CalendarHelper.intervals(for: event)) ?? []
        guard let first = resolvedIntervals.first else {
            return DateInterval(start: Date(), end: Date())
        }
        guard let last = resolvedIntervals.last else {
            return first
        }
        return DateInterval(start: first.start, end: last.end)
    }

    private func hexColor(from cgColor: CGColor) -> String {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        let converted = colorSpace.flatMap { cgColor.converted(to: $0, intent: .defaultIntent, options: nil) }
        guard let components = converted?.components ?? cgColor.components else {
            return "#8E8E93"
        }

        let redComponent: CGFloat
        let greenComponent: CGFloat
        let blueComponent: CGFloat
        if components.count >= 3 {
            redComponent = components[0]
            greenComponent = components[1]
            blueComponent = components[2]
        } else if components.count == 2 {
            redComponent = components[0]
            greenComponent = components[0]
            blueComponent = components[0]
        } else {
            return "#8E8E93"
        }

        let red = Int((redComponent * 255.0).rounded())
        let green = Int((greenComponent * 255.0).rounded())
        let blue = Int((blueComponent * 255.0).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

enum CalendarSyncError: Error {
    case calendarNotFound
    case calendarReadOnly
    case invalidInterval
}
