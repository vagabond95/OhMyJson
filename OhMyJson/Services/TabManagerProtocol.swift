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
    var maxTabs: Int { get }
    var warningThreshold: Int { get }

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

    func updateTabInput(id: UUID, text: String)
    func updateTabParseResult(id: UUID, result: JSONParseResult)
    func updateTabSearchState(id: UUID, searchText: String, beautifySearchIndex: Int, treeSearchIndex: Int)
    func updateTabViewMode(id: UUID, viewMode: ViewMode)
    func updateTabSearchVisibility(id: UUID, isVisible: Bool)
    func updateTabInputScrollPosition(id: UUID, position: CGFloat)
    func updateTabScrollPosition(id: UUID, position: CGFloat)
    func updateTabTreeSelectedNodeId(id: UUID, nodeId: UUID?)
    func updateTabTreeScrollAnchor(id: UUID, nodeId: UUID?)
    func updateTabTreeHorizontalScroll(id: UUID, offset: CGFloat)
}
