import SwiftUI

@main
struct MacBoxApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1040, minHeight: 680)
        }
        .defaultSize(width: 1280, height: 768)
    }
}
