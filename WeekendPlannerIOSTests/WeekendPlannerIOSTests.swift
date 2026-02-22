//
//  WeekendPlannerIOSTests.swift
//  WeekendPlannerIOSTests
//
//  Created by Mazhar-Elstub on 07/02/2026.
//

import Foundation
import Supabase
import Testing
import UserNotifications
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
    func plannerWeekKeyAnchorsDaysToSaturdayWeek() {
        let friday = makeDate(year: 2026, month: 2, day: 13)
        let saturday = makeDate(year: 2026, month: 2, day: 14)
        let monday = makeDate(year: 2026, month: 2, day: 16)

        #expect(CalendarHelper.plannerWeekKey(for: friday) == "2026-02-14")
        #expect(CalendarHelper.plannerWeekKey(for: saturday) == "2026-02-14")
        #expect(CalendarHelper.plannerWeekKey(for: monday) == "2026-02-14")
    }

    @Test
    func monthSelectionKeyHandlesPastAndUpcoming() {
        let reference = makeDate(year: 2026, month: 2, day: 15)
        #expect(CalendarHelper.monthSelectionKey(for: "2026-02-14", referenceDate: reference) == "upcoming")
        #expect(CalendarHelper.monthSelectionKey(for: "2026-02-07", referenceDate: reference) == "historical")
        #expect(CalendarHelper.monthSelectionKey(for: "2026-05-02", referenceDate: reference) == "2026-05-01")
    }

    @Test
    @MainActor
    func annualLeaveWithoutWeekendAdjacencyAttachesToNextWeekendDisplay() {
        let state = AppState()
        resetAnnualLeaveContext(state)
        state.addAnnualLeaveDay(makeDate(year: 2026, month: 2, day: 18), note: "AL")

        let previousWeekendReasons = state.offDayReasons(for: "2026-02-14", day: .wed)
        let nextWeekendReasons = state.offDayReasons(for: "2026-02-21", day: .wed)

        #expect(!containsAnnualLeave(previousWeekendReasons))
        #expect(containsAnnualLeave(nextWeekendReasons))
    }

    @Test
    @MainActor
    func adjacentMondayTuesdayAnnualLeaveStaysWithPreviousWeekendAndDelaysHistory() {
        let state = AppState()
        resetAnnualLeaveContext(state)
        state.addAnnualLeaveRange(
            from: makeDate(year: 2026, month: 2, day: 16),
            to: makeDate(year: 2026, month: 2, day: 17),
            note: "Bridge leave"
        )

        #expect(containsAnnualLeave(state.offDayReasons(for: "2026-02-14", day: .mon)))
        #expect(containsAnnualLeave(state.offDayReasons(for: "2026-02-14", day: .tue)))
        #expect(!containsAnnualLeave(state.offDayReasons(for: "2026-02-21", day: .mon)))

        #expect(!state.isWeekendInPast("2026-02-14", referenceDate: makeDate(year: 2026, month: 2, day: 17)))
        #expect(state.isWeekendInPast("2026-02-14", referenceDate: makeDate(year: 2026, month: 2, day: 18)))
    }

    @Test
    @MainActor
    func fullWeekAnnualLeaveAttachesToNextWeekendAndLeavesPreviousHistorical() {
        let state = AppState()
        resetAnnualLeaveContext(state)
        state.addAnnualLeaveRange(
            from: makeDate(year: 2026, month: 2, day: 16),
            to: makeDate(year: 2026, month: 2, day: 20),
            note: "Full week"
        )

        #expect(!containsAnnualLeave(state.offDayReasons(for: "2026-02-14", day: .mon)))
        #expect(!containsAnnualLeave(state.offDayReasons(for: "2026-02-14", day: .thu)))
        #expect(containsAnnualLeave(state.offDayReasons(for: "2026-02-21", day: .mon)))
        #expect(containsAnnualLeave(state.offDayReasons(for: "2026-02-21", day: .fri)))

        #expect(state.isWeekendInPast("2026-02-14", referenceDate: makeDate(year: 2026, month: 2, day: 16)))
    }

    @Test
    @MainActor
    func tuesdayWednesdayWeekend_AssociatesAdjacentMondayToCurrentWindow() {
        let state = AppState()
        resetAnnualLeaveContext(state)
        state.weekendConfiguration = WeekendConfiguration(
            weekendDays: [.tue, .wed],
            includeFridayEvening: false,
            fridayEveningStartHour: 17,
            fridayEveningStartMinute: 0,
            includePublicHolidays: false,
            publicHolidayRegionPreference: .automatic
        )
        state.addAnnualLeaveDay(makeDate(year: 2026, month: 2, day: 16), note: "Bridge")

        #expect(containsAnnualLeave(state.offDayReasons(for: "2026-02-14", day: .mon)))
        #expect(!containsAnnualLeave(state.offDayReasons(for: "2026-02-21", day: .mon)))
    }

    @Test
    @MainActor
    func tuesdayWednesdayWeekend_AssociatesNonAdjacentSundayToNextWindow() {
        let state = AppState()
        resetAnnualLeaveContext(state)
        state.weekendConfiguration = WeekendConfiguration(
            weekendDays: [.tue, .wed],
            includeFridayEvening: false,
            fridayEveningStartHour: 17,
            fridayEveningStartMinute: 0,
            includePublicHolidays: false,
            publicHolidayRegionPreference: .automatic
        )
        state.addAnnualLeaveDay(makeDate(year: 2026, month: 2, day: 15), note: "Single day")

        #expect(!containsAnnualLeave(state.offDayReasons(for: "2026-02-14", day: .sun)))
        #expect(containsAnnualLeave(state.offDayReasons(for: "2026-02-21", day: .sun)))
    }

    @Test
    @MainActor
    func tuesdayWednesdayWeekend_HistoricalCutoffTracksConfiguredWeekendEnd() {
        let state = AppState()
        resetAnnualLeaveContext(state)
        state.weekendConfiguration = WeekendConfiguration(
            weekendDays: [.tue, .wed],
            includeFridayEvening: false,
            fridayEveningStartHour: 17,
            fridayEveningStartMinute: 0,
            includePublicHolidays: false,
            publicHolidayRegionPreference: .automatic
        )

        #expect(!state.isWeekendInPast("2026-02-14", referenceDate: makeDate(year: 2026, month: 2, day: 18)))
        #expect(state.isWeekendInPast("2026-02-14", referenceDate: makeDate(year: 2026, month: 2, day: 19)))
    }

    @Test
    @MainActor
    func visiblePlannerDays_UsesChronologicalOrderWithAssociatedAnnualLeave() {
        let state = AppState()
        resetAnnualLeaveContext(state)
        state.weekendConfiguration = WeekendConfiguration(
            weekendDays: [.sat, .sun],
            includeFridayEvening: true,
            fridayEveningStartHour: 17,
            fridayEveningStartMinute: 0,
            includePublicHolidays: false,
            publicHolidayRegionPreference: .automatic
        )
        state.addAnnualLeaveRange(
            from: makeDate(year: 2026, month: 2, day: 18),
            to: makeDate(year: 2026, month: 2, day: 19),
            note: "AL"
        )

        let visibleDays = state.visiblePlannerDays(for: "2026-02-21", events: [])
        #expect(visibleDays == [.wed, .thu, .fri, .sat, .sun])
    }

    @Test
    @MainActor
    func plannerDisplayDate_UsesAssociatedAnnualLeaveDateForHeaders() {
        let state = AppState()
        resetAnnualLeaveContext(state)
        state.weekendConfiguration = WeekendConfiguration(
            weekendDays: [.sat, .sun],
            includeFridayEvening: true,
            fridayEveningStartHour: 17,
            fridayEveningStartMinute: 0,
            includePublicHolidays: false,
            publicHolidayRegionPreference: .automatic
        )
        state.addAnnualLeaveRange(
            from: makeDate(year: 2026, month: 2, day: 18),
            to: makeDate(year: 2026, month: 2, day: 19),
            note: "AL"
        )

        let wedDate = state.plannerDisplayDate(for: "2026-02-21", day: .wed)
        let satDate = state.plannerDisplayDate(for: "2026-02-21", day: .sat)

        #expect(wedDate.map(CalendarHelper.formatKey) == "2026-02-18")
        #expect(satDate.map(CalendarHelper.formatKey) == "2026-02-21")
    }

    @Test
    @MainActor
    func plannerDisplayWeekKey_UsesAssociatedAnnualLeaveWeekend() {
        let state = AppState()
        resetAnnualLeaveContext(state)
        state.addAnnualLeaveRange(
            from: makeDate(year: 2026, month: 2, day: 18),
            to: makeDate(year: 2026, month: 2, day: 20),
            note: "AL"
        )

        #expect(state.plannerDisplayWeekKey(for: makeDate(year: 2026, month: 2, day: 18)) == "2026-02-21")
        #expect(state.plannerDisplayWeekKey(for: makeDate(year: 2026, month: 2, day: 21)) == "2026-02-21")
    }

    @Test
    @MainActor
    func offDaysSummaryLabel_DoesNotIncludePersonalReminderCount() {
        let state = AppState()
        state.weekendConfiguration = WeekendConfiguration(
            weekendDays: [.sat, .sun],
            includeFridayEvening: false,
            fridayEveningStartHour: 17,
            fridayEveningStartMinute: 0,
            includePublicHolidays: false,
            publicHolidayRegionPreference: .automatic
        )
        state.personalReminders = [
            PersonalReminder(
                id: UUID().uuidString,
                title: "Birthday",
                kind: .birthday,
                month: 3,
                day: 13,
                year: nil,
                repeatsAnnually: true,
                createdAt: Date()
            )
        ]

        let summary = state.offDaysSummaryLabel

        #expect(summary.contains("Sat, Sun"))
        #expect(!summary.localizedCaseInsensitiveContains("reminder"))
    }

    @Test
    @MainActor
    func availableDisplayOffDayOptions_IncludeAssociatedAnnualLeaveContinuously() {
        let state = AppState()
        resetAnnualLeaveContext(state)
        state.addAnnualLeaveRange(
            from: makeDate(year: 2026, month: 2, day: 18),
            to: makeDate(year: 2026, month: 2, day: 20),
            note: "AL"
        )

        let options = state.availableDisplayOffDayOptions(for: "2026-02-21")
        #expect(options.map(\.day) == [.wed, .thu, .fri, .sat, .sun])
        #expect(options.map { CalendarHelper.formatKey($0.date) } == [
            "2026-02-18",
            "2026-02-19",
            "2026-02-20",
            "2026-02-21",
            "2026-02-22"
        ])
    }

    @Test
    @MainActor
    func appStateIntervals_UseAssociatedAnnualLeaveDatesForPlannerEvent() {
        let state = AppState()
        resetAnnualLeaveContext(state)
        state.addAnnualLeaveRange(
            from: makeDate(year: 2026, month: 2, day: 18),
            to: makeDate(year: 2026, month: 2, day: 19),
            note: "AL"
        )
        let event = WeekendEvent(
            id: "event-display-span",
            title: "Span",
            type: PlanType.plan.rawValue,
            weekendKey: "2026-02-21",
            days: [WeekendDay.wed.rawValue, WeekendDay.thu.rawValue, WeekendDay.fri.rawValue, WeekendDay.sat.rawValue, WeekendDay.sun.rawValue],
            startTime: "00:00",
            endTime: "23:59",
            userId: "user-1",
            calendarEventIdentifier: nil
        )

        let intervals = state.intervals(for: event)
        #expect(intervals.count == 5)
        #expect(CalendarHelper.formatKey(intervals.first?.start ?? Date()) == "2026-02-18")
        #expect(CalendarHelper.formatKey(intervals.last?.start ?? Date()) == "2026-02-22")
    }

    @Test
    @MainActor
    func personalReminderOutsideOffDays_AppearsAsSupplementalLine() {
        let state = AppState()
        resetAnnualLeaveContext(state)
        resetPersonalReminders(state)
        state.weekendConfiguration = WeekendConfiguration(
            weekendDays: [.sat, .sun],
            includeFridayEvening: false,
            fridayEveningStartHour: 17,
            fridayEveningStartMinute: 0,
            includePublicHolidays: false,
            publicHolidayRegionPreference: .automatic
        )
        let birthdayDate = makeDate(year: 2026, month: 2, day: 17)
        state.addPersonalReminder(
            title: "Alex",
            kind: .birthday,
            date: birthdayDate,
            repeatsAnnually: true
        )

        let weekendKey = CalendarHelper.plannerWeekKey(for: birthdayDate)
        let visibleDays = state.visiblePlannerDays(for: weekendKey, events: [])
        let supplementalLines = state.supplementalReminderLines(for: weekendKey, events: [])

        #expect(!visibleDays.contains(.tue))
        #expect(supplementalLines.count == 1)
        #expect(supplementalLines.first?.day == .tue)
        #expect(supplementalLines.first?.pills.first?.label == "Birthday: Alex")
    }

    @Test
    @MainActor
    func dismissHolidayInfoPill_RemovesPersonalReminder() {
        let state = AppState()
        resetAnnualLeaveContext(state)
        resetPersonalReminders(state)
        state.weekendConfiguration = WeekendConfiguration(
            weekendDays: [.sat, .sun],
            includeFridayEvening: false,
            fridayEveningStartHour: 17,
            fridayEveningStartMinute: 0,
            includePublicHolidays: false,
            publicHolidayRegionPreference: .automatic
        )
        let reminderDate = makeDate(year: 2026, month: 2, day: 17)
        state.addPersonalReminder(
            title: "Water plants",
            kind: .reminder,
            date: reminderDate,
            repeatsAnnually: false
        )

        let weekendKey = CalendarHelper.plannerWeekKey(for: reminderDate)
        let pills = state.holidayInfoPills(for: weekendKey, day: .tue, events: [])
        let personalPill = pills.first { $0.personalReminderID != nil }

        #expect(personalPill != nil)
        if let personalPill {
            state.dismissHolidayInfoPill(personalPill)
        }
        #expect(state.personalReminders.isEmpty)
    }

    @Test
    @MainActor
    func plannerDisplayDay_MapsAssociatedDatesAcrossWednesdayToSundaySpan() {
        let state = AppState()
        resetAnnualLeaveContext(state)
        state.addAnnualLeaveRange(
            from: makeDate(year: 2026, month: 2, day: 18),
            to: makeDate(year: 2026, month: 2, day: 20),
            note: "AL"
        )

        let weekendKey = "2026-02-21"
        #expect(state.plannerDisplayDay(for: makeDate(year: 2026, month: 2, day: 18), weekendKey: weekendKey) == .wed)
        #expect(state.plannerDisplayDay(for: makeDate(year: 2026, month: 2, day: 19), weekendKey: weekendKey) == .thu)
        #expect(state.plannerDisplayDay(for: makeDate(year: 2026, month: 2, day: 20), weekendKey: weekendKey) == .fri)
        #expect(state.plannerDisplayDay(for: makeDate(year: 2026, month: 2, day: 21), weekendKey: weekendKey) == .sat)
        #expect(state.plannerDisplayDay(for: makeDate(year: 2026, month: 2, day: 22), weekendKey: weekendKey) == .sun)
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
    func intervalsSupportFridayAndMondayPlannerDays() {
        let event = WeekendEvent(
            id: "event-2",
            title: "Extended break",
            type: PlanType.plan.rawValue,
            weekendKey: "2026-02-14",
            days: [WeekendDay.fri.rawValue, WeekendDay.mon.rawValue],
            startTime: "09:00",
            endTime: "11:00",
            userId: "user-1",
            calendarEventIdentifier: nil
        )

        let intervals = CalendarHelper.intervals(for: event)
        #expect(intervals.count == 2)
        #expect(CalendarHelper.formatKey(intervals[0].start) == "2026-02-13")
        #expect(CalendarHelper.formatKey(intervals[1].start) == "2026-02-16")
    }

    @Test
    func nextWeekendKeyMovesForwardByOneWeekend() {
        #expect(CalendarHelper.nextWeekendKey(after: "2026-04-04") == "2026-04-11")
    }

    @Test
    @MainActor
    func starterFromLastWeekendSelectsMostRecentWeekendThenEarliestTime() {
        let state = AppState()
        state.events = [
            WeekendEvent(
                id: "older",
                title: "Older",
                type: PlanType.plan.rawValue,
                weekendKey: "2026-02-28",
                days: [WeekendDay.sat.rawValue],
                startTime: "08:00",
                endTime: "09:00",
                userId: "user-1",
                calendarEventIdentifier: nil
            ),
            WeekendEvent(
                id: "latest-late",
                title: "Later slot",
                type: PlanType.plan.rawValue,
                weekendKey: "2026-03-07",
                days: [WeekendDay.sat.rawValue],
                startTime: "12:00",
                endTime: "13:00",
                userId: "user-1",
                calendarEventIdentifier: nil
            ),
            WeekendEvent(
                id: "latest-early",
                title: "Earlier slot",
                type: PlanType.plan.rawValue,
                weekendKey: "2026-03-07",
                days: [WeekendDay.sat.rawValue],
                startTime: "09:00",
                endTime: "10:00",
                userId: "user-1",
                calendarEventIdentifier: nil
            )
        ]

        let starter = state.starterFromLastWeekend(referenceDate: makeDate(year: 2026, month: 3, day: 14))
        #expect(starter?.id == "latest-early")
    }

    @Test
    @MainActor
    func starterFromSameMonthLastYearSelectsLatestWeekendThenEarliestTime() {
        let state = AppState()
        state.events = [
            WeekendEvent(
                id: "different-month",
                title: "Other",
                type: PlanType.plan.rawValue,
                weekendKey: "2025-07-26",
                days: [WeekendDay.sat.rawValue],
                startTime: "10:00",
                endTime: "11:00",
                userId: "user-1",
                calendarEventIdentifier: nil
            ),
            WeekendEvent(
                id: "same-month-older",
                title: "Older weekend",
                type: PlanType.plan.rawValue,
                weekendKey: "2025-08-02",
                days: [WeekendDay.sat.rawValue],
                startTime: "10:00",
                endTime: "11:00",
                userId: "user-1",
                calendarEventIdentifier: nil
            ),
            WeekendEvent(
                id: "same-month-late",
                title: "Latest weekend late slot",
                type: PlanType.plan.rawValue,
                weekendKey: "2025-08-30",
                days: [WeekendDay.sat.rawValue],
                startTime: "18:00",
                endTime: "19:00",
                userId: "user-1",
                calendarEventIdentifier: nil
            ),
            WeekendEvent(
                id: "same-month-early",
                title: "Latest weekend early slot",
                type: PlanType.plan.rawValue,
                weekendKey: "2025-08-30",
                days: [WeekendDay.sat.rawValue],
                startTime: "08:00",
                endTime: "09:00",
                userId: "user-1",
                calendarEventIdentifier: nil
            )
        ]

        let starter = state.starterFromSameMonthLastYear(referenceDate: makeDate(year: 2026, month: 8, day: 16))
        #expect(starter?.id == "same-month-early")
    }

    @Test
    func weekendIntersectionFindsWeekendDaysInsideInterval() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let start = calendar.date(from: DateComponents(year: 2026, month: 2, day: 14, hour: 9, minute: 0)) ?? Date()
        let end = calendar.date(from: DateComponents(year: 2026, month: 2, day: 15, hour: 11, minute: 0)) ?? Date()

        let intersection = CalendarHelper.weekendIntersection(start: start, end: end)
        #expect(intersection?.weekendKey == "2026-02-14")
        #expect(intersection?.days == [.sat, .sun])
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
    func countdownPhaseBeforeWeekendIsCountingDown() {
        let utc = TimeZone(secondsFromGMT: 0) ?? .current
        let date = makeDate(year: 2026, month: 2, day: 13, hour: 12, minute: 0, timeZone: utc)

        let countdown = WorkweekCountdownState.from(
            date: date,
            timeZone: utc,
            configuration: .defaults
        )

        #expect(countdown.phase == .countingDown)
        #expect(countdown.centerLabel.contains("to weekend"))
        #expect(countdown.weekendStartLabel == "Sat")
    }

    @Test
    func countdownOffDayModeFlag_IsFalseDuringCountingDown() {
        let utc = TimeZone(secondsFromGMT: 0) ?? .current
        let date = makeDate(year: 2026, month: 2, day: 13, hour: 12, minute: 0, timeZone: utc)

        let countdown = WorkweekCountdownState.from(
            date: date,
            timeZone: utc,
            configuration: .defaults
        )

        #expect(!countdown.isOffDayMode)
    }

    @Test
    func countdownOffDayModeFlag_IsTrueDuringBurstAndActive() {
        let utc = TimeZone(secondsFromGMT: 0) ?? .current
        let start = makeDate(year: 2026, month: 2, day: 14, hour: 0, minute: 0, timeZone: utc)
        let afterBurst = start.addingTimeInterval(3)

        let burstCountdown = WorkweekCountdownState.from(
            date: start,
            timeZone: utc,
            configuration: .defaults
        )
        let activeCountdown = WorkweekCountdownState.from(
            date: afterBurst,
            timeZone: utc,
            configuration: .defaults
        )

        #expect(burstCountdown.phase == .weekendBurst)
        #expect(activeCountdown.phase == .weekendActive)
        #expect(burstCountdown.isOffDayMode)
        #expect(activeCountdown.isOffDayMode)
    }

    @Test
    func countdownPhaseAtWeekendStartIsBurst() {
        let utc = TimeZone(secondsFromGMT: 0) ?? .current
        let date = makeDate(year: 2026, month: 2, day: 14, hour: 0, minute: 0, timeZone: utc)

        let countdown = WorkweekCountdownState.from(
            date: date,
            timeZone: utc,
            configuration: .defaults
        )

        #expect(countdown.phase == .weekendBurst)
        #expect(countdown.centerLabel == "Your weekend starts now!")
    }

    @Test
    func countdownPhaseAfterBurstWindowIsWeekendActive() {
        let utc = TimeZone(secondsFromGMT: 0) ?? .current
        let weekendStart = makeDate(year: 2026, month: 2, day: 14, hour: 0, minute: 0, timeZone: utc)
        let date = weekendStart.addingTimeInterval(3)

        let countdown = WorkweekCountdownState.from(
            date: date,
            timeZone: utc,
            configuration: .defaults
        )

        #expect(countdown.phase == .weekendActive)
        #expect(countdown.centerLabel == "Weekend mode is on")
    }

    @Test
    func countdownRespectsFridayEveningStartConfiguration() {
        let utc = TimeZone(secondsFromGMT: 0) ?? .current
        let configuration = WeekendConfiguration(
            weekendDays: [.sat, .sun],
            includeFridayEvening: true,
            fridayEveningStartHour: 17,
            fridayEveningStartMinute: 0,
            includePublicHolidays: true,
            publicHolidayRegionPreference: .automatic
        )
        let beforeStart = makeDate(year: 2026, month: 2, day: 13, hour: 16, minute: 59, timeZone: utc)
        let atStart = makeDate(year: 2026, month: 2, day: 13, hour: 17, minute: 0, timeZone: utc)

        let beforeCountdown = WorkweekCountdownState.from(
            date: beforeStart,
            timeZone: utc,
            configuration: configuration
        )
        let atStartCountdown = WorkweekCountdownState.from(
            date: atStart,
            timeZone: utc,
            configuration: configuration
        )

        #expect(beforeCountdown.phase == .countingDown)
        #expect(beforeCountdown.weekendStartLabel == "Fri")
        #expect(atStartCountdown.phase == .weekendBurst)
    }

    @Test
    func countdownUsesConfiguredWeekendStartDayWhenFridayEveningDisabled() {
        let utc = TimeZone(secondsFromGMT: 0) ?? .current
        let configuration = WeekendConfiguration(
            weekendDays: [.sun],
            includeFridayEvening: false,
            fridayEveningStartHour: 17,
            fridayEveningStartMinute: 0,
            includePublicHolidays: true,
            publicHolidayRegionPreference: .automatic
        )
        let saturdayNoon = makeDate(year: 2026, month: 2, day: 14, hour: 12, minute: 0, timeZone: utc)

        let countdown = WorkweekCountdownState.from(
            date: saturdayNoon,
            timeZone: utc,
            configuration: configuration
        )

        #expect(countdown.phase == .countingDown)
        #expect(countdown.weekendStartLabel == "Sun")
    }

    @Test
    func countdownRespectsConfiguredTimeZone() {
        let utc = TimeZone(secondsFromGMT: 0) ?? .current
        let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? utc
        let absoluteDate = makeDate(year: 2026, month: 2, day: 13, hour: 23, minute: 30, timeZone: utc)

        let utcCountdown = WorkweekCountdownState.from(
            date: absoluteDate,
            timeZone: utc,
            configuration: .defaults
        )
        let tokyoCountdown = WorkweekCountdownState.from(
            date: absoluteDate,
            timeZone: tokyo,
            configuration: .defaults
        )

        #expect(utcCountdown.phase == .countingDown)
        #expect(tokyoCountdown.phase == .weekendActive)
    }

    @Test
    @MainActor
    func countdownWindowContext_UsesAssociatedAnnualLeaveStart() {
        let state = AppState()
        resetAnnualLeaveContext(state)
        state.addAnnualLeaveRange(
            from: makeDate(year: 2026, month: 2, day: 18),
            to: makeDate(year: 2026, month: 2, day: 20),
            note: "AL"
        )

        let utc = TimeZone(secondsFromGMT: 0) ?? .current
        let referenceDate = makeDate(year: 2026, month: 2, day: 17, hour: 12, minute: 0, timeZone: utc)
        let context = state.countdownWindowContext(referenceDate: referenceDate, timeZone: utc)

        #expect(context?.weekendStartLabel == "Wed")
        #expect(CalendarHelper.formatKey(context?.windowStart ?? Date()) == "2026-02-18")
    }

    @Test
    @MainActor
    func countdownPhase_UsesAssociatedAnnualLeaveWindowWhenProvided() {
        let state = AppState()
        resetAnnualLeaveContext(state)
        state.addAnnualLeaveRange(
            from: makeDate(year: 2026, month: 2, day: 18),
            to: makeDate(year: 2026, month: 2, day: 20),
            note: "AL"
        )

        let utc = TimeZone(secondsFromGMT: 0) ?? .current
        let beforeStart = makeDate(year: 2026, month: 2, day: 17, hour: 12, minute: 0, timeZone: utc)
        let start = makeDate(year: 2026, month: 2, day: 18, hour: 0, minute: 0, timeZone: utc)

        let beforeContext = state.countdownWindowContext(referenceDate: beforeStart, timeZone: utc)
        let startContext = state.countdownWindowContext(referenceDate: start, timeZone: utc)

        let beforeCountdown = WorkweekCountdownState.from(
            date: beforeStart,
            timeZone: utc,
            configuration: .defaults,
            countdownWindow: beforeContext
        )
        let atStartCountdown = WorkweekCountdownState.from(
            date: start,
            timeZone: utc,
            configuration: .defaults,
            countdownWindow: startContext
        )

        #expect(beforeCountdown.phase == .countingDown)
        #expect(beforeCountdown.weekendStartLabel == "Wed")
        #expect(atStartCountdown.phase == .weekendBurst)
        #expect(atStartCountdown.weekendStartLabel == "Wed")
    }

    @Test
    @MainActor
    func onboardingCompletionIsScopedPerUser() {
        let state = AppState()
        let userA = "user-a-\(UUID().uuidString.lowercased())"
        let userB = "user-b-\(UUID().uuidString.lowercased())"

        state.markOnboardingCompleted(userId: userA)

        #expect(state.hasCompletedOnboarding(userId: userA))
        #expect(!state.hasCompletedOnboarding(userId: userB))
    }

    @Test
    @MainActor
    func onboardingEvaluationRequiresSignedInUserUnlessOverridden() {
        let state = AppState()
        state.showAuthSplash = false

        state.evaluateOnboardingPresentation()
        #expect(!state.showOnboarding)

        let overrideUser = "user-override-\(UUID().uuidString.lowercased())"
        state.evaluateOnboardingPresentation(userIdOverride: overrideUser)
        #expect(state.showOnboarding)

        state.markOnboardingCompleted(userId: overrideUser)
        state.evaluateOnboardingPresentation(userIdOverride: overrideUser)
        #expect(!state.showOnboarding)
    }

    @Test
    @MainActor
    func presentOnboardingFromSettingsAlwaysShowsReplay() {
        let state = AppState()
        state.showOnboarding = false
        state.showOnboardingChecklist = true

        state.presentOnboardingFromSettings()

        #expect(state.showOnboarding)
        #expect(!state.showOnboardingChecklist)
    }

    @Test
    @MainActor
    func openSettingsDestination_SelectsSettingsTabAndPendingPath() {
        let state = AppState()
        state.selectedTab = .overview
        state.pendingSettingsPath = []

        state.openSettingsDestination(.personalReminders)

        #expect(state.selectedTab == .settings)
        #expect(state.pendingSettingsPath == [.personalReminders])
    }

    @Test
    @MainActor
    func openSettingsPath_SelectsSettingsTabAndSupportsNestedNavigation() {
        let state = AppState()
        state.selectedTab = .overview
        state.pendingSettingsPath = []

        state.openSettingsPath([.dataPrivacy, .advancedDiagnostics])

        #expect(state.selectedTab == .settings)
        #expect(state.pendingSettingsPath == [.dataPrivacy, .advancedDiagnostics])
    }

    @Test
    @MainActor
    func openAdvancedDiagnosticsInSettings_UsesNestedSettingsPath() {
        let state = AppState()
        state.selectedTab = .overview
        state.pendingSettingsPath = []

        state.openAdvancedDiagnosticsInSettings()

        #expect(state.selectedTab == .settings)
        #expect(state.pendingSettingsPath == [.dataPrivacy, .advancedDiagnostics])
    }

    @Test
    @MainActor
    func openOnboardingSettingsStep_HidesChecklistAndUsesSettingsRoutingHelper() {
        let state = AppState()
        state.showOnboardingChecklist = true
        state.selectedTab = .overview
        state.pendingSettingsPath = []

        state.openOnboardingSettingsStep(.offDays)

        #expect(!state.showOnboardingChecklist)
        #expect(state.selectedTab == .settings)
        #expect(state.pendingSettingsPath == [.offDays])
    }

    @Test
    func daySelectionRulesAllowSingleDaySelection() {
        let options = makeOffDayOptions([.fri, .sat, .sun])
        let selection: Set<WeekendDay> = [.sat]
        #expect(AddPlanDaySelectionRules.isContiguousSelection(selection, available: options))
    }

    @Test
    func daySelectionRulesAllowAdjacentExtension() {
        let options = makeOffDayOptions([.fri, .sat, .sun])
        let selection: Set<WeekendDay> = [.sat]
        let allowed = AddPlanDaySelectionRules.isActionAllowed(
            currentSelection: selection,
            day: .sun,
            action: .add,
            available: options
        )
        #expect(allowed)
    }

    @Test
    func daySelectionRulesBlockNonAdjacentSelection() {
        let options = makeOffDayOptions([.fri, .sat, .sun])
        let selection: Set<WeekendDay> = [.fri, .sun]
        #expect(!AddPlanDaySelectionRules.isContiguousSelection(selection, available: options))
    }

    @Test
    func daySelectionRulesAllowRemovingEdgeDay() {
        let options = makeOffDayOptions([.fri, .sat, .sun])
        let selection: Set<WeekendDay> = [.fri, .sat, .sun]
        let allowed = AddPlanDaySelectionRules.isActionAllowed(
            currentSelection: selection,
            day: .sun,
            action: .remove,
            available: options
        )
        #expect(allowed)
    }

    @Test
    func daySelectionRulesBlockRemovingMiddleDay() {
        let options = makeOffDayOptions([.fri, .sat, .sun])
        let selection: Set<WeekendDay> = [.fri, .sat, .sun]
        let allowed = AddPlanDaySelectionRules.isActionAllowed(
            currentSelection: selection,
            day: .sat,
            action: .remove,
            available: options
        )
        #expect(!allowed)
    }

    @Test
    func daySelectionRulesTreatAssociatedWednesdayToSundayAsContiguous() {
        let options: [OffDayOption] = [
            OffDayOption(day: .wed, date: makeDate(year: 2026, month: 2, day: 18), reasons: [.annualLeave(note: "AL")]),
            OffDayOption(day: .thu, date: makeDate(year: 2026, month: 2, day: 19), reasons: [.annualLeave(note: "AL")]),
            OffDayOption(day: .fri, date: makeDate(year: 2026, month: 2, day: 20), reasons: [.annualLeave(note: "AL")]),
            OffDayOption(day: .sat, date: makeDate(year: 2026, month: 2, day: 21), reasons: [.weekend(day: .sat)]),
            OffDayOption(day: .sun, date: makeDate(year: 2026, month: 2, day: 22), reasons: [.weekend(day: .sun)])
        ]

        let selection: Set<WeekendDay> = [.wed, .thu, .fri, .sat, .sun]
        #expect(AddPlanDaySelectionRules.isContiguousSelection(selection, available: options))
    }

    @Test
    @MainActor
    func readinessStateRespectsProtectionAndCoverage() {
        let state = AppState()
        state.weekendConfiguration = .defaults
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
    @MainActor
    func conflictAcknowledgementTransitionsPendingState() {
        let state = AppState()
        let eventID = "imported-event"
        state.importConflicts[eventID] = .pending

        state.acknowledgeConflict(eventId: eventID)

        #expect(state.importConflictState(for: eventID) == .acknowledged)
    }

    @Test
    @MainActor
    func eventCalendarAttributionFallsBackToPrimaryCalendar() {
        let state = AppState()
        state.selectedCalendarId = "calendar-a"
        state.events = [
            WeekendEvent(
                id: "event-1",
                title: "Dinner",
                type: PlanType.plan.rawValue,
                calendarId: "calendar-a",
                weekendKey: "2026-03-14",
                days: [WeekendDay.sat.rawValue],
                startTime: "19:00",
                endTime: "21:00",
                userId: "user-1",
                calendarEventIdentifier: nil
            )
        ]
        state.eventCalendarAttributions = [:]

        #expect(state.eventCalendarIDs(for: "event-1") == ["calendar-a"])
    }

    @Test
    func weeklyReportIncludesWeeklyCountsAndStreak() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        calendar.firstWeekday = 1
        let reportService = ReportService(calendar: calendar)
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
                completedAt: makeDate(year: 2026, month: 3, day: 18),
                cancelledAt: nil,
                clientUpdatedAt: makeDate(year: 2026, month: 3, day: 17),
                updatedAt: makeDate(year: 2026, month: 3, day: 18),
                createdAt: makeDate(year: 2026, month: 3, day: 17),
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
                completedAt: makeDate(year: 2026, month: 3, day: 11),
                cancelledAt: nil,
                clientUpdatedAt: makeDate(year: 2026, month: 3, day: 10),
                updatedAt: makeDate(year: 2026, month: 3, day: 11),
                createdAt: makeDate(year: 2026, month: 3, day: 10),
                deletedAt: nil
            )
        ]

        let report = reportService.weeklyReportSnapshot(events: events, referenceDate: reference)
        #expect(report.thisWeekCreated == 1)
        #expect(report.thisWeekCompleted == 1)
        #expect(report.lastWeekCreated == 1)
        #expect(report.lastWeekCompleted == 1)
        #expect(report.currentStreak >= 1)
        #expect(report.bestStreak >= report.currentStreak)
    }

    @Test
    func accountDeletionOwnershipModeRawValuesAreStable() {
        #expect(AccountDeletionOwnershipMode.transfer.rawValue == "transfer")
        #expect(AccountDeletionOwnershipMode.delete.rawValue == "delete")
    }

    @Test
    func userNoticeDecodesExpectedAPIShape() throws {
        let raw = """
        {
          "id": "notice-1",
          "user_id": "user-1",
          "type": "calendar_deleted",
          "title": "Shared calendar removed",
          "message": "\\"Team\\" was removed because the owner deleted their account.",
          "metadata": {
            "reason": "owner_deleted_account",
            "calendar_name": "Team"
          },
          "created_at": "2026-02-15T10:30:00Z",
          "read_at": null
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let notice = try decoder.decode(UserNotice.self, from: Data(raw.utf8))

        #expect(notice.id == "notice-1")
        #expect(notice.userId == "user-1")
        #expect(notice.type == "calendar_deleted")
        #expect(notice.metadata["reason"] == "owner_deleted_account")
        #expect(notice.isUnread)
    }

    @Test
    @MainActor
    func deleteAccountSuccessClearsLocalState() async {
        let state = AppState()
        state.showAuthSplash = false
        state.calendars = [
            PlannerCalendar(
                id: "calendar-1",
                name: "Personal",
                ownerUserId: "user-1",
                shareCode: "ABCD1234",
                maxMembers: 5,
                memberCount: 1,
                createdAt: Date(),
                updatedAt: Date()
            )
        ]
        state.events = [
            WeekendEvent(
                id: "event-1",
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
        state.notices = [
            UserNotice(
                id: "notice-1",
                userId: "user-1",
                type: "calendar_deleted",
                title: "Shared calendar removed",
                message: "Test notice",
                metadata: [:],
                createdAt: Date(),
                readAt: nil
            )
        ]

        let success = await state.deleteAccount(mode: .transfer) {
            DeleteAccountRPCResult(
                deletedUserId: "user-1",
                transferredCalendarCount: 1,
                deletedCalendarCount: 0,
                noticesCreatedCount: 0
            )
        }

        #expect(success)
        #expect(state.showAuthSplash)
        #expect(state.calendars.isEmpty)
        #expect(state.events.isEmpty)
        #expect(state.notices.isEmpty)
        #expect(state.authMessage == "Account deleted permanently.")
    }

    @Test
    @MainActor
    func deleteAccountFailurePreservesCurrentState() async {
        struct ForcedFailure: LocalizedError {
            var errorDescription: String? { "forced failure" }
        }

        let state = AppState()
        state.showAuthSplash = false
        state.events = [
            WeekendEvent(
                id: "event-1",
                title: "Dinner",
                type: PlanType.plan.rawValue,
                weekendKey: "2026-03-14",
                days: [WeekendDay.sun.rawValue],
                startTime: "18:00",
                endTime: "20:00",
                userId: "user-1",
                calendarEventIdentifier: nil
            )
        ]

        let success = await state.deleteAccount(mode: .delete) {
            throw ForcedFailure()
        }

        #expect(!success)
        #expect(!state.showAuthSplash)
        #expect(state.events.count == 1)
        #expect(state.authMessage?.contains("Could not delete account.") == true)
    }

    @Test
    @MainActor
    func sendPasswordResetRequiresEmail() async {
        let state = AppState()

        await state.sendPasswordReset(email: "   ")

        #expect(state.authMessage == "Enter your email to reset your password.")
        #expect(!state.isLoading)
    }

    @Test
    @MainActor
    func sendPasswordResetSuccessShowsConfirmationMessage() async {
        let state = AppState()
        var capturedEmail: String?

        await state.sendPasswordReset(email: "  user@example.com  ") { email in
            capturedEmail = email
        }

        #expect(capturedEmail == "user@example.com")
        #expect(state.authMessage == "If an account exists for this email, a reset link has been sent. Check your inbox and spam folder.")
        #expect(!state.isLoading)
    }

    @Test
    @MainActor
    func sendPasswordResetFailureShowsErrorMessage() async {
        struct ForcedFailure: LocalizedError {
            var errorDescription: String? { "forced failure" }
        }

        let state = AppState()

        await state.sendPasswordReset(email: "user@example.com") { _ in
            throw ForcedFailure()
        }

        #expect(state.authMessage == "forced failure")
        #expect(!state.isLoading)
    }

    @Test
    func persistenceCoordinatorImmediateWriteTouchesOnlyTargetFile() async throws {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent("wp-cache-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDirectory) }

        let store = LocalCacheStore(fileManager: fileManager, directoryURL: tempDirectory)
        let coordinator = PersistenceCoordinator(
            store: store,
            debounceInterval: 0.05,
            queue: DispatchQueue(label: "weekendplanner.tests.persistence.immediate")
        )

        coordinator.scheduleSave(["event-a"], fileName: "events.json", policy: .immediate)
        try await Task.sleep(nanoseconds: 150_000_000)

        let eventsFile = tempDirectory.appendingPathComponent("events.json").path
        let protectionsFile = tempDirectory.appendingPathComponent("protections.json").path
        #expect(fileManager.fileExists(atPath: eventsFile))
        #expect(!fileManager.fileExists(atPath: protectionsFile))
    }

    @Test
    func persistenceCoordinatorDebounceCoalescesLatestValue() async throws {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent("wp-cache-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDirectory) }

        let store = LocalCacheStore(fileManager: fileManager, directoryURL: tempDirectory)
        let coordinator = PersistenceCoordinator(
            store: store,
            debounceInterval: 0.05,
            queue: DispatchQueue(label: "weekendplanner.tests.persistence.debounce")
        )

        coordinator.scheduleSave(["old"], fileName: "queue.json", policy: .debounced)
        coordinator.scheduleSave(["new"], fileName: "queue.json", policy: .debounced)
        try await Task.sleep(nanoseconds: 250_000_000)

        let payload = store.load([String].self, fileName: "queue.json", fallback: [])
        #expect(payload == ["new"])
    }

    @Test
    @MainActor
    func mergedEventsIncludePendingUpsertWhenRemoteIsEmpty() {
        let state = AppState()
        let localEvent = makeEvent(id: "event-1", title: "Local draft", calendarId: "calendar-a")
        let pending = [
            PendingSyncOperation(
                type: .upsertEvent,
                entityId: localEvent.id,
                event: localEvent,
                calendarId: localEvent.calendarId
            )
        ]

        let merged = state.mergedEventsForSelectedCalendar(
            remoteEvents: [],
            selectedCalendarId: "calendar-a",
            pendingOperations: pending
        )

        #expect(merged.map(\.id) == ["event-1"])
        #expect(merged.first?.title == "Local draft")
    }

    @Test
    @MainActor
    func mergedEventsExcludePendingDelete() {
        let state = AppState()
        let remoteEvent = makeEvent(id: "event-1", title: "Remote", calendarId: "calendar-a")
        let pending = [
            PendingSyncOperation(
                type: .deleteEvent,
                entityId: remoteEvent.id,
                calendarId: remoteEvent.calendarId
            )
        ]

        let merged = state.mergedEventsForSelectedCalendar(
            remoteEvents: [remoteEvent],
            selectedCalendarId: "calendar-a",
            pendingOperations: pending
        )

        #expect(merged.isEmpty)
    }

    @Test
    @MainActor
    func mergedEventsPreferPendingLocalUpdateOverRemote() {
        let state = AppState()
        let remoteEvent = makeEvent(id: "event-1", title: "Remote title", calendarId: "calendar-a")
        let localEvent = makeEvent(id: "event-1", title: "Local edited title", calendarId: "calendar-a")
        let pending = [
            PendingSyncOperation(
                type: .upsertEvent,
                entityId: localEvent.id,
                event: localEvent,
                calendarId: localEvent.calendarId
            )
        ]

        let merged = state.mergedEventsForSelectedCalendar(
            remoteEvents: [remoteEvent],
            selectedCalendarId: "calendar-a",
            pendingOperations: pending
        )

        #expect(merged.map(\.id) == ["event-1"])
        #expect(merged.first?.title == "Local edited title")
    }

    @Test
    @MainActor
    func mergedEventsRemovePendingUpsertMovedToAnotherCalendar() {
        let state = AppState()
        let remoteEvent = makeEvent(id: "event-1", title: "Remote title", calendarId: "calendar-a")
        let movedEvent = makeEvent(id: "event-1", title: "Moved", calendarId: "calendar-b")
        let pending = [
            PendingSyncOperation(
                type: .upsertEvent,
                entityId: movedEvent.id,
                event: movedEvent,
                calendarId: movedEvent.calendarId
            )
        ]

        let merged = state.mergedEventsForSelectedCalendar(
            remoteEvents: [remoteEvent],
            selectedCalendarId: "calendar-a",
            pendingOperations: pending
        )

        #expect(merged.isEmpty)
    }

    @Test
    @MainActor
    func syncStateReturnsRetryingWhenPendingOperationHasRetryState() throws {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent("wp-cache-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDirectory) }

        let store = LocalCacheStore(fileManager: fileManager, directoryURL: tempDirectory)
        let event = makeEvent(id: "event-1", calendarId: "calendar-a")
        store.save(
            [
                PendingSyncOperation(
                    type: .upsertEvent,
                    entityId: event.id,
                    event: event,
                    calendarId: event.calendarId
                )
            ],
            fileName: "sync_queue_cache.json"
        )
        store.save(["event-1": SyncState.retrying], fileName: "sync_states_cache.json")

        let coordinator = PersistenceCoordinator(
            store: store,
            debounceInterval: 5,
            queue: DispatchQueue(label: "weekendplanner.tests.syncstate.retrying")
        )
        let state = AppState(localCacheStore: store, persistenceCoordinator: coordinator)

        #expect(state.syncState(for: "event-1") == .retrying)
    }

    @Test
    @MainActor
    func syncStateReturnsPendingWhenQueuedWithoutRetryState() throws {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent("wp-cache-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDirectory) }

        let store = LocalCacheStore(fileManager: fileManager, directoryURL: tempDirectory)
        let event = makeEvent(id: "event-2", calendarId: "calendar-a")
        store.save(
            [
                PendingSyncOperation(
                    type: .upsertEvent,
                    entityId: event.id,
                    event: event,
                    calendarId: event.calendarId
                )
            ],
            fileName: "sync_queue_cache.json"
        )

        let coordinator = PersistenceCoordinator(
            store: store,
            debounceInterval: 5,
            queue: DispatchQueue(label: "weekendplanner.tests.syncstate.pending")
        )
        let state = AppState(localCacheStore: store, persistenceCoordinator: coordinator)

        #expect(state.syncState(for: "event-2") == .pending)
    }

    @Test
    @MainActor
    func syncStateReturnsSyncedWhenNoPendingOperationExists() {
        let state = AppState()
        #expect(state.syncState(for: "no-op-event") == .synced)
    }

    @Test
    @MainActor
    func enqueueOperationPersistsSyncQueueAndStateImmediately() async throws {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent("wp-cache-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDirectory) }

        let store = LocalCacheStore(fileManager: fileManager, directoryURL: tempDirectory)
        let coordinator = PersistenceCoordinator(
            store: store,
            debounceInterval: 5,
            queue: DispatchQueue(label: "weekendplanner.tests.syncstate.persist")
        )
        let state = AppState(localCacheStore: store, persistenceCoordinator: coordinator)
        let event = makeEvent(id: "event-immediate", calendarId: "calendar-a")

        state.enqueueOperation(
            PendingSyncOperation(
                type: .upsertEvent,
                entityId: event.id,
                event: event,
                calendarId: event.calendarId
            )
        )

        try await Task.sleep(nanoseconds: 150_000_000)
        let queue = store.load([PendingSyncOperation].self, fileName: "sync_queue_cache.json", fallback: [])
        let states = store.load([String: SyncState].self, fileName: "sync_states_cache.json", fallback: [:])
        #expect(queue.count == 1)
        #expect(queue.first?.entityId == "event-immediate")
        #expect(states["event-immediate"] == .pending)
    }

    @Test
    @MainActor
    func forceRetryPendingOperationsResetsBackoffAndPersistsQueue() async throws {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent("wp-cache-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDirectory) }

        let store = LocalCacheStore(fileManager: fileManager, directoryURL: tempDirectory)
        let coordinator = PersistenceCoordinator(
            store: store,
            debounceInterval: 5,
            queue: DispatchQueue(label: "weekendplanner.tests.syncstate.force-retry")
        )
        let event = makeEvent(id: "event-force-retry", calendarId: "calendar-a")
        let futureRetryAt = Date().addingTimeInterval(1200)
        store.save(
            [
                PendingSyncOperation(
                    type: .upsertEvent,
                    entityId: event.id,
                    attemptCount: 4,
                    nextAttemptAt: futureRetryAt,
                    event: event,
                    calendarId: event.calendarId
                )
            ],
            fileName: "sync_queue_cache.json"
        )

        let state = AppState(localCacheStore: store, persistenceCoordinator: coordinator)
        let beforeForce = Date()
        state.forceRetryPendingOperations(reason: "tests-force-retry")
        try await Task.sleep(nanoseconds: 200_000_000)

        let queue = store.load([PendingSyncOperation].self, fileName: "sync_queue_cache.json", fallback: [])
        #expect(queue.count == 1)
        #expect(queue[0].entityId == "event-force-retry")
        #expect(queue[0].nextAttemptAt <= Date().addingTimeInterval(1))
        #expect(queue[0].nextAttemptAt >= beforeForce.addingTimeInterval(-1))
    }

    @Test
    @MainActor
    func indexedDerivedStateTracksEventsConflictsAndQuickAddOrdering() {
        let state = AppState()
        state.events = [
            WeekendEvent(
                id: "event-1",
                title: "Dinner",
                type: PlanType.plan.rawValue,
                weekendKey: "2026-03-14",
                days: [WeekendDay.sat.rawValue],
                startTime: "18:00",
                endTime: "20:00",
                userId: "user-1",
                calendarEventIdentifier: nil
            )
        ]

        #expect(state.events(for: "2026-03-14").map(\.id) == ["event-1"])
        #expect(state.status(for: "2026-03-14").type == "plan")

        state.importConflicts = ["event-1": .pending]
        #expect(state.hasPendingImportConflict(weekendKey: "2026-03-14"))
        state.importConflicts = ["event-1": .acknowledged]
        #expect(!state.hasPendingImportConflict(weekendKey: "2026-03-14"))

        state.quickAddChips = [
            QuickAddChip(
                id: "chip-low",
                title: "Coffee",
                type: PlanType.plan.rawValue,
                days: [WeekendDay.sat.rawValue],
                startTime: "09:00",
                endTime: "10:00",
                usageCount: 2,
                lastUsedAt: makeDate(year: 2026, month: 2, day: 1)
            ),
            QuickAddChip(
                id: "chip-high",
                title: "Hike",
                type: PlanType.plan.rawValue,
                days: [WeekendDay.sun.rawValue],
                startTime: "08:00",
                endTime: "10:00",
                usageCount: 8,
                lastUsedAt: makeDate(year: 2026, month: 2, day: 14)
            )
        ]

        #expect(state.topQuickAddChips(limit: 1).first?.id == "chip-high")
    }

    @Test
    func notificationTapResolver_UsesAddPlanForPlanningNudgeDefaultTap() {
        let service = NotificationService(autoConfigure: false)

        let decision = service.resolveTapDecision(
            requestIdentifier: "weekend.nudge.next",
            userInfo: [
                "type": "planning-nudge",
                "weekendKey": "2026-03-14"
            ],
            actionIdentifier: UNNotificationDefaultActionIdentifier
        )

        #expect(decision.payloadType == .planningNudge)
        #expect(decision.routeAction == .addPlan("2026-03-14"))
        #expect(decision.fallbackReason == nil)
    }

    @Test
    func notificationTapResolver_DefaultTapOpensWeekendForNonNudgeNotifications() {
        let service = NotificationService(autoConfigure: false)

        let summaryDecision = service.resolveTapDecision(
            requestIdentifier: "weekend.summary.next",
            userInfo: [
                "type": "summary",
                "weekendKey": "2026-03-21"
            ],
            actionIdentifier: UNNotificationDefaultActionIdentifier
        )
        let eventDecision = service.resolveTapDecision(
            requestIdentifier: "weekend.event.event-1.sat",
            userInfo: [
                "type": "event",
                "weekendKey": "2026-03-21"
            ],
            actionIdentifier: UNNotificationDefaultActionIdentifier
        )

        #expect(summaryDecision.routeAction == .openWeekend("2026-03-21"))
        #expect(eventDecision.routeAction == .openWeekend("2026-03-21"))
    }

    @Test
    func notificationTapResolver_ExplicitActionsOverrideDefaultDestination() {
        let service = NotificationService(autoConfigure: false)

        let addDecision = service.resolveTapDecision(
            requestIdentifier: "weekend.summary.next",
            userInfo: [
                "type": "summary",
                "weekendKey": "2026-03-21"
            ],
            actionIdentifier: "weekend.action.add"
        )
        let openDecision = service.resolveTapDecision(
            requestIdentifier: "weekend.nudge.next",
            userInfo: [
                "type": "planning-nudge",
                "weekendKey": "2026-03-21"
            ],
            actionIdentifier: "weekend.action.open"
        )

        #expect(addDecision.routeAction == .addPlan("2026-03-21"))
        #expect(openDecision.routeAction == .openWeekend("2026-03-21"))
    }

    @Test
    func notificationTapResolver_SnoozeDoesNotEmitNavigationRoute() {
        let service = NotificationService(autoConfigure: false)

        let decision = service.resolveTapDecision(
            requestIdentifier: "weekend.summary.next",
            userInfo: [
                "type": "summary",
                "weekendKey": "2026-03-21"
            ],
            actionIdentifier: "weekend.action.snooze"
        )

        #expect(decision.routeAction == nil)
    }

    @Test
    func notificationTapResolver_FallsBackToUpcomingWeekendForAddPlanWhenPayloadMissingWeekendKey() {
        let service = NotificationService(autoConfigure: false)

        let decision = service.resolveTapDecision(
            requestIdentifier: "weekend.nudge.next",
            userInfo: [
                "type": "planning-nudge"
            ],
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            upcomingWeekendKeyProvider: { "2026-04-04" }
        )

        #expect(decision.routeAction == .addPlan("2026-04-04"))
        #expect(decision.fallbackReason == "missing-weekend-key-used-next-upcoming")
    }

    @Test
    func notificationTapResolver_FallsBackToPlannerMessageForOpenWeekendWhenPayloadMissingWeekendKey() {
        let service = NotificationService(autoConfigure: false)

        let decision = service.resolveTapDecision(
            requestIdentifier: "weekend.summary.next",
            userInfo: [
                "type": "summary"
            ],
            actionIdentifier: UNNotificationDefaultActionIdentifier
        )

        guard case .openPlanner(let message)? = decision.routeAction else {
            Issue.record("Expected openPlanner fallback route.")
            return
        }
        #expect(message == "That notification is no longer actionable. Opening Planner instead.")
        #expect(decision.fallbackReason == "missing-weekend-key-opened-planner")
    }

    @Test
    @MainActor
    func appStateNotificationRouting_DefersRouteWhileAuthSplashShownAndReplaysAfterUnlock() {
        let state = AppState()
        state.session = makeSession()
        state.showAuthSplash = true

        state.handleNotificationRouteAction(.addPlan("2026-05-16"))
        #expect(state.pendingAddPlanWeekendKey == nil)

        state.showAuthSplash = false
        state.replayDeferredNotificationRouteIfNeeded()

        #expect(state.pendingAddPlanWeekendKey == "2026-05-16")
    }

    @Test
    @MainActor
    func appStateNotificationRouting_DefersRouteWhenSessionMissingAndReplaysAfterSessionRestore() {
        let state = AppState()
        state.showAuthSplash = false
        state.session = nil

        state.handleNotificationRouteAction(.openWeekend("2026-05-23"))
        #expect(state.pendingWeekendSelection == nil)

        state.session = makeSession()
        state.replayDeferredNotificationRouteIfNeeded()

        #expect(state.pendingWeekendSelection == "2026-05-23")
    }

    @Test
    @MainActor
    func appStateNotificationRouting_OpenPlannerRouteSetsTransientMessage() {
        let state = AppState()
        state.session = makeSession()
        state.showAuthSplash = false

        state.handleNotificationRouteAction(.openPlanner(message: "Legacy payload"))

        #expect(state.selectedTab == .weekend)
        #expect(state.pendingNotificationMessage == "Legacy payload")
    }

    @Test
    @MainActor
    func shareURLRouting_IgnoresInvalidRoutesAndAcceptsValidPayloadID() {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wp-share-url-\(UUID().uuidString)", isDirectory: true)
        let store = SharedInboxStore(
            appGroupIdentifier: "test.group.invalid",
            fallbackBaseDirectory: tempDirectory
        )
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let payload = IncomingSharePayload(
            id: UUID(),
            url: URL(string: "https://example.com"),
            text: "Read this article",
            sourceAppBundleID: "com.apple.mobilesafari"
        )
        store.save(payload)

        let state = AppState(sharedInboxStore: store)
        state.session = makeSession()
        state.showAuthSplash = false

        state.handleIncomingURL(URL(string: "notweekend://share?id=\(payload.id.uuidString)")!)
        #expect(state.pendingAddPlanWeekendKey == nil)

        state.handleIncomingURL(URL(string: "theweekend://share?id=bad-id")!)
        #expect(state.pendingAddPlanWeekendKey == nil)

        state.handleIncomingURL(URL(string: "theweekend://share?id=\(payload.id.uuidString)")!)
        #expect(state.pendingAddPlanWeekendKey != nil)
        #expect(state.pendingAddPlanPrefill?.title == "Read this article")
        #expect(store.load(id: payload.id) == nil)
    }

    @Test
    @MainActor
    func sharePayloadRouting_SignedInStagesAddPlanPrefillAndClearsStore() {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wp-share-signedin-\(UUID().uuidString)", isDirectory: true)
        let store = SharedInboxStore(
            appGroupIdentifier: "test.group.invalid",
            fallbackBaseDirectory: tempDirectory
        )
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let payload = IncomingSharePayload(
            id: UUID(),
            url: URL(string: "https://www.theweekend.org.uk/plans"),
            text: "Trip ideas\nCheck this one",
            sourceAppBundleID: "com.apple.mobilesafari"
        )
        store.save(payload)

        let state = AppState(sharedInboxStore: store)
        state.session = makeSession()
        state.showAuthSplash = false

        state.handleSharePayload(id: payload.id)

        #expect(state.selectedTab == .weekend)
        #expect(state.pendingAddPlanWeekendKey != nil)
        #expect(state.pendingAddPlanPrefill?.title == "Trip ideas")
        #expect(state.pendingAddPlanPrefill?.details?.contains("https://www.theweekend.org.uk/plans") == true)
        #expect(store.load(id: payload.id) == nil)
    }

    @Test
    @MainActor
    func sharePayloadRouting_DefersWhenSignedOutAndReplaysAfterSignIn() {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wp-share-deferred-\(UUID().uuidString)", isDirectory: true)
        let store = SharedInboxStore(
            appGroupIdentifier: "test.group.invalid",
            fallbackBaseDirectory: tempDirectory
        )
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let payload = IncomingSharePayload(
            id: UUID(),
            url: URL(string: "https://example.com/weekend"),
            text: "Weekend ideas",
            sourceAppBundleID: "com.apple.mobilemail"
        )
        store.save(payload)

        let state = AppState(sharedInboxStore: store)
        state.session = nil
        state.showAuthSplash = false

        state.handleSharePayload(id: payload.id)
        #expect(state.pendingAddPlanWeekendKey == nil)
        #expect(state.pendingAddPlanPrefill == nil)
        #expect(store.load(id: payload.id) != nil)

        state.session = makeSession()
        state.replayDeferredSharePayloadIfNeeded()

        #expect(state.pendingAddPlanWeekendKey != nil)
        #expect(state.pendingAddPlanPrefill?.title == "Weekend ideas")
        #expect(store.load(id: payload.id) == nil)
    }

    @Test
    func sharePrefillMapping_UsesTextThenHostAndBuildsDescription() {
        let textAndURL = IncomingSharePayload(
            id: UUID(),
            url: URL(string: "https://www.example.com/ideas"),
            text: "Plan this weekend\nMore context here",
            sourceAppBundleID: "com.apple.mobilesafari"
        )
        let textAndURLPrefill = AddPlanPrefill.from(payload: textAndURL)
        #expect(textAndURLPrefill?.title == "Plan this weekend")
        #expect(textAndURLPrefill?.details?.contains("More context here") == true)
        #expect(textAndURLPrefill?.details?.contains("https://www.example.com/ideas") == true)

        let urlOnly = IncomingSharePayload(
            id: UUID(),
            url: URL(string: "https://www.apple.com/newsroom"),
            text: nil,
            sourceAppBundleID: "com.apple.mobilesafari"
        )
        let urlOnlyPrefill = AddPlanPrefill.from(payload: urlOnly)
        #expect(urlOnlyPrefill?.title == "apple.com")
        #expect(urlOnlyPrefill?.details == "https://www.apple.com/newsroom")

        let empty = IncomingSharePayload(
            id: UUID(),
            url: nil,
            text: "   \n  ",
            sourceAppBundleID: nil
        )
        #expect(AddPlanPrefill.from(payload: empty) == nil)
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0,
        second: Int = 0,
        timeZone: TimeZone = TimeZone(secondsFromGMT: 0) ?? .current
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute,
                second: second
            )
        ) ?? Date()
        return date
    }

    private func makeOffDayOptions(_ days: [WeekendDay], weekendKey: String = "2026-03-14") -> [OffDayOption] {
        days.compactMap { day in
            guard let date = CalendarHelper.dateForPlannerDay(day, weekendKey: weekendKey) else { return nil }
            return OffDayOption(day: day, date: date, reasons: [.weekend(day: day)])
        }
        .sorted { $0.day.plannerRowSortOrder < $1.day.plannerRowSortOrder }
    }

    private func makeEvent(
        id: String,
        title: String = "Plan",
        calendarId: String? = "calendar-a",
        weekendKey: String = "2026-03-14"
    ) -> WeekendEvent {
        WeekendEvent(
            id: id,
            title: title,
            type: PlanType.plan.rawValue,
            calendarId: calendarId,
            weekendKey: weekendKey,
            days: [WeekendDay.sat.rawValue],
            startTime: "09:00",
            endTime: "10:00",
            userId: "user-1",
            calendarEventIdentifier: nil
        )
    }

    private func makeSession() -> Session {
        let now = Date()
        let user = User(
            id: UUID(),
            appMetadata: [:],
            userMetadata: [:],
            aud: "authenticated",
            email: "tests@example.com",
            createdAt: now,
            updatedAt: now
        )
        return Session(
            accessToken: "test-access-token",
            tokenType: "bearer",
            expiresIn: 3600,
            expiresAt: now.addingTimeInterval(3600).timeIntervalSince1970,
            refreshToken: "test-refresh-token",
            user: user
        )
    }

    private func containsAnnualLeave(_ reasons: [OffDayReason]) -> Bool {
        reasons.contains {
            if case .annualLeave = $0 {
                return true
            }
            return false
        }
    }

    @MainActor
    private func resetAnnualLeaveContext(_ state: AppState) {
        state.weekendConfiguration = .defaults
        for leave in state.annualLeaveDays {
            state.removeAnnualLeaveDay(leave.dateKey)
        }
    }

    @MainActor
    private func resetPersonalReminders(_ state: AppState) {
        for reminder in state.personalReminders {
            state.removePersonalReminder(reminder.id)
        }
    }
}
