import SwiftUI

@main
struct PhophyApp: App {
    init() {
        AppSettings.registerDefaults()
        BackgroundWork.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}
