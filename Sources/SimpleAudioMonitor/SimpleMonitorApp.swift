import AppKit
import SwiftUI

@main
struct SimpleAudioMonitorApp: App {
    @StateObject private var audioMonitor = AudioMonitor()

    init() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        let existingInstance = NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == bundleIdentifier && $0.processIdentifier != currentProcessID
        }

        guard let existingInstance else { return }
        existingInstance.activate(options: [.activateAllWindows])
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }

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
