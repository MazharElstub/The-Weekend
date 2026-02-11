//
//  WeekendPlannerIOSTests.swift
//  WeekendPlannerIOSTests
//
//  Created by Mazhar-Elstub on 07/02/2026.
//

import Foundation
import Testing
@testable import WeekendPlannerIOS

struct WeekendPlannerIOSTests {
    @Test
    func weekendKeyParsesSaturdayAndSunday() {
        let saturday = makeDate(year: 2026, month: 2, day: 14)
        let sunday = makeDate(year: 2026, month: 2, day: 15)
        let monday = makeDate(year: 2026, month: 2, day: 16)

        #expect(CalendarHelper.weekendKey(for: saturday) == "2026-02-14")
        #expect(CalendarHelper.weekendKey(for: sunday) == "2026-02-14")
        #expect(CalendarHelper.weekendKey(for: monday) == nil)
    }

    @Test
    func monthSelectionKeyHandlesPastAndUpcoming() {
        let reference = makeDate(year: 2026, month: 2, day: 15)
        #expect(CalendarHelper.monthSelectionKey(for: "2026-02-14", referenceDate: reference) == "upcoming")
        #expect(CalendarHelper.monthSelectionKey(for: "2026-02-07", referenceDate: reference) == "previous")
        #expect(CalendarHelper.monthSelectionKey(for: "2026-05-02", referenceDate: reference) == "2026-05-01")
    }

    @Test
    func intervalsForWeekendEventBuildsExpectedDayWindows() {
        let event = WeekendEvent(
            id: "event-1",
            title: "Brunch",
            type: PlanType.plan.rawValue,
            weekendKey: "2026-03-14",
            days: [WeekendDay.sat.rawValue, WeekendDay.sun.rawValue],
            startTime: "10:00",
            endTime: "12:00",
            userId: "user-1",
            calendarEventIdentifier: nil
        )

        let intervals = CalendarHelper.intervals(for: event)
        #expect(intervals.count == 2)
        #expect(CalendarHelper.formatKey(intervals[0].start) == "2026-03-14")
        #expect(CalendarHelper.formatKey(intervals[1].start) == "2026-03-15")
    }

    @Test
    func nextWeekendKeyMovesForwardByOneWeekend() {
        #expect(CalendarHelper.nextWeekendKey(after: "2026-04-04") == "2026-04-11")
    }

    @Test
    func weekendEventLifecycleTransitions() {
        let base = WeekendEvent(
            id: "event-1",
            title: "Hike",
            type: PlanType.plan.rawValue,
            weekendKey: "2026-02-14",
            days: [WeekendDay.sat.rawValue],
            startTime: "09:00",
            endTime: "11:00",
            userId: "user-1",
            calendarEventIdentifier: nil
        )

        let completed = base.withLifecycleStatus(.completed, at: makeDate(year: 2026, month: 2, day: 14))
        #expect(completed.lifecycleStatus == .completed)
        #expect(completed.completedAt != nil)
        #expect(completed.cancelledAt == nil)

        let cancelled = completed.withLifecycleStatus(.cancelled, at: makeDate(year: 2026, month: 2, day: 15))
        #expect(cancelled.lifecycleStatus == .cancelled)
        #expect(cancelled.completedAt == nil)
        #expect(cancelled.cancelledAt != nil)

        let reopened = cancelled.withLifecycleStatus(.planned, at: makeDate(year: 2026, month: 2, day: 16))
        #expect(reopened.lifecycleStatus == .planned)
        #expect(reopened.completedAt == nil)
        #expect(reopened.cancelledAt == nil)
    }

    @Test
    @MainActor
    func readinessStateRespectsProtectionAndCoverage() {
        let state = AppState()
        state.events = []
        state.protections = []
        #expect(state.readiness(for: "2026-03-14") == .unplanned)

        state.events = [
            WeekendEvent(
                id: "a",
                title: "Brunch",
                type: PlanType.plan.rawValue,
                weekendKey: "2026-03-14",
                days: [WeekendDay.sat.rawValue],
                startTime: "10:00",
                endTime: "12:00",
                userId: "user-1",
                calendarEventIdentifier: nil
            )
        ]
        #expect(state.readiness(for: "2026-03-14") == .partiallyPlanned)

        state.events.append(
            WeekendEvent(
                id: "b",
                title: "Dinner",
                type: PlanType.plan.rawValue,
                weekendKey: "2026-03-14",
                days: [WeekendDay.sun.rawValue],
                startTime: "18:00",
                endTime: "20:00",
                userId: "user-1",
                calendarEventIdentifier: nil
            )
        )
        #expect(state.readiness(for: "2026-03-14") == .ready)

        state.protections.insert("2026-03-14")
        #expect(state.readiness(for: "2026-03-14") == .protected)
    }

    @Test
    func weeklyReportIncludesStreakAndGoalProgress() {
        let goalService = GoalService()
        let reference = makeDate(year: 2026, month: 3, day: 18)

        let events = [
            WeekendEvent(
                id: "e1",
                title: "Plan 1",
                type: PlanType.plan.rawValue,
                weekendKey: "2026-03-14",
                days: [WeekendDay.sat.rawValue],
                startTime: "09:00",
                endTime: "10:00",
                userId: "user",
                calendarEventIdentifier: nil,
                status: WeekendEventStatus.completed.rawValue,
                completedAt: makeDate(year: 2026, month: 3, day: 15),
                cancelledAt: nil,
                clientUpdatedAt: makeDate(year: 2026, month: 3, day: 12),
                updatedAt: makeDate(year: 2026, month: 3, day: 15),
                createdAt: makeDate(year: 2026, month: 3, day: 12),
                deletedAt: nil
            ),
            WeekendEvent(
                id: "e2",
                title: "Plan 2",
                type: PlanType.plan.rawValue,
                weekendKey: "2026-03-07",
                days: [WeekendDay.sun.rawValue],
                startTime: "11:00",
                endTime: "12:00",
                userId: "user",
                calendarEventIdentifier: nil,
                status: WeekendEventStatus.completed.rawValue,
                completedAt: makeDate(year: 2026, month: 3, day: 8),
                cancelledAt: nil,
                clientUpdatedAt: makeDate(year: 2026, month: 3, day: 6),
                updatedAt: makeDate(year: 2026, month: 3, day: 8),
                createdAt: makeDate(year: 2026, month: 3, day: 6),
                deletedAt: nil
            )
        ]

        let goals = [
            MonthlyGoal(
                id: "goal-1",
                userId: "user",
                monthKey: "2026-03",
                plannedTarget: 6,
                completedTarget: 4,
                createdAt: reference,
                updatedAt: reference
            )
        ]

        let report = goalService.weeklyReportSnapshot(events: events, goals: goals, referenceDate: reference)
        #expect(report.goalMonthKey == "2026-03")
        #expect(report.goalPlannedTarget == 6)
        #expect(report.goalCompletedTarget == 4)
        #expect(report.currentStreak >= 1)
        #expect(report.bestStreak >= report.currentStreak)
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
        return date
    }
}
