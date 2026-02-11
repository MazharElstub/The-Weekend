import SwiftUI

@main
struct TheWeekendApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .preferredColorScheme(state.useDarkMode ? .dark : .light)
                .task {
                    await state.bootstrap()
                }
        }
    }
}
