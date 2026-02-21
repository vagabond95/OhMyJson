//
//  TabManager.swift
//  OhMyJson
//
//  Manages tab lifecycle, creation, deletion, and LRU tracking
//

import Foundation
import Observation

@Observable
class TabManager: TabManagerProtocol {
    static let shared = TabManager()

    var tabs: [JSONTab] = []
    var activeTabId: UUID?

    let maxTabs = 10
    let warningThreshold = 8

    private let tabTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd, HH:mm:ss"
        return formatter
    }()

    private init() {
        // Initialize with no tabs - tabs are created on demand
    }

    /// Create a new tab with optional JSON content
    /// - Parameter json: Optional JSON string to initialize the tab with
    /// - Returns: UUID of the created tab
    @discardableResult
    func createTab(with json: String?) -> UUID {
        // Note: LRU eviction and toast warnings are now handled by ViewerViewModel (mediator).
        // TabManager only manages tab data.

        // Create new tab with timestamp-based title and default view mode
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

        return newTab.id
    }

    /// Close a specific tab
    /// - Parameter id: UUID of the tab to close
    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        // Note: "last tab → close window" logic is now handled by ViewerViewModel (mediator).
        // TabManager only removes from the tab array.

        tabs.remove(at: index)

        // If we closed the active tab, select another
        if activeTabId == id {
            // Select the previous tab if available, otherwise the first
            let newIndex = max(0, index - 1)
            if newIndex < tabs.count {
                activeTabId = tabs[newIndex].id
            } else if let first = tabs.first {
                activeTabId = first.id
            }
        }
    }

    /// Select a specific tab and mark it as accessed
    /// - Parameter id: UUID of the tab to select
    func selectTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        activeTabId = id
        tabs[index].markAsAccessed()
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

    /// Get the UUID of the oldest (least recently accessed) tab
    /// - Returns: UUID of the oldest tab, or nil if no tabs exist
    func getOldestTab() -> UUID? {
        return tabs.min(by: { $0.lastAccessedAt < $1.lastAccessedAt })?.id
    }

    /// Check if we can create a new tab without auto-closing
    /// - Returns: true if under max limit
    func canCreateTab() -> Bool {
        return tabs.count < maxTabs
    }

    /// Get the currently active tab
    var activeTab: JSONTab? {
        guard let activeId = activeTabId else { return nil }
        return tabs.first(where: { $0.id == activeId })
    }

    /// Update the input text of a specific tab
    /// - Parameters:
    ///   - id: UUID of the tab
    ///   - text: New input text
    func updateTabInput(id: UUID, text: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].inputText = text
    }

    /// Update the parse result of a specific tab
    /// - Parameters:
    ///   - id: UUID of the tab
    ///   - result: New parse result
    func updateTabParseResult(id: UUID, result: JSONParseResult) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].parseResult = result
    }

    /// Update the search state of a specific tab
    /// - Parameters:
    ///   - id: UUID of the tab
    ///   - searchText: Current search text
    ///   - beautifySearchIndex: Current search result index for beautify view
    ///   - treeSearchIndex: Current search result index for tree view
    func updateTabSearchState(id: UUID, searchText: String, beautifySearchIndex: Int, treeSearchIndex: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].searchText = searchText
        tabs[index].beautifySearchIndex = beautifySearchIndex
        tabs[index].treeSearchIndex = treeSearchIndex
    }

    /// Update the view mode of a specific tab
    /// - Parameters:
    ///   - id: UUID of the tab
    ///   - viewMode: New view mode (beautify or tree)
    func updateTabViewMode(id: UUID, viewMode: ViewMode) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].viewMode = viewMode
    }

    /// Update the input view scroll position
    func updateTabInputScrollPosition(id: UUID, position: CGFloat) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].inputScrollPosition = position
    }

    /// Update the beautify view scroll position
    func updateTabScrollPosition(id: UUID, position: CGFloat) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].beautifyScrollPosition = position
    }

    /// Update the search bar visibility of a specific tab
    /// - Parameters:
    ///   - id: UUID of the tab
    ///   - isVisible: Whether the search bar is visible
    func updateTabSearchVisibility(id: UUID, isVisible: Bool) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].isSearchVisible = isVisible
    }

    /// Update the selected node ID for tree view
    /// - Parameters:
    ///   - id: UUID of the tab
    ///   - nodeId: UUID of the selected node in tree view
    func updateTabTreeSelectedNodeId(id: UUID, nodeId: UUID?) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].treeSelectedNodeId = nodeId
    }

    /// Update the scroll anchor node ID for tree view
    /// - Parameters:
    ///   - id: UUID of the tab
    ///   - nodeId: UUID of the scroll anchor node in tree view
    func updateTabTreeScrollAnchor(id: UUID, nodeId: UUID?) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].treeScrollAnchorId = nodeId
    }

    /// Update the horizontal scroll offset for tree view
    func updateTabTreeHorizontalScroll(id: UUID, offset: CGFloat) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].treeHorizontalScrollOffset = offset
    }

    /// Update the search dismiss state of a specific tab
    func updateTabSearchDismissState(id: UUID, beautifyDismissed: Bool, treeDismissed: Bool) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].beautifySearchDismissed = beautifyDismissed
        tabs[index].treeSearchDismissed = treeDismissed
    }

    /// Close all tabs
    func closeAllTabs() {
        tabs.removeAll()
        activeTabId = nil
    }

    /// Get tab index for display purposes
    /// - Parameter id: UUID of the tab
    /// - Returns: 1-based index, or 0 if not found
    func getTabIndex(id: UUID) -> Int {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return 0 }
        return index + 1
    }
}
