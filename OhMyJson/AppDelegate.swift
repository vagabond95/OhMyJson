//
//  AppDelegate.swift
//  OhMyJson
//

#if os(macOS)
import AppKit
import SwiftUI
import Combine
import Sparkle
import Sentry

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var onboardingController: OnboardingWindowController?
    private var hotKeyCancellable: AnyCancellable?
    private var updateCheckCancellable: AnyCancellable?

    /// Sparkle updater controller
    private var updaterController: SPUStandardUpdaterController!

    /// ViewModel — created and owned here, shared with Views via .environmentObject()
    private var viewModel: ViewerViewModel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        SentrySDK.start { options in
            options.dsn = "https://c5c66ba71a0ff4f9bb96dffe4a2a3aca@o4510913120174080.ingest.us.sentry.io/4510913122467841"
            options.enableAutoSessionTracking = false
            #if DEBUG
            options.debug = true
            options.environment = "debug"
            #else
            options.environment = "production"
            #endif
        }

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

        // Initialize Sparkle updater (startingUpdater: false so we can configure before starting)
        updaterController = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        updaterController.updater.automaticallyChecksForUpdates = AppSettings.shared.autoCheckForUpdates
        do {
            try updaterController.updater.start()
        } catch {
            print("Failed to start Sparkle updater: \(error)")
        }

        setupMenuBar()
        setupMainMenu()

        setupHotKey()
        registerURLSchemeHandler()

        // Listen for hotkey changes via Combine
        hotKeyCancellable = AppSettings.shared.hotKeyChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setupHotKey()
            }

        // Listen for "Check for Updates" requests from SettingsPopover
        updateCheckCancellable = NotificationCenter.default.publisher(for: .checkForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updaterController.checkForUpdates(nil)
                NSApp.activate()
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
        let checkForUpdatesItem = NSMenuItem(title: String(localized: "menu.check_for_updates"), action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        checkForUpdatesItem.target = updaterController
        appMenu.addItem(checkForUpdatesItem)
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

        let closeTabItem = NSMenuItem(title: String(localized: "menu.close_tab"), action: #selector(closeTab), keyEquivalent: AppShortcut.closeTab.keyEquivalent)
        closeTabItem.keyEquivalentModifierMask = AppShortcut.closeTab.modifiers
        closeTabItem.target = self
        fileMenu.addItem(closeTabItem)

        fileMenu.addItem(NSMenuItem.separator())

        let prevTabItem = NSMenuItem(title: String(localized: "menu.previous_tab"), action: #selector(showPreviousTab), keyEquivalent: AppShortcut.previousTab.keyEquivalent)
        prevTabItem.keyEquivalentModifierMask = AppShortcut.previousTab.modifiers
        prevTabItem.target = self
        fileMenu.addItem(prevTabItem)

        let nextTabItem = NSMenuItem(title: String(localized: "menu.next_tab"), action: #selector(showNextTab), keyEquivalent: AppShortcut.nextTab.keyEquivalent)
        nextTabItem.keyEquivalentModifierMask = AppShortcut.nextTab.modifiers
        nextTabItem.target = self
        fileMenu.addItem(nextTabItem)

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

        let treeItem = NSMenuItem(title: String(localized: "menu.tree_mode"), action: #selector(switchToTree), keyEquivalent: AppShortcut.treeMode.keyEquivalent)
        treeItem.keyEquivalentModifierMask = AppShortcut.treeMode.modifiers
        treeItem.target = self
        viewMenu.addItem(treeItem)

        viewMenu.addItem(NSMenuItem.separator())

        let expandAllItem = NSMenuItem(title: String(localized: "menu.expand_all"), action: #selector(expandAll), keyEquivalent: AppShortcut.expandAll.keyEquivalent)
        expandAllItem.keyEquivalentModifierMask = AppShortcut.expandAll.modifiers
        expandAllItem.target = self
        viewMenu.addItem(expandAllItem)

        let collapseAllItem = NSMenuItem(title: String(localized: "menu.collapse_all"), action: #selector(collapseAll), keyEquivalent: AppShortcut.collapseAll.keyEquivalent)
        collapseAllItem.keyEquivalentModifierMask = AppShortcut.collapseAll.modifiers
        collapseAllItem.target = self
        viewMenu.addItem(collapseAllItem)

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

    @objc private func expandAll(_ sender: Any?) {
        if onboardingController?.isShowing == true { return }
        viewModel.expandAllNodes()
    }

    @objc private func collapseAll(_ sender: Any?) {
        if onboardingController?.isShowing == true { return }
        viewModel.collapseAllNodes()
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

        // Check for Updates
        let checkForUpdatesItem = NSMenuItem(title: String(localized: "menu.check_for_updates"), action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        checkForUpdatesItem.target = updaterController
        menu.addItem(checkForUpdatesItem)

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
            NSApp.activate()
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
        window.delegate = self
        settingsWindow = window

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    // MARK: - NSWindowDelegate (Settings window)

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === settingsWindow else { return }
        settingsWindow?.delegate = nil
        settingsWindow = nil
    }

    @objc private func quitApp(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
    }

    private func setupHotKey() {
        let combo = AppSettings.shared.openHotKeyCombo

        HotKeyManager.shared.start(combo: combo) { [weak self] in
            self?.viewModel.handleHotKey()
        }
    }

    // MARK: - URL Scheme Handling

    private func registerURLSchemeHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else { return }
        guard onboardingController?.isShowing != true else { return }

        let action = URLSchemeHandler.parseAction(from: url)
        switch action {
        case .openFromClipboard:
            viewModel.handleHotKey()
        case .unknown:
            break
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

    // MARK: - SPUStandardUserDriverDelegate (Gentle Reminders)

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false // Always suppress Sparkle's modal UI
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if !handleShowingUpdate {
            viewModel.setUpdateAvailable(version: update.displayVersionString)
        }
    }

    func standardUserDriverWillFinishUpdateSession() {}

    // MARK: - SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        viewModel.setUpdateAvailable(version: item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {}

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.stop()
        hotKeyCancellable = nil
        updateCheckCancellable = nil
        WindowManager.shared.closeViewer()
    }
}
#endif
