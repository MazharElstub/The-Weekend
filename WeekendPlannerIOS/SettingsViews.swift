import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum SettingsDestination: Hashable {
    case account
    case calendars
    case notifications
    case preferences
    case dataPrivacy
    case about
}

struct SettingsHomeView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    NavigationLink(value: SettingsDestination.account) {
                        SettingsNavRow(
                            icon: "person.crop.circle",
                            title: "Account",
                            subtitle: state.session?.user.email ?? "Signed out"
                        )
                    }
                }

                Section("Planning") {
                    NavigationLink(value: SettingsDestination.calendars) {
                        SettingsNavRow(
                            icon: "calendar",
                            title: "Calendars",
                            subtitle: calendarsSubtitle
                        )
                    }
                    NavigationLink(value: SettingsDestination.notifications) {
                        SettingsNavRow(
                            icon: "bell.badge",
                            title: "Notifications",
                            subtitle: notificationsSubtitle
                        )
                    }
                    NavigationLink(value: SettingsDestination.preferences) {
                        SettingsNavRow(
                            icon: "slider.horizontal.3",
                            title: "Preferences",
                            subtitle: preferencesSubtitle
                        )
                    }
                }

                Section("Data & Privacy") {
                    NavigationLink(value: SettingsDestination.dataPrivacy) {
                        SettingsNavRow(
                            icon: "lock.shield",
                            title: "Data & Privacy",
                            subtitle: "Calendar access: \(state.calendarPermissionState.label)"
                        )
                    }
                }

                Section("About") {
                    NavigationLink(value: SettingsDestination.about) {
                        SettingsNavRow(
                            icon: "info.circle",
                            title: "About",
                            subtitle: appVersionSubtitle
                        )
                    }
                }
            }
            .weekendSettingsListStyle()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .account:
                    AccountSettingsView()
                case .calendars:
                    CalendarSettingsView()
                case .notifications:
                    NotificationSettingsView()
                case .preferences:
                    PreferencesSettingsView()
                case .dataPrivacy:
                    DataPrivacySettingsView()
                case .about:
                    AboutSettingsView()
                }
            }
            .task {
                await state.refreshNotificationPermissionState()
                await state.refreshCalendarPermissionState()
                await state.flushPendingOperations()
            }
        }
    }

    private var calendarsSubtitle: String {
        let count = state.calendars.count
        if let selected = selectedCalendar {
            return "\(selected.name) • \(count) calendar\(count == 1 ? "" : "s")"
        }
        return count == 0 ? "No calendars yet" : "\(count) calendar\(count == 1 ? "" : "s")"
    }

    private var notificationsSubtitle: String {
        if !state.notificationPermissionState.canDeliverNotifications {
            return state.notificationPermissionState.label
        }
        let enabledCount = [
            state.notificationPreferences.weeklySummaryEnabled,
            state.notificationPreferences.planningNudgeEnabled,
            state.notificationPreferences.eventReminderEnabled,
            state.notificationPreferences.sundayWrapUpEnabled,
            state.notificationPreferences.mondayRecapEnabled
        ].filter { $0 }.count
        return enabledCount == 0 ? "Enabled • no reminders active" : "Enabled • \(enabledCount) reminder type\(enabledCount == 1 ? "" : "s")"
    }

    private var preferencesSubtitle: String {
        let theme = "\(state.appTheme.label) theme"
        let protection = state.protectionMode == .block ? "Block protected weekends" : "Warn on protected weekends"
        let countdownTimeZone = state.countdownTimeZoneIdentifier == nil ? "System countdown time" : "Custom countdown time"
        return "\(theme) • \(protection) • \(countdownTimeZone)"
    }

    private var appVersionSubtitle: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "Version \(version) (\(build))"
    }

    private var selectedCalendar: PlannerCalendar? {
        guard let selectedId = state.selectedCalendarId else { return nil }
        return state.calendars.first(where: { $0.id == selectedId })
    }
}

struct SettingsNavRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct AccountSettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        List {
            Section {
                LabeledContent("Email", value: state.session?.user.email ?? "Signed out")
            } footer: {
                Text("You are signed in with this account.")
            }
            Section {
                Button("Sign out", role: .destructive) {
                    Task { await state.signOut() }
                }
            }
        }
        .weekendSettingsListStyle()
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CalendarSettingsView: View {
    @EnvironmentObject private var state: AppState

    @State private var qrInviteCalendar: PlannerCalendar?
    @State private var renameCalendarName = ""
    @State private var newCalendarName = ""
    @State private var joinCalendarCode = ""
    @State private var calendarActionMessage: String?

    var body: some View {
        List {
            Section {
                if state.calendars.isEmpty {
                    Text("No calendars yet. Create one to start planning.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Calendar", selection: activeCalendarBinding) {
                        ForEach(state.calendars) { calendar in
                            Text(calendar.name).tag(calendar.id)
                        }
                    }

                    if let selected = selectedCalendar {
                        LabeledContent("Name", value: selected.name)
                        LabeledContent("Share code", value: selected.shareCode)
                        LabeledContent("Members", value: "\(selected.memberCount)/\(selected.maxMembers)")

                        ShareLink(item: inviteShareText(for: selected)) {
                            Label("Share invite code", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            copyShareCode(selected.shareCode)
                            calendarActionMessage = "Share code copied."
                        } label: {
                            Label("Copy invite code", systemImage: "doc.on.doc")
                        }
                        Button {
                            qrInviteCalendar = selected
                        } label: {
                            Label("Show invite QR code", systemImage: "qrcode")
                        }

                        TextField("New name for selected calendar", text: $renameCalendarName)
                            .textInputAutocapitalization(.words)
                        Button("Save calendar name") {
                            Task {
                                let success = await state.renameCalendar(
                                    calendarId: selected.id,
                                    to: renameCalendarName
                                )
                                if success {
                                    renameCalendarName = ""
                                    calendarActionMessage = "Calendar renamed."
                                } else {
                                    calendarActionMessage = state.authMessage ?? "Could not rename calendar."
                                }
                            }
                        }
                        .disabled(renameCalendarName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            } header: {
                Text("Active Calendar")
            } footer: {
                Text("Select the calendar you are currently planning in.")
            }

            Section("Create Calendar") {
                TextField("New calendar name", text: $newCalendarName)
                    .textInputAutocapitalization(.words)
                Button("Create calendar") {
                    Task {
                        let success = await state.createCalendar(name: newCalendarName)
                        if success {
                            newCalendarName = ""
                            calendarActionMessage = "Calendar created."
                        } else {
                            calendarActionMessage = state.authMessage ?? "Could not create calendar."
                        }
                    }
                }
                .disabled(newCalendarName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section {
                TextField("Join with share code", text: $joinCalendarCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Join shared calendar") {
                    Task {
                        let success = await state.joinCalendar(shareCode: joinCalendarCode)
                        if success {
                            joinCalendarCode = ""
                            calendarActionMessage = "Joined shared calendar."
                        } else {
                            calendarActionMessage = state.authMessage ?? "Could not join calendar."
                        }
                    }
                }
                .disabled(joinCalendarCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Join Shared Calendar")
            } footer: {
                Text("Shared calendars support up to 5 collaborators.")
            }

            if let calendarActionMessage {
                Section {
                    Text(calendarActionMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .weekendSettingsListStyle()
        .navigationTitle("Calendars")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $qrInviteCalendar) { calendar in
            CalendarInviteQRSheet(calendar: calendar) { code in
                copyShareCode(code)
                calendarActionMessage = "Share code copied."
            }
        }
    }

    private var selectedCalendar: PlannerCalendar? {
        guard let selectedId = state.selectedCalendarId else { return nil }
        return state.calendars.first(where: { $0.id == selectedId })
    }

    private var activeCalendarBinding: Binding<String> {
        Binding(
            get: { state.selectedCalendarId ?? state.calendars.first?.id ?? "" },
            set: { value in
                Task { await state.switchCalendar(to: value) }
            }
        )
    }

    private func inviteShareText(for calendar: PlannerCalendar) -> String {
        """
        Join my calendar "\(calendar.name)" on The Weekend.
        Share code: \(calendar.shareCode)

        In the app, go to Settings -> Join shared calendar and paste this code.
        """
    }
}

struct NotificationSettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        List {
            Section {
                LabeledContent("Notifications", value: state.notificationPermissionState.label)

                if state.notificationPermissionState == .notDetermined {
                    Button("Enable notifications") {
                        Task { await state.requestNotificationPermissionIfNeeded() }
                    }
                }

                if state.notificationPermissionState == .denied {
                    Button("Open iOS Settings") {
                        openSystemSettings()
                    }
                }
            } header: {
                Text("Status")
            } footer: {
                if !state.notificationPermissionState.canDeliverNotifications {
                    Text("Enable notifications to receive weekend reminders.")
                }
            }

            Section("Weekly Summary") {
                Toggle("Weekly weekend summary", isOn: weeklySummaryEnabledBinding)
                if state.notificationPreferences.weeklySummaryEnabled {
                    Picker("Summary day", selection: weeklySummaryWeekdayBinding) {
                        ForEach(weekdayOptions) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    DatePicker(
                        "Summary time",
                        selection: weeklySummaryTimeBinding,
                        displayedComponents: .hourAndMinute
                    )
                }
            }

            Section("Planning Nudge") {
                Toggle("Planning nudge for free weekends", isOn: planningNudgeEnabledBinding)
                if state.notificationPreferences.planningNudgeEnabled {
                    Picker("Nudge day", selection: planningNudgeWeekdayBinding) {
                        ForEach(weekdayOptions) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    DatePicker(
                        "Nudge time",
                        selection: planningNudgeTimeBinding,
                        displayedComponents: .hourAndMinute
                    )
                }
            }

            Section("Event Reminders") {
                Toggle("Event reminders", isOn: eventReminderEnabledBinding)
                if state.notificationPreferences.eventReminderEnabled {
                    Picker("Remind me before events", selection: eventLeadMinutesBinding) {
                        ForEach(eventLeadOptions, id: \.self) { minutes in
                            Text(leadTimeLabel(for: minutes)).tag(minutes)
                        }
                    }
                }
            }

            Section {
                Toggle("Sunday wrap-up reminder", isOn: sundayWrapUpEnabledBinding)
                Toggle("Monday recap reminder", isOn: mondayRecapEnabledBinding)
            } header: {
                Text("Weekend Lifecycle")
            } footer: {
                Text("Reminder times use your current iPhone time zone.")
            }
        }
        .weekendSettingsListStyle()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }

    private struct WeekdayOption: Identifiable {
        let value: Int
        let label: String
        var id: Int { value }
    }

    private var weekdayOptions: [WeekdayOption] {
        let symbols = Calendar.current.weekdaySymbols
        return symbols.enumerated().map { index, value in
            WeekdayOption(value: index + 1, label: value)
        }
    }

    private var eventLeadOptions: [Int] {
        let base = [15, 30, 60, 90, 120, 180, 240]
        let current = state.notificationPreferences.eventLeadMinutes
        return base.contains(current) ? base : (base + [max(0, current)]).sorted()
    }

    private var weeklySummaryEnabledBinding: Binding<Bool> {
        Binding(
            get: { state.notificationPreferences.weeklySummaryEnabled },
            set: { value in
                state.updateNotificationPreferences { preferences in
                    preferences.weeklySummaryEnabled = value
                }
            }
        )
    }

    private var planningNudgeEnabledBinding: Binding<Bool> {
        Binding(
            get: { state.notificationPreferences.planningNudgeEnabled },
            set: { value in
                state.updateNotificationPreferences { preferences in
                    preferences.planningNudgeEnabled = value
                }
            }
        )
    }

    private var eventReminderEnabledBinding: Binding<Bool> {
        Binding(
            get: { state.notificationPreferences.eventReminderEnabled },
            set: { value in
                state.updateNotificationPreferences { preferences in
                    preferences.eventReminderEnabled = value
                }
            }
        )
    }

    private var sundayWrapUpEnabledBinding: Binding<Bool> {
        Binding(
            get: { state.notificationPreferences.sundayWrapUpEnabled },
            set: { value in
                state.updateNotificationPreferences { preferences in
                    preferences.sundayWrapUpEnabled = value
                }
            }
        )
    }

    private var mondayRecapEnabledBinding: Binding<Bool> {
        Binding(
            get: { state.notificationPreferences.mondayRecapEnabled },
            set: { value in
                state.updateNotificationPreferences { preferences in
                    preferences.mondayRecapEnabled = value
                }
            }
        )
    }

    private var weeklySummaryWeekdayBinding: Binding<Int> {
        Binding(
            get: { state.notificationPreferences.weeklySummaryWeekday },
            set: { value in
                state.updateNotificationPreferences { preferences in
                    preferences.weeklySummaryWeekday = min(max(value, 1), 7)
                }
            }
        )
    }

    private var planningNudgeWeekdayBinding: Binding<Int> {
        Binding(
            get: { state.notificationPreferences.planningNudgeWeekday },
            set: { value in
                state.updateNotificationPreferences { preferences in
                    preferences.planningNudgeWeekday = min(max(value, 1), 7)
                }
            }
        )
    }

    private var eventLeadMinutesBinding: Binding<Int> {
        Binding(
            get: { state.notificationPreferences.eventLeadMinutes },
            set: { value in
                state.updateNotificationPreferences { preferences in
                    preferences.eventLeadMinutes = max(0, value)
                }
            }
        )
    }

    private var weeklySummaryTimeBinding: Binding<Date> {
        Binding(
            get: {
                timeDate(
                    hour: state.notificationPreferences.weeklySummaryHour,
                    minute: state.notificationPreferences.weeklySummaryMinute
                )
            },
            set: { value in
                let components = Calendar.current.dateComponents([.hour, .minute], from: value)
                state.updateNotificationPreferences { preferences in
                    preferences.weeklySummaryHour = components.hour ?? 18
                    preferences.weeklySummaryMinute = components.minute ?? 0
                }
            }
        )
    }

    private var planningNudgeTimeBinding: Binding<Date> {
        Binding(
            get: {
                timeDate(
                    hour: state.notificationPreferences.planningNudgeHour,
                    minute: state.notificationPreferences.planningNudgeMinute
                )
            },
            set: { value in
                let components = Calendar.current.dateComponents([.hour, .minute], from: value)
                state.updateNotificationPreferences { preferences in
                    preferences.planningNudgeHour = components.hour ?? 10
                    preferences.planningNudgeMinute = components.minute ?? 0
                }
            }
        )
    }

    private func timeDate(hour: Int, minute: Int) -> Date {
        let now = Date()
        return Calendar.current.date(
            bySettingHour: min(max(hour, 0), 23),
            minute: min(max(minute, 0), 59),
            second: 0,
            of: now
        ) ?? now
    }

    private func leadTimeLabel(for minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) minutes before"
        }
        if minutes.isMultiple(of: 60) {
            let hours = minutes / 60
            return "\(hours) \(hours == 1 ? "hour" : "hours") before"
        }
        let hours = Double(minutes) / 60.0
        return String(format: "%.1f hours before", hours)
    }
}

struct PreferencesSettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        List {
            Section {
                Picker(
                    "Appearance",
                    selection: Binding(
                        get: { state.appTheme },
                        set: { state.setTheme($0) }
                    )
                ) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                Toggle(
                    "Block new plans on protected weekends",
                    isOn: Binding(
                        get: { state.protectionMode == .block },
                        set: { state.setProtectionMode($0 ? .block : .warn) }
                    )
                )
                NavigationLink {
                    CountdownTimeZoneSettingsView()
                } label: {
                    LabeledContent("Weekend countdown time zone", value: state.countdownTimeZoneDisplayName)
                }
            } footer: {
                Text("Use System appearance to follow iOS styling. Use block mode to prevent adding plans on protected weekends. Choose a custom time zone if you want weekend countdowns to follow a different region.")
            }
        }
        .weekendSettingsListStyle()
        .navigationTitle("Preferences")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CountdownTimeZoneSettingsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private static let allIdentifiers = TimeZone.knownTimeZoneIdentifiers.sorted()

    var body: some View {
        List {
            Section {
                Button {
                    state.setCountdownTimeZoneIdentifier(nil)
                    dismiss()
                } label: {
                    HStack {
                        Text("Use device time zone")
                            .foregroundStyle(.primary)
                        Spacer()
                        if state.countdownTimeZoneIdentifier == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.planBlue)
                        }
                    }
                }
            } footer: {
                Text("If enabled, countdown follows your iPhone's current time zone.")
            }

            Section("Time Zones") {
                ForEach(filteredIdentifiers, id: \.self) { identifier in
                    Button {
                        state.setCountdownTimeZoneIdentifier(identifier)
                        dismiss()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cityLabel(for: identifier))
                                    .foregroundStyle(.primary)
                                Text("\(regionLabel(for: identifier)) • \(gmtOffsetLabel(for: identifier))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if state.countdownTimeZoneIdentifier == identifier {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.planBlue)
                            }
                        }
                    }
                }
            }
        }
        .weekendSettingsListStyle()
        .navigationTitle("Countdown Time Zone")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search city or region")
    }

    private var filteredIdentifiers: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Self.allIdentifiers }
        return Self.allIdentifiers.filter { identifier in
            identifier.localizedCaseInsensitiveContains(query)
                || cityLabel(for: identifier).localizedCaseInsensitiveContains(query)
                || regionLabel(for: identifier).localizedCaseInsensitiveContains(query)
        }
    }

    private func cityLabel(for identifier: String) -> String {
        identifier
            .split(separator: "/")
            .last
            .map { String($0).replacingOccurrences(of: "_", with: " ") }
            ?? identifier
    }

    private func regionLabel(for identifier: String) -> String {
        let components = identifier.split(separator: "/")
        guard components.count > 1 else { return "Region" }
        return components.dropLast().joined(separator: " / ").replacingOccurrences(of: "_", with: " ")
    }

    private func gmtOffsetLabel(for identifier: String) -> String {
        guard let timeZone = TimeZone(identifier: identifier) else { return "GMT" }
        let seconds = timeZone.secondsFromGMT(for: Date())
        let sign = seconds >= 0 ? "+" : "-"
        let absolute = abs(seconds)
        let hours = absolute / 3600
        let minutes = (absolute % 3600) / 60
        return String(format: "GMT%@%02d:%02d", sign, hours, minutes)
    }
}

struct DataPrivacySettingsView: View {
    @EnvironmentObject private var state: AppState

    @AppStorage("settings.show_sync_diagnostics") private var showSyncDiagnostics = false
    @AppStorage("settings.show_activity_history") private var showActivityHistory = false
    @AppStorage("settings.show_weekly_report") private var showWeeklyReport = false

    var body: some View {
        List {
            Section("Calendar Integration") {
                LabeledContent("Status", value: state.calendarPermissionState.label)

                if state.calendarPermissionState == .notDetermined {
                    Button("Enable calendar access") {
                        Task { await state.requestCalendarPermissionIfNeeded() }
                    }
                }

                if state.calendarPermissionState == .denied || state.calendarPermissionState == .restricted {
                    Button("Open iOS Settings") {
                        openSystemSettings()
                    }
                }

                Text("Used for conflict checks and optional Apple Calendar export when saving plans.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Plan Templates") {
                if state.planTemplates.isEmpty {
                    Text("No templates saved yet. Save one from the Add Plan form.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(state.planTemplates.prefix(10)) { template in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name)
                                    .font(.subheadline.weight(.semibold))
                                Text(template.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Delete", role: .destructive) {
                                state.removeTemplate(template)
                            }
                            .font(.caption)
                        }
                    }
                }
            }

            Section {
                DisclosureGroup(isExpanded: $showSyncDiagnostics) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(state.pendingOperations.isEmpty ? "All synced" : "\(state.pendingOperations.count) pending")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                        if state.isSyncing {
                            Text("Sync in progress...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if !state.pendingOperations.isEmpty {
                            Text("Pending changes will retry automatically when connection is available.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Label("Sync diagnostics", systemImage: "arrow.triangle.2.circlepath")
                }

                DisclosureGroup(isExpanded: $showActivityHistory) {
                    if state.auditEntries.isEmpty {
                        Text("No activity yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(state.auditEntries.prefix(12)) { entry in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.action)
                                        .font(.subheadline.weight(.semibold))
                                    Text(auditTimestamp(entry.occurredAt))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.top, 6)
                    }
                } label: {
                    Label("Activity history (30 days)", systemImage: "clock.arrow.circlepath")
                }

                DisclosureGroup(isExpanded: $showWeeklyReport) {
                    let report = state.weeklyReportSnapshot()
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Created this week")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(report.thisWeekCreated)")
                                    .font(.title3.weight(.semibold))
                            }
                            Spacer()
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Completed this week")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(report.thisWeekCompleted)")
                                    .font(.title3.weight(.semibold))
                            }
                        }

                        Text("Last week: \(report.lastWeekCreated) created, \(report.lastWeekCompleted) completed")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            TagPill(text: "Current streak \(report.currentStreak)", color: .planBlue)
                            TagPill(text: "Best \(report.bestStreak)", color: .freeGreen)
                        }

                        Stepper(
                            "Monthly created goal: \(report.goalPlannedTarget)",
                            value: plannedGoalBinding,
                            in: 0...40
                        )
                        Stepper(
                            "Monthly completed goal: \(report.goalCompletedTarget)",
                            value: completedGoalBinding,
                            in: 0...40
                        )

                        Text("Goal progress: \(report.goalPlannedProgress)/\(report.goalPlannedTarget) created • \(report.goalCompletedProgress)/\(report.goalCompletedTarget) completed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 6)
                } label: {
                    Label("Weekly report & goals", systemImage: "chart.bar")
                }
            } header: {
                Text("Advanced")
            } footer: {
                Text("Advanced sections stay collapsed until you expand them.")
            }
        }
        .weekendSettingsListStyle()
        .navigationTitle("Data & Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await state.refreshCalendarPermissionState()
            await state.flushPendingOperations()
        }
    }

    private var plannedGoalBinding: Binding<Int> {
        Binding(
            get: { state.weeklyReportSnapshot().goalPlannedTarget },
            set: { value in
                let snapshot = state.weeklyReportSnapshot()
                state.setMonthlyGoal(
                    monthKey: snapshot.goalMonthKey,
                    plannedTarget: value,
                    completedTarget: snapshot.goalCompletedTarget
                )
            }
        )
    }

    private var completedGoalBinding: Binding<Int> {
        Binding(
            get: { state.weeklyReportSnapshot().goalCompletedTarget },
            set: { value in
                let snapshot = state.weeklyReportSnapshot()
                state.setMonthlyGoal(
                    monthKey: snapshot.goalMonthKey,
                    plannedTarget: snapshot.goalPlannedTarget,
                    completedTarget: value
                )
            }
        )
    }

    private func auditTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct AboutSettingsView: View {
    var body: some View {
        List {
            Section("App") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Build", value: appBuild)
            }
            Section {
                Text("The Weekend helps you coordinate weekends across personal and shared calendars.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .weekendSettingsListStyle()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    }
}

private func openSystemSettings() {
    #if canImport(UIKit)
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
    #endif
}

private func copyShareCode(_ code: String) {
    #if canImport(UIKit)
    UIPasteboard.general.string = code
    #endif
}

private extension View {
    @ViewBuilder
    func weekendSettingsListStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.listStyle(.insetGrouped)
        } else {
            self
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
        }
    }
}
