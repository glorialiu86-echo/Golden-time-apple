import SwiftUI
import UserNotifications

@main
struct GoldenTimeApp: App {
    init() {
        UNUserNotificationCenter.current().delegate = TwilightReminderNotificationDelegate.shared
        GTWatchConnectivitySync.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            GoldenTimePhoneRootView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
