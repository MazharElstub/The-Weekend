import SwiftUI

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
            .tint(.primary)
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
        withAnimation(.easeInOut(duration: 0.2)) {
            state.selectedTab = tabs[nextIndex]
        }
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
        let months = CalendarHelper.getMonths()
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
                    Button(action: { onSelectWeekend(key) }) {
                        statusDot(for: status.type)
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
    private func statusDot(for type: String) -> some View {
        if type == "protected" {
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
        let upcomingOptions = options.filter { $0.year == nil }
        let yearSections = monthSelectorYearSections(from: options.filter { $0.year != nil })

        VStack(alignment: .leading, spacing: 6) {
            if !upcomingOptions.isEmpty {
                LazyVGrid(columns: monthSelectorColumns, alignment: .leading, spacing: 6) {
                    ForEach(upcomingOptions) { option in
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
        let option = options.first { $0.key == selectedKey } ?? options[0]

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

                if option.weekends.isEmpty {
                    Text("No weekends left")
                        .font(.callout)
                        .foregroundColor(.secondary)
                } else {
                    VStack(spacing: 36) {
                        ForEach(option.weekends) { weekend in
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
}

struct WeekendRowView: View {
    @EnvironmentObject private var state: AppState
    let weekend: WeekendInfo
    let status: WeekendStatus
    let events: [WeekendEvent]
    let isProtected: Bool
    var onTap: () -> Void
    @State private var eventToRemove: WeekendEvent?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            accentIndicator

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(weekend.label)
                        .font(.headline)
                    Text(status.label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(1)
                }

                VStack(alignment: .leading, spacing: 10) {
                    DayColumnView(day: .sat, events: eventsForDay(.sat), status: status) { event in
                        eventToRemove = event
                    }
                    DayColumnView(day: .sun, events: eventsForDay(.sun), status: status) { event in
                        eventToRemove = event
                    }
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
}

struct DayColumnView: View {
    let day: WeekendDay
    let events: [WeekendEvent]
    let status: WeekendStatus
    var onRemove: (WeekendEvent) -> Void

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
                    TimelineItemView(event: event) {
                        onRemove(event)
                    }
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
            }

            Spacer()
            Button(action: onRemove) {
                Image(systemName: "trash")
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
            return "00:00 - 23:59"
        }
        return "\(formatTime(event.startTime)) - \(formatTime(event.endTime))"
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
    @State private var showAddProtectedPrompt = false

    var body: some View {
        let saturday = CalendarHelper.parseKey(weekendKey) ?? Date()
        let label = CalendarHelper.formatWeekendLabel(saturday)
        let events = state.events(for: weekendKey)
        let isProtected = state.isProtected(weekendKey)

        VStack(alignment: .leading, spacing: 16) {
            Text(label)
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                DayDetailColumn(day: .sat, events: eventsFor(.sat), isProtected: isProtected) { event in
                    eventToRemove = event
                }
                DayDetailColumn(day: .sun, events: eventsFor(.sun), isProtected: isProtected) { event in
                    eventToRemove = event
                }
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
    }

    private func eventsFor(_ day: WeekendDay) -> [WeekendEvent] {
        state.events(for: weekendKey).filter { $0.dayValues.contains(day) }
    }
}

struct DayDetailColumn: View {
    let day: WeekendDay
    let events: [WeekendEvent]
    let isProtected: Bool
    var onRemove: (WeekendEvent) -> Void

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
                    TimelineItemView(event: event) {
                        onRemove(event)
                    }
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

    var body: some View {
        NavigationStack {
            Form {
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
            }
            .navigationTitle("Add a weekend event")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add your new plan") {
                        Task { await handleSubmit() }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if let key = weekendKey, let date = CalendarHelper.parseKey(key) {
                    self.date = date
                }
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

        let startString = allDay ? "00:00" : CalendarHelper.timeString(from: startTime)
        let endString = allDay ? "23:59" : CalendarHelper.timeString(from: endTime)
        if !allDay && startString >= endString {
            errorMessage = "End time should be after start time."
            showError = true
            return
        }

        guard let userId = state.session?.user.id.uuidString.lowercased() else { return }
        let payload = NewWeekendEvent(
            title: title,
            type: planType.rawValue,
            weekendKey: weekendKey,
            days: selectedDays.map { $0.rawValue },
            startTime: startString,
            endTime: endString,
            userId: userId
        )

        let success = await state.addEvent(payload)
        if success {
            dismiss()
        }
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
                        Toggle("Send me a weekly weekend summary email", isOn: .constant(false))
                        Toggle("Remind me on Thursday about upcoming plans", isOn: .constant(false))
                    }
                }
            }
        }
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
