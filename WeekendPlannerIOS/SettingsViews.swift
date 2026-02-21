import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum SettingsDestination: Hashable {
    case account
    case calendars
    case notifications
    case offDays
    case personalReminders
    case preferences
    case dataPrivacy
    case advancedDiagnostics
    case about
}

struct SettingsHomeView: View {
    @EnvironmentObject private var state: AppState
    @State private var path: [SettingsDestination] = []
    var onAddPlan: (() -> Void)? = nil
    var onAddReminder: (() -> Void)? = nil

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(homeSections) { section in
                    Section(section.title) {
                        ForEach(section.rows) { row in
                            settingsHomeRow(row)
                        }
                    }
                }
            }
            .weekendSettingsListStyle()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let onAddPlan {
                        if let onAddReminder {
                            Menu {
                                Button {
                                    onAddPlan()
                                } label: {
                                    Label("Add plan", systemImage: "calendar.badge.plus")
                                }
                                Button {
                                    onAddReminder()
                                } label: {
                                    Label("Add reminder", systemImage: "bell.badge")
                                }
                            } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel("Add")
                        } else {
                            Button {
                                onAddPlan()
                            } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel("Add a new plan")
                        }
                    }
                }
            }
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .account:
                    AccountSettingsView()
                case .calendars:
                    CalendarSettingsView()
                case .notifications:
                    NotificationSettingsView()
                case .offDays:
                    OffDaysSettingsView()
                case .personalReminders:
                    PersonalRemindersSettingsView()
                case .preferences:
                    PreferencesSettingsView()
                case .dataPrivacy:
                    DataPrivacySettingsView()
                case .advancedDiagnostics:
                    AdvancedDiagnosticsSettingsView()
                case .about:
                    AboutSettingsView()
                }
            }
            .task {
                await state.refreshNotificationPermissionState()
                await state.refreshCalendarPermissionState()
                await state.refreshNotices()
                state.scheduleSyncFlush(reason: "settings-home")
                applyPendingPathIfNeeded()
            }
            .onAppear {
                applyPendingPathIfNeeded()
            }
            .onChange(of: state.pendingSettingsPath) { _, _ in
                applyPendingPathIfNeeded()
            }
        }
    }

    private struct SettingsHomeRow: Identifiable {
        let id: String
        let destination: SettingsDestination?
        let icon: String
        let title: String
        let subtitle: String
        let accessibilityIdentifier: String?
        let action: (() -> Void)?
    }

    private struct SettingsHomeSection: Identifiable {
        let id: String
        let title: String
        let rows: [SettingsHomeRow]
    }

    private var homeSections: [SettingsHomeSection] {
        [
            SettingsHomeSection(
                id: "planning-essentials",
                title: "Planning Essentials",
                rows: [
                    SettingsHomeRow(
                        id: "life-schedule",
                        destination: .offDays,
                        icon: "sun.max",
                        title: "Life Schedule",
                        subtitle: offDaysSubtitle,
                        accessibilityIdentifier: nil,
                        action: nil
                    ),
                    SettingsHomeRow(
                        id: "birthdays-reminders",
                        destination: .personalReminders,
                        icon: "gift",
                        title: "Birthdays & Reminders",
                        subtitle: personalRemindersSubtitle,
                        accessibilityIdentifier: nil,
                        action: nil
                    ),
                    SettingsHomeRow(
                        id: "calendars",
                        destination: .calendars,
                        icon: "calendar",
                        title: "Calendars",
                        subtitle: calendarsSubtitle,
                        accessibilityIdentifier: nil,
                        action: nil
                    ),
                    SettingsHomeRow(
                        id: "notifications",
                        destination: .notifications,
                        icon: "bell.badge",
                        title: "Notifications",
                        subtitle: notificationsSubtitle,
                        accessibilityIdentifier: nil,
                        action: nil
                    )
                ]
            ),
            SettingsHomeSection(
                id: "account-data",
                title: "Account & Data",
                rows: [
                    SettingsHomeRow(
                        id: "account",
                        destination: .account,
                        icon: "person.crop.circle",
                        title: "Account",
                        subtitle: accountSubtitle,
                        accessibilityIdentifier: PageEdgeLayoutContract.settingsAccountContainerID,
                        action: nil
                    ),
                    SettingsHomeRow(
                        id: "data-privacy",
                        destination: .dataPrivacy,
                        icon: "lock.shield",
                        title: "Data & Privacy",
                        subtitle: "Calendar access: \(state.calendarPermissionState.label)",
                        accessibilityIdentifier: nil,
                        action: nil
                    )
                ]
            ),
            SettingsHomeSection(
                id: "app",
                title: "App",
                rows: [
                    SettingsHomeRow(
                        id: "preferences",
                        destination: .preferences,
                        icon: "slider.horizontal.3",
                        title: "Preferences",
                        subtitle: preferencesSubtitle,
                        accessibilityIdentifier: nil,
                        action: nil
                    ),
                    SettingsHomeRow(
                        id: "about",
                        destination: .about,
                        icon: "info.circle",
                        title: "About",
                        subtitle: appVersionSubtitle,
                        accessibilityIdentifier: nil,
                        action: nil
                    ),
                    SettingsHomeRow(
                        id: "onboarding",
                        destination: nil,
                        icon: "sparkles",
                        title: "View onboarding",
                        subtitle: "Replay the intro and setup tips",
                        accessibilityIdentifier: "settings.view-onboarding",
                        action: { state.presentOnboardingFromSettings() }
                    )
                ]
            )
        ]
    }

    @ViewBuilder
    private func settingsHomeRow(_ row: SettingsHomeRow) -> some View {
        if let destination = row.destination {
            if let accessibilityIdentifier = row.accessibilityIdentifier {
                NavigationLink(value: destination) {
                    SettingsNavRow(icon: row.icon, title: row.title, subtitle: row.subtitle)
                }
                .accessibilityIdentifier(accessibilityIdentifier)
            } else {
                NavigationLink(value: destination) {
                    SettingsNavRow(icon: row.icon, title: row.title, subtitle: row.subtitle)
                }
            }
        } else if let action = row.action {
            if let accessibilityIdentifier = row.accessibilityIdentifier {
                Button(action: action) {
                    SettingsNavRow(icon: row.icon, title: row.title, subtitle: row.subtitle)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(accessibilityIdentifier)
            } else {
                Button(action: action) {
                    SettingsNavRow(icon: row.icon, title: row.title, subtitle: row.subtitle)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var accountSubtitle: String {
        let base = state.session?.user.email ?? "Signed out"
        let unread = state.unreadNoticeCount
        guard unread > 0 else { return base }
        return "\(base) • \(unread) new notice\(unread == 1 ? "" : "s")"
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

    private var offDaysSubtitle: String {
        state.offDaysSummaryLabel
    }

    private var personalRemindersSubtitle: String {
        let count = state.personalReminders.count
        if count == 0 {
            return "No personal reminders"
        }
        return "\(count) reminder\(count == 1 ? "" : "s")"
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

    private func applyPendingPathIfNeeded() {
        guard !state.pendingSettingsPath.isEmpty else { return }
        path = state.pendingSettingsPath
        state.consumePendingSettingsPath()
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
    @State private var pendingDeletionMode: AccountDeletionOwnershipMode?
    @State private var showDeleteModePicker = false
    @State private var showDeleteConfirmation = false
    @State private var accountActionMessage: String?
    private static let noticeDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        List {
            Section {
                LabeledContent("Email", value: state.session?.user.email ?? "Signed out")
            } footer: {
                Text("You are signed in with this account.")
            }

            Section("Notices") {
                if state.notices.isEmpty {
                    Text("No account notices.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(state.notices.prefix(20))) { notice in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(notice.title)
                                    .font(.subheadline.weight(.semibold))
                                if notice.isUnread {
                                    Text("NEW")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.planBlue.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                            Text(notice.message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(noticeTimestamp(notice.createdAt))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard notice.isUnread else { return }
                            Task { await state.markNoticeRead(noticeId: notice.id) }
                        }
                    }
                }
            }
            Section {
                Button("Sign out", role: .destructive) {
                    Task {
                        await state.signOut()
                        accountActionMessage = state.authMessage ?? "Signed out."
                    }
                }
                .disabled(state.isLoading || state.session == nil)
            } header: {
                Text("Session")
            }

            Section {
                Button("Delete account", role: .destructive) {
                    pendingDeletionMode = nil
                    showDeleteModePicker = true
                }
                .disabled(state.isLoading || state.session == nil)
            } header: {
                Text("Delete Account")
            } footer: {
                Text("This permanently deletes your account and data. This action cannot be undone.")
            }

            if let accountActionMessage {
                Section {
                    Text(accountActionMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .weekendSettingsListStyle()
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Choose shared calendar handling",
            isPresented: $showDeleteModePicker,
            titleVisibility: .visible
        ) {
            Button("Transfer owned shared calendars (recommended)") {
                pendingDeletionMode = .transfer
                showDeleteConfirmation = true
            }
            Button("Delete owned shared calendars and notify members", role: .destructive) {
                pendingDeletionMode = .delete
                showDeleteConfirmation = true
            }
            Button("Cancel", role: .cancel) {
                pendingDeletionMode = nil
            }
        } message: {
            Text("If you own shared calendars, choose whether to transfer ownership or delete those calendars before removing your account.")
        }
        .alert(
            "Delete account permanently?",
            isPresented: $showDeleteConfirmation,
            presenting: pendingDeletionMode
        ) { mode in
            Button("Delete Account", role: .destructive) {
                Task {
                    let success = await state.deleteAccount(mode: mode)
                    accountActionMessage = success
                        ? (state.authMessage ?? "Account deleted permanently.")
                        : (state.authMessage ?? "Could not delete account.")
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDeletionMode = nil
            }
        } message: { mode in
            Text(deleteConfirmationMessage(for: mode))
        }
        .task {
            let token = PerformanceMonitor.shared.begin(.accountScreenOpen)
            await state.refreshNotices()
            await state.markAllNoticesRead()
            PerformanceMonitor.shared.end(token)
            _ = state.capturePerformanceSnapshot()
        }
    }

    private func deleteConfirmationMessage(for mode: AccountDeletionOwnershipMode) -> String {
        switch mode {
        case .transfer:
            return "Your account and personal data will be permanently deleted. Owned shared calendars will transfer to another member when possible."
        case .delete:
            return "Your account and personal data will be permanently deleted. Owned shared calendars without transfer will be removed, and members will receive an in-app notice."
        }
    }

    private func noticeTimestamp(_ date: Date) -> String {
        Self.noticeDateFormatter.string(from: date)
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
                        LabeledContent("Members", value: "\(selected.memberCount)/\(selected.maxMembers)")
                    }
                }
            } header: {
                Text("Current Calendar")
            } footer: {
                Text("Select the calendar you are currently planning in.")
            }

            Section {
                if let selected = selectedCalendar {
                    LabeledContent("Share code", value: selected.shareCode)

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
                } else {
                    Text("Create or join a calendar to unlock sharing.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Invite & Share")
            } footer: {
                Text("Shared calendars support up to 5 collaborators.")
            }

            Section("Rename Current Calendar") {
                if let selected = selectedCalendar {
                    TextField("New name", text: $renameCalendarName)
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
                } else {
                    Text("No active calendar selected.")
                        .foregroundStyle(.secondary)
                }
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

            Section("Join Calendar") {
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

struct OffDaysSettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var showAddAnnualLeave = false
    @State private var annualLeaveStartDate = CalendarHelper.calendar.startOfDay(for: Date())
    @State private var annualLeaveEndDate = CalendarHelper.calendar.startOfDay(for: Date())
    @State private var annualLeaveNote = ""

    private static let annualLeaveDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private var fridayEveningStartBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: state.weekendConfiguration.fridayEveningStartHour,
                    minute: state.weekendConfiguration.fridayEveningStartMinute,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { newValue in
                state.setFridayEveningStartTime(newValue)
            }
        )
    }

    private var annualLeaveRows: [AnnualLeaveDay] {
        state.annualLeaveDays.sorted { $0.dateKey < $1.dateKey }
    }

    var body: some View {
        List {
            Section {
                ForEach(WeekendDay.allCases.sorted { $0.naturalSortOrder < $1.naturalSortOrder }) { day in
                    Toggle(
                        day.label,
                        isOn: Binding(
                            get: { state.weekendConfiguration.weekendDays.contains(day) },
                            set: { state.setWeekendDayEnabled(day, isOn: $0) }
                        )
                    )
                }
            } header: {
                Text("Weekly non-working days")
            } footer: {
                Text("These are your regular non-working days shown in planning.")
            }

            Section("Friday evening start") {
                Toggle(
                    "Include Friday night",
                    isOn: Binding(
                        get: { state.weekendConfiguration.includeFridayEvening },
                        set: { state.setFridayEveningEnabled($0) }
                    )
                )

                DatePicker(
                    "Friday start time",
                    selection: fridayEveningStartBinding,
                    displayedComponents: .hourAndMinute
                )
                .disabled(!state.weekendConfiguration.includeFridayEvening)
            }

            Section {
                Toggle(
                    "Include public holidays",
                    isOn: Binding(
                        get: { state.weekendConfiguration.includePublicHolidays },
                        set: { state.setIncludePublicHolidays($0) }
                    )
                )

                Picker(
                    "Holiday region",
                    selection: Binding(
                        get: { state.weekendConfiguration.publicHolidayRegionPreference },
                        set: { state.setPublicHolidayRegionPreference($0) }
                    )
                ) {
                    ForEach(PublicHolidayRegionPreference.allCases) { region in
                        Text(region.label).tag(region)
                    }
                }
                .disabled(!state.weekendConfiguration.includePublicHolidays)
            } header: {
                Text("Public holidays")
            } footer: {
                Text("Automatic uses your iPhone region. You can override to another supported region.")
            }

            Section("Annual leave") {
                if annualLeaveRows.isEmpty {
                    Text("No annual leave days added.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(annualLeaveRows) { leave in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formattedAnnualLeaveDate(leave.dateKey))
                                .foregroundStyle(.primary)
                            if !leave.note.isEmpty {
                                Text(leave.note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: deleteAnnualLeaveDays)
                }

                Button("Add annual leave range") {
                    let today = CalendarHelper.calendar.startOfDay(for: Date())
                    annualLeaveStartDate = today
                    annualLeaveEndDate = today
                    annualLeaveNote = ""
                    showAddAnnualLeave = true
                }
            }

        }
        .weekendSettingsListStyle()
        .navigationTitle("Life Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddAnnualLeave) {
            NavigationStack {
                List {
                    Section("Dates") {
                        AnnualLeaveRangeCalendarPicker(
                            startDate: $annualLeaveStartDate,
                            endDate: $annualLeaveEndDate,
                            dateRange: CalendarHelper.planningDateRange()
                        )
                        Text("Tap a start date, then an end date.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        LabeledContent("Start", value: formattedDate(annualLeaveStartDate))
                        LabeledContent("End", value: formattedDate(annualLeaveEndDate))
                    }

                    Section("Details") {
                        TextField("Note (optional)", text: $annualLeaveNote)
                    }
                }
                .weekendSettingsListStyle()
                .navigationTitle("Add Annual Leave")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showAddAnnualLeave = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            state.addAnnualLeaveRange(
                                from: annualLeaveStartDate,
                                to: annualLeaveEndDate,
                                note: annualLeaveNote
                            )
                            showAddAnnualLeave = false
                        }
                    }
                }
            }
        }
    }

    private func deleteAnnualLeaveDays(at offsets: IndexSet) {
        for index in offsets {
            guard annualLeaveRows.indices.contains(index) else { continue }
            state.removeAnnualLeaveDay(annualLeaveRows[index].dateKey)
        }
    }

    private func formattedAnnualLeaveDate(_ key: String) -> String {
        guard let date = CalendarHelper.parseKey(key) else { return key }
        return Self.annualLeaveDateFormatter.string(from: date)
    }

    private func formattedDate(_ date: Date) -> String {
        Self.annualLeaveDateFormatter.string(from: date)
    }
}

struct AddPersonalReminderSheetView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var reminderTitle: String
    @State private var reminderKind: PersonalReminder.Kind
    @State private var reminderDate: Date
    @State private var reminderRepeatsAnnually: Bool

    init(
        initialKind: PersonalReminder.Kind = .reminder,
        initialDate: Date = CalendarHelper.calendar.startOfDay(for: Date())
    ) {
        _reminderTitle = State(initialValue: "")
        _reminderKind = State(initialValue: initialKind)
        _reminderDate = State(initialValue: initialDate)
        _reminderRepeatsAnnually = State(initialValue: initialKind == .birthday)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Type") {
                    Picker("Reminder type", selection: $reminderKind) {
                        ForEach(PersonalReminder.Kind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Details") {
                    TextField(
                        reminderKind == .birthday ? "Name" : "Reminder title",
                        text: $reminderTitle
                    )
                    DatePicker(
                        "Date",
                        selection: $reminderDate,
                        displayedComponents: .date
                    )
                    Toggle(
                        "Repeat yearly",
                        isOn: Binding(
                            get: {
                                reminderKind == .birthday ? true : reminderRepeatsAnnually
                            },
                            set: { newValue in
                                if reminderKind != .birthday {
                                    reminderRepeatsAnnually = newValue
                                }
                            }
                        )
                    )
                    .disabled(reminderKind == .birthday)
                }
            }
            .weekendSettingsListStyle()
            .navigationTitle("Add Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: reminderKind) { _, newKind in
                if newKind == .birthday {
                    reminderRepeatsAnnually = true
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        state.addPersonalReminder(
                            title: reminderTitle,
                            kind: reminderKind,
                            date: reminderDate,
                            repeatsAnnually: reminderRepeatsAnnually
                        )
                        dismiss()
                    }
                    .disabled(reminderTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct PersonalRemindersSettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var showAddReminder = false

    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private var reminderRows: [PersonalReminder] {
        state.personalReminders.sorted { lhs, rhs in
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

    var body: some View {
        List {
            Section {
                if reminderRows.isEmpty {
                    Text("No personal reminders yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(reminderRows) { reminder in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formattedReminderTitle(reminder))
                                .foregroundStyle(.primary)
                            Text(formattedReminderSubtitle(reminder))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: deleteReminders)
                }

                Button("Add reminder") {
                    showAddReminder = true
                }
            } footer: {
                Text("Birthdays repeat yearly by default. Add one-time reminders for specific dates.")
            }
        }
        .weekendSettingsListStyle()
        .navigationTitle("Birthdays & Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddReminder) {
            AddPersonalReminderSheetView()
        }
    }

    private func deleteReminders(at offsets: IndexSet) {
        for index in offsets {
            guard reminderRows.indices.contains(index) else { continue }
            state.removePersonalReminder(reminderRows[index].id)
        }
    }

    private func formattedReminderTitle(_ reminder: PersonalReminder) -> String {
        let trimmed = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
        switch reminder.kind {
        case .birthday:
            if trimmed.isEmpty {
                return "Birthday"
            }
            if trimmed.lowercased().contains("birthday") {
                return trimmed
            }
            return "Birthday: \(trimmed)"
        case .reminder:
            return trimmed.isEmpty ? "Reminder" : trimmed
        }
    }

    private func formattedReminderSubtitle(_ reminder: PersonalReminder) -> String {
        let dateLabel: String
        if reminder.repeatsAnnually {
            dateLabel = formattedRecurringReminderDate(reminder)
        } else {
            dateLabel = formattedOneOffReminderDate(reminder)
        }
        let cadenceLabel = reminder.repeatsAnnually ? "Repeats yearly" : "One-time"
        return "\(reminder.kind.label) • \(dateLabel) • \(cadenceLabel)"
    }

    private func formattedRecurringReminderDate(_ reminder: PersonalReminder) -> String {
        var components = DateComponents()
        components.year = 2000
        components.month = reminder.month
        components.day = reminder.day
        if let date = CalendarHelper.calendar.date(from: components) {
            return Self.monthDayFormatter.string(from: date)
        }
        return "\(reminder.month)/\(reminder.day)"
    }

    private func formattedOneOffReminderDate(_ reminder: PersonalReminder) -> String {
        guard let year = reminder.year else {
            return formattedRecurringReminderDate(reminder)
        }
        var components = DateComponents()
        components.year = year
        components.month = reminder.month
        components.day = reminder.day
        guard let date = CalendarHelper.calendar.date(from: components) else {
            return "\(year)-\(reminder.month)-\(reminder.day)"
        }
        return Self.fullDateFormatter.string(from: date)
    }
}

private struct AnnualLeaveRangeCalendarPicker: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    let dateRange: ClosedRange<Date>
    @State private var visibleMonth: Date
    @State private var expectingRangeEnd = false

    init(
        startDate: Binding<Date>,
        endDate: Binding<Date>,
        dateRange: ClosedRange<Date>
    ) {
        _startDate = startDate
        _endDate = endDate
        self.dateRange = dateRange
        let anchor = min(startDate.wrappedValue, endDate.wrappedValue)
        _visibleMonth = State(initialValue: CalendarHelper.monthStart(for: anchor))
    }

    private var calendar: Calendar { CalendarHelper.calendar }

    private var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }

    private var weekdaySymbols: [String] {
        calendar.shortStandaloneWeekdaySymbols
    }

    private var normalizedStart: Date {
        let normalized = calendar.startOfDay(for: startDate)
        return normalized <= normalizedEnd ? normalized : normalizedEnd
    }

    private var normalizedEnd: Date {
        let normalized = calendar.startOfDay(for: endDate)
        let start = calendar.startOfDay(for: startDate)
        return normalized >= start ? normalized : start
    }

    private var currentMonthDays: [Date?] {
        guard let dayRange = calendar.range(of: .day, in: .month, for: visibleMonth) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: visibleMonth)
        let leadingSpaces = max(0, firstWeekday - 1)
        var cells: [Date?] = Array(repeating: nil, count: leadingSpaces)
        let year = calendar.component(.year, from: visibleMonth)
        let month = calendar.component(.month, from: visibleMonth)
        for day in dayRange {
            let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
            cells.append(date)
        }
        while !cells.count.isMultiple(of: 7) {
            cells.append(nil)
        }
        return cells
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    moveMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .disabled(!canMoveMonth(by: -1))

                Spacer()

                Text(monthFormatter.string(from: visibleMonth))
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button {
                    moveMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .disabled(!canMoveMonth(by: 1))
            }
            .padding(.horizontal, 2)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(currentMonthDays.enumerated()), id: \.offset) { _, item in
                    if let day = item {
                        dayCell(day)
                    } else {
                        Color.clear
                            .frame(height: 34)
                    }
                }
            }
        }
        .onChange(of: startDate) { _, newDate in
            syncVisibleMonthIfNeeded(for: newDate)
        }
        .onChange(of: endDate) { _, newDate in
            syncVisibleMonthIfNeeded(for: newDate)
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Date) -> some View {
        let normalizedDay = calendar.startOfDay(for: day)
        let lower = calendar.startOfDay(for: dateRange.lowerBound)
        let upper = calendar.startOfDay(for: dateRange.upperBound)
        let inRange = normalizedDay >= lower && normalizedDay <= upper
        let isBoundary = calendar.isDate(normalizedDay, inSameDayAs: normalizedStart) ||
            calendar.isDate(normalizedDay, inSameDayAs: normalizedEnd)
        let isInSelectedRange = normalizedDay >= normalizedStart && normalizedDay <= normalizedEnd

        Button {
            guard inRange else { return }
            applySelection(normalizedDay)
        } label: {
            Text("\(calendar.component(.day, from: normalizedDay))")
                .font(.callout.weight(isBoundary ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .foregroundStyle(foregroundColor(inRange: inRange, isBoundary: isBoundary))
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            isBoundary ? Color.planBlue.opacity(0.22) :
                                (isInSelectedRange ? Color.planBlue.opacity(0.12) : Color.clear)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isBoundary ? Color.planBlue.opacity(0.45) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!inRange)
    }

    private func foregroundColor(inRange: Bool, isBoundary: Bool) -> Color {
        if !inRange {
            return .secondary.opacity(0.45)
        }
        if isBoundary {
            return .primary
        }
        return .primary
    }

    private func applySelection(_ day: Date) {
        if !expectingRangeEnd {
            startDate = day
            endDate = day
            expectingRangeEnd = true
            return
        }

        let start = calendar.startOfDay(for: startDate)
        if day < start {
            startDate = day
            endDate = start
        } else {
            endDate = day
        }
        expectingRangeEnd = false
    }

    private func syncVisibleMonthIfNeeded(for date: Date) {
        let monthStart = CalendarHelper.monthStart(for: date)
        if !calendar.isDate(monthStart, equalTo: visibleMonth, toGranularity: .month) {
            visibleMonth = monthStart
        }
    }

    private func canMoveMonth(by delta: Int) -> Bool {
        guard let candidate = calendar.date(byAdding: .month, value: delta, to: visibleMonth) else { return false }
        let monthStart = CalendarHelper.monthStart(for: candidate)
        let rangeLower = CalendarHelper.monthStart(for: dateRange.lowerBound)
        let rangeUpper = CalendarHelper.monthStart(for: dateRange.upperBound)
        return monthStart >= rangeLower && monthStart <= rangeUpper
    }

    private func moveMonth(by delta: Int) {
        guard canMoveMonth(by: delta),
              let candidate = calendar.date(byAdding: .month, value: delta, to: visibleMonth) else { return }
        visibleMonth = CalendarHelper.monthStart(for: candidate)
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

    var body: some View {
        List {
            Section("Permissions & Integrations") {
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

                Toggle(
                    "Enable calendar import sync",
                    isOn: Binding(
                        get: { state.calendarImportSettings.isEnabled },
                        set: { enabled in
                            Task { await state.setCalendarImportEnabled(enabled) }
                        }
                    )
                )
                .disabled(!state.calendarPermissionState.canReadEvents)

                if state.calendarPermissionState.canReadEvents, state.calendarImportSettings.isEnabled {
                    if state.availableExternalCalendars.isEmpty {
                        Text("No device calendars available.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(state.availableExternalCalendars) { calendar in
                            Button {
                                state.toggleImportedSourceCalendar(calendar.id)
                            } label: {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(color(for: calendar.colorHex))
                                        .frame(width: 8, height: 8)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(calendar.title)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        Text(calendar.sourceTitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if !calendar.allowsWrites {
                                        Text("Read-only")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Image(systemName: state.isImportedSourceCalendarSelected(calendar.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(state.isImportedSourceCalendarSelected(calendar.id) ? Color.planBlue : Color.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    LabeledContent("Last sync", value: state.calendarImportLastSyncLabel)
                    Button("Import now") {
                        Task { await state.reconcileImportedCalendarEvents(trigger: .manual) }
                    }
                }

                Text("Used for conflict checks, optional Apple Calendar export, and weekend import from calendars connected to this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                NavigationLink(value: SettingsDestination.advancedDiagnostics) {
                    SettingsNavRow(
                        icon: "speedometer",
                        title: "Advanced diagnostics",
                        subtitle: "Sync health, activity history, and weekly report"
                    )
                }
            } header: {
                Text("Advanced")
            } footer: {
                Text("Advanced tools are available in a separate screen.")
            }
        }
        .weekendSettingsListStyle()
        .navigationTitle("Data & Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await state.refreshCalendarPermissionState()
            await state.refreshAvailableExternalCalendars()
            state.scheduleSyncFlush(reason: "settings-data-privacy")
        }
    }

    private func color(for hex: String) -> Color {
        let cleaned = hex.replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
            return .secondary
        }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        return Color(red: red, green: green, blue: blue)
    }
}

struct AdvancedDiagnosticsSettingsView: View {
    @EnvironmentObject private var state: AppState

    @AppStorage("settings.show_sync_diagnostics") private var showSyncDiagnostics = false
    @AppStorage("settings.show_activity_history") private var showActivityHistory = false
    @AppStorage("settings.show_weekly_report") private var showWeeklyReport = false
    @State private var performanceSnapshot: PerformanceSnapshot = .empty

    var body: some View {
        List {
            Section {
                DisclosureGroup(isExpanded: $showSyncDiagnostics) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(state.hasPendingOperations ? "\(state.pendingOperationCount) pending" : "All synced")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                        if let nextRetryLabel = state.nextPendingSyncRetryLabel, state.hasPendingOperations {
                            Text("Next retry \(nextRetryLabel).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if state.syncInProgress {
                            Text("Sync in progress...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if state.hasPendingOperations {
                            Text("Pending changes will retry automatically when connection is available.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let lastSyncErrorMessage = state.lastSyncErrorMessage {
                            Text("Last sync error")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(lastSyncErrorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        Button("Retry now") {
                            state.forceRetryPendingOperations(reason: "settings-sync-diagnostics-retry")
                        }
                        .font(.caption.weight(.semibold))
                        .disabled(!state.hasPendingOperations || state.syncInProgress)
                    }
                    .padding(.top, 6)
                } label: {
                    Label("Sync diagnostics", systemImage: "arrow.triangle.2.circlepath")
                }

                DisclosureGroup(isExpanded: $showActivityHistory) {
                    if state.recentAuditEntries(limit: 1).isEmpty {
                        Text("No activity yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(state.recentAuditEntries(limit: 12)) { entry in
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
                    }
                    .padding(.top, 6)
                } label: {
                    Label("Weekly report", systemImage: "chart.bar")
                }

                DisclosureGroup {
                    if performanceSnapshot.metrics.isEmpty {
                        Text("No performance samples captured yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Snapshot: \(auditTimestamp(performanceSnapshot.generatedAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(performanceSnapshot.metrics) { metric in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(metric.key.rawValue)
                                        .font(.subheadline.weight(.semibold))
                                    Text("count \(metric.count) • avg \(formattedMilliseconds(metric.averageMs)) • p95 \(formattedMilliseconds(metric.p95Ms)) • max \(formattedMilliseconds(metric.maxMs))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Button("Refresh performance snapshot") {
                                performanceSnapshot = state.capturePerformanceSnapshot()
                            }
                            .font(.caption)
                        }
                        .padding(.top, 6)
                    }
                } label: {
                    Label("Performance snapshot", systemImage: "speedometer")
                }
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("These tools are intended for troubleshooting and performance monitoring.")
            }
        }
        .weekendSettingsListStyle()
        .navigationTitle("Advanced Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            state.scheduleSyncFlush(reason: "settings-advanced-diagnostics")
            performanceSnapshot = state.currentPerformanceSnapshot()
        }
    }

    private func auditTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formattedMilliseconds(_ value: Double) -> String {
        String(format: "%.1fms", value)
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
