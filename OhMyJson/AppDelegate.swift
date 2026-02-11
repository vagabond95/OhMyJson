//
//  AppDelegate.swift
//  OhMyJson
//

#if os(macOS)
import AppKit
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var onboardingController: OnboardingWindowController?
    private var accessibilityCancellable: AnyCancellable?
    private var hotKeyCancellable: AnyCancellable?
    private var shortcutsCancellable: AnyCancellable?

    // Menu item references for dynamic shortcut updates
    private weak var newTabMenuItem: NSMenuItem?
    private weak var closeTabMenuItem: NSMenuItem?
    private weak var prevTabMenuItem: NSMenuItem?
    private weak var nextTabMenuItem: NSMenuItem?
    private weak var beautifyMenuItem: NSMenuItem?
    private weak var treeMenuItem: NSMenuItem?

    /// ViewModel — created and owned here, shared with Views via .environmentObject()
    private var viewModel: ViewerViewModel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateOldInstances()

        // Create ViewModel with real service dependencies
        viewModel = ViewerViewModel(
            tabManager: TabManager.shared,
            clipboardService: ClipboardService.shared,
            jsonParser: JSONParser.shared,
            windowManager: WindowManager.shared
        )

        // Wire ViewModel into WindowManager for delegate callbacks
        WindowManager.shared.viewModel = viewModel

        // Set up window show callback — ViewModel calls this when it needs a window
        viewModel.onNeedShowWindow = { [weak self] in
            self?.ensureWindowShown()
        }

        setupMenuBar()
        setupMainMenu()

        AccessibilityManager.shared.startMonitoring()
        AccessibilityManager.shared.promptAccessibilityPermission()
        setupAccessibilityObserver()
        setupHotKey()

        // Listen for hotkey changes via Combine
        hotKeyCancellable = AppSettings.shared.hotKeyChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setupHotKey()
            }

        // Listen for app shortcut changes to update menu key equivalents
        shortcutsCancellable = AppSettings.shared.appShortcutsChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.updateMenuShortcuts()
            }

        // Show onboarding on first launch, otherwise open window immediately
        if !AppSettings.shared.hasSeenOnboarding {
            showOnboarding()
        } else {
            openWindowWithNewTab(json: nil)
        }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App Menu (OhMyJson)
        let appMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        let aboutItem = NSMenuItem(title: String(localized: "menu.about"), action: #selector(showSettings), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        appMenu.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(title: String(localized: "menu.settings"), action: #selector(showSettings), keyEquivalent: AppShortcut.settings.keyEquivalent)
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: String(localized: "menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: AppShortcut.quit.keyEquivalent))
        mainMenu.addItem(appMenuItem)

        // File Menu - Only Command+N and Command+W overrides
        let fileMenu = NSMenu(title: "File")
        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu

        let newTabItem = NSMenuItem(title: String(localized: "menu.new_tab"), action: #selector(newTab), keyEquivalent: AppShortcut.newTab.keyEquivalent)
        newTabItem.keyEquivalentModifierMask = AppShortcut.newTab.modifiers
        newTabItem.target = self
        fileMenu.addItem(newTabItem)
        self.newTabMenuItem = newTabItem

        let closeTabItem = NSMenuItem(title: String(localized: "menu.close_tab"), action: #selector(closeTab), keyEquivalent: AppShortcut.closeTab.keyEquivalent)
        closeTabItem.keyEquivalentModifierMask = AppShortcut.closeTab.modifiers
        closeTabItem.target = self
        fileMenu.addItem(closeTabItem)
        self.closeTabMenuItem = closeTabItem

        fileMenu.addItem(NSMenuItem.separator())

        let prevTabItem = NSMenuItem(title: String(localized: "menu.previous_tab"), action: #selector(showPreviousTab), keyEquivalent: AppShortcut.previousTab.keyEquivalent)
        prevTabItem.keyEquivalentModifierMask = AppShortcut.previousTab.modifiers
        prevTabItem.target = self
        fileMenu.addItem(prevTabItem)
        self.prevTabMenuItem = prevTabItem

        let nextTabItem = NSMenuItem(title: String(localized: "menu.next_tab"), action: #selector(showNextTab), keyEquivalent: AppShortcut.nextTab.keyEquivalent)
        nextTabItem.keyEquivalentModifierMask = AppShortcut.nextTab.modifiers
        nextTabItem.target = self
        fileMenu.addItem(nextTabItem)
        self.nextTabMenuItem = nextTabItem

        mainMenu.addItem(fileMenuItem)

        // View Menu - Find and view mode switching
        let viewMenu = NSMenu(title: "View")
        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu

        let findItem = NSMenuItem(title: String(localized: "menu.find"), action: #selector(toggleSearch), keyEquivalent: AppShortcut.find.keyEquivalent)
        findItem.target = self
        viewMenu.addItem(findItem)

        viewMenu.addItem(NSMenuItem.separator())

        let beautifyItem = NSMenuItem(title: String(localized: "menu.beautify_mode"), action: #selector(switchToBeautify), keyEquivalent: AppShortcut.beautifyMode.keyEquivalent)
        beautifyItem.keyEquivalentModifierMask = AppShortcut.beautifyMode.modifiers
        beautifyItem.target = self
        viewMenu.addItem(beautifyItem)
        self.beautifyMenuItem = beautifyItem

        let treeItem = NSMenuItem(title: String(localized: "menu.tree_mode"), action: #selector(switchToTree), keyEquivalent: AppShortcut.treeMode.keyEquivalent)
        treeItem.keyEquivalentModifierMask = AppShortcut.treeMode.modifiers
        treeItem.target = self
        viewMenu.addItem(treeItem)
        self.treeMenuItem = treeItem

        mainMenu.addItem(viewMenuItem)

        // Edit Menu - Standard system actions (responder chain handles these)
        let editMenu = NSMenu(title: "Edit")
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        editMenu.addItem(NSMenuItem(title: String(localized: "menu.undo"), action: Selector(("undo:")), keyEquivalent: AppShortcut.undo.keyEquivalent))
        editMenu.addItem(NSMenuItem(title: String(localized: "menu.redo"), action: Selector(("redo:")), keyEquivalent: AppShortcut.redo.keyEquivalent))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: String(localized: "menu.cut"), action: #selector(NSText.cut(_:)), keyEquivalent: AppShortcut.cut.keyEquivalent))
        editMenu.addItem(NSMenuItem(title: String(localized: "menu.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: AppShortcut.copy.keyEquivalent))
        editMenu.addItem(NSMenuItem(title: String(localized: "menu.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: AppShortcut.paste.keyEquivalent))
        editMenu.addItem(NSMenuItem(title: String(localized: "menu.select_all"), action: #selector(NSText.selectAll(_:)), keyEquivalent: AppShortcut.selectAll.keyEquivalent))
        mainMenu.addItem(editMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    private func updateMenuShortcuts() {
        newTabMenuItem?.keyEquivalent = AppShortcut.newTab.keyEquivalent
        newTabMenuItem?.keyEquivalentModifierMask = AppShortcut.newTab.modifiers

        closeTabMenuItem?.keyEquivalent = AppShortcut.closeTab.keyEquivalent
        closeTabMenuItem?.keyEquivalentModifierMask = AppShortcut.closeTab.modifiers

        prevTabMenuItem?.keyEquivalent = AppShortcut.previousTab.keyEquivalent
        prevTabMenuItem?.keyEquivalentModifierMask = AppShortcut.previousTab.modifiers

        nextTabMenuItem?.keyEquivalent = AppShortcut.nextTab.keyEquivalent
        nextTabMenuItem?.keyEquivalentModifierMask = AppShortcut.nextTab.modifiers

        beautifyMenuItem?.keyEquivalent = AppShortcut.beautifyMode.keyEquivalent
        beautifyMenuItem?.keyEquivalentModifierMask = AppShortcut.beautifyMode.modifiers

        treeMenuItem?.keyEquivalent = AppShortcut.treeMode.keyEquivalent
        treeMenuItem?.keyEquivalentModifierMask = AppShortcut.treeMode.modifiers
    }

    @objc private func newTab(_ sender: Any?) {
        if onboardingController?.isShowing == true { return }
        openWindowWithNewTab(json: nil)
    }

    @objc private func closeTab(_ sender: Any?) {
        if onboardingController?.isShowing == true { return }

        // If the Settings window is the key window, close it instead of a tab
        if let window = settingsWindow, window.isKeyWindow {
            window.close()
            settingsWindow = nil
            return
        }

        if let activeTabId = viewModel.activeTabId {
            viewModel.closeTab(id: activeTabId)
        }
    }

    @objc private func toggleSearch(_ sender: Any?) {
        if onboardingController?.isShowing == true { return }
        withAnimation(.easeInOut(duration: Animation.quick)) {
            viewModel.isSearchVisible.toggle()
        }
    }

    @objc private func switchToBeautify(_ sender: Any?) {
        if onboardingController?.isShowing == true { return }
        viewModel.switchViewMode(to: .beautify)
    }

    @objc private func switchToTree(_ sender: Any?) {
        if onboardingController?.isShowing == true { return }
        viewModel.switchViewMode(to: .tree)
    }

    @objc private func showPreviousTab(_ sender: Any?) {
        viewModel.selectPreviousTab()
    }

    @objc private func showNextTab(_ sender: Any?) {
        viewModel.selectNextTab()
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
        let openItem = NSMenuItem(title: String(localized: "menu.open"), action: #selector(openViewer), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        // Settings
        let settingsItem = NSMenuItem(title: String(localized: "menu.settings"), action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: String(localized: "menu.quit"), action: #selector(quitApp), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        setupMenu()
    }

    @objc private func openViewer(_ sender: Any?) {
        if onboardingController?.isShowing == true { return }
        viewModel.handleHotKey()
    }

    @objc private func showSettings(_ sender: Any?) {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "settings.title")
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.contentViewController = NSHostingController(
            rootView: SettingsWindowView()
                .environment(AppSettings.shared)
        )
        settingsWindow = window

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
    }

    private func setupAccessibilityObserver() {
        accessibilityCancellable = AccessibilityManager.shared.accessibilityChanged
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] granted in
                if granted {
                    self?.setupHotKey()
                } else {
                    HotKeyManager.shared.stop()
                }
            }
    }

    private func setupHotKey() {
        let combo = AppSettings.shared.openHotKeyCombo

        HotKeyManager.shared.start(combo: combo) { [weak self] in
            self?.viewModel.handleHotKey()
        }
    }

    // MARK: - Window Creation Helper

    /// Creates a new tab (via ViewModel) and ensures the window is open
    private func openWindowWithNewTab(json: String?) {
        // Create tab via ViewModel (handles LRU, parsing, etc.)
        viewModel.createNewTab(with: json)

        // ensureWindowShown is called by ViewModel's onNeedShowWindow callback if needed
    }

    /// Called by ViewModel when it needs the window to be shown
    private func ensureWindowShown() {
        guard !WindowManager.shared.isViewerOpen else { return }

        let contentView = ViewerWindow()
            .environment(viewModel!)
            .environment(AppSettings.shared)

        WindowManager.shared.createAndShowWindow(contentView: contentView)
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
        setupHotKey()
        openWindowWithNewTab(json: SampleData.json)

        // Trigger confetti in ViewerWindow after a short delay for window to appear
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.confettiDelay) { [weak self] in
            self?.viewModel.triggerConfetti()
        }
    }

    // MARK: - Duplicate Process Detection

    /// Terminate any previously running instances of this app to prevent zombie processes
    private func terminateOldInstances() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        guard !bundleID.isEmpty else { return }

        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        for app in runningApps where app.processIdentifier != currentPID {
            app.terminate()
            print("Terminated old instance: PID \(app.processIdentifier)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.stop()
        AccessibilityManager.shared.stopMonitoring()
        accessibilityCancellable = nil
        hotKeyCancellable = nil
        shortcutsCancellable = nil
        WindowManager.shared.closeViewer()
    }
}
#endif
