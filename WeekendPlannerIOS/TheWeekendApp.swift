import SwiftUI

@main
struct TheWeekendApp: App {
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .preferredColorScheme(state.appTheme.preferredColorScheme)
                .task {
                    await state.bootstrap()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task {
                        await state.refreshNotificationPermissionState()
                        await state.refreshCalendarPermissionState()
                        await state.rescheduleNotifications()
                        await state.flushPendingOperations()
                    }
                }
        }
    }
}
