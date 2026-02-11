import Foundation
import UserNotifications

enum NotificationRouteAction {
    case openWeekend(String)
    case addPlan(String)
}

final class NotificationService: NSObject {
    static let shared = NotificationService()

    private let center: UNUserNotificationCenter
    private let calendar: Calendar

    private let appIdentifierPrefix = "weekend."
    private let summaryIdentifier = "weekend.summary.next"
    private let nudgeIdentifier = "weekend.nudge.next"
    private let sundayWrapUpIdentifier = "weekend.wrapup.next"
    private let mondayRecapIdentifier = "weekend.recap.next"
    private let eventIdentifierPrefix = "weekend.event."
    private let maxEventReminderCount = 40

    private let generalCategoryIdentifier = "weekend.category.general"
    private let eventCategoryIdentifier = "weekend.category.event"
    private let actionOpenIdentifier = "weekend.action.open"
    private let actionAddPlanIdentifier = "weekend.action.add"
    private let actionSnoozeIdentifier = "weekend.action.snooze"

    private var routeHandler: ((NotificationRouteAction) -> Void)?
    private var pendingRoutes: [NotificationRouteAction] = []

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    init(center: UNUserNotificationCenter = .current(), calendar: Calendar = .current) {
        self.center = center
        self.calendar = calendar
        super.init()
        self.center.delegate = self
        registerNotificationActions()
    }

    func setRouteHandler(_ handler: @escaping (NotificationRouteAction) -> Void) {
        routeHandler = handler
        if !pendingRoutes.isEmpty {
            let buffered = pendingRoutes
            pendingRoutes.removeAll()
            buffered.forEach(handler)
        }
    }

    func authorizationStatus() async -> NotificationPermissionState {
        let settings = await notificationSettings()
        return NotificationPermissionState(status: settings.authorizationStatus)
    }

    func requestAuthorization() async -> NotificationPermissionState {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // Keep state update resilient even if the request throws.
        }
        return await authorizationStatus()
    }

    func rescheduleNotifications(
        events: [WeekendEvent],
        protections: Set<String>,
        preferences: NotificationPreferences,
        sessionIsActive: Bool,
        now: Date = Date()
    ) async {
        await clearAppManagedNotifications()

        guard sessionIsActive else { return }
        let permissionState = await authorizationStatus()
        guard permissionState.canDeliverNotifications else { return }

        var requests: [UNNotificationRequest] = []
        if let summary = weeklySummaryRequest(events: events, protections: protections, preferences: preferences, now: now) {
            requests.append(summary)
        }
        if let nudge = planningNudgeRequest(events: events, protections: protections, preferences: preferences, now: now) {
            requests.append(nudge)
        }
        if let wrapUp = sundayWrapUpRequest(events: events, preferences: preferences, now: now) {
            requests.append(wrapUp)
        }
        if let recap = mondayRecapRequest(events: events, preferences: preferences, now: now) {
            requests.append(recap)
        }
        requests.append(contentsOf: eventReminderRequests(events: events, preferences: preferences, now: now))

        for request in requests {
            await addRequest(request)
        }
    }

    private func weeklySummaryRequest(
        events: [WeekendEvent],
        protections: Set<String>,
        preferences: NotificationPreferences,
        now: Date
    ) -> UNNotificationRequest? {
        guard preferences.weeklySummaryEnabled else { return nil }
        guard let fireDate = nextWeekdayOccurrence(
            weekday: preferences.weeklySummaryWeekday,
            hour: preferences.weeklySummaryHour,
            minute: preferences.weeklySummaryMinute,
            after: now
        ) else { return nil }
        guard let saturday = nextSaturday(onOrAfter: fireDate) else { return nil }

        let weekendKey = CalendarHelper.formatKey(saturday)
        let weekendEvents = events.filter { $0.weekendKey == weekendKey && $0.lifecycleStatus == .planned }
        let hasProtection = protections.contains(weekendKey)

        let content = UNMutableNotificationContent()
        content.title = "Weekend Summary"
        if weekendEvents.isEmpty {
            content.body = hasProtection
                ? "This weekend is protected. Tap to review your plans."
                : "No plans yet for this weekend. Tap to set one up."
        } else {
            let noun = weekendEvents.count == 1 ? "plan" : "plans"
            content.body = "This weekend has \(weekendEvents.count) \(noun). Tap to review."
        }
        content.sound = .default
        content.categoryIdentifier = generalCategoryIdentifier
        content.userInfo = [
            "type": "summary",
            "weekendKey": weekendKey
        ]

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents(for: fireDate),
            repeats: false
        )
        return UNNotificationRequest(identifier: summaryIdentifier, content: content, trigger: trigger)
    }

    private func planningNudgeRequest(
        events: [WeekendEvent],
        protections: Set<String>,
        preferences: NotificationPreferences,
        now: Date
    ) -> UNNotificationRequest? {
        guard preferences.planningNudgeEnabled else { return nil }
        guard let fireDate = nextWeekdayOccurrence(
            weekday: preferences.planningNudgeWeekday,
            hour: preferences.planningNudgeHour,
            minute: preferences.planningNudgeMinute,
            after: now
        ) else { return nil }
        guard let saturday = nextSaturday(onOrAfter: fireDate) else { return nil }

        let weekendKey = CalendarHelper.formatKey(saturday)
        let hasPlans = events.contains { $0.weekendKey == weekendKey && $0.lifecycleStatus == .planned }
        let hasProtection = protections.contains(weekendKey)
        guard !hasPlans && !hasProtection else { return nil }

        let content = UNMutableNotificationContent()
        content.title = "Weekend Planning Reminder"
        content.body = "Your weekend is still free. Add a plan now."
        content.sound = .default
        content.categoryIdentifier = generalCategoryIdentifier
        content.userInfo = [
            "type": "planning-nudge",
            "weekendKey": weekendKey
        ]

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents(for: fireDate),
            repeats: false
        )
        return UNNotificationRequest(identifier: nudgeIdentifier, content: content, trigger: trigger)
    }

    private func eventReminderRequests(
        events: [WeekendEvent],
        preferences: NotificationPreferences,
        now: Date
    ) -> [UNNotificationRequest] {
        guard preferences.eventReminderEnabled else { return [] }
        let leadMinutes = max(0, preferences.eventLeadMinutes)

        struct EventCandidate {
            let identifier: String
            let content: UNNotificationContent
            let fireDate: Date
        }

        var candidates: [EventCandidate] = []

        for event in events where event.lifecycleStatus == .planned {
            guard let saturday = CalendarHelper.parseKey(event.weekendKey) else { continue }
            for day in event.dayValues {
                guard let dayDate = dateForWeekendDay(day, saturday: saturday) else { continue }
                guard let fireDate = eventReminderDate(
                    for: event,
                    dayDate: dayDate,
                    leadMinutes: leadMinutes
                ) else { continue }
                guard fireDate > now else { continue }

                let content = UNMutableNotificationContent()
                content.title = "Upcoming Plan"
                if event.isAllDay {
                    content.body = "\(event.title) starts on \(day.label)."
                } else {
                    let startLabel = formattedStartTime(for: event, dayDate: dayDate)
                    content.body = "\(event.title) starts \(day.label) at \(startLabel)."
                }
                content.sound = .default
                content.categoryIdentifier = eventCategoryIdentifier
                content.userInfo = [
                    "type": "event",
                    "eventId": event.id,
                    "weekendKey": event.weekendKey,
                    "day": day.rawValue
                ]

                candidates.append(
                    EventCandidate(
                        identifier: "\(eventIdentifierPrefix)\(event.id).\(day.rawValue)",
                        content: content,
                        fireDate: fireDate
                    )
                )
            }
        }

        return candidates
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(maxEventReminderCount)
            .map {
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: dateComponents(for: $0.fireDate),
                    repeats: false
                )
                return UNNotificationRequest(identifier: $0.identifier, content: $0.content, trigger: trigger)
            }
    }

    private func sundayWrapUpRequest(
        events: [WeekendEvent],
        preferences: NotificationPreferences,
        now: Date
    ) -> UNNotificationRequest? {
        guard preferences.sundayWrapUpEnabled else { return nil }
        guard let fireDate = nextWeekdayOccurrence(
            weekday: 1,
            hour: 19,
            minute: 0,
            after: now
        ) else { return nil }
        guard let sundayDate = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: fireDate),
              let saturday = calendar.date(byAdding: .day, value: -1, to: sundayDate) else {
            return nil
        }

        let weekendKey = CalendarHelper.formatKey(calendar.startOfDay(for: saturday))
        let weekendEvents = events.filter { $0.weekendKey == weekendKey }
        let plannedCount = weekendEvents.filter { $0.lifecycleStatus == .planned }.count
        let completedCount = weekendEvents.filter { $0.lifecycleStatus == .completed }.count
        let cancelledCount = weekendEvents.filter { $0.lifecycleStatus == .cancelled }.count

        let content = UNMutableNotificationContent()
        content.title = "Weekend Wrap-up"
        content.body = "Planned \(plannedCount) • Completed \(completedCount) • Cancelled \(cancelledCount)."
        content.sound = .default
        content.categoryIdentifier = generalCategoryIdentifier
        content.userInfo = [
            "type": "sunday-wrap-up",
            "weekendKey": weekendKey
        ]

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents(for: fireDate),
            repeats: false
        )
        return UNNotificationRequest(identifier: sundayWrapUpIdentifier, content: content, trigger: trigger)
    }

    private func mondayRecapRequest(
        events: [WeekendEvent],
        preferences: NotificationPreferences,
        now: Date
    ) -> UNNotificationRequest? {
        guard preferences.mondayRecapEnabled else { return nil }
        guard let fireDate = nextWeekdayOccurrence(
            weekday: 2,
            hour: 9,
            minute: 0,
            after: now
        ) else { return nil }
        guard let mondayDate = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: fireDate),
              let saturday = calendar.date(byAdding: .day, value: -2, to: mondayDate) else {
            return nil
        }

        let weekendKey = CalendarHelper.formatKey(calendar.startOfDay(for: saturday))
        let weekendEvents = events.filter { $0.weekendKey == weekendKey }
        let completedCount = weekendEvents.filter { $0.lifecycleStatus == .completed }.count
        let plannedCount = weekendEvents.filter { $0.lifecycleStatus == .planned }.count

        let content = UNMutableNotificationContent()
        content.title = "Weekend Recap"
        content.body = "You completed \(completedCount) plans. \(plannedCount) stayed open."
        content.sound = .default
        content.categoryIdentifier = generalCategoryIdentifier
        content.userInfo = [
            "type": "monday-recap",
            "weekendKey": weekendKey
        ]

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents(for: fireDate),
            repeats: false
        )
        return UNNotificationRequest(identifier: mondayRecapIdentifier, content: content, trigger: trigger)
    }

    private func eventReminderDate(for event: WeekendEvent, dayDate: Date, leadMinutes: Int) -> Date? {
        if event.isAllDay {
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dayDate)
        }

        let components = event.startTime.split(separator: ":")
        guard components.count >= 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]),
              let startDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayDate) else {
            return nil
        }

        return calendar.date(byAdding: .minute, value: -leadMinutes, to: startDate)
    }

    private func formattedStartTime(for event: WeekendEvent, dayDate: Date) -> String {
        let components = event.startTime.split(separator: ":")
        guard components.count >= 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]),
              let startDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayDate) else {
            return event.startTime
        }
        return timeFormatter.string(from: startDate)
    }

    private func dateForWeekendDay(_ day: WeekendDay, saturday: Date) -> Date? {
        switch day {
        case .sat:
            return calendar.startOfDay(for: saturday)
        case .sun:
            guard let sunday = calendar.date(byAdding: .day, value: 1, to: saturday) else { return nil }
            return calendar.startOfDay(for: sunday)
        }
    }

    private func dateComponents(for date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    }

    private func nextWeekdayOccurrence(weekday: Int, hour: Int, minute: Int, after date: Date) -> Date? {
        var components = DateComponents()
        components.weekday = min(max(weekday, 1), 7)
        components.hour = min(max(hour, 0), 23)
        components.minute = min(max(minute, 0), 59)
        components.second = 0
        return calendar.nextDate(
            after: date,
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }

    private func nextSaturday(onOrAfter date: Date) -> Date? {
        let start = calendar.startOfDay(for: date)
        for offset in 0...7 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            if calendar.component(.weekday, from: candidate) == 7 {
                return candidate
            }
        }
        return nil
    }

    private func clearAppManagedNotifications() async {
        let pendingIDs = await appManagedPendingIdentifiers()
        if !pendingIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: pendingIDs)
        }

        let deliveredIDs = await appManagedDeliveredIdentifiers()
        if !deliveredIDs.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
        }
    }

    private func appManagedPendingIdentifiers() async -> [String] {
        let requests = await pendingRequests()
        return requests
            .map(\.identifier)
            .filter { $0.hasPrefix(appIdentifierPrefix) }
    }

    private func appManagedDeliveredIdentifiers() async -> [String] {
        let notifications = await deliveredNotifications()
        return notifications
            .map(\.request.identifier)
            .filter { $0.hasPrefix(appIdentifierPrefix) }
    }

    private func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private func pendingRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }

    private func deliveredNotifications() async -> [UNNotification] {
        await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { notifications in
                continuation.resume(returning: notifications)
            }
        }
    }

    private func addRequest(_ request: UNNotificationRequest) async {
        await withCheckedContinuation { continuation in
            center.add(request) { _ in
                continuation.resume()
            }
        }
    }

    private func registerNotificationActions() {
        let openAction = UNNotificationAction(
            identifier: actionOpenIdentifier,
            title: "Open weekend",
            options: [.foreground]
        )
        let addAction = UNNotificationAction(
            identifier: actionAddPlanIdentifier,
            title: "Add plan",
            options: [.foreground]
        )
        let snoozeAction = UNNotificationAction(
            identifier: actionSnoozeIdentifier,
            title: "Snooze 1h",
            options: []
        )

        let generalCategory = UNNotificationCategory(
            identifier: generalCategoryIdentifier,
            actions: [openAction, addAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )

        let eventCategory = UNNotificationCategory(
            identifier: eventCategoryIdentifier,
            actions: [openAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([generalCategory, eventCategory])
    }

    private func emitRoute(_ route: NotificationRouteAction) {
        if let routeHandler {
            routeHandler(route)
        } else {
            pendingRoutes.append(route)
        }
    }

    private func weekendKey(from userInfo: [AnyHashable: Any]) -> String? {
        userInfo["weekendKey"] as? String
    }

    private func mutableContentCopy(from content: UNNotificationContent) -> UNMutableNotificationContent {
        let copy = UNMutableNotificationContent()
        copy.title = content.title
        copy.subtitle = content.subtitle
        copy.body = content.body
        copy.badge = content.badge
        copy.sound = content.sound
        copy.userInfo = content.userInfo
        copy.categoryIdentifier = content.categoryIdentifier
        copy.threadIdentifier = content.threadIdentifier
        copy.targetContentIdentifier = content.targetContentIdentifier
        copy.interruptionLevel = content.interruptionLevel
        copy.relevanceScore = content.relevanceScore
        return copy
    }

    private func snooze(_ request: UNNotificationRequest, by seconds: TimeInterval) async {
        let snoozedContent = mutableContentCopy(from: request.content)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(60, seconds), repeats: false)
        let snoozedRequest = UNNotificationRequest(
            identifier: request.identifier,
            content: snoozedContent,
            trigger: trigger
        )
        await addRequest(snoozedRequest)
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let request = response.notification.request

        if response.actionIdentifier == actionSnoozeIdentifier {
            await snooze(request, by: 3600)
            return
        }

        guard let weekendKey = weekendKey(from: request.content.userInfo) else { return }

        switch response.actionIdentifier {
        case actionAddPlanIdentifier:
            emitRoute(.addPlan(weekendKey))
        case actionOpenIdentifier, UNNotificationDefaultActionIdentifier:
            emitRoute(.openWeekend(weekendKey))
        default:
            break
        }
    }
}
