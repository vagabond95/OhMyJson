//
//  WindowManager.swift
//  OhMyJson
//
//  Pure window lifecycle manager. Data state moved to ViewerViewModel (Phase 3).
//

#if os(macOS)
import AppKit
import SwiftUI
import Combine

// Custom NSHostingView that prevents window dragging from titlebar area
class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }
}

@Observable
class WindowManager: NSObject, NSWindowDelegate, WindowManagerProtocol {
    static let shared = WindowManager()

    private(set) var isViewerOpen = false

    private var viewerWindow: NSWindow?
    private var themeCancellable: AnyCancellable?

    /// Weak reference to ViewModel for window delegate callbacks
    weak var viewModel: ViewerViewModel?

    private override init() {
        super.init()
        // Update window background color when theme changes
        themeCancellable = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.viewerWindow?.backgroundColor = AppSettings.shared.currentTheme.nsBackground
            }
    }

    deinit {
        themeCancellable?.cancel()
    }

    // MARK: - Window Lifecycle

    /// Create and show the viewer window with the given content view
    func createAndShowWindow<Content: View>(contentView: Content) {
        let hostingView = ClickThroughHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: WindowSize.defaultWidth, height: WindowSize.defaultHeight),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.title = "OhMyJson"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = AppSettings.shared.currentTheme.nsBackground
        window.center()
        window.setFrameAutosaveName("ViewerWindow")

        window.minSize = NSSize(width: WindowSize.minWidth, height: WindowSize.minHeight)

        // CRITICAL: Disable window dragging from background to allow button clicks in titlebar area
        window.isMovableByWindowBackground = false

        window.isReleasedWhenClosed = false
        window.delegate = self

        viewerWindow = window
        isViewerOpen = true

        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        repositionTrafficLights(in: window)
    }

    /// Protocol conformance — used by ViewModel to show window (delegates to createAndShowWindow)
    func createNewTab(with jsonString: String?) {
        // This is a no-op if window is already open.
        // Actual window creation is done by AppDelegate via createAndShowWindow().
        // This method exists for WindowManagerProtocol conformance.
        // The ViewModel calls this, but AppDelegate handles the actual window creation flow.
        if !isViewerOpen {
            // Window creation is triggered by AppDelegate, not here
            // This path should not be reached in normal flow
        }
        bringToFront()
    }

    private func repositionTrafficLights(in window: NSWindow) {
        guard let closeButton = window.standardWindowButton(.closeButton),
              let titlebarView = closeButton.superview else { return }

        let tabBarHeight: CGFloat = 40
        let titlebarHeight = titlebarView.frame.height
        guard titlebarHeight > 0 else { return }

        let pushDown = (tabBarHeight - titlebarHeight) / 2
        guard pushDown > 0 else { return }

        let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for type in buttonTypes {
            guard let button = window.standardWindowButton(type) else { continue }
            let buttonHeight = button.frame.height
            let defaultY = (titlebarHeight - buttonHeight) / 2
            // Use default x position from AppKit (reset on each resize) + consistent left padding
            button.setFrameOrigin(NSPoint(x: button.frame.origin.x + 8, y: defaultY - pushDown))
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        repositionTrafficLights(in: window)
    }

    /// Flag to allow programmatic close without interception
    private var allowClose = false

    /// Intercept window close (Command+W or red button) to close tab instead
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // If programmatic close is requested, allow it
        if allowClose {
            allowClose = false
            return true
        }

        // Delegate tab close to ViewModel (mediator)
        if let activeTabId = viewModel?.activeTabId {
            viewModel?.closeTab(id: activeTabId)
        }

        // Prevent default window close - ViewModel will call closeViewer if last tab
        return false
    }

    func windowWillClose(_ notification: Notification) {
        isViewerOpen = false
        // Break delegate retain cycle before releasing window
        viewerWindow?.delegate = nil
        viewerWindow = nil
        // Delegate cleanup to ViewModel
        viewModel?.onWindowWillClose()
        // Return to accessory app only if no other visible windows remain
        let hasOtherWindows = NSApp.windows.contains { $0.isVisible && $0 !== notification.object as? NSWindow }
        if !hasOtherWindows {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func closeViewer() {
        allowClose = true
        viewerWindow?.close()
    }

    func bringToFront() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        viewerWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func isViewerWindow(_ window: NSWindow) -> Bool {
        viewerWindow != nil && window === viewerWindow
    }
}
#endif
