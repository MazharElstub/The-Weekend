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
}
