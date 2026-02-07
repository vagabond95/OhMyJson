//
//  AppDelegate.swift
//  OhMyJson
//

#if os(macOS)
import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsPanel: NSPanel?
    private var onboardingController: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupMainMenu()
        setupHotKey()

        // Listen for hotkey changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotKeyChanged),
            name: .openHotKeyChanged,
            object: nil
        )

        // Show onboarding on first launch
        if !AppSettings.shared.hasSeenOnboarding {
            showOnboarding()
        }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App Menu (OhMyJson)
        let appMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        let aboutItem = NSMenuItem(title: "About OhMyJson", action: #selector(showSettings), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        appMenu.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Quit OhMyJson", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        mainMenu.addItem(appMenuItem)

        // File Menu - Only Command+N and Command+W overrides
        let fileMenu = NSMenu(title: "File")
        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu

        let newTabItem = NSMenuItem(title: "New Tab", action: #selector(newTab), keyEquivalent: "n")
        newTabItem.target = self
        fileMenu.addItem(newTabItem)

        // Command+W is handled by WindowManager.windowShouldClose, but add menu item for visibility
        let closeTabItem = NSMenuItem(title: "Close Tab", action: #selector(closeTab), keyEquivalent: "w")
        closeTabItem.target = self
        fileMenu.addItem(closeTabItem)

        mainMenu.addItem(fileMenuItem)

        // Edit Menu - Standard system actions (responder chain handles these)
        let editMenu = NSMenu(title: "Edit")
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        mainMenu.addItem(editMenuItem)

        // Window Menu - Standard window management
        let windowMenu = NSMenu(title: "Window")
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(NSMenuItem.separator())
        let prevTabItem = NSMenuItem(title: "Show Previous Tab", action: #selector(showPreviousTab), keyEquivalent: "[")
        prevTabItem.keyEquivalentModifierMask = [.command, .shift]
        prevTabItem.target = self
        windowMenu.addItem(prevTabItem)
        let nextTabItem = NSMenuItem(title: "Show Next Tab", action: #selector(showNextTab), keyEquivalent: "]")
        nextTabItem.keyEquivalentModifierMask = [.command, .shift]
        nextTabItem.target = self
        windowMenu.addItem(nextTabItem)
        mainMenu.addItem(windowMenuItem)
        NSApplication.shared.windowsMenu = windowMenu

        NSApplication.shared.mainMenu = mainMenu
    }

    @objc private func newTab(_ sender: Any?) {
        if onboardingController?.isShowing == true { return }
        WindowManager.shared.createNewTab(with: nil)
    }

    @objc private func closeTab(_ sender: Any?) {
        if onboardingController?.isShowing == true { return }
        if let activeTabId = TabManager.shared.activeTabId {
            TabManager.shared.closeTab(id: activeTabId)
        }
    }

    @objc private func showPreviousTab(_ sender: Any?) {
        TabManager.shared.selectPreviousTab()
    }

    @objc private func showNextTab(_ sender: Any?) {
        TabManager.shared.selectNextTab()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "curlybraces", accessibilityDescription: "OhMyJson")
            button.action = #selector(statusBarButtonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        setupMenu()
    }

    private func setupMenu() {
        let menu = NSMenu()

        // Open
        let openItem = NSMenuItem(title: "Open", action: #selector(openViewer), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        // Settings
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit OhMyJson", action: #selector(quitApp), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        setupMenu()
    }

    @objc private func openViewer(_ sender: Any?) {
        if onboardingController?.isShowing == true { return }
        handleHotKey()
    }

    @objc private func showSettings(_ sender: Any?) {
        if settingsPanel == nil {
            let panel = NSPanel(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            panel.title = "OhMyJson"
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.backgroundColor = .clear
            panel.contentViewController = NSHostingController(rootView: SettingsWindowView())
            settingsPanel = panel
        }

        settingsPanel?.center()
        settingsPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
    }

    @objc private func hotKeyChanged(_ notification: Notification) {
        // Restart hotkey manager with new combo
        setupHotKey()
    }

    private func setupHotKey() {
        let combo = AppSettings.shared.openHotKeyCombo

        HotKeyManager.shared.start(combo: combo) { [weak self] in
            self?.handleHotKey()
        }
    }

    private func handleHotKey() {
        // Read clipboard content
        guard let clipboardText = ClipboardService.shared.readText(), !clipboardText.isEmpty else {
            // Case 1: Clipboard is empty → create tab with empty state
            WindowManager.shared.createNewTab(with: nil)
            return
        }

        // Check size (5MB limit)
        let sizeInBytes = clipboardText.utf8.count
        let sizeInMB = Double(sizeInBytes) / (1024 * 1024)

        if sizeInMB > 5.0 {
            // Case: Size exceeds 5MB → show confirmation dialog
            showSizeConfirmationDialog(size: sizeInMB, text: clipboardText)
            return
        }

        // Validate JSON
        let parseResult = JSONParser.shared.parse(clipboardText)

        switch parseResult {
        case .success:
            // Case 3: Valid JSON → create tab with JSON
            WindowManager.shared.createNewTab(with: clipboardText)

        case .failure:
            // Case 2: Invalid JSON → show toast + create empty tab
            ToastManager.shared.show("Invalid JSON in clipboard", duration: 2.0)
            WindowManager.shared.createNewTab(with: nil)
        }
    }

    private func showSizeConfirmationDialog(size: Double, text: String) {
        let alert = NSAlert()
        alert.messageText = "Lager JSON "
        alert.informativeText = String(format: "Exceed JSON size over 5MB (%.1f MB)\nLoading..", size)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            // User chose "계속" - proceed with creating tab
            WindowManager.shared.createNewTab(with: text)
        }
        // If user chose "취소", do nothing
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        HotKeyManager.shared.isEnabled = false

        let controller = OnboardingWindowController()
        controller.onDismiss = { [weak self] in
            self?.completeOnboarding()
        }
        controller.show()
        onboardingController = controller
    }

    private func completeOnboarding() {
        AppSettings.shared.hasSeenOnboarding = true
        HotKeyManager.shared.isEnabled = true
        onboardingController = nil
        WindowManager.shared.createNewTab(with: SampleData.json)

        // Trigger confetti in ViewerWindow after a short delay for window to appear
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(name: .onboardingCompleted, object: nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.stop()
    }
}
#endif
