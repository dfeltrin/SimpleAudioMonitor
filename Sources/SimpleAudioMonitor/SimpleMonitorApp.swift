import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftUI creates the window during launch; wait for the next run-loop turn
        // so its final content size is available before positioning it.
        DispatchQueue.main.async { [weak self] in
            self?.moveMainWindowToTopRight()
        }
    }

    @MainActor
    private func moveMainWindowToTopRight() {
        guard let window = NSApp.windows.first(where: { $0.isVisible }) ?? NSApp.windows.first,
              let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let windowFrame = window.frame
        window.setFrameOrigin(
            NSPoint(
                x: visibleFrame.maxX - windowFrame.width,
                y: visibleFrame.maxY - windowFrame.height
            )
        )
    }
}

@main
struct SimpleAudioMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
                .frame(minWidth: 210, minHeight: 700)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}
