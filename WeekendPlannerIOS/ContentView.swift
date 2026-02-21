import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
#if canImport(UIKit)
import UIKit
#endif

enum PageEdgeLayoutContract {
    static let dashboardLegendContainerID = "dashboard.legend.container"
    static let dashboardCountdownRailID = "dashboard.countdown.rail"
    static let dashboardCountdownLifePillID = "dashboard.countdown.lifePill"
    static let dashboardCountdownLifePillTextID = "dashboard.countdown.lifePill.text"
    static let plannerMonthSelectorContainerID = "planner.monthSelector.container"
    static let settingsAccountContainerID = "settings.account.container"
    static let plannerWeekendCardIDPrefix = "planner.weekend.card."
    static let plannerInterCardReminderRowIDPrefix = "planner.intercard.reminder.row."
    static let frameAlignmentTolerance: CGFloat = 1.0
}

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var detailSelection: WeekendSelection?
    @State private var addPlanPresentation: AddPlanPresentation?
    @State private var showAddReminderSheet = false

    var body: some View {
        ZStack {
            AppGradientBackground()
            TabView(selection: $state.selectedTab) {
                NavigationStack {
                    tabListLayout(showLegend: true) {
                        OverviewView(
                            onSelectWeekend: { key in
                                detailSelection = WeekendSelection(id: key)
                            },
                            onSelectMonth: { key in
                                state.selectedMonthKey = key
                                state.selectedTab = .weekend
                            }
                        )
                    }
                    .navigationTitle("Dashboard")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            addToolbarButton
                        }
                    }
                }
                .tag(AppTab.overview)
                .tabItem {
                    Label(AppTab.overview.rawValue, systemImage: "square.grid.2x2")
                }

                NavigationStack {
                    tabListLayout {
                        WeekendView(onSelectWeekend: { key in
                            detailSelection = WeekendSelection(id: key)
                        })
                    }
                    .navigationTitle("Planner")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            addToolbarButton
                        }
                    }
                }
                .tag(AppTab.weekend)
                .tabItem {
                    Label(AppTab.weekend.rawValue, systemImage: "calendar")
                }

                SettingsHomeView(
                    onAddPlan: presentAddPlanForNextHoliday,
                    onAddReminder: presentAddReminderSheet
                )
                .tag(AppTab.settings)
                .tabItem {
                    Label(AppTab.settings.rawValue, systemImage: "gearshape")
                }
            }
            .tint(.planBlue)
            .modifier(LegacyTabBarBackgroundModifier())
            .simultaneousGesture(
                DragGesture(minimumDistance: 30, coordinateSpace: .local)
                    .onEnded { value in
                        handleTabSwipe(value)
                    }
            )
        }
        .sheet(item: $detailSelection) { selection in
            WeekendDetailsView(
                weekendKey: selection.id,
                onAddPlans: { key, bypass in
                    addPlanPresentation = AddPlanPresentation(
                        weekendKey: key,
                        bypassProtection: bypass,
                        initialDate: nil
                    )
                }
            )
        }
        .sheet(item: $addPlanPresentation) { presentation in
            AddPlanView(
                weekendKey: presentation.weekendKey,
                bypassProtection: presentation.bypassProtection,
                initialDate: presentation.initialDate
            )
            .id(presentation.id)
        }
        .sheet(isPresented: $showAddReminderSheet) {
            AddPersonalReminderSheetView()
                .environmentObject(state)
        }
        .fullScreenCover(isPresented: $state.showOnboarding) {
            OnboardingCarouselView(
                onSkip: { state.completeOnboardingAndShowChecklist() },
                onGetStarted: { state.completeOnboardingAndShowChecklist() }
            )
            .environmentObject(state)
        }
        .fullScreenCover(isPresented: $state.showOnboardingChecklist) {
            OnboardingSetupChecklistView(
                onLifeSchedule: { state.openOnboardingSettingsStep(.offDays) },
                onSharing: { state.openOnboardingSettingsStep(.calendars) },
                onAddPlan: { state.openOnboardingAddPlanStep() },
                onContinue: { state.closeOnboardingChecklist() }
            )
            .environmentObject(state)
        }
        .overlay {
            if state.showAuthSplash {
                AuthSplashView()
            }
        }
        .onAppear {
            applyPendingNavigationIfNeeded()
        }
        .onChange(of: state.pendingWeekendSelection) { _, _ in
            applyPendingNavigationIfNeeded()
        }
        .onChange(of: state.pendingAddPlanWeekendKey) { _, _ in
            applyPendingNavigationIfNeeded()
        }
        .onChange(of: state.showAuthSplash) { _, _ in
            applyPendingNavigationIfNeeded()
        }
        .onChange(of: state.showOnboarding) { _, _ in
            applyPendingNavigationIfNeeded()
        }
        .onChange(of: state.showOnboardingChecklist) { _, _ in
            applyPendingNavigationIfNeeded()
        }
        .onChange(of: scenePhase) { _, _ in
            applyPendingNavigationIfNeeded()
        }
    }

    @ViewBuilder
    private func tabListLayout<Content: View>(
        showLegend: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        List {
            if showLegend {
                LegendView()
                    .accessibilityIdentifier(PageEdgeLayoutContract.dashboardLegendContainerID)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            content()
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .weekendTabListStyle()
    }

    private func handleTabSwipe(_ value: DragGesture.Value) {
        let horizontal = value.translation.width
        let vertical = value.translation.height
        guard abs(horizontal) > abs(vertical) * 1.2 else { return }
        guard abs(horizontal) >= 50 else { return }
        if horizontal < 0 {
            switchTab(by: 1)
        } else {
            switchTab(by: -1)
        }
    }

    private func switchTab(by delta: Int) {
        let tabs = AppTab.allCases
        guard let index = tabs.firstIndex(of: state.selectedTab) else { return }
        let nextIndex = max(0, min(tabs.count - 1, index + delta))
        guard nextIndex != index else { return }
        triggerSwipeHaptic()
        withAnimation(.easeInOut(duration: 0.2)) {
            state.selectedTab = tabs[nextIndex]
        }
    }

    private func triggerSwipeHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    @ViewBuilder
    private var addToolbarButton: some View {
        // Keep the system toolbar placement so all tabs use the same nav-bar spacing behavior.
        Menu {
            Button {
                presentAddPlanForNextHoliday()
            } label: {
                Label("Add plan", systemImage: "calendar.badge.plus")
            }
            Button {
                presentAddReminderSheet()
            } label: {
                Label("Add reminder", systemImage: "bell.badge")
            }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Add")
    }

    private func presentAddPlanForNextHoliday() {
        let initialDate = state.nextFutureHolidayDate() ?? Date()
        addPlanPresentation = AddPlanPresentation(
            weekendKey: CalendarHelper.plannerWeekKey(for: initialDate),
            bypassProtection: false,
            initialDate: initialDate
        )
    }

    private func presentAddReminderSheet() {
        showAddReminderSheet = true
    }

    private var hasBlockingOverlay: Bool {
        state.showAuthSplash || state.showOnboarding || state.showOnboardingChecklist
    }

    private func applyPendingNavigationIfNeeded() {
        guard scenePhase == .active else { return }
        guard !hasBlockingOverlay else { return }

        if let weekendKey = state.pendingAddPlanWeekendKey {
            addPlanPresentation = AddPlanPresentation(
                weekendKey: weekendKey,
                bypassProtection: state.pendingAddPlanBypassProtection,
                initialDate: state.pendingAddPlanInitialDate
            )
            state.consumePendingAddPlanSelection()
            return
        }

        if let weekendKey = state.pendingWeekendSelection {
            detailSelection = WeekendSelection(id: weekendKey)
            state.consumePendingWeekendSelection()
        }
    }
}

private struct AddPlanPresentation: Identifiable {
    let id = UUID()
    let weekendKey: String?
    let bypassProtection: Bool
    let initialDate: Date?
}

private struct LegacyTabBarBackgroundModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        }
    }
}

extension View {
    @ViewBuilder
    func weekendRootListStyle(trimTopContentMargin: Bool) -> some View {
        if #available(iOS 26.0, *) {
            if trimTopContentMargin {
                self
                    .listStyle(.insetGrouped)
                    .contentMargins(.top, 0, for: .scrollContent)
            } else {
                self
                    .listStyle(.insetGrouped)
            }
        } else {
            if trimTopContentMargin {
                self
                    .listStyle(.insetGrouped)
                    .contentMargins(.top, 0, for: .scrollContent)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            } else {
                self
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }
        }
    }

    @ViewBuilder
    func weekendTabListStyle() -> some View {
        weekendRootListStyle(trimTopContentMargin: true)
    }

    @ViewBuilder
    func weekendSettingsListStyle() -> some View {
        weekendRootListStyle(trimTopContentMargin: false)
    }
}

struct LegendView: View {
    var body: some View {
        HStack(spacing: 10) {
            legendItem(text: "Free") {
                StatusDot(color: .freeGreen)
            }
            legendItem(text: "Local plans") {
                StatusDot(color: .planBlue)
            }
            legendItem(text: "Travel plans") {
                StatusDot(color: .travelCoral)
            }
            legendItem(text: "Protected") {
                ProtectedStripeDot(size: 10)
            }
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: AppSurfaceStyle.primaryCardCornerRadius, style: .continuous)
                .fill(AppSurfaceStyle.settingsCardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppSurfaceStyle.primaryCardCornerRadius, style: .continuous)
                .stroke(AppSurfaceStyle.settingsSeparator, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func legendItem<Icon: View>(text: String, @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: 5) {
            icon()
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .allowsTightening(true)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct WeekMeltRailView: View {
    @EnvironmentObject private var appState: AppState
    var onSelectWeekend: ((String) -> Void)? = nil

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: false)) { timeline in
            let countdownWindow = appState.countdownWindowContext(
                referenceDate: timeline.date,
                timeZone: appState.countdownTimeZone
            )
            let countdown = WorkweekCountdownState.from(
                date: timeline.date,
                timeZone: appState.countdownTimeZone,
                configuration: appState.weekendConfiguration,
                countdownWindow: countdownWindow
            )
            let pulseWave = sin(.pi * countdown.burstProgress)
            let burstEnergy = countdown.phase == .weekendBurst
                ? (0.35 + (0.65 * pulseWave))
                : 0
            let labelScale = countdown.phase == .weekendBurst
                ? (1 + (0.05 * burstEnergy))
                : 1
            let activeWeekendKey = appState.plannerDisplayWeekKey(for: timeline.date)
            Group {
                if countdown.isOffDayMode {
                    offDayLifePill(
                        countdown: countdown,
                        burstEnergy: burstEnergy,
                        weekendKey: activeWeekendKey
                    )
                    .transition(
                        .opacity.combined(with: .scale(scale: 0.97))
                    )
                } else {
                    countdownRail(
                        countdown: countdown,
                        burstEnergy: burstEnergy,
                        labelScale: labelScale
                    )
                    .transition(
                        .opacity.combined(with: .scale(scale: 0.98))
                    )
                }
            }
            .animation(.easeInOut(duration: 0.24), value: countdown.phase)
            .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private func countdownRail(
        countdown: WorkweekCountdownState,
        burstEnergy: CGFloat,
        labelScale: CGFloat
    ) -> some View {
        HStack(spacing: 8) {
            Text(countdown.workweekStartLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            GeometryReader { geometry in
                let width = geometry.size.width
                let remainingWidth = max(0, width * (1 - countdown.progress))
                let markerPosition = max(8, min(width - 8, width - remainingWidth))
                let showMarker = remainingWidth > 0 || countdown.phase != .countingDown

                ZStack {
                    Capsule()
                        .fill(
                            countdown.phase == .countingDown
                                ? AppSurfaceStyle.settingsChipBackground
                                : Color.planBlue.opacity(0.16)
                        )

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: countdown.phase == .countingDown
                                    ? [
                                        Color.planBlue.opacity(0.36),
                                        Color.travelCoral.opacity(0.30),
                                        Color.freeGreen.opacity(0.34)
                                    ]
                                    : [
                                        Color.planBlue.opacity(0.65),
                                        Color.travelCoral.opacity(0.58),
                                        Color.freeGreen.opacity(0.62)
                                    ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: remainingWidth)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    ForEach(1..<5, id: \.self) { index in
                        Rectangle()
                            .fill(AppSurfaceStyle.settingsSeparator.opacity(0.6))
                            .frame(width: 1, height: 16)
                            .position(
                                x: width * CGFloat(index) / 5.0,
                                y: geometry.size.height / 2
                            )
                    }

                    if showMarker {
                        ZStack {
                            if countdown.phase == .weekendBurst {
                                Circle()
                                    .stroke(Color.white.opacity(0.8 - (0.45 * countdown.burstProgress)), lineWidth: 2)
                                    .frame(
                                        width: 16 + (18 * burstEnergy),
                                        height: 16 + (18 * burstEnergy)
                                    )
                                    .blur(radius: 0.4)
                            }

                            Circle()
                                .fill(Color.white.opacity(0.95))
                                .frame(width: 16, height: 16)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            countdown.phase == .countingDown
                                                ? Color.planBlue.opacity(0.6)
                                                : Color.white.opacity(0.92),
                                            lineWidth: 2
                                        )
                                )
                        }
                        .shadow(
                            color: countdown.phase == .countingDown
                                ? Color.planBlue.opacity(0.24)
                                : Color.travelCoral.opacity(0.42),
                            radius: countdown.phase == .countingDown ? 5 : (6 + (5 * burstEnergy)),
                            x: 0,
                            y: 0
                        )
                        .position(x: markerPosition, y: geometry.size.height / 2)
                    }

                    Text(countdown.centerLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(
                            countdown.phase == .countingDown
                                ? Color.primary
                                : Color.white
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .scaleEffect(labelScale)
                        .shadow(
                            color: countdown.phase == .countingDown
                                ? .clear
                                : Color.black.opacity(0.2),
                            radius: 2,
                            x: 0,
                            y: 1
                        )
                }
                .overlay(
                    Capsule()
                        .stroke(
                            countdown.phase == .countingDown
                                ? Color.primary.opacity(0.18)
                                : Color.white.opacity(0.42),
                            lineWidth: countdown.phase == .countingDown ? 1.2 : 1.4
                        )
                )
            }
            .frame(height: 32)

            Text(countdown.weekendStartLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier(PageEdgeLayoutContract.dashboardCountdownRailID)
    }

    @ViewBuilder
    private func offDayLifePill(
        countdown: WorkweekCountdownState,
        burstEnergy: CGFloat,
        weekendKey: String
    ) -> some View {
        let isBurst = countdown.phase == .weekendBurst
        let heroTitle = "View your weekend plans here"
        let pillScale = isBurst ? (1 + (0.026 * burstEnergy)) : 1
        let shadowRadius = isBurst ? (8 + (4 * burstEnergy)) : 7

        let pillContent = HStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.planBlue)

            Text(heroTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.84)
                .accessibilityIdentifier(PageEdgeLayoutContract.dashboardCountdownLifePillTextID)
                .accessibilityLabel(heroTitle)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .frame(maxWidth: .infinity)
        .scaleEffect(pillScale)
        .background {
            ZStack {
                Capsule()
                    .fill(AppSurfaceStyle.settingsCardBackground)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.planBlue.opacity(isBurst ? 0.20 : 0.14),
                                Color.planBlue.opacity(isBurst ? 0.08 : 0.04)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        }
        .overlay(
            Capsule()
                .stroke(
                    Color.planBlue.opacity(isBurst ? 0.42 : 0.28),
                    lineWidth: isBurst ? 1.2 : 1
                )
        )
        .shadow(
            color: Color.black.opacity(0.10),
            radius: shadowRadius,
            x: 0,
            y: 4
        )
        .shadow(
            color: Color.planBlue.opacity(isBurst ? 0.24 : 0.12),
            radius: isBurst ? 10 : 7,
            x: 0,
            y: 3
        )
        .accessibilityIdentifier(PageEdgeLayoutContract.dashboardCountdownLifePillID)

        if let onSelectWeekend {
            Button {
                onSelectWeekend(weekendKey)
            } label: {
                pillContent
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens your weekend plans")
        } else {
            pillContent
        }
    }
}

struct WorkweekCountdownState {
    enum Phase: Equatable {
        case countingDown
        case weekendBurst
        case weekendActive
    }

    static let burstDuration: TimeInterval = 2.5

    let progress: CGFloat
    let phase: Phase
    let burstProgress: CGFloat
    let centerLabel: String
    let workweekStartLabel: String
    let weekendStartLabel: String

    var isOffDayMode: Bool {
        phase != .countingDown
    }

    static func from(
        date: Date,
        timeZone: TimeZone,
        configuration: WeekendConfiguration,
        countdownWindow: CountdownWindowContext? = nil
    ) -> WorkweekCountdownState {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        if let countdownWindow {
            let totalDuration = max(1, countdownWindow.windowStart.timeIntervalSince(countdownWindow.workweekStart))
            let elapsed = min(max(0, date.timeIntervalSince(countdownWindow.workweekStart)), totalDuration)
            let progress = CGFloat(elapsed / totalDuration)
            let workweekStartLabel = shortDayLabel(for: countdownWindow.workweekStart, calendar: calendar)

            if date >= countdownWindow.windowStart && date < countdownWindow.windowEndExclusive {
                let burstElapsed = max(0, date.timeIntervalSince(countdownWindow.windowStart))
                let isBurstPhase = burstElapsed < burstDuration
                let burstProgress = CGFloat(min(max(burstElapsed / burstDuration, 0), 1))
                return WorkweekCountdownState(
                    progress: 1,
                    phase: isBurstPhase ? .weekendBurst : .weekendActive,
                    burstProgress: isBurstPhase ? burstProgress : 1,
                    centerLabel: isBurstPhase ? "Your weekend starts now!" : "Weekend mode is on",
                    workweekStartLabel: workweekStartLabel,
                    weekendStartLabel: countdownWindow.weekendStartLabel
                )
            }

            let remaining = max(0, countdownWindow.windowStart.timeIntervalSince(date))
            return WorkweekCountdownState(
                progress: progress,
                phase: .countingDown,
                burstProgress: 0,
                centerLabel: "\(countdownText(remaining)) to weekend",
                workweekStartLabel: workweekStartLabel,
                weekendStartLabel: countdownWindow.weekendStartLabel
            )
        }

        let startOfToday = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfToday)
        let daysSinceMonday = (weekday + 5) % 7
        let mondayStart = calendar.date(byAdding: .day, value: -daysSinceMonday, to: startOfToday) ?? startOfToday
        let startDay = countdownStartDay(configuration: configuration)
        let weekendDayOffset = (startDay.calendarWeekday + 5) % 7
        let weekendDayDate = calendar.date(byAdding: .day, value: weekendDayOffset, to: mondayStart) ?? mondayStart
        let weekendStartHour = (startDay == .fri && configuration.includeFridayEvening)
            ? configuration.fridayEveningStartHour
            : 0
        let weekendStartMinute = (startDay == .fri && configuration.includeFridayEvening)
            ? configuration.fridayEveningStartMinute
            : 0
        let weekendStart = calendar.date(
            bySettingHour: weekendStartHour,
            minute: weekendStartMinute,
            second: 0,
            of: weekendDayDate
        ) ?? weekendDayDate

        let totalDuration = max(1, weekendStart.timeIntervalSince(mondayStart))
        let elapsed = min(max(0, date.timeIntervalSince(mondayStart)), totalDuration)
        let progress = CGFloat(elapsed / totalDuration)
        let weekendLabel = startDay.shortLabel

        if date >= weekendStart {
            let burstElapsed = max(0, date.timeIntervalSince(weekendStart))
            let isBurstPhase = burstElapsed < burstDuration
            let burstProgress = CGFloat(min(max(burstElapsed / burstDuration, 0), 1))
            return WorkweekCountdownState(
                progress: 1,
                phase: isBurstPhase ? .weekendBurst : .weekendActive,
                burstProgress: isBurstPhase ? burstProgress : 1,
                centerLabel: isBurstPhase ? "Your weekend starts now!" : "Weekend mode is on",
                workweekStartLabel: shortDayLabel(for: mondayStart, calendar: calendar),
                weekendStartLabel: weekendLabel
            )
        }

        let remaining = max(0, weekendStart.timeIntervalSince(date))
        return WorkweekCountdownState(
            progress: progress,
            phase: .countingDown,
            burstProgress: 0,
            centerLabel: "\(countdownText(remaining)) to weekend",
            workweekStartLabel: shortDayLabel(for: mondayStart, calendar: calendar),
            weekendStartLabel: weekendLabel
        )
    }

    private static func countdownStartDay(configuration: WeekendConfiguration) -> WeekendDay {
        if configuration.includeFridayEvening {
            return .fri
        }
        return configuration
            .normalizedWeekendDays
            .sorted { $0.plannerRowSortOrder < $1.plannerRowSortOrder }
            .first ?? .sat
    }

    private static func countdownText(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval / 60)
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return "\(days)d \(hours)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private static func shortDayLabel(for date: Date, calendar: Calendar) -> String {
        WeekendDay.from(calendarWeekday: calendar.component(.weekday, from: date))?.shortLabel ?? "Mon"
    }
}

struct OverviewView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.colorScheme) private var colorScheme
    var onSelectWeekend: (String) -> Void
    var onSelectMonth: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WeekMeltRailView(onSelectWeekend: onSelectWeekend)

            ForEach(yearSections) { section in
                yearDividerHeader(section.year)

                LazyVGrid(columns: overviewColumns, spacing: 14) {
                    ForEach(section.months) { option in
                        monthCard(for: option)
                    }
                }
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var overviewColumns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible())]
    }

    private var yearSections: [OverviewYearSection] {
        let months = CalendarHelper.getMonths().filter { !isMonthInPast($0) }
        var sections: [OverviewYearSection] = []

        for month in months {
            guard let year = month.year else { continue }

            if let lastIndex = sections.indices.last, sections[lastIndex].year == year {
                sections[lastIndex].months.append(month)
            } else {
                sections.append(OverviewYearSection(year: year, months: [month]))
            }
        }

        return sections
    }

    @ViewBuilder
    private func yearDividerHeader(_ year: Int) -> some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(yearDividerColor)
                .frame(height: 1)
            Text(String(year))
                .font(.caption.weight(.semibold))
                .tracking(2)
                .foregroundColor(.secondary)
            Rectangle()
                .fill(yearDividerColor)
                .frame(height: 1)
        }
        .padding(.vertical, 2)
    }

    private var yearDividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.6) : AppSurfaceStyle.settingsSeparator
    }

    private func isMonthInPast(_ option: MonthOption) -> Bool {
        let currentMonthStart = CalendarHelper.calendar.date(
            from: CalendarHelper.calendar.dateComponents([.year, .month], from: Date())
        ) ?? Date()
        let currentMonthKey = CalendarHelper.formatKey(currentMonthStart)
        return option.key < currentMonthKey
    }

    @ViewBuilder
    private func monthCard(for option: MonthOption) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(option.shortLabel)
                .font(.body.weight(.medium))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(12)), count: 5), alignment: .leading, spacing: 6) {
                ForEach(option.weekends) { weekend in
                    let key = CalendarHelper.formatKey(weekend.saturday)
                    let status = state.status(for: key)
                    let isPastWeekend = state.isWeekendInPast(key)
                    Button(action: { onSelectWeekend(key) }) {
                        statusDot(for: status.type, isPastWeekend: isPastWeekend)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppSurfaceStyle.settingsCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppSurfaceStyle.primaryCardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppSurfaceStyle.primaryCardCornerRadius, style: .continuous)
                .stroke(AppSurfaceStyle.settingsSeparator, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: AppSurfaceStyle.primaryCardCornerRadius, style: .continuous))
        .onTapGesture {
            onSelectMonth(option.key)
        }
    }

    private func color(for type: String) -> Color {
        switch type {
        case "travel": return .travelCoral
        case "plan": return .planBlue
        default: return .freeGreen
        }
    }

    @ViewBuilder
    private func statusDot(for type: String, isPastWeekend: Bool) -> some View {
        if isPastWeekend {
            Circle()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 12, height: 12)
        } else if type == "protected" {
            ProtectedStripeDot(size: 12)
        } else {
            Circle()
                .fill(color(for: type))
                .frame(width: 12, height: 12)
        }
    }
}

struct WeekendView: View {
    @EnvironmentObject private var state: AppState
    var onSelectWeekend: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            MonthSelectorView(selectedKey: $state.selectedMonthKey)

            Divider()
                .overlay(AppSurfaceStyle.settingsSeparator)
                .padding(.horizontal, 2)
                .padding(.vertical, 2)

            MonthDisplayView(selectedKey: state.selectedMonthKey, onSelectWeekend: onSelectWeekend)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct MonthSelectorView: View {
    @Binding var selectedKey: String
    @State private var selectedYear = CalendarHelper.currentPlanningYear()

    var body: some View {
        let options = CalendarHelper.getMonthOptions()
        let quickOptions = quickSelectorOptions(from: options)
        let yearOptions = CalendarHelper.planningYears()
        let monthOptions = options
            .filter { $0.year == selectedYear }
            .sorted { $0.key < $1.key }
        let quickRows = chunked(quickOptions, size: 2)
        let monthRows = chunked(monthOptions, size: 4)

        VStack(alignment: .leading, spacing: 10) {
            if !quickRows.isEmpty {
                VStack(spacing: 6) {
                    ForEach(Array(quickRows.enumerated()), id: \.offset) { _, row in
                        optionRow(row, columns: 2)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                yearSelector(yearOptions: yearOptions)
                VStack(spacing: 6) {
                    ForEach(Array(monthRows.enumerated()), id: \.offset) { _, row in
                        optionRow(row, columns: 4)
                    }
                }
            }
        }
        .onAppear {
            syncYearToCurrentSelection(options: options)
        }
        .onChange(of: selectedKey) { _, _ in
            syncYearToCurrentSelection(options: CalendarHelper.getMonthOptions())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier(PageEdgeLayoutContract.plannerMonthSelectorContainerID)
    }

    private func quickSelectorOptions(from options: [MonthOption]) -> [MonthOption] {
        let priority = ["upcoming", "historical"]
        return options
            .filter { priority.contains($0.key) }
            .sorted { lhs, rhs in
                (priority.firstIndex(of: lhs.key) ?? priority.count) < (priority.firstIndex(of: rhs.key) ?? priority.count)
            }
    }

    @ViewBuilder
    private func optionRow(_ options: [MonthOption], columns: Int) -> some View {
        HStack(spacing: 8) {
            ForEach(options) { option in
                monthOptionButton(option)
                    .disabled(isMonthInPast(option))
            }
            ForEach(0..<max(0, columns - options.count), id: \.self) { _ in
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chunked(_ options: [MonthOption], size: Int) -> [[MonthOption]] {
        guard size > 0 else { return [options] }
        var rows: [[MonthOption]] = []
        var index = 0
        while index < options.count {
            rows.append(Array(options[index..<min(index + size, options.count)]))
            index += size
        }
        return rows
    }

    @ViewBuilder
    private func yearSelector(yearOptions: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu {
                ForEach(yearOptions, id: \.self) { year in
                    Button(String(year)) {
                        selectYear(year)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(String(selectedYear))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(.planBlue)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(AppSurfaceStyle.settingsCardBackground)
                )
                .overlay(
                    Capsule()
                        .stroke(AppSurfaceStyle.settingsSeparator, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(AppSurfaceStyle.settingsSeparator)
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func monthOptionButton(_ option: MonthOption) -> some View {
        let isPast = isMonthInPast(option)
        let isSelected = selectedKey == option.key && !isPast
        Button(action: { selectedKey = option.key }) {
            Text(option.shortLabel)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background {
                    if isSelected {
                        Capsule().fill(Color.planBlue.opacity(0.22))
                    } else if isPast {
                        Capsule().fill(Color.secondary.opacity(0.16))
                    } else {
                        Capsule().fill(AppSurfaceStyle.settingsCardBackground)
                    }
                }
                .foregroundColor(
                    isSelected
                        ? .planBlue
                        : (isPast ? .secondary : .primary)
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(
                        isSelected ? Color.planBlue.opacity(0.45) : AppSurfaceStyle.settingsSeparator,
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
        .opacity(isPast ? 0.78 : 1)
    }

    private func syncYearToCurrentSelection(options: [MonthOption]) {
        guard let selectedOption = options.first(where: { $0.key == selectedKey }),
              let selectedOptionYear = selectedOption.year else {
            return
        }
        selectedYear = selectedOptionYear
    }

    private func selectYear(_ year: Int) {
        selectedYear = year
        let options = CalendarHelper.getMonthOptions()
        let monthOptions = options.filter { $0.year == year }.sorted { $0.key < $1.key }
        guard let currentMonth = monthOptions.first(where: { !isMonthInPast($0) }) ?? monthOptions.first else { return }
        selectedKey = currentMonth.key
    }

    private func isMonthInPast(_ option: MonthOption) -> Bool {
        let currentMonthStart = CalendarHelper.calendar.date(
            from: CalendarHelper.calendar.dateComponents([.year, .month], from: Date())
        ) ?? Date()
        let currentMonthKey = CalendarHelper.formatKey(currentMonthStart)
        return option.key < currentMonthKey
    }
}

struct MonthDisplayView: View {
    @EnvironmentObject private var state: AppState
    let selectedKey: String
    var onSelectWeekend: (String) -> Void
    private static let pastEventInputTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    private static let pastEventOutputTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        let options = CalendarHelper.getMonthOptions()
        if let option = options.first(where: { $0.key == selectedKey }) ?? options.first {
            if option.key == "historical" {
                historicalPlansCard(for: option)
            } else {
                upcomingPlansCard(for: option)
            }
        } else {
            plannerMonthContainer {
                Text("No month data available")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func upcomingPlansCard(for option: MonthOption) -> some View {
        let visibleWeekends = option.weekends.filter {
            !state.isWeekendInPast(CalendarHelper.formatKey($0.saturday))
        }

        plannerMonthContainer {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(option.key == "upcoming" ? option.title : option.shortLabel)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(option.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if visibleWeekends.isEmpty {
                    Text("No weekends left")
                        .font(.callout)
                        .foregroundColor(.secondary)
                } else {
                    VStack(spacing: 14) {
                        ForEach(Array(visibleWeekends.enumerated()), id: \.offset) { index, weekend in
                            let key = CalendarHelper.formatKey(weekend.saturday)
                            let weekendEvents = state.events(for: key)
                            let weekendAnchorDate = CalendarHelper.calendar.startOfDay(for: weekend.saturday)
                            let supplementalReminderLines = state.supplementalReminderLines(for: key, events: weekendEvents)
                            let leadingReminderLines = supplementalReminderLines.filter { $0.date < weekendAnchorDate }
                            let trailingReminderLines = supplementalReminderLines.filter { $0.date >= weekendAnchorDate }

                            if !leadingReminderLines.isEmpty {
                                BetweenWeekendReminderRowsView(
                                    reminderLines: leadingReminderLines,
                                    onTapReminder: {
                                        state.openSettingsDestination(.personalReminders)
                                    }
                                )
                            }

                            WeekendRowView(
                                weekend: weekend,
                                status: state.status(for: key),
                                events: weekendEvents,
                                isProtected: state.isProtected(key),
                                hasWeekendNote: state.hasWeekendNote(weekendKey: key),
                                hasPendingConflict: state.hasPendingImportConflict(weekendKey: key),
                                onTap: { onSelectWeekend(key) },
                                onDuplicateEvent: { event in
                                    guard let targetWeekendKey = CalendarHelper.nextWeekendKey(after: event.weekendKey) else { return }
                                    Task {
                                        _ = await state.duplicateEvent(eventId: event.id, toWeekendKey: targetWeekendKey)
                                    }
                                },
                                onRemoveEvent: { event in
                                    Task { await state.removeEvent(event) }
                                },
                                syncStateForEvent: { event in state.syncState(for: event.id) },
                                isImportedEvent: { event in state.isImportedEvent(event.id) },
                                conflictStateForEvent: { event in state.importConflictState(for: event.id) },
                                onAcknowledgeConflict: { event in
                                    state.acknowledgeConflict(eventId: event.id)
                                }
                            )

                            if index < visibleWeekends.count - 1 && !trailingReminderLines.isEmpty {
                                BetweenWeekendReminderRowsView(
                                    reminderLines: trailingReminderLines,
                                    onTapReminder: {
                                        state.openSettingsDestination(.personalReminders)
                                    }
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func historicalPlansCard(for option: MonthOption) -> some View {
        plannerMonthContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(option.title)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(option.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if pastEventEntries.isEmpty {
                    Text("No past plans from the last 12 months.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(pastEventEntries) { entry in
                                PastEventRowView(entry: entry) {
                                    onSelectWeekend(entry.weekendKey)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: 420)
                }
            }
        }
    }

    @ViewBuilder
    private func plannerMonthContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pastEventEntries: [PastEventEntry] {
        let now = Date()
        guard let rangeStart = CalendarHelper.calendar.date(byAdding: .month, value: -12, to: now) else { return [] }

        return state.events
            .flatMap { event in
                guard let saturday = CalendarHelper.parseKey(event.weekendKey),
                      saturday >= rangeStart,
                      state.isWeekendInPast(event.weekendKey, referenceDate: now) else {
                    return [PastEventEntry]()
                }

                let weekendLabel = CalendarHelper.formatWeekendLabel(saturday)
                return event.dayValues.compactMap { day in
                    guard let dayDate = pastEventDate(for: day, saturday: saturday) else { return nil }
                    return PastEventEntry(
                        id: "\(event.id)-\(day.rawValue)",
                        weekendKey: event.weekendKey,
                        date: dayDate,
                        title: event.title,
                        weekendLabel: weekendLabel,
                        dayLabel: day.label,
                        timeLabel: pastEventTimeLabel(for: event),
                        typeLabel: event.planType == .travel ? "Travel plan" : "Local plan"
                    )
                }
            }
            .sorted { $0.date > $1.date }
    }

    private func pastEventDate(for day: WeekendDay, saturday: Date) -> Date? {
        let weekendKey = CalendarHelper.formatKey(saturday)
        return CalendarHelper.dateForPlannerDay(day, weekendKey: weekendKey)
    }

    private func pastEventTimeLabel(for event: WeekendEvent) -> String {
        if event.isAllDay {
            return "All day"
        }
        return "\(formattedTime(event.startTime)) - \(formattedTime(event.endTime))"
    }

    private func formattedTime(_ value: String) -> String {
        guard let date = Self.pastEventInputTimeFormatter.date(from: value) else { return value }
        return Self.pastEventOutputTimeFormatter.string(from: date)
    }
}

struct PastEventEntry: Identifiable {
    let id: String
    let weekendKey: String
    let date: Date
    let title: String
    let weekendLabel: String
    let dayLabel: String
    let timeLabel: String
    let typeLabel: String
}

struct PastEventRowView: View {
    let entry: PastEventEntry
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(entry.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("PAST")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.secondary.opacity(0.18))
                        )
                }

                Text("\(entry.weekendLabel) • \(entry.dayLabel)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(entry.timeLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(entry.typeLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppSurfaceStyle.cardStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct WeekendRowView: View {
    @EnvironmentObject private var state: AppState
    let weekend: WeekendInfo
    let status: WeekendStatus
    let events: [WeekendEvent]
    let isProtected: Bool
    let hasWeekendNote: Bool
    let hasPendingConflict: Bool
    var onTap: () -> Void
    var onDuplicateEvent: (WeekendEvent) -> Void
    var onRemoveEvent: (WeekendEvent) -> Void
    var syncStateForEvent: (WeekendEvent) -> SyncState
    var isImportedEvent: (WeekendEvent) -> Bool
    var conflictStateForEvent: (WeekendEvent) -> ImportConflictState
    var onAcknowledgeConflict: (WeekendEvent) -> Void
    @State private var eventToRemove: WeekendEvent?
    @State private var eventToEdit: WeekendEvent?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsStatusBanner {
                weekendStatusBanner
            }

            VStack(alignment: .leading, spacing: 12) {
                if !showsStatusBanner {
                    HStack(alignment: .center, spacing: 8) {
                        Text(state.holidayRangeLabel(for: weekendKey))
                            .font(.subheadline.weight(.medium))
                        weekendMetaIcons
                        Spacer(minLength: 8)
                        compactStatusLabel
                    }
                }

                ForEach(Array(displayDays.enumerated()), id: \.element) { index, day in
                    if index > 0 {
                        Divider()
                            .overlay(AppSurfaceStyle.settingsSeparator)
                    }
                    DayColumnView(
                        day: day,
                        dayDate: state.plannerDisplayDate(for: weekendKey, day: day),
                        events: eventsForDay(day),
                        holidayPills: holidayPillsForDay(day),
                        status: status,
                        onEdit: { eventToEdit = $0 },
                        onMove: { eventToEdit = $0 },
                        onDuplicate: onDuplicateEvent,
                        onRemove: { eventToRemove = $0 },
                        syncStateForEvent: syncStateForEvent,
                        isImportedEvent: isImportedEvent,
                        conflictStateForEvent: conflictStateForEvent,
                        onAcknowledgeConflict: onAcknowledgeConflict,
                        onDeleteReminderPill: { pill in
                            state.dismissHolidayInfoPill(pill)
                        }
                    )
                }

            }
            .padding(14)
        }
        .background(AppSurfaceStyle.settingsCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppSurfaceStyle.primaryCardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppSurfaceStyle.primaryCardCornerRadius, style: .continuous)
                .stroke(AppSurfaceStyle.settingsSeparator, lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("\(PageEdgeLayoutContract.plannerWeekendCardIDPrefix)\(weekendKey)")
        .contentShape(RoundedRectangle(cornerRadius: AppSurfaceStyle.primaryCardCornerRadius, style: .continuous))
        .onTapGesture {
            onTap()
        }
        .alert(item: $eventToRemove) { event in
            Alert(
                title: Text("Remove this plan?"),
                message: Text(event.title),
                primaryButton: .destructive(Text("Remove")) {
                    onRemoveEvent(event)
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(item: $eventToEdit) { event in
            AddPlanView(
                weekendKey: event.weekendKey,
                bypassProtection: true,
                editingEvent: event
            )
        }
    }

    private var weekendKey: String {
        CalendarHelper.formatKey(weekend.saturday)
    }

    private var displayDays: [WeekendDay] {
        state.visiblePlannerDays(for: weekendKey, events: events)
    }

    private func eventsForDay(_ day: WeekendDay) -> [WeekendEvent] {
        state.plannerDisplayEvents(for: weekendKey, day: day, events: events)
    }

    private func holidayPillsForDay(_ day: WeekendDay) -> [HolidayInfoPill] {
        state.holidayInfoPills(for: weekendKey, day: day, events: events)
    }

    private var showsStatusBanner: Bool {
        status.type == "travel" || status.type == "plan" || status.type == "free"
    }

    private var compactStatusLabel: some View {
        Text(status.label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var weekendMetaIcons: some View {
        if hasWeekendNote {
            Image(systemName: "note.text")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(6)
                .background(AppSurfaceStyle.settingsChipBackground)
                .clipShape(Circle())
                .accessibilityLabel("Weekend note available")
        }
        if hasPendingConflict {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(6)
                .background(AppSurfaceStyle.settingsChipBackground)
                .clipShape(Circle())
                .accessibilityLabel("Conflict needs review")
        }
    }

    private var weekendStatusBanner: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(state.holidayRangeLabel(for: weekendKey))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                weekendMetaIcons
            }
            Spacer(minLength: 8)
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: statusBannerSymbol)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(statusBannerColor)
                Text(statusBannerTitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            LinearGradient(
                colors: [
                    statusBannerColor.opacity(0.24),
                    statusBannerColor.opacity(0.1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(statusBannerColor.opacity(0.22))
                .frame(height: 1)
        }
    }

    private var statusBannerColor: Color {
        switch status.type {
        case "travel":
            return .travelCoral
        case "plan":
            return .planBlue
        default:
            return .freeGreen
        }
    }

    private var statusBannerTitle: String {
        switch status.type {
        case "travel":
            return "Travel plans"
        case "plan":
            return "Local plans"
        case "free":
            return "Free weekend"
        default:
            return status.label
        }
    }

    private var statusBannerSymbol: String {
        switch status.type {
        case "travel":
            return "airplane.departure"
        case "plan":
            return "mappin.and.ellipse"
        default:
            return "sparkles"
        }
    }
}

struct DayColumnView: View {
    let day: WeekendDay
    let dayDate: Date?
    let events: [WeekendEvent]
    let holidayPills: [HolidayInfoPill]
    let status: WeekendStatus
    var onEdit: (WeekendEvent) -> Void
    var onMove: (WeekendEvent) -> Void
    var onDuplicate: (WeekendEvent) -> Void
    var onRemove: (WeekendEvent) -> Void
    var syncStateForEvent: (WeekendEvent) -> SyncState
    var isImportedEvent: (WeekendEvent) -> Bool
    var conflictStateForEvent: (WeekendEvent) -> ImportConflictState
    var onAcknowledgeConflict: (WeekendEvent) -> Void
    var onDeleteReminderPill: (HolidayInfoPill) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(dayHeaderLabel)
                    .font(.caption.weight(.semibold))
                    .tracking(1)
                    .foregroundColor(.secondary)
                Spacer(minLength: 8)
                if !holidayPills.isEmpty {
                    DayHeaderPillsView(pills: holidayPills, onDeleteReminder: onDeleteReminderPill)
                }
            }

            if events.isEmpty {
                if status.type == "protected" {
                    Text("Protected")
                        .font(.footnote.weight(.medium))
                        .italic()
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        TimelineItemView(
                            event: event,
                            syncState: syncStateForEvent(event),
                            isImported: isImportedEvent(event),
                            importConflictState: conflictStateForEvent(event),
                            onEdit: { onEdit(event) },
                            onMove: { onMove(event) },
                            onDuplicate: { onDuplicate(event) },
                            onRemove: { onRemove(event) },
                            onAcknowledgeConflict: { onAcknowledgeConflict(event) }
                        )

                        if index < events.count - 1 {
                            Divider()
                                .overlay(AppSurfaceStyle.settingsSeparator)
                                .padding(.leading, 18)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dayHeaderLabel: String {
        guard let dayDate else { return day.label }
        return "\(day.label) \(CalendarHelper.dayFormatter.string(from: dayDate))"
    }
}

struct DayHeaderPillsView: View {
    let pills: [HolidayInfoPill]
    var onDeleteReminder: (HolidayInfoPill) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(pills) { pill in
                pillChip(for: pill)
            }
        }
    }

    private func pillBackgroundColor(for pill: HolidayInfoPill) -> Color {
        if pill.isAnnualLeave {
            return .planBlue
        }
        return Color(.sRGB, white: 0.38, opacity: 1)
    }

    private func pillStrokeColor(for pill: HolidayInfoPill) -> Color {
        if pill.isAnnualLeave {
            return Color.planBlue.opacity(0.45)
        }
        return Color.white.opacity(0.16)
    }

    @ViewBuilder
    private func pillChip(for pill: HolidayInfoPill) -> some View {
        let label = Text(pill.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(2)
            .truncationMode(.tail)
            .multilineTextAlignment(.center)
            .allowsTightening(true)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(width: 164)
            .frame(minHeight: 24)
            .background(pillBackgroundColor(for: pill))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(pillStrokeColor(for: pill), lineWidth: 1)
            )

        if pill.isRemovableReminder {
            label
                .contextMenu {
                    Button("Delete reminder", role: .destructive) {
                        onDeleteReminder(pill)
                    }
                }
        } else {
            label
        }
    }
}

struct SupplementalReminderLineView: View {
    let day: WeekendDay
    let date: Date
    let pills: [HolidayInfoPill]
    var onDeleteReminderPill: (HolidayInfoPill) -> Void = { _ in }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(dateLabel)
                .font(.caption2.weight(.semibold))
                .tracking(0.3)
                .foregroundStyle(.secondary)
                .frame(minWidth: 74, alignment: .leading)

            Rectangle()
                .fill(AppSurfaceStyle.settingsSeparator)
                .frame(height: 1)

            DayHeaderPillsView(pills: pills, onDeleteReminder: onDeleteReminderPill)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dateLabel: String {
        "\(day.shortLabel) \(Self.dateFormatter.string(from: date))"
    }
}

struct BetweenWeekendReminderRowsView: View {
    let reminderLines: [SupplementalReminderLine]
    var onTapReminder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(reminderLines) { reminderLine in
                Button(action: onTapReminder) {
                    BetweenWeekendReminderRowView(reminderLine: reminderLine)
                }
                .buttonStyle(BetweenWeekendReminderButtonStyle())
                .accessibilityIdentifier(
                    "\(PageEdgeLayoutContract.plannerInterCardReminderRowIDPrefix)\(reminderLine.id)"
                )
                .accessibilityLabel("Birthdays and reminders")
                .accessibilityHint("Opens reminder settings")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
    }
}

private struct BetweenWeekendReminderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.988 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct BetweenWeekendReminderRowView: View {
    let reminderLine: SupplementalReminderLine

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "bell.badge.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(AppSurfaceStyle.settingsChipBackground.opacity(0.7))
                    .clipShape(Circle())

                Text(dateLabel)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.secondary.opacity(0.88))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
            BetweenWeekendReminderPillsView(pills: reminderLine.pills)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(minHeight: 38)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.clear)
        .overlay(
            Capsule()
                .stroke(AppSurfaceStyle.settingsSeparator.opacity(0.65), lineWidth: 1)
        )
        .contentShape(Capsule())
    }

    private var dateLabel: String {
        Self.dateFormatter.string(from: reminderLine.date)
    }
}

private struct BetweenWeekendReminderPillsView: View {
    let pills: [HolidayInfoPill]

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(pills) { pill in
                Text(pill.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                    .allowsTightening(true)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(width: 164)
                    .frame(minHeight: 24)
                    .background(Color(.sRGB, white: 0.38, opacity: 1))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )
            }
        }
    }
}

struct TimelineItemView: View {
    @State private var showingSyncStatusInfo = false
    let event: WeekendEvent
    let syncState: SyncState
    let isImported: Bool
    let importConflictState: ImportConflictState
    var onEdit: () -> Void
    var onMove: () -> Void
    var onDuplicate: () -> Void
    var onRemove: () -> Void
    var onAcknowledgeConflict: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(event.planType == .travel ? Color.travelCoral : Color.planBlue)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 4) {
                    Text(timeLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(event.title)
                        .font(.subheadline.weight(.medium))
                    if isImported {
                        Label("Imported", systemImage: "arrow.down.circle")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .labelStyle(.iconOnly)
                            .padding(.leading, 2)
                            .accessibilityLabel("Imported calendar event")
                    }
                }

                Spacer()
                HStack(spacing: 8) {
                    if importConflictState == .pending {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.orange)
                            .frame(width: 22, height: 22)
                            .background(Color.orange.opacity(0.14))
                            .clipShape(Circle())
                            .accessibilityLabel("Conflict pending")
                    } else if importConflictState == .acknowledged {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 22, height: 22)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Circle())
                            .accessibilityLabel("Conflict acknowledged")
                    }
                    if syncState != .synced {
                        Button {
                            showingSyncStatusInfo = true
                        } label: {
                            Image(systemName: syncIcon)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(syncColor)
                                .frame(width: 22, height: 22)
                                .background(syncColor.opacity(0.14))
                                .clipShape(Circle())
                                .accessibilityLabel(syncLabel)
                        }
                        .buttonStyle(.plain)
                    }

                    Menu {
                        Button {
                            onEdit()
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button {
                            onMove()
                        } label: {
                            Label("Move to another weekend", systemImage: "arrowshape.turn.up.right")
                        }
                        Button {
                            onDuplicate()
                        } label: {
                            Label("Duplicate to next weekend", systemImage: "plus.square.on.square")
                        }
                        if importConflictState == .pending {
                            Divider()
                            Button {
                                onAcknowledgeConflict()
                            } label: {
                                Label("Acknowledge conflict warning", systemImage: "checkmark.circle")
                            }
                        }
                        Divider()
                        Button(role: .destructive) {
                            onRemove()
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.title3.weight(.semibold))
                            .frame(width: 30, height: 30)
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("More actions")
                }
            }

        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .alert(syncStatusAlertTitle, isPresented: $showingSyncStatusInfo) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(syncStatusAlertMessage)
        }
    }

    private func formatTime(_ value: String) -> String {
        let parts = value.split(separator: ":")
        guard parts.count >= 2 else { return value }
        return "\(parts[0]):\(parts[1])"
    }

    private var timeLabel: String {
        if event.isAllDay {
            return "All day"
        }
        return "\(formatTime(event.startTime)) - \(formatTime(event.endTime))"
    }

    private var syncLabel: String {
        switch syncState {
        case .pending: return "Pending"
        case .retrying: return "Retrying"
        case .synced: return "Synced"
        }
    }

    private var syncIcon: String {
        switch syncState {
        case .pending: return "icloud.and.arrow.up"
        case .retrying: return "arrow.clockwise.circle.fill"
        case .synced: return "checkmark.circle.fill"
        }
    }

    private var syncColor: Color {
        switch syncState {
        case .pending: return .orange
        case .retrying: return .red
        case .synced: return .secondary
        }
    }

    private var syncStatusAlertTitle: String {
        switch syncState {
        case .pending:
            return "Sync queued"
        case .retrying:
            return "Sync issue"
        case .synced:
            return "Synced"
        }
    }

    private var syncStatusAlertMessage: String {
        switch syncState {
        case .pending:
            return "This plan is queued to sync to the cloud. No action is needed unless it stays like this for several minutes."
        case .retrying:
            return "This plan couldn't sync yet. The app will retry automatically. If it keeps happening, check internet connection and sign-in status."
        case .synced:
            return "This plan is synced."
        }
    }
}

struct WeekendDetailsView: View {
    @EnvironmentObject private var state: AppState
    let weekendKey: String
    var onAddPlans: (String, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showProtectionPrompt = false
    @State private var showBlockedAlert = false
    @State private var eventToRemove: WeekendEvent?
    @State private var eventToEdit: WeekendEvent?
    @State private var showAddProtectedPrompt = false
    @State private var carryForwardResultMessage: String?
    @State private var weekendNoteDraft = ""
    @State private var savedWeekendNoteDraft = ""
    @State private var selectedDetent: PresentationDetent = .large

    var body: some View {
        let events = state.events(for: weekendKey)
        let isProtected = state.isProtected(weekendKey)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(state.holidayRangeLabel(for: weekendKey))
                    .font(.title3.weight(.semibold))

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 8) {
                        Label("Weekend note", systemImage: "note.text")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 8)
                        Button {
                            guard hasUnsavedWeekendNoteChanges else { return }
                            state.setWeekendNote(weekendKey: weekendKey, note: weekendNoteDraft)
                            savedWeekendNoteDraft = weekendNoteDraft
                        } label: {
                            Text(hasUnsavedWeekendNoteChanges ? "Save changes" : "Saved")
                        }
                        .buttonStyle(
                            PillButtonStyle(
                                fill: hasUnsavedWeekendNoteChanges ? AppSurfaceStyle.primaryButtonFill : Color.green.opacity(0.18),
                                foreground: hasUnsavedWeekendNoteChanges ? AppSurfaceStyle.primaryButtonForeground : Color.green
                            )
                        )
                    }
                TextEditor(text: $weekendNoteDraft)
                    .font(.callout)
                    .frame(minHeight: 92, maxHeight: 130)
                    .padding(8)
                    .background(AppSurfaceStyle.dayItemFill)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppSurfaceStyle.dayStroke, lineWidth: 1)
                    )
                }
                .padding(12)
                .background(AppSurfaceStyle.dayCardFill)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppSurfaceStyle.dayStroke, lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(visibleDays.enumerated()), id: \.element) { index, day in
                        if index > 0 {
                            Divider()
                                .overlay(AppSurfaceStyle.settingsSeparator)
                        }
                        DayDetailColumn(
                            day: day,
                            dayDate: state.plannerDisplayDate(for: weekendKey, day: day),
                            events: eventsFor(day),
                            holidayPills: holidayPillsFor(day),
                            isProtected: isProtected,
                            onEdit: { eventToEdit = $0 },
                            onMove: { eventToEdit = $0 },
                            onDuplicate: duplicateEvent,
                            onRemove: { eventToRemove = $0 },
                            syncStateForEvent: { event in state.syncState(for: event.id) },
                            isImportedEvent: { event in state.isImportedEvent(event.id) },
                            conflictStateForEvent: { event in state.importConflictState(for: event.id) },
                            onAcknowledgeConflict: { event in state.acknowledgeConflict(eventId: event.id) },
                            onDeleteReminderPill: { pill in
                                state.dismissHolidayInfoPill(pill)
                            }
                        )
                    }

                    if !supplementalReminderLines.isEmpty {
                        if !visibleDays.isEmpty {
                            Divider()
                                .overlay(AppSurfaceStyle.settingsSeparator)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(supplementalReminderLines) { reminderLine in
                                SupplementalReminderLineView(
                                    day: reminderLine.day,
                                    date: reminderLine.date,
                                    pills: reminderLine.pills,
                                    onDeleteReminderPill: { pill in
                                        state.dismissHolidayInfoPill(pill)
                                    }
                                )
                            }
                        }
                    }
                }

                HStack {
                    Toggle(isOn: Binding(
                        get: { isProtected },
                        set: { shouldProtect in
                            guard shouldProtect != isProtected else { return }
                            if shouldProtect {
                                if events.isEmpty {
                                    Task { await state.toggleProtection(weekendKey: weekendKey, removePlans: false) }
                                } else {
                                    showProtectionPrompt = true
                                }
                            } else {
                                Task { await state.toggleProtection(weekendKey: weekendKey, removePlans: false) }
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Protect weekend")
                            Text(isProtected ? "Protected" : "Not protected")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(.planBlue)
                }

                Button("Add plans for this weekend") {
                    if isProtected {
                        if state.protectionMode == .block {
                            showBlockedAlert = true
                            return
                        }
                        showAddProtectedPrompt = true
                    } else {
                        onAddPlans(weekendKey, false)
                        dismiss()
                    }
                }
                .buttonStyle(
                    PillButtonStyle(
                        fill: AppSurfaceStyle.primaryButtonFill,
                        foreground: AppSurfaceStyle.primaryButtonForeground
                    )
                )

                if let nextWeekendKey = CalendarHelper.nextWeekendKey(after: weekendKey) {
                    Button("Move incomplete plans to next weekend") {
                        Task {
                            let count = await state.carryForwardIncompleteEvents(
                                fromWeekendKey: weekendKey,
                                toWeekendKey: nextWeekendKey
                            )
                            carryForwardResultMessage = count == 0
                                ? "No incomplete plans were moved."
                                : "\(count) plan\(count == 1 ? "" : "s") moved to next weekend."
                        }
                    }
                    .buttonStyle(OutlinePillButtonStyle(stroke: AppSurfaceStyle.cardStroke, foreground: .primary))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .onAppear {
            let storedNote = state.weekendNote(for: weekendKey)
            weekendNoteDraft = storedNote
            savedWeekendNoteDraft = storedNote
        }
        .confirmationDialog(
            "This weekend already has plans",
            isPresented: $showProtectionPrompt,
            titleVisibility: .visible
        ) {
            Button("Remove all plans & protect", role: .destructive) {
                Task { await state.toggleProtection(weekendKey: weekendKey, removePlans: true) }
            }
            Button("Keep existing plans") {
                Task { await state.toggleProtection(weekendKey: weekendKey, removePlans: false) }
            }
        } message: {
            Text("Do you want to remove existing plans before protecting?")
        }
        .alert("Protected weekend", isPresented: $showBlockedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This weekend is protected. Remove protection to add plans.")
        }
        .confirmationDialog(
            "This weekend is protected",
            isPresented: $showAddProtectedPrompt,
            titleVisibility: .visible
        ) {
            Button("Add anyway") {
                onAddPlans(weekendKey, true)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Do you want to add plans anyway?")
        }
        .alert(item: $eventToRemove) { event in
            Alert(
                title: Text("Remove this plan?"),
                message: Text(event.title),
                primaryButton: .destructive(Text("Remove")) {
                    Task { await state.removeEvent(event) }
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(item: $eventToEdit) { event in
            AddPlanView(
                weekendKey: event.weekendKey,
                bypassProtection: true,
                editingEvent: event
            )
        }
        .alert("Carry-forward result", isPresented: Binding(
            get: { carryForwardResultMessage != nil },
            set: { if !$0 { carryForwardResultMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(carryForwardResultMessage ?? "")
        }
    }

    private func eventsFor(_ day: WeekendDay) -> [WeekendEvent] {
        state.plannerDisplayEvents(for: weekendKey, day: day, events: state.events(for: weekendKey))
    }

    private func holidayPillsFor(_ day: WeekendDay) -> [HolidayInfoPill] {
        state.holidayInfoPills(for: weekendKey, day: day, events: state.events(for: weekendKey))
    }

    private var visibleDays: [WeekendDay] {
        state.visiblePlannerDays(for: weekendKey, events: state.events(for: weekendKey))
    }

    private var supplementalReminderLines: [SupplementalReminderLine] {
        state.supplementalReminderLines(for: weekendKey, events: state.events(for: weekendKey))
    }

    private func duplicateEvent(_ event: WeekendEvent) {
        guard let targetWeekendKey = CalendarHelper.nextWeekendKey(after: event.weekendKey) else { return }
        Task {
            _ = await state.duplicateEvent(eventId: event.id, toWeekendKey: targetWeekendKey)
        }
    }

    private var hasUnsavedWeekendNoteChanges: Bool {
        normalizedWeekendNote(weekendNoteDraft) != normalizedWeekendNote(savedWeekendNoteDraft)
    }

    private func normalizedWeekendNote(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct DayDetailColumn: View {
    let day: WeekendDay
    let dayDate: Date?
    let events: [WeekendEvent]
    let holidayPills: [HolidayInfoPill]
    let isProtected: Bool
    var onEdit: (WeekendEvent) -> Void
    var onMove: (WeekendEvent) -> Void
    var onDuplicate: (WeekendEvent) -> Void
    var onRemove: (WeekendEvent) -> Void
    var syncStateForEvent: (WeekendEvent) -> SyncState
    var isImportedEvent: (WeekendEvent) -> Bool
    var conflictStateForEvent: (WeekendEvent) -> ImportConflictState
    var onAcknowledgeConflict: (WeekendEvent) -> Void
    var onDeleteReminderPill: (HolidayInfoPill) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(dayHeaderLabel)
                    .font(.caption.weight(.semibold))
                    .tracking(1)
                    .foregroundColor(.secondary)
                Spacer(minLength: 8)
                if !holidayPills.isEmpty {
                    DayHeaderPillsView(pills: holidayPills, onDeleteReminder: onDeleteReminderPill)
                }
            }

            if events.isEmpty {
                if isProtected {
                    Text("Protected")
                        .font(.footnote.weight(.medium))
                        .italic()
                        .foregroundColor(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppSurfaceStyle.dayItemFill)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(AppSurfaceStyle.dayStroke, lineWidth: 1)
                        )
                }
            } else {
                ForEach(events) { event in
                    TimelineItemView(
                        event: event,
                        syncState: syncStateForEvent(event),
                        isImported: isImportedEvent(event),
                        importConflictState: conflictStateForEvent(event),
                        onEdit: { onEdit(event) },
                        onMove: { onMove(event) },
                        onDuplicate: { onDuplicate(event) },
                        onRemove: { onRemove(event) },
                        onAcknowledgeConflict: { onAcknowledgeConflict(event) }
                    )
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppSurfaceStyle.dayCardFill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppSurfaceStyle.dayStroke, lineWidth: 1)
        )
    }

    private var dayHeaderLabel: String {
        guard let dayDate else { return day.label }
        return "\(day.label) \(CalendarHelper.dayFormatter.string(from: dayDate))"
    }
}

struct AddPlanView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    let weekendKey: String?
    let bypassProtection: Bool
    let editingEvent: WeekendEvent?
    let initialDate: Date?

    @State private var title = ""
    @State private var planType: PlanType = .plan
    @State private var startDateTime: Date
    @State private var endDateTime: Date
    @State private var allDay = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showProtectedPrompt = false
    @State private var exportToCalendar = false
    @State private var calendarConflicts: [CalendarConflict] = []
    @State private var isCheckingConflicts = false
    @State private var hasInitialized = false
    @State private var eventDescription = ""
    @State private var selectedCalendarIDs: Set<String> = []
    @State private var repeatOption: EventRepeatOption = .never
    @State private var isApplyingDateNormalization = false
    @State private var conflictRefreshTask: Task<Void, Never>?
    @State private var dateSelectionConstraintMessage: String?

    init(
        weekendKey: String?,
        bypassProtection: Bool,
        editingEvent: WeekendEvent? = nil,
        initialDate: Date? = nil
    ) {
        self.weekendKey = weekendKey
        self.bypassProtection = bypassProtection
        self.editingEvent = editingEvent
        self.initialDate = initialDate

        let calendar = CalendarHelper.calendar
        let baseDate: Date
        if let editingEvent,
           let editingDate = Self.defaultWeekendDate(from: editingEvent.weekendKey) {
            baseDate = editingDate
        } else if let initialDate {
            baseDate = CalendarHelper.calendar.startOfDay(for: initialDate)
        } else if let weekendKey,
                  let selectedDate = Self.defaultWeekendDate(from: weekendKey) {
            baseDate = selectedDate
        } else {
            baseDate = Date()
        }

        let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: baseDate) ?? baseDate
        let end = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: baseDate) ?? start.addingTimeInterval(3600)
        _startDateTime = State(initialValue: start)
        _endDateTime = State(initialValue: end)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Title")) {
                    TextField("Surf trip, wedding, retreat", text: $title)
                }

                Section(
                    header: Text("Description (optional)"),
                    footer: Text("Shown only when this specific plan is opened.")
                ) {
                    TextEditor(text: $eventDescription)
                        .frame(minHeight: 44, maxHeight: 44)
                }

                Section(
                    header: Text("Type"),
                    footer: Text("Select travel plans when you'll be away from home.")
                ) {
                    Picker("Type", selection: $planType) {
                        Text("Local plans").tag(PlanType.plan)
                        Text("Travel plans").tag(PlanType.travel)
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("Calendar")) {
                    if state.calendars.isEmpty {
                        Text("No calendars available.")
                            .foregroundColor(.secondary)
                    } else {
                        Menu {
                            ForEach(state.calendars) { calendar in
                                Button {
                                    selectPlannerCalendar(calendar.id)
                                } label: {
                                    HStack(spacing: 10) {
                                        Circle()
                                            .fill(calendarTintColor(for: calendar.id))
                                            .frame(width: 10, height: 10)
                                        Text(calendar.name)
                                        if selectedPlannerCalendar?.id == calendar.id {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Text("Calendar")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if let selectedPlannerCalendar {
                                    Circle()
                                        .fill(calendarTintColor(for: selectedPlannerCalendar.id))
                                        .frame(width: 10, height: 10)
                                    Text(selectedPlannerCalendar.name)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("None")
                                        .foregroundStyle(.secondary)
                                }
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section(
                    header: Text("Schedule"),
                    footer: scheduleFooter
                ) {
                    Toggle("All-day", isOn: $allDay)

                    scheduleRow(title: "Starts", selection: $startDateTime)
                    scheduleRow(title: "Ends", selection: $endDateTime)
                }

                Section {
                    Menu {
                        ForEach(EventRepeatOption.allCases) { option in
                            Button {
                                repeatOption = option
                            } label: {
                                HStack {
                                    Text(option.label)
                                    if repeatOption == option {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Text("Repeat")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(repeatOption.label)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section(header: Text("Apple Calendar")) {
                    HStack {
                        Text("Access")
                        Spacer()
                        Text(state.calendarPermissionState.label)
                            .foregroundColor(.secondary)
                    }

                    if state.calendarPermissionState == .notDetermined {
                        Button("Enable calendar access") {
                            Task { await state.requestCalendarPermissionIfNeeded() }
                        }
                    } else if state.calendarPermissionState == .denied || state.calendarPermissionState == .restricted {
                        Button("Open iOS Settings") {
                            openSystemSettings()
                        }
                    }

                    Toggle("Add this plan to Apple Calendar", isOn: $exportToCalendar)
                        .onChange(of: exportToCalendar) { _, shouldExport in
                            guard shouldExport else { return }
                            guard !state.calendarPermissionState.canWriteEvents else { return }
                            Task {
                                await state.requestCalendarPermissionIfNeeded()
                                if !state.calendarPermissionState.canWriteEvents {
                                    exportToCalendar = false
                                }
                            }
                        }
                }

                if state.calendarPermissionState.canReadEvents && !calendarConflicts.isEmpty {
                    Section(header: Text("Calendar conflicts")) {
                        Text("This plan overlaps with existing Apple Calendar events.")
                            .font(.callout)
                            .foregroundColor(.red)
                        Text("Conflicts are informational only and do not change your selected dates.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ForEach(calendarConflicts.prefix(3)) { conflict in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(conflict.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(conflictDetailText(conflict))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

            }
            .navigationTitle(isEditing ? "Edit weekend event" : "")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save changes" : "Add your new plan") {
                        Task { await handleSubmit() }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                configureInitialState()
                normalizeDateSelection()
                scheduleConflictRefresh()
            }
            .onChange(of: weekendKey) { _, newValue in
                guard !isEditing, let newValue else { return }
                applyDefaultWeekendDate(from: newValue)
                normalizeDateSelection()
            }
            .onChange(of: startDateTime) { _, _ in
                normalizeDateSelection()
            }
            .onChange(of: endDateTime) { _, _ in
                normalizeDateSelection()
            }
            .onChange(of: allDay) { _, _ in
                normalizeDateSelection()
            }
            .onChange(of: state.weekendConfiguration) { _, _ in
                normalizeDateSelection()
            }
            .onChange(of: state.annualLeaveDays) { _, _ in
                normalizeDateSelection()
            }
            .onChange(of: conflictTaskToken) { _, _ in
                scheduleConflictRefresh()
            }
            .onDisappear {
                conflictRefreshTask?.cancel()
            }
            .alert("Oops", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .confirmationDialog(
                "Protected weekend",
                isPresented: $showProtectedPrompt,
                titleVisibility: .visible
            ) {
                Button("Add anyway") {
                    Task { await savePlan(force: true) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This weekend is protected. Do you want to add plans anyway?")
            }
        }
    }

    private var isEditing: Bool {
        editingEvent != nil
    }

    private var plannerWeekKey: String {
        state.plannerDisplayWeekKey(for: startDateTime)
    }

    private var selectedDays: Set<WeekendDay> {
        selectionDetails?.days ?? []
    }

    private var conflictTaskToken: String {
        let daysToken = selectedDays
            .sorted { $0.plannerRowSortOrder < $1.plannerRowSortOrder }
            .map(\.rawValue)
            .joined(separator: ",")
        return "\(plannerWeekKey)|\(daysToken)|\(allDay)|\(Int(startDateTime.timeIntervalSince1970))|\(Int(endDateTime.timeIntervalSince1970))|\(editingEvent?.id ?? "new")|\(state.calendarPermissionState.rawValue)"
    }

    private func handleSubmit() async {
        await savePlan(force: bypassProtection)
    }

    private func configureInitialState() {
        guard !hasInitialized else { return }
        defer { hasInitialized = true }
        dateSelectionConstraintMessage = nil

        if let editingEvent {
            title = editingEvent.title
            planType = editingEvent.planType
            eventDescription = state.eventDescription(for: editingEvent.id)
            let attributedCalendarIDs = Set(state.eventCalendarIDs(for: editingEvent.id))
            if let selectedCalendarId = state.selectedCalendarId,
               attributedCalendarIDs.contains(selectedCalendarId) {
                // Keep the edit context aligned with the currently visible calendar.
                selectedCalendarIDs = [selectedCalendarId]
            } else if let primaryCalendarId = editingEvent.calendarId,
                      attributedCalendarIDs.contains(primaryCalendarId) {
                selectedCalendarIDs = [primaryCalendarId]
            } else if let fallback = attributedCalendarIDs.sorted().first {
                selectedCalendarIDs = [fallback]
            } else if let calendarId = editingEvent.calendarId {
                selectedCalendarIDs = [calendarId]
            }
            allDay = editingEvent.isAllDay

            let sortedDays = editingEvent.dayValues
                .sorted { $0.plannerRowSortOrder < $1.plannerRowSortOrder }
            let startDay = sortedDays.first
            let endDay = sortedDays.last ?? startDay
            let startDate = startDay
                .flatMap { state.plannerDisplayDate(for: editingEvent.weekendKey, day: $0) }
                ?? Self.defaultWeekendDate(from: editingEvent.weekendKey, preferredDay: startDay)
                ?? Date()
            let endDate = endDay
                .flatMap { state.plannerDisplayDate(for: editingEvent.weekendKey, day: $0) }
                ?? Self.defaultWeekendDate(from: editingEvent.weekendKey, preferredDay: endDay)
                ?? startDate

            if allDay {
                startDateTime = CalendarHelper.calendar.startOfDay(for: startDate)
                endDateTime = CalendarHelper.calendar.date(bySettingHour: 23, minute: 59, second: 0, of: endDate) ?? endDate
            } else {
                startDateTime = dateByApplying(timeString: editingEvent.startTime, toDay: startDate)
                    ?? CalendarHelper.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: startDate)
                    ?? startDate
                endDateTime = dateByApplying(timeString: editingEvent.endTime, toDay: startDate)
                    ?? CalendarHelper.calendar.date(bySettingHour: 17, minute: 0, second: 0, of: startDate)
                    ?? startDateTime.addingTimeInterval(3600)
            }

            exportToCalendar = state.isEventExportedToCalendar(eventId: editingEvent.id)
            return
        }

        if let initialDate {
            let normalized = CalendarHelper.calendar.startOfDay(for: initialDate)
            let startComponents = CalendarHelper.calendar.dateComponents([.hour, .minute], from: startDateTime)
            let endComponents = CalendarHelper.calendar.dateComponents([.hour, .minute], from: endDateTime)
            startDateTime = dateByApplying(timeComponents: startComponents, toDay: normalized) ?? normalized
            endDateTime = dateByApplying(timeComponents: endComponents, toDay: normalized) ?? startDateTime
        } else if let key = weekendKey {
            applyDefaultWeekendDate(from: key)
        }
        if selectedCalendarIDs.isEmpty {
            if let selected = state.selectedCalendarId {
                selectedCalendarIDs = [selected]
            } else if let first = state.calendars.first?.id {
                selectedCalendarIDs = [first]
            }
        }
    }

    private func applyDefaultWeekendDate(from key: String) {
        let preferred = state.preferredOffDayDate(for: key) ?? Self.defaultWeekendDate(from: key)
        guard let selectedDate = preferred else { return }
        let startTime = CalendarHelper.calendar.dateComponents([.hour, .minute], from: startDateTime)
        let endTime = CalendarHelper.calendar.dateComponents([.hour, .minute], from: endDateTime)
        startDateTime = dateByApplying(timeComponents: startTime, toDay: selectedDate)
            ?? selectedDate
        endDateTime = dateByApplying(timeComponents: endTime, toDay: selectedDate)
            ?? startDateTime
    }

    private static func defaultWeekendDate(from key: String, preferredDay: WeekendDay? = nil) -> Date? {
        guard let parsed = CalendarHelper.parseKey(key) else { return nil }
        let normalizedKey = CalendarHelper.plannerWeekKey(for: parsed)
        guard let day = preferredDay else {
            return CalendarHelper.parseKey(normalizedKey).map { CalendarHelper.calendar.startOfDay(for: $0) }
        }
        return CalendarHelper.dateForPlannerDay(day, weekendKey: normalizedKey)
            ?? CalendarHelper.parseKey(normalizedKey)
            ?? parsed
    }

    private var weekendDateRange: ClosedRange<Date> {
        CalendarHelper.planningDateRange()
    }

    private func savePlan(force: Bool) async {
        guard let selection = selectionDetails else {
            errorMessage = "Choose start and end dates from configured holidays."
            showError = true
            return
        }
        let weekendKey = selection.weekendKey

        if selection.days.isEmpty {
            errorMessage = "Please choose at least one holiday in this week."
            showError = true
            return
        }

        if !allDay && !CalendarHelper.calendar.isDate(startDateTime, inSameDayAs: endDateTime) {
            errorMessage = "Timed plans must start and end on the same holiday."
            showError = true
            return
        }

        if selectedCalendarIDs.isEmpty {
            errorMessage = "Please select at least one calendar."
            showError = true
            return
        }

        if state.isProtected(weekendKey) && !force {
            if state.protectionMode == .block {
                errorMessage = "This weekend is protected. Remove protection to add plans."
                showError = true
                return
            }
            showProtectedPrompt = true
            return
        }

        if exportToCalendar && !state.calendarPermissionState.canWriteEvents {
            await state.requestCalendarPermissionIfNeeded()
            guard state.calendarPermissionState.canWriteEvents else {
                errorMessage = "Apple Calendar access is required to export this plan."
                showError = true
                exportToCalendar = false
                return
            }
        }

        let startString = allDay ? "00:00" : CalendarHelper.timeString(from: startDateTime)
        let endString = allDay ? "23:59" : CalendarHelper.timeString(from: endDateTime)
        if !allDay && endDateTime <= startDateTime {
            errorMessage = "End time should be after start time."
            showError = true
            return
        }

        let sortedDays = selection.days
            .sorted { lhs, rhs in
                let left = selection.dayDateByDay[lhs]
                    ?? state.plannerDisplayDate(for: weekendKey, day: lhs)
                    ?? Date.distantFuture
                let right = selection.dayDateByDay[rhs]
                    ?? state.plannerDisplayDate(for: weekendKey, day: rhs)
                    ?? Date.distantFuture
                if left == right {
                    return lhs.plannerRowSortOrder < rhs.plannerRowSortOrder
                }
                return left < right
            }
            .map(\.rawValue)
        let orderedCalendarIDs = selectedCalendarIDs.sorted()
        let primaryCalendarID = preferredPrimaryCalendarID(
            from: orderedCalendarIDs,
            preferred: state.selectedCalendarId ?? editingEvent?.calendarId
        )
        let success: Bool

        if let editingEvent {
            let payload = UpdateWeekendEvent(
                title: title,
                type: planType.rawValue,
                calendarId: primaryCalendarID,
                attributedCalendarIDs: orderedCalendarIDs,
                weekendKey: weekendKey,
                days: sortedDays,
                startTime: startString,
                endTime: endString
            )
            success = await state.updateEvent(
                eventId: editingEvent.id,
                payload,
                exportToCalendar: exportToCalendar,
                attributedCalendarIDs: Set(orderedCalendarIDs)
            )
            if success {
                state.setEventDescription(for: editingEvent.id, description: eventDescription)
            }
        } else {
            guard let userId = state.session?.user.id.uuidString.lowercased() else { return }
            let newEventId = UUID().uuidString
            let payload = NewWeekendEvent(
                id: newEventId,
                title: title,
                type: planType.rawValue,
                calendarId: primaryCalendarID,
                attributedCalendarIDs: orderedCalendarIDs,
                weekendKey: weekendKey,
                days: sortedDays,
                startTime: startString,
                endTime: endString,
                userId: userId
            )
            success = await state.addEvent(
                payload,
                exportToCalendar: exportToCalendar,
                attributedCalendarIDs: Set(orderedCalendarIDs)
            )
            if success {
                state.setEventDescription(for: newEventId, description: eventDescription)
            }
        }

        if success {
            dismiss()
        }
    }

    @ViewBuilder
    private func scheduleRow(title: String, selection: Binding<Date>) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer()
            DatePicker(
                "",
                selection: selection,
                in: weekendDateRange,
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            if !allDay {
                DatePicker(
                    "",
                    selection: selection,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.compact)
            }
        }
    }

    private var scheduleFooterText: String {
        "Only configured holidays can be selected."
    }

    @ViewBuilder
    private var scheduleFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(scheduleFooterText)
            if let dateSelectionConstraintMessage {
                Text(dateSelectionConstraintMessage)
                    .foregroundColor(.orange)
            }
        }
    }

    private var selectedPlannerCalendar: PlannerCalendar? {
        if let selectedId = selectedCalendarIDs.first,
           let selected = state.calendars.first(where: { $0.id == selectedId }) {
            return selected
        }
        if let selectedId = state.selectedCalendarId,
           let selected = state.calendars.first(where: { $0.id == selectedId }) {
            return selected
        }
        return state.calendars.first
    }

    private func selectPlannerCalendar(_ calendarId: String) {
        selectedCalendarIDs = [calendarId]
    }

    private func calendarTintColor(for calendarId: String) -> Color {
        let palette: [Color] = [
            .planBlue,
            .travelCoral,
            .freeGreen,
            .pink,
            .orange,
            .teal,
            .indigo
        ]
        let scalarSum = calendarId.unicodeScalars.reduce(0) { partial, scalar in
            partial + Int(scalar.value)
        }
        return palette[abs(scalarSum) % palette.count]
    }

    private func normalizeDateSelection() {
        guard !isApplyingDateNormalization else { return }
        isApplyingDateNormalization = true
        defer { isApplyingDateNormalization = false }

        let calendar = CalendarHelper.calendar
        var adjustedStart = startDateTime
        var adjustedEnd = endDateTime
        let requestedEndDay = calendar.startOfDay(for: adjustedEnd)
        var clampReason: EndDateClampReason?

        guard let normalizedStartDay = normalizedOffDayDate(
            from: adjustedStart,
            preferredWeekKey: state.plannerDisplayWeekKey(for: adjustedStart)
        ) else {
            return
        }
        let preservedStartTime = calendar.dateComponents([.hour, .minute], from: adjustedStart)
        adjustedStart = dateByApplying(timeComponents: preservedStartTime, toDay: normalizedStartDay) ?? normalizedStartDay

        var weekKey = state.plannerDisplayWeekKey(for: adjustedStart)
        var options = state.availableDisplayOffDayOptions(for: weekKey)
        if options.isEmpty,
           let fallback = normalizedOffDayDate(from: adjustedStart, preferredWeekKey: nil) {
            let preservedEndTime = calendar.dateComponents([.hour, .minute], from: adjustedEnd)
            adjustedStart = dateByApplying(timeComponents: preservedStartTime, toDay: fallback) ?? fallback
            adjustedEnd = dateByApplying(timeComponents: preservedEndTime, toDay: fallback) ?? adjustedStart
            weekKey = state.plannerDisplayWeekKey(for: adjustedStart)
            options = state.availableDisplayOffDayOptions(for: weekKey)
        }

        guard !options.isEmpty else {
            startDateTime = adjustedStart
            endDateTime = adjustedEnd
            return
        }

        let optionDayKeys = Set(options.map { dayKey(for: $0.date) })
        if !optionDayKeys.contains(dayKey(for: adjustedStart)),
           let fallback = nearestOptionDate(to: adjustedStart, options: options) {
            adjustedStart = dateByApplying(timeComponents: preservedStartTime, toDay: fallback) ?? fallback
            weekKey = state.plannerDisplayWeekKey(for: adjustedStart)
            options = state.availableDisplayOffDayOptions(for: weekKey)
        }

        let finalOptionDayKeys = Set(options.map { dayKey(for: $0.date) })
        let endOutsidePlannerWeek = state.plannerDisplayWeekKey(for: adjustedEnd) != weekKey
        if endOutsidePlannerWeek || !finalOptionDayKeys.contains(dayKey(for: adjustedEnd)) {
            let target = nearestOptionDate(to: adjustedEnd, options: options)
                ?? CalendarHelper.calendar.startOfDay(for: adjustedStart)
            let preservedEndTime = calendar.dateComponents([.hour, .minute], from: adjustedEnd)
            adjustedEnd = dateByApplying(timeComponents: preservedEndTime, toDay: target) ?? target
            clampReason = endOutsidePlannerWeek ? .outsidePlannerWeek : .nonOffDay
        }

        let startDay = calendar.startOfDay(for: adjustedStart)
        var endDay = calendar.startOfDay(for: adjustedEnd)
        if endDay < startDay {
            adjustedEnd = dateByApplying(timeComponents: calendar.dateComponents([.hour, .minute], from: adjustedEnd), toDay: startDay) ?? adjustedEnd
            endDay = startDay
        }

        let contiguousBlock = contiguousOptionDays(containing: startDay, options: options)
        if !containsDay(contiguousBlock, day: endDay) {
            let fallbackDay: Date
            if allDay, let nearest = nearestDate(to: endDay, candidates: contiguousBlock) {
                fallbackDay = nearest
            } else {
                fallbackDay = startDay
            }
            adjustedEnd = dateByApplying(timeComponents: calendar.dateComponents([.hour, .minute], from: adjustedEnd), toDay: fallbackDay) ?? adjustedEnd
            endDay = fallbackDay
            if clampReason == nil {
                clampReason = .nonContiguous
            }
        }

        if allDay {
            adjustedStart = calendar.startOfDay(for: startDay)
            adjustedEnd = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: endDay) ?? adjustedEnd
        } else {
            if !calendar.isDate(adjustedStart, inSameDayAs: adjustedEnd) {
                adjustedEnd = dateByApplying(timeComponents: calendar.dateComponents([.hour, .minute], from: adjustedEnd), toDay: startDay) ?? adjustedEnd
            }
            if adjustedEnd <= adjustedStart {
                let oneHourLater = calendar.date(byAdding: .hour, value: 1, to: adjustedStart) ?? adjustedStart.addingTimeInterval(3600)
                let dayEnd = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: startDay) ?? oneHourLater
                adjustedEnd = min(oneHourLater, dayEnd)
            }
        }

        if adjustedStart != startDateTime {
            startDateTime = adjustedStart
        }
        if adjustedEnd != endDateTime {
            endDateTime = adjustedEnd
        }

        let finalEndDay = calendar.startOfDay(for: adjustedEnd)
        if !calendar.isDate(finalEndDay, inSameDayAs: requestedEndDay) {
            dateSelectionConstraintMessage = endDateConstraintMessage(
                requestedEndDay: requestedEndDay,
                adjustedEndDay: finalEndDay,
                startDay: startDay,
                allowedBlock: contiguousBlock,
                reason: clampReason
            )
        } else {
            dateSelectionConstraintMessage = nil
        }
    }

    private var selectionDetails: AddPlanSelectionDetails? {
        let calendar = CalendarHelper.calendar
        let weekendKey = state.plannerDisplayWeekKey(for: startDateTime)
        let startDay = calendar.startOfDay(for: startDateTime)
        let endDay = calendar.startOfDay(for: endDateTime)
        guard endDay >= startDay else { return nil }

        var cursor = startDay
        var daySelection = Set<WeekendDay>()
        var dayDateByDay: [WeekendDay: Date] = [:]
        while cursor <= endDay {
            guard state.isOffDay(cursor),
                  let plannerDay = state.plannerDisplayDay(for: cursor, weekendKey: weekendKey) else {
                return nil
            }
            daySelection.insert(plannerDay)
            dayDateByDay[plannerDay] = calendar.startOfDay(for: cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        guard !daySelection.isEmpty else { return nil }
        let isContiguous = AddPlanDaySelectionRules.isContiguousSelection(
            daySelection,
            available: state.availableDisplayOffDayOptions(for: weekendKey)
        )
        guard isContiguous else { return nil }
        return AddPlanSelectionDetails(weekendKey: weekendKey, days: daySelection, dayDateByDay: dayDateByDay)
    }

    private func dateByApplying(timeString: String, toDay day: Date) -> Date? {
        let parts = timeString.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return nil
        }
        return CalendarHelper.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    private func dateByApplying(timeComponents: DateComponents, toDay day: Date) -> Date? {
        let hour = timeComponents.hour ?? 0
        let minute = timeComponents.minute ?? 0
        return CalendarHelper.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    private func normalizedOffDayDate(from date: Date, preferredWeekKey: String?) -> Date? {
        let calendar = CalendarHelper.calendar
        let normalized = calendar.startOfDay(for: date)

        if state.isOffDay(normalized) {
            return normalized
        }

        if let preferredWeekKey {
            let options = state.availableDisplayOffDayOptions(for: preferredWeekKey)
            if let nearest = nearestOptionDate(to: normalized, options: options) {
                return calendar.startOfDay(for: nearest)
            }
        }

        let range = weekendDateRange
        var best: Date?
        var bestDistance: TimeInterval = .greatestFiniteMagnitude
        var cursor = calendar.startOfDay(for: range.lowerBound)
        let upperBound = calendar.startOfDay(for: range.upperBound)

        while cursor <= upperBound {
            if state.isOffDay(cursor) {
                let distance = abs(cursor.timeIntervalSince(normalized))
                if distance < bestDistance {
                    best = cursor
                    bestDistance = distance
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return best
    }

    private func nearestOptionDate(to date: Date, options: [OffDayOption]) -> Date? {
        let calendar = CalendarHelper.calendar
        let normalized = calendar.startOfDay(for: date)
        return options
            .map(\.date)
            .min {
                abs(calendar.startOfDay(for: $0).timeIntervalSince(normalized)) <
                abs(calendar.startOfDay(for: $1).timeIntervalSince(normalized))
            }
            .map { calendar.startOfDay(for: $0) }
    }

    private func contiguousOptionDays(containing date: Date, options: [OffDayOption]) -> [Date] {
        let calendar = CalendarHelper.calendar
        let sorted = options
            .map { calendar.startOfDay(for: $0.date) }
            .sorted()
        guard let index = sorted.firstIndex(where: { calendar.isDate($0, inSameDayAs: date) }) else {
            return sorted
        }

        var lower = index
        while lower > 0 {
            let previous = sorted[lower - 1]
            let current = sorted[lower]
            let delta = calendar.dateComponents([.day], from: previous, to: current).day ?? 0
            if delta == 1 {
                lower -= 1
            } else {
                break
            }
        }

        var upper = index
        while upper < sorted.count - 1 {
            let current = sorted[upper]
            let next = sorted[upper + 1]
            let delta = calendar.dateComponents([.day], from: current, to: next).day ?? 0
            if delta == 1 {
                upper += 1
            } else {
                break
            }
        }

        return Array(sorted[lower...upper])
    }

    private func containsDay(_ days: [Date], day: Date) -> Bool {
        let calendar = CalendarHelper.calendar
        return days.contains { calendar.isDate($0, inSameDayAs: day) }
    }

    private func nearestDate(to target: Date, candidates: [Date]) -> Date? {
        let calendar = CalendarHelper.calendar
        let normalized = calendar.startOfDay(for: target)
        return candidates.min {
            abs($0.timeIntervalSince(normalized)) < abs($1.timeIntervalSince(normalized))
        }
    }

    private func dayKey(for date: Date) -> String {
        CalendarHelper.formatKey(CalendarHelper.calendar.startOfDay(for: date))
    }

    private func endDateConstraintMessage(
        requestedEndDay: Date,
        adjustedEndDay: Date,
        startDay: Date,
        allowedBlock: [Date],
        reason: EndDateClampReason?
    ) -> String {
        let allowedStart = allowedBlock.first ?? startDay
        let allowedEnd = allowedBlock.last ?? startDay
        let adjustedLabel = formattedConstraintDate(adjustedEndDay)
        let requestedLabel = formattedConstraintDate(requestedEndDay)
        let allowedStartLabel = formattedConstraintDate(allowedStart)
        let allowedEndLabel = formattedConstraintDate(allowedEnd)

        if let reason {
            switch reason {
            case .outsidePlannerWeek:
                return "End date moved to \(adjustedLabel). \(requestedLabel) is in a different planner window than the selected start date (\(allowedStartLabel) - \(allowedEndLabel)). Existing full-day plans are not what caused this adjustment."
            case .nonOffDay:
                return "End date moved to \(adjustedLabel) because \(requestedLabel) is not currently an off day."
            case .nonContiguous:
                return "End date moved to \(adjustedLabel). One plan can only cover contiguous off days (\(allowedStartLabel) - \(allowedEndLabel))."
            }
        }

        return "End date moved to \(adjustedLabel)."
    }

    private enum EndDateClampReason {
        case outsidePlannerWeek
        case nonOffDay
        case nonContiguous
    }

    private func formattedConstraintDate(_ date: Date) -> String {
        Self.constraintDateFormatter.string(from: date)
    }

    private static let constraintDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        return formatter
    }()

    private func preferredPrimaryCalendarID(from calendarIDs: [String], preferred: String?) -> String? {
        if let preferred, calendarIDs.contains(preferred) {
            return preferred
        }
        if let selected = state.selectedCalendarId, calendarIDs.contains(selected) {
            return selected
        }
        return calendarIDs.first
    }

    private func scheduleConflictRefresh() {
        conflictRefreshTask?.cancel()
        conflictRefreshTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await refreshCalendarConflicts()
        }
    }

    private func refreshCalendarConflicts() async {
        guard state.calendarPermissionState.canReadEvents else {
            calendarConflicts = []
            return
        }
        guard let selection = selectionDetails else {
            calendarConflicts = []
            return
        }

        let intervals = selectionIntervals(selection)

        guard !intervals.isEmpty else {
            calendarConflicts = []
            return
        }

        isCheckingConflicts = true
        defer { isCheckingConflicts = false }
        calendarConflicts = await state.calendarConflicts(
            for: intervals,
            ignoringEventID: editingEvent?.id
        )
    }

    private func conflictDetailText(_ conflict: CalendarConflict) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "\(formatter.string(from: conflict.startDate)) - \(formatter.string(from: conflict.endDate)) • \(conflict.calendarName)"
    }

    private func openSystemSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }

    private func selectionIntervals(_ selection: AddPlanSelectionDetails) -> [DateInterval] {
        let calendar = CalendarHelper.calendar
        let startComponents = calendar.dateComponents([.hour, .minute], from: startDateTime)
        let endComponents = calendar.dateComponents([.hour, .minute], from: endDateTime)

        let sortedDays = selection.days.sorted { lhs, rhs in
            let left = selection.dayDateByDay[lhs]
                ?? state.plannerDisplayDate(for: selection.weekendKey, day: lhs)
                ?? Date.distantFuture
            let right = selection.dayDateByDay[rhs]
                ?? state.plannerDisplayDate(for: selection.weekendKey, day: rhs)
                ?? Date.distantFuture
            if left == right {
                return lhs.plannerRowSortOrder < rhs.plannerRowSortOrder
            }
            return left < right
        }

        var intervals: [DateInterval] = []
        for day in sortedDays {
            guard let dayDate = selection.dayDateByDay[day]
                ?? state.plannerDisplayDate(for: selection.weekendKey, day: day) else {
                continue
            }
            let normalizedDay = calendar.startOfDay(for: dayDate)

            if allDay {
                guard let end = calendar.date(byAdding: .day, value: 1, to: normalizedDay) else { continue }
                intervals.append(DateInterval(start: normalizedDay, end: end))
                continue
            }

            guard let startHour = startComponents.hour,
                  let startMinute = startComponents.minute,
                  let endHour = endComponents.hour,
                  let endMinute = endComponents.minute,
                  let start = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: normalizedDay),
                  let end = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: normalizedDay),
                  end > start else {
                continue
            }
            intervals.append(DateInterval(start: start, end: end))
        }

        return intervals.sorted { $0.start < $1.start }
    }
}

private struct AddPlanSelectionDetails {
    let weekendKey: String
    let days: Set<WeekendDay>
    let dayDateByDay: [WeekendDay: Date]
}

private enum EventRepeatOption: String, CaseIterable, Identifiable {
    case never
    case dailyHolidaysOnly
    case weekly
    case fortnightly
    case fourWeekly
    case annually

    var id: String { rawValue }

    var label: String {
        switch self {
        case .never:
            return "Never"
        case .dailyHolidaysOnly:
            return "Daily (holidays only)"
        case .weekly:
            return "Weekly"
        case .fortnightly:
            return "Fortnightly"
        case .fourWeekly:
            return "Four-weekly"
        case .annually:
            return "Annually"
        }
    }
}

enum AddPlanDayChipAction {
    case add
    case remove
}

enum AddPlanDaySelectionRules {
    static func isContiguousSelection(_ selection: Set<WeekendDay>, available: [OffDayOption]) -> Bool {
        guard !selection.isEmpty else { return false }
        let calendar = CalendarHelper.calendar
        var availableDatesByDay: [WeekendDay: Date] = [:]
        for option in available {
            availableDatesByDay[option.day] = calendar.startOfDay(for: option.date)
        }
        guard selection.allSatisfy({ availableDatesByDay[$0] != nil }) else { return false }

        let sortedDates = selection
            .compactMap { availableDatesByDay[$0] }
            .sorted()
        guard !sortedDates.isEmpty else { return false }

        for index in 1..<sortedDates.count {
            let previous = sortedDates[index - 1]
            let current = sortedDates[index]
            let delta = calendar.dateComponents([.day], from: previous, to: current).day ?? 0
            if delta != 1 {
                return false
            }
        }
        return true
    }

    static func isActionAllowed(
        currentSelection: Set<WeekendDay>,
        day: WeekendDay,
        action: AddPlanDayChipAction,
        available: [OffDayOption]
    ) -> Bool {
        let availableDays = Set(available.map(\.day))
        guard availableDays.contains(day) else { return false }

        var candidate = currentSelection.intersection(availableDays)
        switch action {
        case .add:
            candidate.insert(day)
        case .remove:
            candidate.remove(day)
        }

        guard !candidate.isEmpty else { return false }
        return isContiguousSelection(candidate, available: available)
    }
}

private struct OffDayCalendarPicker: View {
    @Binding var selectedDate: Date
    let dateRange: ClosedRange<Date>
    let isDateOffDay: (Date) -> Bool
    let reasonsForDate: (Date) -> [OffDayReason]
    @State private var visibleMonth: Date

    init(
        selectedDate: Binding<Date>,
        dateRange: ClosedRange<Date>,
        isDateOffDay: @escaping (Date) -> Bool,
        reasonsForDate: @escaping (Date) -> [OffDayReason]
    ) {
        _selectedDate = selectedDate
        self.dateRange = dateRange
        self.isDateOffDay = isDateOffDay
        self.reasonsForDate = reasonsForDate
        _visibleMonth = State(initialValue: CalendarHelper.monthStart(for: selectedDate.wrappedValue))
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
        .onChange(of: selectedDate) { _, newDate in
            let monthStart = CalendarHelper.monthStart(for: newDate)
            if !calendar.isDate(monthStart, equalTo: visibleMonth, toGranularity: .month) {
                visibleMonth = monthStart
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Date) -> some View {
        let normalizedDay = calendar.startOfDay(for: day)
        let inRange = normalizedDay >= calendar.startOfDay(for: dateRange.lowerBound) &&
            normalizedDay <= calendar.startOfDay(for: dateRange.upperBound)
        let reasons = reasonsForDate(normalizedDay)
        let isOffDay = inRange && isDateOffDay(normalizedDay)
        let isSelected = calendar.isDate(normalizedDay, inSameDayAs: selectedDate)

        Button {
            guard isOffDay else { return }
            selectedDate = normalizedDay
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: normalizedDay))")
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                Circle()
                    .fill(markerColor(for: reasons))
                    .frame(width: 4, height: 4)
                    .opacity(reasons.isEmpty ? 0 : 1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .foregroundStyle(foregroundColor(isOffDay: isOffDay, isSelected: isSelected))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.planBlue.opacity(0.2) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.planBlue.opacity(0.45) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isOffDay)
    }

    private func foregroundColor(isOffDay: Bool, isSelected: Bool) -> Color {
        if isSelected { return .primary }
        if isOffDay { return .primary }
        return .secondary.opacity(0.45)
    }

    private func markerColor(for reasons: [OffDayReason]) -> Color {
        if reasons.contains(where: {
            if case .publicHoliday = $0 { return true }
            return false
        }) {
            return .orange
        }
        if reasons.contains(where: {
            if case .annualLeave = $0 { return true }
            return false
        }) {
            return .travelCoral
        }
        return .freeGreen
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

struct CalendarInviteQRSheet: View {
    let calendar: PlannerCalendar
    var onCopyCode: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    private let ciContext = CIContext()

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 46, height: 6)
                .padding(.top, 6)

            Text("Invite to \(calendar.name)")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            if let image = qrCodeImage(for: calendar.shareCode) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 240, height: 240)
                    .padding(10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: AppSurfaceStyle.primaryCardCornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppSurfaceStyle.primaryCardCornerRadius, style: .continuous)
                            .stroke(AppSurfaceStyle.cardStroke, lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: AppSurfaceStyle.primaryCardCornerRadius, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 240, height: 240)
                    .overlay(
                        Text("Could not generate QR code.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    )
            }

            Text("Share code: \(calendar.shareCode)")
                .font(.body.monospaced().weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppSurfaceStyle.dayCardFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppSurfaceStyle.dayStroke, lineWidth: 1)
                )

            Text("Ask your collaborator to scan this QR code, then paste the code into Join shared calendar.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Button {
                onCopyCode(calendar.shareCode)
            } label: {
                Label("Copy invite code", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OutlinePillButtonStyle(stroke: AppSurfaceStyle.cardStroke, foreground: .primary))
            .padding(.horizontal, 20)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(
                PillButtonStyle(
                    fill: AppSurfaceStyle.primaryButtonFill,
                    foreground: AppSurfaceStyle.primaryButtonForeground
                )
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .padding(.top, 8)
        .presentationDetents([.medium])
    }

    private func qrCodeImage(for code: String) -> UIImage? {
        guard let data = code.data(using: .utf8) else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = ciContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct AuthSplashView: View {
    @EnvironmentObject private var state: AppState
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ZStack {
            AppSurfaceStyle.modalScrim.ignoresSafeArea()
            CardContainer {
                VStack(alignment: .leading, spacing: 16) {
                    Text("WEEKEND PLANNER")
                        .font(.caption)
                        .tracking(3)
                        .foregroundColor(.secondary)

                    Text("Welcome back")
                        .font(.system(size: 30, weight: .bold, design: .rounded))

                    Text("Sign in to see your plans across devices.")
                        .font(.callout)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Account")
                            .font(.headline)
                        Text(state.session == nil ? "Not signed in." : "Signed in")
                            .font(.callout)
                            .foregroundColor(.secondary)

                        TextField("you@example.com", text: $email)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(PillTextFieldStyle())
                        SecureField("Minimum 6 characters", text: $password)
                            .textFieldStyle(PillTextFieldStyle())
                    }

                    VStack(spacing: 10) {
                        Button("Sign in") {
                            Task { await state.signIn(email: email, password: password) }
                        }
                        .buttonStyle(OutlinePillButtonStyle(stroke: AppSurfaceStyle.cardStroke, foreground: .primary))

                        Button("Create account") {
                            Task { await state.signUp(email: email, password: password) }
                        }
                        .buttonStyle(
                            PillButtonStyle(
                                fill: AppSurfaceStyle.primaryButtonFill,
                                foreground: AppSurfaceStyle.primaryButtonForeground
                            )
                        )
                    }

                    if let message = state.authMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(maxWidth: 520)
        }
    }
}

private struct OnboardingPage: Identifiable {
    let id: Int
    let icon: String
    let title: String
    let message: String
}

struct OnboardingCarouselView: View {
    @State private var pageIndex = 0
    var onSkip: () -> Void
    var onGetStarted: () -> Void

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            id: 0,
            icon: "calendar.badge.clock",
            title: "Plan weekends and holidays with clarity.",
            message: "The Weekend helps you organize your time off in one place, with practical planning that stays easy to manage."
        ),
        OnboardingPage(
            id: 1,
            icon: "sun.max",
            title: "Shape your Life Schedule.",
            message: "Set weekly non-working days, include public holidays, and add annual leave so your planner reflects your real availability."
        ),
        OnboardingPage(
            id: 2,
            icon: "person.2.fill",
            title: "Plan better together.",
            message: "Use shared calendars to coordinate plans with others and keep everyone aligned on what weekends are free."
        )
    ]

    var body: some View {
        ZStack {
            AppSurfaceStyle.modalScrim.ignoresSafeArea()

            CardContainer {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        Text("THE WEEKEND")
                            .font(.caption.weight(.semibold))
                            .tracking(2.5)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Skip") {
                            onSkip()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("onboarding.skip")
                    }

                    TabView(selection: $pageIndex) {
                        ForEach(pages) { page in
                            VStack(spacing: 14) {
                                Image(systemName: page.icon)
                                    .font(.system(size: 36, weight: .semibold))
                                    .foregroundStyle(Color.planBlue)
                                    .frame(height: 44)

                                Text(page.title)
                                    .font(.title3.weight(.bold))
                                    .multilineTextAlignment(.center)
                                    .accessibilityIdentifier("onboarding.page.title")

                                Text(page.message)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .tag(page.id)
                            .padding(.horizontal, 6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 300)

                    HStack(spacing: 7) {
                        ForEach(pages) { page in
                            Capsule()
                                .fill(page.id == pageIndex ? Color.planBlue.opacity(0.75) : Color.secondary.opacity(0.25))
                                .frame(width: page.id == pageIndex ? 18 : 6, height: 6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 2)

                    if pageIndex < pages.count - 1 {
                        Button("Next") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                pageIndex = min(pageIndex + 1, pages.count - 1)
                            }
                        }
                        .buttonStyle(
                            PillButtonStyle(
                                fill: AppSurfaceStyle.primaryButtonFill,
                                foreground: AppSurfaceStyle.primaryButtonForeground
                            )
                        )
                        .accessibilityIdentifier("onboarding.next")
                    } else {
                        Button("Get started") {
                            onGetStarted()
                        }
                        .buttonStyle(
                            PillButtonStyle(
                                fill: AppSurfaceStyle.primaryButtonFill,
                                foreground: AppSurfaceStyle.primaryButtonForeground
                            )
                        )
                        .accessibilityIdentifier("onboarding.get-started")
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(maxWidth: 560)
            .accessibilityIdentifier("onboarding.carousel")
            .padding(.horizontal, 24)
        }
    }
}

struct OnboardingSetupChecklistView: View {
    @EnvironmentObject private var state: AppState
    var onLifeSchedule: () -> Void
    var onSharing: () -> Void
    var onAddPlan: () -> Void
    var onContinue: () -> Void

    private var hasCustomizedLifeSchedule: Bool {
        state.weekendConfiguration != .defaults || !state.annualLeaveDays.isEmpty
    }

    private var hasConfiguredSharing: Bool {
        state.calendars.count > 1
    }

    private var hasAddedPlan: Bool {
        !state.events.isEmpty
    }

    var body: some View {
        ZStack {
            AppSurfaceStyle.modalScrim.ignoresSafeArea()

            CardContainer {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Quick setup")
                            .font(.title2.weight(.bold))

                        Text("Choose what you want to do first.")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        onboardingStep(
                            icon: "sun.max",
                            title: "Set up Life Schedule",
                            subtitle: hasCustomizedLifeSchedule
                                ? "Configured"
                                : "Choose non-working days and holidays.",
                            isDone: hasCustomizedLifeSchedule,
                            actionTitle: hasCustomizedLifeSchedule ? "Review" : "Set up",
                            action: onLifeSchedule
                        )
                        .accessibilityIdentifier("onboarding.checklist.life-schedule")

                        onboardingStep(
                            icon: "person.2.fill",
                            title: "Set up Sharing",
                            subtitle: hasConfiguredSharing
                                ? "Shared calendars active"
                                : "Create or join a shared calendar.",
                            isDone: hasConfiguredSharing,
                            actionTitle: hasConfiguredSharing ? "Manage" : "Set up",
                            action: onSharing
                        )
                        .accessibilityIdentifier("onboarding.checklist.sharing")

                        onboardingStep(
                            icon: "plus.circle.fill",
                            title: "Add your first plan",
                            subtitle: hasAddedPlan
                                ? "You already have plans in your calendar."
                                : "Create your first weekend plan.",
                            isDone: hasAddedPlan,
                            actionTitle: hasAddedPlan ? "Add another" : "Add plan",
                            action: onAddPlan
                        )
                        .accessibilityIdentifier("onboarding.checklist.add-plan")

                        Button("Continue to app") {
                            onContinue()
                        }
                        .buttonStyle(
                            PillButtonStyle(
                                fill: AppSurfaceStyle.primaryButtonFill,
                                foreground: AppSurfaceStyle.primaryButtonForeground
                            )
                        )
                        .padding(.top, 6)
                        .accessibilityIdentifier("onboarding.checklist.continue")
                    }
                    .padding(.horizontal, 8)
                }
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 24)
            .accessibilityIdentifier("onboarding.checklist")
        }
    }

    @ViewBuilder
    private func onboardingStep(
        icon: String,
        title: String,
        subtitle: String,
        isDone: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(isDone ? Color.freeGreen : Color.planBlue)
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.freeGreen)
                }
            }

            Button(actionTitle) {
                action()
            }
            .buttonStyle(OutlinePillButtonStyle(stroke: AppSurfaceStyle.cardStroke, foreground: .primary))
        }
        .padding(12)
        .background(AppSurfaceStyle.settingsCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppSurfaceStyle.settingsSeparator, lineWidth: 1)
        )
    }
}

struct WeekendSelection: Identifiable {
    let id: String
}

struct OverviewYearSection: Identifiable {
    let year: Int
    var months: [MonthOption]

    var id: Int { year }
}

enum OverviewItem: Identifiable {
    case year(Int)
    case month(MonthOption)

    var id: String {
        switch self {
        case .year(let value): return "year-\(value)"
        case .month(let option): return option.key
        }
    }

    static func build(from options: [MonthOption]) -> [OverviewItem] {
        var items: [OverviewItem] = []
        var lastYear: Int?
        for option in options {
            if let year = option.year, year != lastYear {
                items.append(.year(year))
                lastYear = year
            }
            items.append(.month(option))
        }
        return items
    }
}

enum MonthSelectorItem: Identifiable {
    case year(Int)
    case option(MonthOption)

    var id: String {
        switch self {
        case .year(let value): return "year-\(value)"
        case .option(let option): return option.key
        }
    }

    static func build(from options: [MonthOption]) -> [MonthSelectorItem] {
        var items: [MonthSelectorItem] = []
        var lastYear: Int?
        for option in options {
            if let year = option.year, year != lastYear {
                items.append(.year(year))
                lastYear = year
            }
            items.append(.option(option))
        }
        return items
    }
}
