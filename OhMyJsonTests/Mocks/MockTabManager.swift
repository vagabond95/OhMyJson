//
//  MockTabManager.swift
//  OhMyJsonTests
//

import Foundation
import CoreGraphics
@testable import OhMyJson

final class MockTabManager: TabManagerProtocol {
    var tabs: [JSONTab] = []
    var activeTabId: UUID?
    var maxTabs: Int = 10
    var warningThreshold: Int = 8

    var activeTab: JSONTab? {
        guard let id = activeTabId else { return nil }
        return tabs.first(where: { $0.id == id })
    }

    var createTabCallCount = 0
    var closeTabCallCount = 0
    var lastClosedTabId: UUID?

    @discardableResult
    func createTab(with json: String?) -> UUID {
        createTabCallCount += 1
        let tab = JSONTab(id: UUID(), inputText: json ?? "", createdAt: Date(), lastAccessedAt: Date(), title: "Tab \(tabs.count + 1)")
        tabs.append(tab)
        activeTabId = tab.id
        return tab.id
    }

    func closeTab(id: UUID) {
        closeTabCallCount += 1
        lastClosedTabId = id
        tabs.removeAll(where: { $0.id == id })
        if activeTabId == id {
            activeTabId = tabs.first?.id
        }
    }

    func selectTab(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabId = id
    }

    func selectPreviousTab() {
        guard let id = activeTabId,
              let index = tabs.firstIndex(where: { $0.id == id }),
              index > 0 else { return }
        activeTabId = tabs[index - 1].id
    }

    func selectNextTab() {
        guard let id = activeTabId,
              let index = tabs.firstIndex(where: { $0.id == id }),
              index < tabs.count - 1 else { return }
        activeTabId = tabs[index + 1].id
    }

    func closeAllTabs() {
        tabs.removeAll()
        activeTabId = nil
    }

    func getOldestTab() -> UUID? {
        tabs.min(by: { $0.lastAccessedAt < $1.lastAccessedAt })?.id
    }

    func canCreateTab() -> Bool {
        tabs.count < maxTabs
    }

    func getTabIndex(id: UUID) -> Int {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return 0 }
        return index + 1
    }

    func updateTabInput(id: UUID, text: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].inputText = text
    }

    func updateTabFullInput(id: UUID, fullText: String?) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].fullInputText = fullText
    }

    func updateTabParseResult(id: UUID, result: JSONParseResult) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].parseResult = result
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

    func updateTabSearchVisibility(id: UUID, isVisible: Bool) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].isSearchVisible = isVisible
    }

    func updateTabInputScrollPosition(id: UUID, position: CGFloat) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].inputScrollPosition = position
    }

    func updateTabScrollPosition(id: UUID, position: CGFloat) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].beautifyScrollPosition = position
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
}
