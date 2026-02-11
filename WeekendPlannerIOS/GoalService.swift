import Foundation

struct MonthlyGoal: Identifiable, Codable, Hashable {
    var id: String
    var userId: String
    var monthKey: String
    var plannedTarget: Int
    var completedTarget: Int
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case monthKey = "month_key"
        case plannedTarget = "planned_target"
        case completedTarget = "completed_target"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct StreakSnapshot: Codable, Hashable {
    let current: Int
    let best: Int
}

struct WeeklyReportSnapshot: Codable, Hashable {
    let thisWeekCreated: Int
    let thisWeekCompleted: Int
    let lastWeekCreated: Int
    let lastWeekCompleted: Int
    let currentStreak: Int
    let bestStreak: Int
    let goalMonthKey: String
    let goalPlannedTarget: Int
    let goalCompletedTarget: Int
    let goalPlannedProgress: Int
    let goalCompletedProgress: Int
}

final class GoalService {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func monthKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 1
        return String(format: "%04d-%02d", year, month)
    }

    func streakSnapshot(events: [WeekendEvent], referenceDate: Date = Date()) -> StreakSnapshot {
        let completedWeekendKeys = Set(events
            .filter { $0.lifecycleStatus == .completed }
            .map(\.weekendKey)
        )

        guard !completedWeekendKeys.isEmpty else {
            return StreakSnapshot(current: 0, best: 0)
        }

        let sortedKeys = completedWeekendKeys
            .compactMap { key -> (String, Date)? in
                guard let date = CalendarHelper.parseKey(key) else { return nil }
                return (key, date)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)

        var best = 0
        var running = 0
        var previousDate: Date?

        for key in sortedKeys {
            guard let date = CalendarHelper.parseKey(key) else { continue }
            if let previousDate,
               let delta = calendar.dateComponents([.day], from: previousDate, to: date).day,
               delta == 7 {
                running += 1
            } else {
                running = 1
            }
            best = max(best, running)
            previousDate = date
        }

        var current = 0
        var cursor = latestCompletedWeekendOnOrBefore(referenceDate: referenceDate, completedWeekendKeys: completedWeekendKeys)

        while let weekendDate = cursor {
            let weekendKey = CalendarHelper.formatKey(weekendDate)
            if completedWeekendKeys.contains(weekendKey) {
                current += 1
                cursor = calendar.date(byAdding: .day, value: -7, to: weekendDate)
            } else {
                break
            }
        }

        return StreakSnapshot(current: current, best: best)
    }

    func weeklyReportSnapshot(
        events: [WeekendEvent],
        goals: [MonthlyGoal],
        referenceDate: Date = Date()
    ) -> WeeklyReportSnapshot {
        let thisWeekInterval = weekInterval(containing: referenceDate)
        let lastWeekReference = calendar.date(byAdding: .day, value: -7, to: referenceDate) ?? referenceDate
        let lastWeekInterval = weekInterval(containing: lastWeekReference)

        let thisWeekCreated = events.filter { event in
            guard let createdAt = event.createdAt ?? event.clientUpdatedAt else { return false }
            return thisWeekInterval.contains(createdAt)
        }.count

        let thisWeekCompleted = events.filter { event in
            guard let completedAt = event.completedAt else { return false }
            return thisWeekInterval.contains(completedAt)
        }.count

        let lastWeekCreated = events.filter { event in
            guard let createdAt = event.createdAt ?? event.clientUpdatedAt else { return false }
            return lastWeekInterval.contains(createdAt)
        }.count

        let lastWeekCompleted = events.filter { event in
            guard let completedAt = event.completedAt else { return false }
            return lastWeekInterval.contains(completedAt)
        }.count

        let streak = streakSnapshot(events: events, referenceDate: referenceDate)
        let monthKey = monthKey(for: referenceDate)
        let goal = goals.first { $0.monthKey == monthKey }

        let monthInterval = monthInterval(containing: referenceDate)
        let monthCreated = events.filter { event in
            guard let createdAt = event.createdAt ?? event.clientUpdatedAt else { return false }
            return monthInterval.contains(createdAt)
        }.count
        let monthCompleted = events.filter { event in
            guard let completedAt = event.completedAt else { return false }
            return monthInterval.contains(completedAt)
        }.count

        return WeeklyReportSnapshot(
            thisWeekCreated: thisWeekCreated,
            thisWeekCompleted: thisWeekCompleted,
            lastWeekCreated: lastWeekCreated,
            lastWeekCompleted: lastWeekCompleted,
            currentStreak: streak.current,
            bestStreak: streak.best,
            goalMonthKey: monthKey,
            goalPlannedTarget: goal?.plannedTarget ?? 6,
            goalCompletedTarget: goal?.completedTarget ?? 4,
            goalPlannedProgress: monthCreated,
            goalCompletedProgress: monthCompleted
        )
    }

    private func latestCompletedWeekendOnOrBefore(referenceDate: Date, completedWeekendKeys: Set<String>) -> Date? {
        let thisWeekendKey = CalendarHelper.weekendKey(for: referenceDate) ?? CalendarHelper.nextUpcomingWeekendKey(referenceDate: referenceDate)
        if let thisWeekendKey,
           let thisWeekendDate = CalendarHelper.parseKey(thisWeekendKey),
           thisWeekendDate <= referenceDate,
           completedWeekendKeys.contains(thisWeekendKey) {
            return thisWeekendDate
        }

        let sorted = completedWeekendKeys
            .compactMap(CalendarHelper.parseKey)
            .filter { $0 <= referenceDate }
            .sorted(by: >)
        return sorted.first
    }

    private func weekInterval(containing date: Date) -> DateInterval {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    private func monthInterval(containing date: Date) -> DateInterval {
        let start = calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }
}
