//
//  TabManagerProtocol.swift
//  OhMyJson
//

import Foundation
import CoreGraphics

protocol TabManagerProtocol: AnyObject {
    var tabs: [JSONTab] { get }
    var activeTabId: UUID? { get set }
    var activeTab: JSONTab? { get }
    var maxTabs: Int { get set }
    var warningThreshold: Int { get set }

    @discardableResult
    func createTab(with json: String?) -> UUID
    func closeTab(id: UUID)
    func selectTab(id: UUID)
    func selectPreviousTab()
    func selectNextTab()
    func closeAllTabs()
    func getOldestTab() -> UUID?
    func canCreateTab() -> Bool
    func getTabIndex(id: UUID) -> Int

    /// Restore tabs from persistent storage. Call once at startup before ViewModel creation.
    func restoreSession()

    /// Cancel pending debounce and synchronously persist the current tab state.
    func flush()

    func updateTabInput(id: UUID, text: String)
    func updateTabFullInput(id: UUID, fullText: String?)
    func updateTabParseResult(id: UUID, result: JSONParseResult)
    func updateTabSearchState(id: UUID, searchText: String, beautifySearchIndex: Int, treeSearchIndex: Int)
    func updateTabViewMode(id: UUID, viewMode: ViewMode)
    func updateTabSearchVisibility(id: UUID, isVisible: Bool)
    func updateTabInputScrollPosition(id: UUID, position: CGFloat)
    func updateTabScrollPosition(id: UUID, position: CGFloat)
    func updateTabTreeSelectedNodeId(id: UUID, nodeId: UUID?)
    func updateTabTreeScrollAnchor(id: UUID, nodeId: UUID?)
    func updateTabTreeHorizontalScroll(id: UUID, offset: CGFloat)
    func updateTabSearchDismissState(id: UUID, beautifyDismissed: Bool, treeDismissed: Bool)
    func updateTabTitle(id: UUID, customTitle: String?)
    func updateTabCompareState(id: UUID, leftText: String?, rightText: String?)
    func moveTab(fromIndex: Int, toIndex: Int)

    /// Persist current state to DB, then dehydrate tabs outside the LRU keep window.
    /// Call after `saveTabState` so the outgoing tab's latest content is preserved in DB.
    func dehydrateAfterTabSwitch(keepCount: Int)

    /// Load `fullInputText` from DB for a dehydrated tab and mark it hydrated.
    func hydrateTabContent(id: UUID)

    /// Async version: offloads SQLite I/O to a background thread, applies mutation on caller.
    func hydrateTabContentAsync(id: UUID) async
}
