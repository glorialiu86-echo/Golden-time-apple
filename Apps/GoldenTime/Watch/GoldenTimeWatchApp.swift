import SwiftUI

@main
struct GoldenTimeWatchApp: App {
    init() {
        GTWatchConnectivitySync.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            GoldenTimeWatchRootView()
        }
    }
}
