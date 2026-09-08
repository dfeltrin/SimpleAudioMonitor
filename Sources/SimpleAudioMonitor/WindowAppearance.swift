import AppKit
import SwiftUI

/// Configures the window hosting this view once SwiftUI has attached it.
struct WindowAppearance: NSViewRepresentable {
    let isCollapsed: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WindowAttachmentView {
        let view = WindowAttachmentView()
        view.onWindowChanged = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: WindowAttachmentView, context: Context) {
        context.coordinator.update(isCollapsed: isCollapsed)
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var window: NSWindow?
        private var expandedStyleMask: NSWindow.StyleMask?
        private var desiredCollapsed = false
        private var appliedCollapsed: Bool?
        private var bottomRightAnchor: NSPoint?
        private var appliedFrameSize: NSSize?
        private var isApplying = false
        private var updateScheduled = false

        func attach(to window: NSWindow?) {
            guard let window, self.window !== window else { return }
            if let previousWindow = self.window {
                NotificationCenter.default.removeObserver(self, name: NSWindow.didMoveNotification, object: previousWindow)
            }
            self.window = window
            expandedStyleMask = window.styleMask.subtracting(.resizable)
            appliedCollapsed = nil
            bottomRightAnchor = nil
            appliedFrameSize = nil
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidMove(_:)),
                name: NSWindow.didMoveNotification,
                object: window
            )
            scheduleUpdate()
        }

        func update(isCollapsed: Bool) {
            guard desiredCollapsed != isCollapsed || appliedCollapsed == nil else { return }
            desiredCollapsed = isCollapsed
            scheduleUpdate()
        }

        private func scheduleUpdate() {
            guard !updateScheduled else { return }
            updateScheduled = true
            // Native style and frame changes must happen outside SwiftUI's
            // current view update; several updates can share this one pass.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.updateScheduled = false
                self.applyAppearance()
            }
        }

        @objc private func windowDidMove(_ notification: Notification) {
            guard !isApplying, !updateScheduled,
                  let window,
                  let appliedFrameSize,
                  window.frame.size == appliedFrameSize else { return }
            // SwiftUI can resize its hosting window before updateNSView runs.
            // Only record moves at the settled size, never an in-flight resize.
            bottomRightAnchor = NSPoint(x: window.frame.maxX, y: window.frame.minY)
        }

        private func applyAppearance() {
            guard let window,
                  let expandedStyleMask,
                  appliedCollapsed != desiredCollapsed else { return }

            let anchor: NSPoint
            if let bottomRightAnchor {
                anchor = bottomRightAnchor
            } else if
               let screen = NSScreen.main ?? window.screen ?? NSScreen.screens.first {
                anchor = NSPoint(x: screen.visibleFrame.maxX, y: screen.visibleFrame.minY)
            } else {
                // Preserve the same bottom-right corner even after the user
                // drags the monitor to another position or display.
                anchor = NSPoint(x: window.frame.maxX, y: window.frame.minY)
            }
            bottomRightAnchor = anchor
            isApplying = true
            defer { isApplying = false }

            let contentSize = NSSize(
                width: desiredCollapsed ? MonitorLayout.collapsedWidth : MonitorLayout.expandedWidth,
                height: MonitorLayout.height
            )

            // Release the previous fixed-size constraints before changing the
            // style. A titled window cannot shrink to a 28-point-wide handle.
            window.contentMinSize = .zero
            window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            window.minSize = .zero
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            window.styleMask = desiredCollapsed ? .borderless : expandedStyleMask
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(srgbRed: 0.075, green: 0.09, blue: 0.105, alpha: 1)
            window.appearance = NSAppearance(named: .darkAqua)
            // SwiftUI controls such as the volume fader use drag gestures. If the
            // whole window background is movable, AppKit can interpret the same
            // gesture as a window drag and move the panel along with the fader.
            window.isMovableByWindowBackground = false

            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = desiredCollapsed
            }

            // Full-size content includes the native titlebar, but SwiftUI keeps
            // its fixed-height panel below that safe area. Account for it here
            // so the hosting view does not grow the window after anchoring it.
            let titlebarHeight = desiredCollapsed ? 0 : max(0, window.frame.height - window.contentLayoutRect.height)
            let nativeContentSize = NSSize(width: contentSize.width, height: contentSize.height + titlebarHeight)
            let frameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: nativeContentSize)).size
            let frame = NSRect(
                x: anchor.x - frameSize.width,
                y: anchor.y,
                width: frameSize.width,
                height: frameSize.height
            )
            window.setFrame(frame, display: true)
            window.contentMinSize = nativeContentSize
            window.contentMaxSize = nativeContentSize
            window.minSize = frameSize
            window.maxSize = frameSize
            appliedFrameSize = frameSize
            appliedCollapsed = desiredCollapsed
        }
    }
}

final class WindowAttachmentView: NSView {
    var onWindowChanged: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChanged?(window)
    }
}
