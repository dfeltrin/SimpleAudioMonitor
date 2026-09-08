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
            self?.moveMainWindowToBottomRight(attemptsRemaining: 10)
        }
    }

    @MainActor
    private func moveMainWindowToBottomRight(attemptsRemaining: Int) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }) ?? NSApp.windows.first else {
            guard attemptsRemaining > 0 else { return }
            DispatchQueue.main.async { [weak self] in
                self?.moveMainWindowToBottomRight(attemptsRemaining: attemptsRemaining - 1)
            }
            return
        }

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        let visibleFrame = screen.visibleFrame
        let windowFrame = window.frame
        window.setFrameOrigin(
            NSPoint(
                x: visibleFrame.maxX - windowFrame.width,
                y: visibleFrame.minY
            )
        )
    }

    @MainActor
    func anchorMainWindowToBottomRight() {
        DispatchQueue.main.async { [weak self] in
            self?.moveMainWindowToBottomRight(attemptsRemaining: 1)
        }
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
                .frame(width: isCollapsed ? 28 : 210, height: 700)
        }
        .onChange(of: isCollapsed) { _, _ in
            appDelegate.anchorMainWindowToBottomRight()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}
