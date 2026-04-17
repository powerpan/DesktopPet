import SwiftUI

@main
struct DesktopPetApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.automatic)
        .defaultSize(width: 480, height: 360)
    }
}
