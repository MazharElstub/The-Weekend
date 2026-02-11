import Foundation
import Supabase

enum PlanType: String, Codable, CaseIterable {
    case plan
    case travel

    var label: String {
        switch self {
        case .plan: return "Local plans"
        case .travel: return "Travel plans"
        }
    }

    var accentHex: String {
        switch self {
        case .plan: return "#5F8FFF"
        case .travel: return "#FF7A5C"
        }
    }
}

enum WeekendDay: String, Codable, CaseIterable {
    case sat
    case sun

    var label: String {
        switch self {
        case .sat: return "Saturday"
        case .sun: return "Sunday"
        }
    }
}

enum ProtectionMode: String {
    case warn
    case block
}

struct WeekendEvent: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let type: String
    let weekendKey: String
    let days: [String]
    let startTime: String
    let endTime: String
    let userId: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case type
        case weekendKey = "weekend_key"
        case days
        case startTime = "start_time"
        case endTime = "end_time"
        case userId = "user_id"
    }

    var planType: PlanType {
        PlanType(rawValue: type) ?? .plan
    }

    var dayValues: [WeekendDay] {
        days.compactMap { WeekendDay(rawValue: $0) }
    }

    var isAllDay: Bool {
        startTime == "00:00" && endTime == "23:59"
    }
}

struct WeekendProtection: Codable {
    let weekendKey: String
    let userId: String

    enum CodingKeys: String, CodingKey {
        case weekendKey = "weekend_key"
        case userId = "user_id"
    }
}

struct NewWeekendProtection: Encodable {
    let weekendKey: String
    let userId: String

    enum CodingKeys: String, CodingKey {
        case weekendKey = "weekend_key"
        case userId = "user_id"
    }
}

struct NewWeekendEvent: Encodable {
    let title: String
    let type: String
    let weekendKey: String
    let days: [String]
    let startTime: String
    let endTime: String
    let userId: String

    enum CodingKeys: String, CodingKey {
        case title
        case type
        case weekendKey = "weekend_key"
        case days
        case startTime = "start_time"
        case endTime = "end_time"
        case userId = "user_id"
    }
}

struct MonthOption: Identifiable, Hashable {
    let id = UUID()
    let key: String
    let title: String
    let shortLabel: String
    let subtitle: String
    let year: Int?
    let weekends: [WeekendInfo]
}

struct WeekendInfo: Identifiable, Hashable {
    let id = UUID()
    let saturday: Date
    let label: String
}

@MainActor
final class AppState: ObservableObject {
    @Published var session: Session?
    @Published var events: [WeekendEvent] = []
    @Published var protections: Set<String> = []
    @Published var selectedTab: AppTab = .overview
    @Published var selectedMonthKey: String = "upcoming"
    @Published var isLoading = false
    @Published var authMessage: String?
    @Published var showAuthSplash = true
    @Published var useDarkMode = false
    @Published var protectionMode: ProtectionMode = .warn

    private let supabase: SupabaseClient

    init() {
        let url = URL(string: "https://vvuxlpsekzohlwywahtq.supabase.co")!
        let key = "sb_publishable_oQir3Zr26EqEERQDzIztcg_TIwK2CBK"
        self.supabase = SupabaseClient(supabaseURL: url, supabaseKey: key)
        self.useDarkMode = UserDefaults.standard.bool(forKey: "weekend-theme-dark")
        if let raw = UserDefaults.standard.string(forKey: "weekend-protection-mode"),
           let mode = ProtectionMode(rawValue: raw) {
            self.protectionMode = mode
        }
    }

    func bootstrap() async {
        do {
            self.session = try await supabase.auth.session
        } catch {
            self.session = nil
        }
        self.showAuthSplash = session == nil
        if session != nil {
            await loadAll()
        }
    }

    func signIn(email: String, password: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await signInWithRetry(email: email, password: password)
            session = try await supabase.auth.session
            showAuthSplash = false
            authMessage = nil
            await loadAll()
        } catch {
            authMessage = authErrorMessage(from: error)
        }
    }

    func signUp(email: String, password: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await supabase.auth.signUp(email: email, password: password)
            authMessage = "Check your email to confirm your account."
        } catch {
            authMessage = authErrorMessage(from: error)
        }
    }

    func signOut() async {
        do {
            try await supabase.auth.signOut()
        } catch {
            authMessage = error.localizedDescription
        }
        session = nil
        showAuthSplash = true
        events = []
        protections = []
    }

    private func signInWithRetry(email: String, password: String) async throws {
        var attempt = 0
        while true {
            do {
                _ = try await supabase.auth.signIn(email: email, password: password)
                return
            } catch {
                attempt += 1
                guard attempt < 3, shouldRetryAuth(error) else { throw error }
                let delayNs = UInt64(attempt) * 500_000_000
                try await Task.sleep(nanoseconds: delayNs)
            }
        }
    }

    private func shouldRetryAuth(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        let retryableCodes: Set<Int> = [
            NSURLErrorNetworkConnectionLost,
            NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost
        ]
        return retryableCodes.contains(nsError.code)
    }

    private func authErrorMessage(from error: Error) -> String {
        if shouldRetryAuth(error) {
            return "The network connection was lost. Please check simulator connectivity and try again."
        }
        return error.localizedDescription
    }

    func loadAll() async {
        await loadEvents()
        await loadProtections()
    }

    func loadEvents() async {
        guard let session = session else { return }
        let userId = normalizedUserId(for: session)
        do {
            let response: [WeekendEvent] = try await supabase
                .from("weekend_events")
                .select()
                .eq("user_id", value: userId)
                .order("weekend_key", ascending: true)
                .execute()
                .value
            self.events = response
        } catch {
            authMessage = error.localizedDescription
        }
    }

    func loadProtections() async {
        guard let session = session else { return }
        let userId = normalizedUserId(for: session)
        do {
            let response: [WeekendProtection] = try await supabase
                .from("weekend_protections")
                .select("weekend_key,user_id")
                .eq("user_id", value: userId)
                .order("weekend_key", ascending: true)
                .execute()
                .value
            self.protections = Set(response.map { $0.weekendKey })
        } catch {
            authMessage = error.localizedDescription
        }
    }

    func addEvent(_ draft: NewWeekendEvent) async -> Bool {
        guard session != nil else { return false }
        do {
            _ = try await supabase.database
                .from("weekend_events")
                .insert(draft)
                .execute()
            await loadEvents()
            return true
        } catch {
            authMessage = error.localizedDescription
            return false
        }
    }

    func removeEvent(_ event: WeekendEvent) async {
        guard let session = session else { return }
        let userId = normalizedUserId(for: session)
        do {
            _ = try await supabase
                .from("weekend_events")
                .delete()
                .eq("id", value: event.id)
                .eq("user_id", value: userId)
                .execute()
            await loadEvents()
        } catch {
            authMessage = error.localizedDescription
        }
    }

    func toggleProtection(weekendKey: String, removePlans: Bool) async {
        guard let session = session else { return }
        let userId = normalizedUserId(for: session)
        if protections.contains(weekendKey) {
            do {
                _ = try await supabase
                    .from("weekend_protections")
                    .delete()
                    .eq("weekend_key", value: weekendKey)
                    .eq("user_id", value: userId)
                    .execute()
                protections.remove(weekendKey)
            } catch {
                authMessage = error.localizedDescription
            }
            return
        }

        if removePlans {
            do {
                _ = try await supabase.database
                    .from("weekend_events")
                    .delete()
                    .eq("weekend_key", value: weekendKey)
                    .eq("user_id", value: userId)
                    .execute()
                await loadEvents()
            } catch {
                authMessage = error.localizedDescription
            }
        }

        do {
            let payload = NewWeekendProtection(
                weekendKey: weekendKey,
                userId: userId
            )
            _ = try await supabase.database
                .from("weekend_protections")
                .insert(payload)
                .execute()
            protections.insert(weekendKey)
        } catch {
            authMessage = error.localizedDescription
        }
    }

    private func normalizedUserId(for session: Session) -> String {
        session.user.id.uuidString.lowercased()
    }

    func isProtected(_ weekendKey: String) -> Bool {
        protections.contains(weekendKey)
    }

    func events(for weekendKey: String) -> [WeekendEvent] {
        events.filter { $0.weekendKey == weekendKey }
    }

    func status(for weekendKey: String) -> WeekendStatus {
        let weekendEvents = events.filter { $0.weekendKey == weekendKey }
        let hasTravel = weekendEvents.contains { $0.planType == .travel }
        let hasPlan = weekendEvents.contains { $0.planType == .plan }
        let isProtected = protections.contains(weekendKey)

        if hasTravel {
            return WeekendStatus(type: "travel", label: "Travel plans")
        }
        if hasPlan {
            return WeekendStatus(type: "plan", label: "Local plans")
        }
        if isProtected {
            return WeekendStatus(type: "protected", label: "Protected")
        }
        return WeekendStatus(type: "free", label: "Free")
    }

    func setTheme(_ isDark: Bool) {
        useDarkMode = isDark
        UserDefaults.standard.set(isDark, forKey: "weekend-theme-dark")
    }

    func setProtectionMode(_ mode: ProtectionMode) {
        protectionMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "weekend-protection-mode")
    }
}

enum AppTab: String, CaseIterable {
    case overview = "Overview"
    case weekend = "Weekend View"
    case settings = "Settings"
}

struct WeekendStatus {
    let type: String
    let label: String
}

struct CalendarHelper {
    static let calendar = Calendar.current
    static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()

    static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()

    static func weekendKey(for date: Date) -> String? {
        let weekday = calendar.component(.weekday, from: date)
        var saturday = date
        if weekday == 7 {
            return formatKey(date)
        }
        if weekday == 1 {
            saturday = calendar.date(byAdding: .day, value: -1, to: date) ?? date
            return formatKey(saturday)
        }
        return nil
    }

    static func formatKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func parseKey(_ key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }

    static func formatWeekendLabel(_ saturday: Date) -> String {
        let sunday = calendar.date(byAdding: .day, value: 1, to: saturday) ?? saturday
        if calendar.isDate(saturday, equalTo: sunday, toGranularity: .month) {
            return "\(monthFormatter.string(from: saturday)) \(dayFormatter.string(from: saturday))–\(dayFormatter.string(from: sunday))"
        }
        return "\(monthFormatter.string(from: saturday)) \(dayFormatter.string(from: saturday)) - \(monthFormatter.string(from: sunday)) \(dayFormatter.string(from: sunday))"
    }

    static func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func getMonths(startingFrom date: Date = Date()) -> [MonthOption] {
        var months: [MonthOption] = []
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date

        for offset in 0..<12 {
            guard let monthDate = calendar.date(byAdding: .month, value: offset, to: start) else { continue }
            let weekends = getWeekends(for: monthDate)
            let option = MonthOption(
                key: formatKey(monthDate),
                title: monthYearFormatter.string(from: monthDate),
                shortLabel: monthFormatter.string(from: monthDate),
                subtitle: String(calendar.component(.year, from: monthDate)),
                year: calendar.component(.year, from: monthDate),
                weekends: weekends
            )
            months.append(option)
        }

        return months
    }

    static func getMonthOptions(startingFrom date: Date = Date()) -> [MonthOption] {
        let months = getMonths(startingFrom: date)
        guard let current = months.first else { return [] }
        let next = months.count > 1 ? months[1] : nil

        let upcomingLabel: String
        if let next = next {
            upcomingLabel = "\(monthFormatter.string(from: CalendarHelper.parseKey(current.key) ?? date)) \(current.subtitle) – \(monthFormatter.string(from: CalendarHelper.parseKey(next.key) ?? date)) \(next.subtitle)"
        } else {
            upcomingLabel = "\(monthFormatter.string(from: CalendarHelper.parseKey(current.key) ?? date)) \(current.subtitle)"
        }

        var upcomingWeekends: [WeekendInfo] = []
        upcomingWeekends.append(contentsOf: current.weekends)
        if let next = next {
            upcomingWeekends.append(contentsOf: next.weekends)
        }

        var options: [MonthOption] = [
            MonthOption(
                key: "upcoming",
                title: "Upcoming weekends",
                shortLabel: "Upcoming",
                subtitle: upcomingLabel,
                year: nil,
                weekends: upcomingWeekends
            )
        ]

        options.append(contentsOf: months)
        return options
    }

    static func getWeekends(for monthDate: Date) -> [WeekendInfo] {
        var weekends: [WeekendInfo] = []
        guard let range = calendar.range(of: .day, in: .month, for: monthDate) else { return [] }
        let year = calendar.component(.year, from: monthDate)
        let month = calendar.component(.month, from: monthDate)

        for day in range {
            if let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
               calendar.component(.weekday, from: date) == 7 {
                let label = formatWeekendLabel(date)
                weekends.append(WeekendInfo(saturday: date, label: label))
            }
        }

        return weekends
    }
}
