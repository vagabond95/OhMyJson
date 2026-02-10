//
//  WindowManager.swift
//  OhMyJson
//

#if os(macOS)
import AppKit
import SwiftUI

// Custom NSHostingView that prevents window dragging from titlebar area
class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }
}

class WindowManager: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = WindowManager()

    @Published private(set) var isViewerOpen = false
    @Published var currentJSON: String? {
        didSet {
            // Cache formatted JSON when currentJSON changes
            if let json = currentJSON {
                _formattedJSONCache = JSONParser.shared.formatJSON(json, indentSize: AppSettings.shared.jsonIndent)
            } else {
                _formattedJSONCache = nil
            }
        }
    }
    @Published var parseResult: JSONParseResult?

    /// Cached formatted JSON string (computed once when currentJSON is set)
    private var _formattedJSONCache: String?
    var formattedJSON: String? { _formattedJSONCache }

    private var viewerWindow: NSWindow?
    private let tabManager = TabManager.shared

    private override init() {
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(jsonIndentChanged),
            name: .jsonIndentChanged,
            object: nil
        )
    }

    @objc private func jsonIndentChanged(_ notification: Notification) {
        guard let json = currentJSON else { return }
        _formattedJSONCache = JSONParser.shared.formatJSON(json, indentSize: AppSettings.shared.jsonIndent)
        objectWillChange.send()
    }

    /// Create a new tab with optional JSON content
    /// If window is not open, create window first
    func createNewTab(with jsonString: String?) {
        // Parse JSON if provided
        let parseResult: JSONParseResult?
        if let json = jsonString {
            parseResult = JSONParser.shared.parse(json)
        } else {
            parseResult = nil
        }

        // Create tab
        let tabId = tabManager.createTab(with: jsonString)

        // Update tab with parse result
        if let result = parseResult {
            tabManager.updateTabParseResult(id: tabId, result: result)
        }

        // If window not open, create it
        if !isViewerOpen {
            createAndShowWindow()
        } else {
            // Window already open, just bring to front
            bringToFront()
        }

        // Update current state to reflect new tab
        currentJSON = jsonString
        self.parseResult = parseResult
    }

    // Legacy compatibility methods (deprecated)
    @available(*, deprecated, renamed: "createNewTab(with:)")
    func openViewer(with jsonString: String) {
        createNewTab(with: jsonString)
    }

    @available(*, deprecated, renamed: "createNewTab(with:)")
    func openViewerEmpty() {
        createNewTab(with: nil)
    }

    @available(*, deprecated, renamed: "createNewTab(with:)")
    func openViewerWithError(message: String) {
        createNewTab(with: nil)
        ToastManager.shared.show(message, duration: Duration.toastLong)
    }

    /// Flag to allow programmatic close without interception
    private var allowClose = false

    private func createAndShowWindow() {
        let contentView = ViewerWindow()
            .environmentObject(self)
            .environmentObject(AppSettings.shared)

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
        window.backgroundColor = NSColor(red: 0.145, green: 0.145, blue: 0.145, alpha: 1.0)  // #252525
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
        NSApp.activate(ignoringOtherApps: true)
        repositionTrafficLights(in: window)
    }

    private func repositionTrafficLights(in window: NSWindow) {
        guard let closeButton = window.standardWindowButton(.closeButton),
              let titlebarView = closeButton.superview else { return }

        // TabBarView total height (content ~28pt + vertical padding 12pt = 40pt)
        let tabBarHeight: CGFloat = 40
        let titlebarHeight = titlebarView.frame.height

        // Push buttons down so they center within the taller tab bar area
        // Default: centered in titlebar (~28pt). Target: centered in tab bar (40pt).
        let pushDown = (tabBarHeight - titlebarHeight) / 2

        let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for type in buttonTypes {
            guard let button = window.standardWindowButton(type) else { continue }
            let buttonHeight = button.frame.height
            let defaultY = (titlebarHeight - buttonHeight) / 2
            button.setFrameOrigin(NSPoint(x: button.frame.origin.x + 8, y: defaultY - pushDown))
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        repositionTrafficLights(in: window)
    }

    /// Intercept window close (Command+W or red button) to close tab instead
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // If programmatic close is requested, allow it
        if allowClose {
            allowClose = false
            return true
        }

        // Otherwise, close current tab instead of window
        if let activeTabId = tabManager.activeTabId {
            tabManager.closeTab(id: activeTabId)
        }

        // Prevent default window close - TabManager will call closeViewer if needed
        return false
    }

    func windowWillClose(_ notification: Notification) {
        isViewerOpen = false
        viewerWindow = nil
        currentJSON = nil
        parseResult = nil
        // Clear all tabs when window closes
        tabManager.closeAllTabs()
        // Return to accessory app (hide from Dock)
        NSApp.setActivationPolicy(.accessory)
    }

    func closeViewer() {
        allowClose = true
        viewerWindow?.close()
    }

    func bringToFront() {
        NSApp.setActivationPolicy(.regular)
        viewerWindow?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        viewerWindow?.makeKeyAndOrderFront(nil)
    }
}
#endif
