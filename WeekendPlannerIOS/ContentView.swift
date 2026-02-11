import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @State private var detailSelection: WeekendSelection?
    @State private var showAddPlan = false
    @State private var addPlanWeekendKey: String?
    @State private var bypassProtectionCheck = false

    var body: some View {
        ZStack {
            AppGradientBackground()
            TabView(selection: $state.selectedTab) {
                pageLayout {
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
                .tag(AppTab.overview)
                .tabItem {
                    Label(AppTab.overview.rawValue, systemImage: "square.grid.2x2")
                }

                pageLayout {
                    WeekendView(onSelectWeekend: { key in
                        detailSelection = WeekendSelection(id: key)
                    })
                }
                .tag(AppTab.weekend)
                .tabItem {
                    Label(AppTab.weekend.rawValue, systemImage: "calendar")
                }

                pageLayout {
                    SettingsView()
                }
                .tag(AppTab.settings)
                .tabItem {
                    Label(AppTab.settings.rawValue, systemImage: "gearshape")
                }
            }
            .tint(.planBlue)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarBackground(.ultraThinMaterial, for: .tabBar)
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
                    addPlanWeekendKey = key
                    bypassProtectionCheck = bypass
                    showAddPlan = true
                }
            )
        }
        .sheet(isPresented: $showAddPlan, onDismiss: {
            bypassProtectionCheck = false
            addPlanWeekendKey = nil
        }) {
            AddPlanView(weekendKey: addPlanWeekendKey, bypassProtection: bypassProtectionCheck)
        }
        .overlay {
            if state.showAuthSplash {
                AuthSplashView()
            }
        }
        .onChange(of: state.pendingWeekendSelection) { _, weekendKey in
            guard let weekendKey else { return }
            detailSelection = WeekendSelection(id: weekendKey)
            state.consumePendingWeekendSelection()
        }
        .onChange(of: state.pendingAddPlanWeekendKey) { _, weekendKey in
            guard let weekendKey else { return }
            addPlanWeekendKey = weekendKey
            bypassProtectionCheck = state.pendingAddPlanBypassProtection
            showAddPlan = true
            state.consumePendingAddPlanSelection()
        }
    }

    @ViewBuilder
    private func pageLayout<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 16) {
            HeaderView()
            LegendView()
            content()
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
}

struct HeaderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The Weekend")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
            Text("YOUR NEXT 12 MONTHS AT A GLANCE")
                .font(.caption)
                .foregroundColor(.secondary)
                .tracking(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LegendView: View {
    var body: some View {
        HStack(spacing: 12) {
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
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.cardStroke, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 12)
    }

    @ViewBuilder
    private func legendItem<Icon: View>(text: String, @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: 4) {
            icon()
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct TabBarView: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 10) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    Text(tab.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .allowsTightening(true)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                        .background(
                            Capsule().fill(selectedTab == tab ? Color.black.opacity(0.85) : Color.cardBackground)
                        )
                        .foregroundColor(selectedTab == tab ? .white : .primary)
                        .overlay(
                            Capsule().stroke(Color.cardStroke, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OverviewView: View {
    @EnvironmentObject private var state: AppState
    var onSelectWeekend: (String) -> Void
    var onSelectMonth: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(yearSections) { section in
                    Text(String(section.year))
                        .font(.caption)
                        .tracking(3)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    LazyVGrid(columns: overviewColumns, spacing: 14) {
                        ForEach(section.months) { option in
                            monthCard(for: option)
                        }
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    private var overviewColumns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible())]
    }

    private var yearSections: [OverviewYearSection] {
        let months = CalendarHelper.getMonths().filter { CalendarHelper.hasRemainingWeekends($0) }
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
    private func monthCard(for option: MonthOption) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(option.shortLabel)
                .font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(12)), count: 5), alignment: .leading, spacing: 6) {
                ForEach(option.weekends) { weekend in
                    let key = CalendarHelper.formatKey(weekend.saturday)
                    let status = state.status(for: key)
                    let isPastWeekend = CalendarHelper.isWeekendInPast(weekend.saturday)
                    Button(action: { onSelectWeekend(key) }) {
                        statusDot(for: status.type, isPastWeekend: isPastWeekend)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.cardStroke, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose a month to see every weekend and what is planned.")
                    .font(.callout)
                    .foregroundColor(.secondary)

                MonthSelectorView(selectedKey: $state.selectedMonthKey)

                MonthDisplayView(selectedKey: state.selectedMonthKey, onSelectWeekend: onSelectWeekend)
            }
        }
    }
}

struct MonthSelectorView: View {
    @Binding var selectedKey: String

    var body: some View {
        let options = CalendarHelper.getMonthOptions()
        let quickOptions = quickSelectorOptions(from: options)
        let yearSections = monthSelectorYearSections(from: options.filter { $0.year != nil })

        VStack(alignment: .leading, spacing: 6) {
            if !quickOptions.isEmpty {
                LazyVGrid(columns: quickSelectorColumns, alignment: .leading, spacing: 6) {
                    ForEach(quickOptions) { option in
                        monthOptionButton(option)
                    }
                }
            }

            ForEach(yearSections) { section in
                Text(String(section.year))
                    .font(.caption)
                    .tracking(3)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                LazyVGrid(columns: monthSelectorColumns, alignment: .leading, spacing: 6) {
                    ForEach(section.options) { option in
                        monthOptionButton(option)
                    }
                }
            }
        }
    }

    private var monthSelectorColumns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    }

    private var quickSelectorColumns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible())]
    }

    private func quickSelectorOptions(from options: [MonthOption]) -> [MonthOption] {
        let priority = ["upcoming", "previous"]
        return options
            .filter { priority.contains($0.key) }
            .sorted { lhs, rhs in
                (priority.firstIndex(of: lhs.key) ?? priority.count) < (priority.firstIndex(of: rhs.key) ?? priority.count)
            }
    }

    private func monthSelectorYearSections(from options: [MonthOption]) -> [MonthSelectorYearSection] {
        var sections: [MonthSelectorYearSection] = []
        for option in options {
            guard let year = option.year else { continue }
            if let lastIndex = sections.indices.last, sections[lastIndex].year == year {
                sections[lastIndex].options.append(option)
            } else {
                sections.append(MonthSelectorYearSection(year: year, options: [option]))
            }
        }
        return sections
    }

    @ViewBuilder
    private func monthOptionButton(_ option: MonthOption) -> some View {
        Button(action: { selectedKey = option.key }) {
            Text(option.shortLabel)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(selectedKey == option.key ? Color.black.opacity(0.9) : Color.cardBackground)
                .foregroundColor(selectedKey == option.key ? .white : .primary)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.cardStroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct MonthDisplayView: View {
    @EnvironmentObject private var state: AppState
    let selectedKey: String
    var onSelectWeekend: (String) -> Void

    var body: some View {
        let options = CalendarHelper.getMonthOptions()
        if let option = options.first(where: { $0.key == selectedKey }) ?? options.first {
            if option.key == "previous" {
                previousPlansCard(for: option)
            } else {
                upcomingPlansCard(for: option)
            }
        } else {
            CardContainer {
                Text("No month data available")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func upcomingPlansCard(for option: MonthOption) -> some View {
        let visibleWeekends = CalendarHelper.remainingWeekends(in: option.weekends)

        CardContainer {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(option.key == "upcoming" ? option.title : option.shortLabel)
                        .font(.headline)
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
                    VStack(spacing: 36) {
                        ForEach(visibleWeekends) { weekend in
                            let key = CalendarHelper.formatKey(weekend.saturday)
                            WeekendRowView(
                                weekend: weekend,
                                status: state.status(for: key),
                                events: state.events(for: key),
                                isProtected: state.isProtected(key),
                                onTap: { onSelectWeekend(key) }
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func previousPlansCard(for option: MonthOption) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(option.title)
                        .font(.headline)
                    Spacer()
                    Text(option.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if pastEventEntries.isEmpty {
                    Text("No past plans from the previous 12 months.")
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

    private var pastEventEntries: [PastEventEntry] {
        let now = Date()
        guard let rangeStart = CalendarHelper.calendar.date(byAdding: .month, value: -12, to: now) else { return [] }

        return state.events
            .flatMap { event in
                guard let saturday = CalendarHelper.parseKey(event.weekendKey),
                      saturday >= rangeStart,
                      CalendarHelper.isWeekendInPast(saturday, referenceDate: now) else {
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
        switch day {
        case .sat:
            return CalendarHelper.calendar.startOfDay(for: saturday)
        case .sun:
            guard let sunday = CalendarHelper.calendar.date(byAdding: .day, value: 1, to: saturday) else { return nil }
            return CalendarHelper.calendar.startOfDay(for: sunday)
        }
    }

    private func pastEventTimeLabel(for event: WeekendEvent) -> String {
        if event.isAllDay {
            return "All day"
        }
        return "\(formattedTime(event.startTime)) - \(formattedTime(event.endTime))"
    }

    private func formattedTime(_ value: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        guard let date = formatter.date(from: value) else { return value }
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
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
                    .stroke(Color.cardStroke, lineWidth: 1)
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
    var onTap: () -> Void
    @State private var eventToRemove: WeekendEvent?
    @State private var eventToEdit: WeekendEvent?

    var body: some View {
        let weekendKey = CalendarHelper.formatKey(weekend.saturday)
        HStack(alignment: .top, spacing: 0) {
            accentIndicator

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center) {
                        Text(weekend.label)
                            .font(.headline)
                        Spacer(minLength: 8)
                        readinessBadge(for: state.readiness(for: weekendKey))
                    }
                    Text(status.label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(1)
                }

                quickAddChips(weekendKey: weekendKey)

                VStack(alignment: .leading, spacing: 10) {
                    DayColumnView(
                        day: .sat,
                        events: eventsForDay(.sat),
                        status: status,
                        onEdit: { eventToEdit = $0 },
                        onMove: { eventToEdit = $0 },
                        onDuplicate: duplicateEvent,
                        onComplete: { event in Task { _ = await state.markEventCompleted(event.id) } },
                        onCancel: { event in Task { _ = await state.markEventCancelled(event.id) } },
                        onReopen: { event in Task { _ = await state.reopenEvent(event.id) } },
                        onSaveTemplate: { state.saveTemplate(from: $0) },
                        onRemove: { eventToRemove = $0 },
                        syncStateForEvent: { event in state.syncState(for: event.id) }
                    )
                    DayColumnView(
                        day: .sun,
                        events: eventsForDay(.sun),
                        status: status,
                        onEdit: { eventToEdit = $0 },
                        onMove: { eventToEdit = $0 },
                        onDuplicate: duplicateEvent,
                        onComplete: { event in Task { _ = await state.markEventCompleted(event.id) } },
                        onCancel: { event in Task { _ = await state.markEventCancelled(event.id) } },
                        onReopen: { event in Task { _ = await state.reopenEvent(event.id) } },
                        onSaveTemplate: { state.saveTemplate(from: $0) },
                        onRemove: { eventToRemove = $0 },
                        syncStateForEvent: { event in state.syncState(for: event.id) }
                    )
                }
            }
            .padding(.leading, 12)
            .padding(.vertical, 8)
            .padding(.trailing, 10)
        }
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            rowBorder
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            onTap()
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
    }

    @ViewBuilder
    private var accentIndicator: some View {
        if status.type == "protected" {
            ProtectedStripeBar(width: 5)
        } else {
            Rectangle()
                .fill(accentColor)
                .frame(width: 4)
        }
    }

    @ViewBuilder
    private var rowBorder: some View {
        if status.type == "protected" {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.protectedStripeGradient, lineWidth: 1)
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        }
    }

    private func eventsForDay(_ day: WeekendDay) -> [WeekendEvent] {
        events.filter { $0.dayValues.contains(day) }.sorted { $0.startTime < $1.startTime }
    }

    private var accentColor: Color {
        switch status.type {
        case "travel": return .travelCoral
        case "plan": return .planBlue
        default: return .freeGreen
        }
    }

    private var borderColor: Color {
        accentColor.opacity(0.4)
    }

    private func duplicateEvent(_ event: WeekendEvent) {
        guard let targetWeekendKey = CalendarHelper.nextWeekendKey(after: event.weekendKey) else { return }
        Task {
            _ = await state.duplicateEvent(eventId: event.id, toWeekendKey: targetWeekendKey)
        }
    }

    @ViewBuilder
    private func quickAddChips(weekendKey: String) -> some View {
        let chips = state.topQuickAddChips(limit: 4)
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chips) { chip in
                        Button {
                            Task { _ = await state.quickAdd(chip: chip, toWeekendKey: weekendKey) }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: chip.type == PlanType.travel.rawValue ? "airplane" : "plus")
                                    .font(.caption2.weight(.bold))
                                Text(chip.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.dayItemBackground)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.dayCardStroke, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isProtected && state.protectionMode == .block)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func readinessBadge(for readiness: WeekendReadinessState) -> some View {
        Text(readiness.label)
            .font(.caption2.weight(.semibold))
            .foregroundColor(readinessForeground(readiness))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(readinessBackground(readiness))
            .clipShape(Capsule())
    }

    private func readinessForeground(_ readiness: WeekendReadinessState) -> Color {
        switch readiness {
        case .protected:
            return .orange
        case .ready:
            return .green
        case .partiallyPlanned:
            return .blue
        case .unplanned:
            return .secondary
        }
    }

    private func readinessBackground(_ readiness: WeekendReadinessState) -> Color {
        switch readiness {
        case .protected:
            return Color.orange.opacity(0.16)
        case .ready:
            return Color.green.opacity(0.14)
        case .partiallyPlanned:
            return Color.blue.opacity(0.14)
        case .unplanned:
            return Color.secondary.opacity(0.12)
        }
    }
}

struct DayColumnView: View {
    let day: WeekendDay
    let events: [WeekendEvent]
    let status: WeekendStatus
    var onEdit: (WeekendEvent) -> Void
    var onMove: (WeekendEvent) -> Void
    var onDuplicate: (WeekendEvent) -> Void
    var onComplete: (WeekendEvent) -> Void
    var onCancel: (WeekendEvent) -> Void
    var onReopen: (WeekendEvent) -> Void
    var onSaveTemplate: (WeekendEvent) -> Void
    var onRemove: (WeekendEvent) -> Void
    var syncStateForEvent: (WeekendEvent) -> SyncState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(day.label)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundColor(.secondary)

            if events.isEmpty {
                Text(status.type == "protected" ? "Protected" : "No plans yet")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.dayItemBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.dayCardStroke, lineWidth: 1)
                    )
            } else {
                ForEach(events) { event in
                    TimelineItemView(
                        event: event,
                        syncState: syncStateForEvent(event),
                        onComplete: { onComplete(event) },
                        onCancel: { onCancel(event) },
                        onReopen: { onReopen(event) },
                        onEdit: { onEdit(event) },
                        onMove: { onMove(event) },
                        onDuplicate: { onDuplicate(event) },
                        onSaveTemplate: { onSaveTemplate(event) },
                        onRemove: { onRemove(event) }
                    )
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dayCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.dayCardStroke, lineWidth: 1)
        )
    }
}

struct TimelineItemView: View {
    let event: WeekendEvent
    let syncState: SyncState
    var onComplete: () -> Void
    var onCancel: () -> Void
    var onReopen: () -> Void
    var onEdit: () -> Void
    var onMove: () -> Void
    var onDuplicate: () -> Void
    var onSaveTemplate: () -> Void
    var onRemove: () -> Void

    var body: some View {
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
                    .font(.callout.weight(.semibold))
                    .strikethrough(event.lifecycleStatus == .cancelled)

                HStack(spacing: 6) {
                    Text(lifecycleLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(lifecycleColor)
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(syncLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(syncColor)
                }
            }

            Spacer()
            Menu {
                if event.lifecycleStatus == .planned {
                    Button {
                        onComplete()
                    } label: {
                        Label("Complete", systemImage: "checkmark.circle")
                    }
                    Button {
                        onCancel()
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                } else {
                    Button {
                        onReopen()
                    } label: {
                        Label("Reopen", systemImage: "arrow.counterclockwise")
                    }
                }
                Divider()
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
                Button {
                    onSaveTemplate()
                } label: {
                    Label("Save as template", systemImage: "bookmark")
                }
                Divider()
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color.dayItemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.dayCardStroke, lineWidth: 1)
        )
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

    private var lifecycleLabel: String {
        switch event.lifecycleStatus {
        case .planned: return "Planned"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }

    private var lifecycleColor: Color {
        switch event.lifecycleStatus {
        case .planned: return .secondary
        case .completed: return .green
        case .cancelled: return .orange
        }
    }

    private var syncLabel: String {
        switch syncState {
        case .pending: return "Pending"
        case .retrying: return "Retrying"
        case .synced: return "Synced"
        }
    }

    private var syncColor: Color {
        switch syncState {
        case .pending: return .orange
        case .retrying: return .red
        case .synced: return .secondary
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
    @State private var showSaveWeekendTemplatePrompt = false
    @State private var weekendTemplateName = ""
    @State private var carryForwardResultMessage: String?

    var body: some View {
        let saturday = CalendarHelper.parseKey(weekendKey) ?? Date()
        let label = CalendarHelper.formatWeekendLabel(saturday)
        let events = state.events(for: weekendKey)
        let isProtected = state.isProtected(weekendKey)

        VStack(alignment: .leading, spacing: 16) {
            Text(label)
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                DayDetailColumn(
                    day: .sat,
                    events: eventsFor(.sat),
                    isProtected: isProtected,
                    onEdit: { eventToEdit = $0 },
                    onMove: { eventToEdit = $0 },
                    onDuplicate: duplicateEvent,
                    onComplete: { event in Task { _ = await state.markEventCompleted(event.id) } },
                    onCancel: { event in Task { _ = await state.markEventCancelled(event.id) } },
                    onReopen: { event in Task { _ = await state.reopenEvent(event.id) } },
                    onSaveTemplate: { state.saveTemplate(from: $0) },
                    onRemove: { eventToRemove = $0 },
                    syncStateForEvent: { event in state.syncState(for: event.id) }
                )
                DayDetailColumn(
                    day: .sun,
                    events: eventsFor(.sun),
                    isProtected: isProtected,
                    onEdit: { eventToEdit = $0 },
                    onMove: { eventToEdit = $0 },
                    onDuplicate: duplicateEvent,
                    onComplete: { event in Task { _ = await state.markEventCompleted(event.id) } },
                    onCancel: { event in Task { _ = await state.markEventCancelled(event.id) } },
                    onReopen: { event in Task { _ = await state.reopenEvent(event.id) } },
                    onSaveTemplate: { state.saveTemplate(from: $0) },
                    onRemove: { eventToRemove = $0 },
                    syncStateForEvent: { event in state.syncState(for: event.id) }
                )
            }

            HStack {
                Text(isProtected ? "Protected" : "Not protected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(isProtected ? "Remove protection" : "Protect weekend") {
                    if isProtected {
                        Task { await state.toggleProtection(weekendKey: weekendKey, removePlans: false) }
                    } else if events.isEmpty {
                        Task { await state.toggleProtection(weekendKey: weekendKey, removePlans: false) }
                    } else {
                        showProtectionPrompt = true
                    }
                }
                .buttonStyle(OutlinePillButtonStyle(stroke: .cardStroke, foreground: .primary))
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
            .buttonStyle(PillButtonStyle(fill: .black, foreground: .white))

            Button("Save weekend as template") {
                weekendTemplateName = label
                showSaveWeekendTemplatePrompt = true
            }
            .buttonStyle(OutlinePillButtonStyle(stroke: .cardStroke, foreground: .primary))

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
                .buttonStyle(OutlinePillButtonStyle(stroke: .cardStroke, foreground: .primary))
            }
        }
        .padding(20)
        .presentationDetents([.medium, .large])
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
        .alert("Save weekend as template", isPresented: $showSaveWeekendTemplatePrompt) {
            TextField("Template name", text: $weekendTemplateName)
            Button("Save") {
                let trimmed = weekendTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                state.saveTemplateBundleFromWeekend(weekendKey: weekendKey, name: trimmed)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This saves all plans from this weekend as a reusable multi-event template.")
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
        state.events(for: weekendKey).filter { $0.dayValues.contains(day) }
    }

    private func duplicateEvent(_ event: WeekendEvent) {
        guard let targetWeekendKey = CalendarHelper.nextWeekendKey(after: event.weekendKey) else { return }
        Task {
            _ = await state.duplicateEvent(eventId: event.id, toWeekendKey: targetWeekendKey)
        }
    }
}

struct DayDetailColumn: View {
    let day: WeekendDay
    let events: [WeekendEvent]
    let isProtected: Bool
    var onEdit: (WeekendEvent) -> Void
    var onMove: (WeekendEvent) -> Void
    var onDuplicate: (WeekendEvent) -> Void
    var onComplete: (WeekendEvent) -> Void
    var onCancel: (WeekendEvent) -> Void
    var onReopen: (WeekendEvent) -> Void
    var onSaveTemplate: (WeekendEvent) -> Void
    var onRemove: (WeekendEvent) -> Void
    var syncStateForEvent: (WeekendEvent) -> SyncState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(day.label)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundColor(.secondary)

            if events.isEmpty {
                Text(isProtected ? "Protected" : "No plans yet")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.dayItemBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.dayCardStroke, lineWidth: 1)
                    )
            } else {
                ForEach(events) { event in
                    TimelineItemView(
                        event: event,
                        syncState: syncStateForEvent(event),
                        onComplete: { onComplete(event) },
                        onCancel: { onCancel(event) },
                        onReopen: { onReopen(event) },
                        onEdit: { onEdit(event) },
                        onMove: { onMove(event) },
                        onDuplicate: { onDuplicate(event) },
                        onSaveTemplate: { onSaveTemplate(event) },
                        onRemove: { onRemove(event) }
                    )
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dayCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.dayCardStroke, lineWidth: 1)
        )
    }
}

struct AddPlanView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    let weekendKey: String?
    let bypassProtection: Bool
    var editingEvent: WeekendEvent? = nil

    @State private var title = ""
    @State private var planType: PlanType = .plan
    @State private var date = Date()
    @State private var selectedDays: Set<WeekendDay> = [.sat, .sun]
    @State private var allDay = false
    @State private var startTime = CalendarHelper.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var endTime = CalendarHelper.calendar.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showProtectedPrompt = false
    @State private var exportToCalendar = false
    @State private var calendarConflicts: [CalendarConflict] = []
    @State private var isCheckingConflicts = false
    @State private var showTemplateSavePrompt = false
    @State private var templateName = ""
    @State private var hasInitialized = false

    var body: some View {
        NavigationStack {
            Form {
                if !isEditing {
                    Section(header: Text("Quick starters")) {
                        Button("Use last weekend") {
                            if let starter = state.starterFromLastWeekend(referenceDate: date) {
                                applyStarter(starter)
                            }
                        }
                        .disabled(state.starterFromLastWeekend(referenceDate: date) == nil)

                        Button("Use same month last year") {
                            if let starter = state.starterFromSameMonthLastYear(referenceDate: date) {
                                applyStarter(starter)
                            }
                        }
                        .disabled(state.starterFromSameMonthLastYear(referenceDate: date) == nil)

                        if !state.planTemplates.isEmpty {
                            Menu("Use template") {
                                ForEach(state.planTemplates) { template in
                                    Button(template.name) {
                                        applyTemplate(template)
                                    }
                                }
                            }
                        }

                        if !state.planTemplateBundles.isEmpty {
                            Menu("Apply weekend template") {
                                ForEach(state.planTemplateBundles) { bundle in
                                    Button(bundle.name) {
                                        Task { await applyTemplateBundle(bundle) }
                                    }
                                }
                            }
                        }
                    }
                }

                Section(header: Text("Title")) {
                    TextField("Surf trip, wedding, retreat", text: $title)
                }

                Section(header: Text("Type")) {
                    Picker("Type", selection: $planType) {
                        Text("Local plans").tag(PlanType.plan)
                        Text("Travel plans").tag(PlanType.travel)
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("Weekend")) {
                    DatePicker("Choose a weekend date", selection: $date, displayedComponents: .date)
                }

                Section(header: Text("Days")) {
                    Toggle("Saturday", isOn: Binding(
                        get: { selectedDays.contains(.sat) },
                        set: { updateDay(.sat, isOn: $0) }
                    ))
                    Toggle("Sunday", isOn: Binding(
                        get: { selectedDays.contains(.sun) },
                        set: { updateDay(.sun, isOn: $0) }
                    ))
                }

                Section {
                    Toggle("All day plan", isOn: $allDay)
                }

                Section(header: Text("Time")) {
                    DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                        .disabled(allDay)
                    DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                        .disabled(allDay)
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

                Section {
                    Button("Save current fields as template") {
                        templateName = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Weekend template" : title
                        showTemplateSavePrompt = true
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedDays.isEmpty)
                }
            }
            .navigationTitle(isEditing ? "Edit weekend event" : "Add a weekend event")
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
            }
            .task(id: conflictTaskToken) {
                await refreshCalendarConflicts()
            }
            .alert("Oops", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .alert("Save template", isPresented: $showTemplateSavePrompt) {
                TextField("Template name", text: $templateName)
                Button("Save") { saveTemplateFromCurrentFields() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You can reuse this setup from the Add Plan screen.")
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

    private var conflictTaskToken: String {
        let daysToken = selectedDays.map(\.rawValue).sorted().joined(separator: ",")
        return "\(CalendarHelper.weekendKey(for: date) ?? "invalid")|\(daysToken)|\(allDay)|\(CalendarHelper.timeString(from: startTime))|\(CalendarHelper.timeString(from: endTime))|\(editingEvent?.id ?? "new")|\(state.calendarPermissionState.rawValue)"
    }

    private func updateDay(_ day: WeekendDay, isOn: Bool) {
        if isOn {
            selectedDays.insert(day)
        } else {
            selectedDays.remove(day)
        }
    }

    private func handleSubmit() async {
        await savePlan(force: bypassProtection)
    }

    private func configureInitialState() {
        guard !hasInitialized else { return }
        defer { hasInitialized = true }

        if let editingEvent {
            title = editingEvent.title
            planType = editingEvent.planType
            if let editDate = CalendarHelper.parseKey(editingEvent.weekendKey) {
                date = editDate
            }
            selectedDays = Set(editingEvent.dayValues)
            allDay = editingEvent.isAllDay
            if let parsedStart = parsedTime(editingEvent.startTime) {
                startTime = parsedStart
            }
            if let parsedEnd = parsedTime(editingEvent.endTime) {
                endTime = parsedEnd
            }
            exportToCalendar = state.isEventExportedToCalendar(eventId: editingEvent.id)
            return
        }

        if let key = weekendKey, let selectedDate = CalendarHelper.parseKey(key) {
            date = selectedDate
        }
    }

    private func applyStarter(_ event: WeekendEvent) {
        title = event.title
        planType = event.planType
        selectedDays = Set(event.dayValues)
        allDay = event.isAllDay
        if let parsedStart = parsedTime(event.startTime) {
            startTime = parsedStart
        }
        if let parsedEnd = parsedTime(event.endTime) {
            endTime = parsedEnd
        }
    }

    private func applyTemplate(_ template: PlanTemplate) {
        title = template.title
        planType = template.planType
        selectedDays = template.dayValues
        allDay = template.isAllDay
        if let parsedStart = parsedTime(template.startTime) {
            startTime = parsedStart
        }
        if let parsedEnd = parsedTime(template.endTime) {
            endTime = parsedEnd
        }
    }

    private func applyTemplateBundle(_ bundle: PlanTemplateBundle) async {
        guard let weekendKey = CalendarHelper.weekendKey(for: date) else {
            errorMessage = "Please choose a Saturday or Sunday before applying a template."
            showError = true
            return
        }
        let created = await state.applyTemplateBundle(bundleId: bundle.id, toWeekendKey: weekendKey)
        if created > 0 {
            dismiss()
        } else {
            errorMessage = "No plans were added from this template."
            showError = true
        }
    }

    private func saveTemplateFromCurrentFields() {
        let trimmedName = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        state.saveTemplate(
            name: trimmedName,
            draft: PlanTemplateDraft(
                title: title,
                type: planType,
                days: selectedDays,
                allDay: allDay,
                startTime: CalendarHelper.timeString(from: startTime),
                endTime: CalendarHelper.timeString(from: endTime)
            )
        )
    }

    private func savePlan(force: Bool) async {
        guard let weekendKey = CalendarHelper.weekendKey(for: date) else {
            errorMessage = "Please choose a Saturday or Sunday."
            showError = true
            return
        }

        if selectedDays.isEmpty {
            errorMessage = "Please pick at least Saturday or Sunday."
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

        let startString = allDay ? "00:00" : CalendarHelper.timeString(from: startTime)
        let endString = allDay ? "23:59" : CalendarHelper.timeString(from: endTime)
        if !allDay && startString >= endString {
            errorMessage = "End time should be after start time."
            showError = true
            return
        }

        let sortedDays = selectedDays.sorted { $0.rawValue < $1.rawValue }.map(\.rawValue)
        let success: Bool

        if let editingEvent {
            let payload = UpdateWeekendEvent(
                title: title,
                type: planType.rawValue,
                weekendKey: weekendKey,
                days: sortedDays,
                startTime: startString,
                endTime: endString
            )
            success = await state.updateEvent(
                eventId: editingEvent.id,
                payload,
                exportToCalendar: exportToCalendar
            )
        } else {
            guard let userId = state.session?.user.id.uuidString.lowercased() else { return }
            let payload = NewWeekendEvent(
                title: title,
                type: planType.rawValue,
                weekendKey: weekendKey,
                days: sortedDays,
                startTime: startString,
                endTime: endString,
                userId: userId
            )
            success = await state.addEvent(payload, exportToCalendar: exportToCalendar)
        }

        if success {
            dismiss()
        }
    }

    private func parsedTime(_ value: String) -> Date? {
        let parts = value.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return nil
        }
        return CalendarHelper.calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: Date()
        )
    }

    private func refreshCalendarConflicts() async {
        guard state.calendarPermissionState.canReadEvents else {
            calendarConflicts = []
            return
        }
        guard let weekendKey = CalendarHelper.weekendKey(for: date) else {
            calendarConflicts = []
            return
        }

        let intervals = CalendarHelper.intervals(
            weekendKey: weekendKey,
            days: selectedDays,
            allDay: allDay,
            startTime: startTime,
            endTime: endTime
        )

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
}

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Settings")
                        .font(.headline)
                    Text("Manage your account, preferences, and notifications.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }

                CardContainer {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Account")
                            .font(.headline)
                        Text(state.session?.user.email ?? "Signed out")
                            .font(.callout)
                            .foregroundColor(.secondary)
                        Button("Sign out") {
                            Task { await state.signOut() }
                        }
                        .buttonStyle(OutlinePillButtonStyle(stroke: .cardStroke, foreground: .primary))
                    }
                }

                CardContainer {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Preferences")
                            .font(.headline)
                        Toggle("Use dark mode", isOn: Binding(
                            get: { state.useDarkMode },
                            set: { state.setTheme($0) }
                        ))
                        Toggle("Block new plans on protected weekends", isOn: Binding(
                            get: { state.protectionMode == .block },
                            set: { state.setProtectionMode($0 ? .block : .warn) }
                        ))
                    }
                }

                CardContainer {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Notifications")
                            .font(.headline)
                        HStack {
                            Text("Status")
                            Spacer()
                            Text(state.notificationPermissionState.label)
                                .foregroundColor(.secondary)
                        }

                        if state.notificationPermissionState == .notDetermined {
                            Button("Enable notifications") {
                                Task { await state.requestNotificationPermissionIfNeeded() }
                            }
                            .buttonStyle(PillButtonStyle(fill: .black.opacity(0.9), foreground: .white))
                        }

                        if state.notificationPermissionState == .denied {
                            Button("Open iOS Settings") {
                                openSystemSettings()
                            }
                            .buttonStyle(OutlinePillButtonStyle(stroke: .cardStroke, foreground: .primary))
                        }

                        Toggle("Weekly weekend summary", isOn: weeklySummaryEnabledBinding)
                        if state.notificationPreferences.weeklySummaryEnabled {
                            Picker("Summary day", selection: weeklySummaryWeekdayBinding) {
                                ForEach(weekdayOptions) { option in
                                    Text(option.label).tag(option.value)
                                }
                            }
                            .pickerStyle(.menu)

                            DatePicker(
                                "Summary time",
                                selection: weeklySummaryTimeBinding,
                                displayedComponents: .hourAndMinute
                            )
                        }

                        Toggle("Planning nudge for free weekends", isOn: planningNudgeEnabledBinding)
                        if state.notificationPreferences.planningNudgeEnabled {
                            Picker("Nudge day", selection: planningNudgeWeekdayBinding) {
                                ForEach(weekdayOptions) { option in
                                    Text(option.label).tag(option.value)
                                }
                            }
                            .pickerStyle(.menu)

                            DatePicker(
                                "Nudge time",
                                selection: planningNudgeTimeBinding,
                                displayedComponents: .hourAndMinute
                            )
                        }

                        Toggle("Event reminders", isOn: eventReminderEnabledBinding)
                        if state.notificationPreferences.eventReminderEnabled {
                            Picker("Remind me before events", selection: eventLeadMinutesBinding) {
                                ForEach(eventLeadOptions, id: \.self) { minutes in
                                    Text(leadTimeLabel(for: minutes)).tag(minutes)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        Toggle("Sunday wrap-up reminder", isOn: sundayWrapUpEnabledBinding)
                        Toggle("Monday recap reminder", isOn: mondayRecapEnabledBinding)

                        Text("Reminder times use your current iPhone time zone.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                CardContainer {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Calendar Integration")
                            .font(.headline)
                        HStack {
                            Text("Status")
                            Spacer()
                            Text(state.calendarPermissionState.label)
                                .foregroundColor(.secondary)
                        }

                        if state.calendarPermissionState == .notDetermined {
                            Button("Enable calendar access") {
                                Task { await state.requestCalendarPermissionIfNeeded() }
                            }
                            .buttonStyle(PillButtonStyle(fill: .black.opacity(0.9), foreground: .white))
                        }

                        if state.calendarPermissionState == .denied || state.calendarPermissionState == .restricted {
                            Button("Open iOS Settings") {
                                openSystemSettings()
                            }
                            .buttonStyle(OutlinePillButtonStyle(stroke: .cardStroke, foreground: .primary))
                        }

                        Text("Used for conflict checks and optional Apple Calendar export when saving plans.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                CardContainer {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Plan Templates")
                            .font(.headline)
                        if state.planTemplates.isEmpty {
                            Text("No templates saved yet. Save one from the Add Plan form.")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(state.planTemplates.prefix(6)) { template in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(template.name)
                                            .font(.subheadline.weight(.semibold))
                                        Text(template.title)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Button("Delete") {
                                        state.removeTemplate(template)
                                    }
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.red)
                                }
                            }
                        }
                    }
                }

                CardContainer {
                    let report = state.weeklyReportSnapshot()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Private Weekly Report")
                            .font(.headline)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Created this week")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(report.thisWeekCreated)")
                                    .font(.title3.weight(.semibold))
                            }
                            Spacer()
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Completed this week")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(report.thisWeekCompleted)")
                                    .font(.title3.weight(.semibold))
                            }
                        }

                        Text("Last week: \(report.lastWeekCreated) created, \(report.lastWeekCompleted) completed")
                            .font(.caption)
                            .foregroundColor(.secondary)

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
                            .foregroundColor(.secondary)
                    }
                }

                CardContainer {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Sync Status")
                                .font(.headline)
                            Spacer()
                            Text(state.pendingOperations.isEmpty ? "All synced" : "\(state.pendingOperations.count) pending")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(state.pendingOperations.isEmpty ? .secondary : .orange)
                        }
                        if state.isSyncing {
                            Text("Sync in progress...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if !state.pendingOperations.isEmpty {
                            Text("Pending changes will retry automatically when connection is available.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                CardContainer {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Activity History (30 days)")
                            .font(.headline)
                        if state.auditEntries.isEmpty {
                            Text("No activity yet.")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(state.auditEntries.prefix(12)) { entry in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.action)
                                        .font(.subheadline.weight(.semibold))
                                    Text(auditTimestamp(entry.occurredAt))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
        .task {
            await state.refreshNotificationPermissionState()
            await state.refreshCalendarPermissionState()
            await state.flushPendingOperations()
        }
    }

    private struct WeekdayOption: Identifiable {
        let value: Int
        let label: String

        var id: Int { value }
    }

    private var weekdayOptions: [WeekdayOption] {
        let symbols = Calendar.current.weekdaySymbols
        return symbols.enumerated().map { (index, value) in
            WeekdayOption(value: index + 1, label: value)
        }
    }

    private var eventLeadOptions: [Int] {
        let base = [15, 30, 60, 90, 120, 180, 240]
        let current = state.notificationPreferences.eventLeadMinutes
        if base.contains(current) {
            return base
        }
        return (base + [max(0, current)]).sorted()
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
                timeDate(hour: state.notificationPreferences.weeklySummaryHour, minute: state.notificationPreferences.weeklySummaryMinute)
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
                timeDate(hour: state.notificationPreferences.planningNudgeHour, minute: state.notificationPreferences.planningNudgeMinute)
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

    private func openSystemSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}

struct AuthSplashView: View {
    @EnvironmentObject private var state: AppState
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.15).ignoresSafeArea()
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
                        .buttonStyle(OutlinePillButtonStyle(stroke: .cardStroke, foreground: .primary))

                        Button("Create account") {
                            Task { await state.signUp(email: email, password: password) }
                        }
                        .buttonStyle(PillButtonStyle(fill: .black.opacity(0.9), foreground: .white))
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

struct WeekendSelection: Identifiable {
    let id: String
}

struct OverviewYearSection: Identifiable {
    let year: Int
    var months: [MonthOption]

    var id: Int { year }
}

struct MonthSelectorYearSection: Identifiable {
    let year: Int
    var options: [MonthOption]

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
