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
                    switch newPhase {
                    case .active:
                        Task {
                            await state.handleAppDidBecomeActive()
                        }
                    case .inactive, .background:
                        Task { @MainActor in
                            state.handleAppWillResignActive()
                        }
                    @unknown default:
                        break
                    }
                }
        }
    }
}
