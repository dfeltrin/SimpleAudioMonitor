import SwiftUI

@main
struct SimpleAudioMonitorApp: App {
    @StateObject private var audioMonitor = AudioMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioMonitor)
                .frame(minWidth: 238, minHeight: 650)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}
