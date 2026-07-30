import SwiftUI

@main
@MainActor
struct RainflowApp: App {
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            AuthGateView()
                .environmentObject(container.authStore)
                .environmentObject(container.ledgerStore)
        }
    }
}
