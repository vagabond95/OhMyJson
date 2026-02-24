//
//  TabManager.swift
//  OhMyJson
//
//  Manages tab lifecycle, creation, deletion, and LRU tracking.
//  Integrates with TabPersistenceService for session restore and auto-save.
//

import Foundation
import Observation

@Observable
class TabManager: TabManagerProtocol {
    static let shared = TabManager()

    var tabs: [JSONTab] = []
    var activeTabId: UUID?

    var maxTabs = 20
    var warningThreshold = 18

    @ObservationIgnored private var persistence: TabPersistenceServiceProtocol?
    @ObservationIgnored private var saveDebounceTask: DispatchWorkItem?

    private let tabTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd, HH:mm:ss"
        return formatter
    }()

    private init() {
        self.persistence = TabPersistenceService.shared
    }

    /// Designated initializer for testing with injected persistence service.
    init(persistence: TabPersistenceServiceProtocol?) {
        self.persistence = persistence
    }

    deinit {
        saveDebounceTask?.cancel()
    }

    // MARK: - Session Persistence

    /// Restore tabs from persistent storage.
    /// Must be called before ViewerViewModel is created (AppDelegate.applicationDidFinishLaunching).
    func restoreSession() {
        guard let persistence else { return }
        let (restoredTabs, activeId) = persistence.loadTabs()
        guard !restoredTabs.isEmpty else { return }
        self.tabs = restoredTabs
        self.activeTabId = activeId ?? restoredTabs.first?.id
    }

    /// Cancel pending debounce and synchronously persist current state.
    func flush() {
        saveDebounceTask?.cancel()
        saveDebounceTask = nil
        persistence?.saveAll(tabs: tabs, activeTabId: activeTabId)
    }

    // MARK: - Private Save Helpers

    private func saveImmediately() {
        saveDebounceTask?.cancel()
        saveDebounceTask = nil
        persistence?.saveAll(tabs: tabs, activeTabId: activeTabId)
    }

    private func scheduleDebouncedSave() {
        saveDebounceTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.persistence?.saveAll(tabs: self.tabs, activeTabId: self.activeTabId)
        }
        saveDebounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + Persistence.saveDebounceInterval, execute: task)
    }

    // MARK: - Tab Creation

    /// Create a new tab with optional JSON content
    /// - Parameter json: Optional JSON string to initialize the tab with
    /// - Returns: UUID of the created tab
    @discardableResult
    func createTab(with json: String?) -> UUID {
        let now = Date()
        let newTab = JSONTab(
            id: UUID(),
            inputText: json ?? "",
            parseResult: nil,
            createdAt: now,
            lastAccessedAt: now,
            title: tabTitleFormatter.string(from: now),
            viewMode: AppSettings.shared.defaultViewMode
        )

        tabs.append(newTab)
        activeTabId = newTab.id

        saveImmediately()

        return newTab.id
    }

    // MARK: - Tab Close

    /// Close a specific tab
    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        tabs.remove(at: index)

        if activeTabId == id {
            let newIndex = max(0, index - 1)
            if newIndex < tabs.count {
                activeTabId = tabs[newIndex].id
            } else if let first = tabs.first {
                activeTabId = first.id
            } else {
                activeTabId = nil
            }
        }

        saveImmediately()
    }

    // MARK: - Tab Selection

    /// Select a specific tab and mark it as accessed
    func selectTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        activeTabId = id
        tabs[index].markAsAccessed()

        saveImmediately()
    }

    /// Select the previous tab (no-op if already at first tab)
    func selectPreviousTab() {
        guard let activeId = activeTabId,
              let index = tabs.firstIndex(where: { $0.id == activeId }),
              index > 0 else { return }
        selectTab(id: tabs[index - 1].id)
    }

    /// Select the next tab (no-op if already at last tab)
    func selectNextTab() {
        guard let activeId = activeTabId,
              let index = tabs.firstIndex(where: { $0.id == activeId }),
              index < tabs.count - 1 else { return }
        selectTab(id: tabs[index + 1].id)
    }

    // MARK: - LRU

    /// Get the UUID of the oldest (least recently accessed) tab
    func getOldestTab() -> UUID? {
        return tabs.min(by: { $0.lastAccessedAt < $1.lastAccessedAt })?.id
    }

    /// Check if we can create a new tab without auto-closing
    func canCreateTab() -> Bool {
        return tabs.count < maxTabs
    }

    // MARK: - Computed

    /// Get the currently active tab
    var activeTab: JSONTab? {
        guard let activeId = activeTabId else { return nil }
        return tabs.first(where: { $0.id == activeId })
    }

    // MARK: - Update Methods

    /// Update the input text of a specific tab
    func updateTabInput(id: UUID, text: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].inputText = text
    }

    /// Update the full (untruncated) input text of a specific tab.
    func updateTabFullInput(id: UUID, fullText: String?) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].fullInputText = fullText
    }

    /// Update the parse result of a specific tab.
    /// When result is `.success`, marks `isParseSuccess = true` and schedules a debounced DB save.
    func updateTabParseResult(id: UUID, result: JSONParseResult) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].parseResult = result

        if case .success = result {
            tabs[index].isParseSuccess = true
            scheduleDebouncedSave()
        } else {
            tabs[index].isParseSuccess = false
        }
    }

    func updateTabSearchState(id: UUID, searchText: String, beautifySearchIndex: Int, treeSearchIndex: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].searchText = searchText
        tabs[index].beautifySearchIndex = beautifySearchIndex
        tabs[index].treeSearchIndex = treeSearchIndex
    }

    func updateTabViewMode(id: UUID, viewMode: ViewMode) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].viewMode = viewMode
    }

    func updateTabInputScrollPosition(id: UUID, position: CGFloat) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].inputScrollPosition = position
    }

    func updateTabScrollPosition(id: UUID, position: CGFloat) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].beautifyScrollPosition = position
    }

    func updateTabSearchVisibility(id: UUID, isVisible: Bool) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].isSearchVisible = isVisible
    }

    func updateTabTreeSelectedNodeId(id: UUID, nodeId: UUID?) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].treeSelectedNodeId = nodeId
    }

    func updateTabTreeScrollAnchor(id: UUID, nodeId: UUID?) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].treeScrollAnchorId = nodeId
    }

    func updateTabTreeHorizontalScroll(id: UUID, offset: CGFloat) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].treeHorizontalScrollOffset = offset
    }

    func updateTabSearchDismissState(id: UUID, beautifyDismissed: Bool, treeDismissed: Bool) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].beautifySearchDismissed = beautifyDismissed
        tabs[index].treeSearchDismissed = treeDismissed
    }

    func updateTabTitle(id: UUID, customTitle: String?) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].customTitle = customTitle
    }

    // MARK: - Memory Offload (LRU Dehydration)

    /// Flush current state to DB, then dehydrate all tabs outside the LRU `keepCount` window.
    /// Dehydrated tabs release `fullInputText` and `parseResult` from memory (`isHydrated = false`).
    func dehydrateAfterTabSwitch(keepCount: Int = Persistence.hydratedTabCount) {
        saveImmediately()
        let keepSet = Set(
            tabs.sorted { $0.lastAccessedAt > $1.lastAccessedAt }
                .prefix(keepCount)
                .map { $0.id }
        )
        for i in tabs.indices where !keepSet.contains(tabs[i].id) && tabs[i].isHydrated {
            tabs[i].parseResult = nil
            tabs[i].fullInputText = nil
            tabs[i].isHydrated = false
        }
    }

    /// Load `fullInputText` from DB for a dehydrated tab and mark it hydrated in memory.
    func hydrateTabContent(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }),
              !tabs[index].isHydrated,
              let content = persistence?.loadTabContent(id: id) else { return }
        tabs[index].fullInputText = content.fullInputText
        tabs[index].isHydrated = true
    }

    // MARK: - Bulk Operations

    /// Close all tabs and clear persistent storage.
    func closeAllTabs() {
        tabs.removeAll()
        activeTabId = nil
        persistence?.deleteAllTabs()
    }

    // MARK: - Utilities

    /// Get tab index for display purposes (1-based)
    func getTabIndex(id: UUID) -> Int {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return 0 }
        return index + 1
    }

    /// Move a tab from one index to another
    func moveTab(fromIndex: Int, toIndex: Int) {
        guard fromIndex != toIndex,
              fromIndex >= 0, fromIndex < tabs.count,
              toIndex >= 0, toIndex < tabs.count else { return }
        let tab = tabs.remove(at: fromIndex)
        tabs.insert(tab, at: toIndex)

        saveImmediately()
    }
}
