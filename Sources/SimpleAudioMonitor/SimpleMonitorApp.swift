import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct SimpleAudioMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var audioMonitor = AudioMonitor()
    @State private var isCollapsed = false

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
            ContentView(isCollapsed: $isCollapsed)
                .environmentObject(audioMonitor)
                .frame(
                    width: isCollapsed ? MonitorLayout.collapsedWidth : MonitorLayout.expandedWidth,
                    height: MonitorLayout.height
                )
                .background(WindowAppearance(isCollapsed: isCollapsed))
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: MonitorLayout.expandedWidth, height: MonitorLayout.height)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}
