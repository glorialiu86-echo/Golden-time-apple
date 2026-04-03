import SwiftUI

@main
struct GoldenTimeApp: App {
    var body: some Scene {
        WindowGroup {
            GoldenTimePhoneRootView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
