import SwiftUI

@main
struct MacBoxApp: App {
    init() {
        Task {
            await LegacyBundleMigrator().repairIfNeeded()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1040, minHeight: 680)
        }
        .defaultSize(width: 1280, height: 768)
    }
}
