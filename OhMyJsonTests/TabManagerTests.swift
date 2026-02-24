//
//  TabManagerTests.swift
//  OhMyJsonTests
//

import Testing
import Foundation
import CoreGraphics
@testable import OhMyJson

// TabManager uses singleton with private init + references WindowManager.shared and ToastManager.shared
// So we test the protocol contract using MockTabManager which mirrors real behavior
@Suite("TabManager Protocol Tests")
struct TabManagerTests {

    private func makeSUT() -> MockTabManager {
        MockTabManager()
    }

    // MARK: - createTab

    @Test("createTab adds a tab and sets it active")
    func createTab() {
        let sut = makeSUT()
        let id = sut.createTab(with: nil)

        #expect(sut.tabs.count == 1)
        #expect(sut.activeTabId == id)
        #expect(sut.createTabCallCount == 1)
    }

    @Test("createTab with JSON content sets inputText")
    func createTabWithJSON() {
        let sut = makeSUT()
        let json = "{\"key\": \"value\"}"
        let id = sut.createTab(with: json)

        let tab = sut.tabs.first(where: { $0.id == id })
        #expect(tab?.inputText == json)
    }

    @Test("createTab with nil sets empty input")
    func createTabWithNil() {
        let sut = makeSUT()
        let id = sut.createTab(with: nil)

        let tab = sut.tabs.first(where: { $0.id == id })
        #expect(tab?.inputText == "")
    }

    @Test("Multiple tabs created sequentially")
    func multipleTabsCreated() {
        let sut = makeSUT()
        let id1 = sut.createTab(with: "1")
        let _ = sut.createTab(with: "2")
        let id3 = sut.createTab(with: "3")

        #expect(sut.tabs.count == 3)
        // Last created tab should be active
        #expect(sut.activeTabId == id3)
        // First tab should still exist
        #expect(sut.tabs.contains(where: { $0.id == id1 }))
    }

    // MARK: - closeTab

    @Test("closeTab removes the tab")
    func closeTab() {
        let sut = makeSUT()
        let id = sut.createTab(with: nil)
        sut.closeTab(id: id)

        #expect(sut.tabs.isEmpty)
        #expect(sut.closeTabCallCount == 1)
        #expect(sut.lastClosedTabId == id)
    }

    @Test("closeTab selects another tab when active is closed")
    func closeActiveTab() {
        let sut = makeSUT()
        let id1 = sut.createTab(with: "1")
        let id2 = sut.createTab(with: "2")
        // id2 is active
        #expect(sut.activeTabId == id2)

        sut.closeTab(id: id2)

        #expect(sut.tabs.count == 1)
        #expect(sut.activeTabId == id1)
    }

    @Test("closeTab on non-active tab keeps active unchanged")
    func closeNonActiveTab() {
        let sut = makeSUT()
        let id1 = sut.createTab(with: "1")
        let id2 = sut.createTab(with: "2")
        // id2 is active

        sut.closeTab(id: id1)

        #expect(sut.tabs.count == 1)
        #expect(sut.activeTabId == id2)
    }

    // MARK: - selectTab

    @Test("selectTab changes active tab")
    func selectTab() {
        let sut = makeSUT()
        let id1 = sut.createTab(with: "1")
        let _ = sut.createTab(with: "2")

        sut.selectTab(id: id1)
        #expect(sut.activeTabId == id1)
    }

    @Test("selectTab with invalid id is no-op")
    func selectInvalidTab() {
        let sut = makeSUT()
        let id = sut.createTab(with: "1")
        sut.selectTab(id: UUID()) // invalid

        #expect(sut.activeTabId == id) // unchanged
    }

    // MARK: - Navigation

    @Test("selectPreviousTab moves to previous")
    func selectPreviousTab() {
        let sut = makeSUT()
        let id1 = sut.createTab(with: "1")
        let _ = sut.createTab(with: "2")
        let id3 = sut.createTab(with: "3")
        sut.selectTab(id: id3)

        sut.selectPreviousTab()
        // Should move to the tab before id3
        #expect(sut.activeTabId != id3)

        // Move all the way to first
        sut.selectPreviousTab()
        sut.selectPreviousTab() // should be no-op at first
        #expect(sut.activeTabId == id1)
    }

    @Test("selectPreviousTab at first tab is no-op")
    func selectPreviousTabAtFirst() {
        let sut = makeSUT()
        let id1 = sut.createTab(with: "1")
        let _ = sut.createTab(with: "2")
        sut.selectTab(id: id1)

        sut.selectPreviousTab()
        #expect(sut.activeTabId == id1) // no change
    }

    @Test("selectNextTab moves to next")
    func selectNextTab() {
        let sut = makeSUT()
        let id1 = sut.createTab(with: "1")
        let _ = sut.createTab(with: "2")
        let id3 = sut.createTab(with: "3")
        sut.selectTab(id: id1)

        sut.selectNextTab()
        #expect(sut.activeTabId != id1)

        sut.selectNextTab()
        #expect(sut.activeTabId == id3)
    }

    @Test("selectNextTab at last tab is no-op")
    func selectNextTabAtLast() {
        let sut = makeSUT()
        let _ = sut.createTab(with: "1")
        let id2 = sut.createTab(with: "2")
        sut.selectTab(id: id2)

        sut.selectNextTab()
        #expect(sut.activeTabId == id2) // no change
    }

    // MARK: - closeAllTabs

    @Test("closeAllTabs removes everything")
    func closeAllTabs() {
        let sut = makeSUT()
        let _ = sut.createTab(with: "1")
        let _ = sut.createTab(with: "2")
        let _ = sut.createTab(with: "3")

        sut.closeAllTabs()

        #expect(sut.tabs.isEmpty)
        #expect(sut.activeTabId == nil)
    }

    // MARK: - getOldestTab (LRU)

    @Test("getOldestTab returns least recently accessed")
    func getOldestTab() {
        let sut = makeSUT()

        // Manually create tabs with controlled lastAccessedAt
        let old = JSONTab(id: UUID(), inputText: "", createdAt: Date(), lastAccessedAt: Date(timeIntervalSince1970: 100), title: "Old")
        let recent = JSONTab(id: UUID(), inputText: "", createdAt: Date(), lastAccessedAt: Date(timeIntervalSince1970: 999), title: "Recent")
        sut.tabs = [recent, old]

        #expect(sut.getOldestTab() == old.id)
    }

    @Test("getOldestTab returns nil for empty tabs")
    func getOldestTabEmpty() {
        let sut = makeSUT()
        #expect(sut.getOldestTab() == nil)
    }

    // MARK: - canCreateTab

    @Test("canCreateTab true when under limit")
    func canCreateTabTrue() {
        let sut = makeSUT()
        sut.maxTabs = 10
        let _ = sut.createTab(with: nil)
        #expect(sut.canCreateTab() == true)
    }

    @Test("canCreateTab false when at limit")
    func canCreateTabFalse() {
        let sut = makeSUT()
        sut.maxTabs = 2
        let _ = sut.createTab(with: nil)
        let _ = sut.createTab(with: nil)
        #expect(sut.canCreateTab() == false)
    }

    // MARK: - activeTab

    @Test("activeTab returns correct tab")
    func activeTab() {
        let sut = makeSUT()
        let id = sut.createTab(with: "test")
        #expect(sut.activeTab?.id == id)
        #expect(sut.activeTab?.inputText == "test")
    }

    @Test("activeTab returns nil when no active tab")
    func activeTabNil() {
        let sut = makeSUT()
        #expect(sut.activeTab == nil)
    }

    // MARK: - getTabIndex

    @Test("getTabIndex returns 1-based index")
    func getTabIndex() {
        let sut = makeSUT()
        let id1 = sut.createTab(with: "1")
        let id2 = sut.createTab(with: "2")
        let id3 = sut.createTab(with: "3")

        #expect(sut.getTabIndex(id: id1) == 1)
        #expect(sut.getTabIndex(id: id2) == 2)
        #expect(sut.getTabIndex(id: id3) == 3)
    }

    @Test("getTabIndex returns 0 for unknown id")
    func getTabIndexUnknown() {
        let sut = makeSUT()
        #expect(sut.getTabIndex(id: UUID()) == 0)
    }

    // MARK: - Update Methods

    @Test("updateTabInput changes input text")
    func updateTabInput() {
        let sut = makeSUT()
        let id = sut.createTab(with: "old")
        sut.updateTabInput(id: id, text: "new")
        #expect(sut.tabs.first(where: { $0.id == id })?.inputText == "new")
    }

    @Test("updateTabParseResult sets result")
    func updateTabParseResult() {
        let sut = makeSUT()
        let id = sut.createTab(with: nil)
        let node = JSONNode(value: .null)
        sut.updateTabParseResult(id: id, result: .success(node))

        let tab = sut.tabs.first(where: { $0.id == id })
        #expect(tab?.hasValidJSON == true)
    }

    @Test("updateTabSearchState sets search fields")
    func updateTabSearchState() {
        let sut = makeSUT()
        let id = sut.createTab(with: nil)
        sut.updateTabSearchState(id: id, searchText: "query", beautifySearchIndex: 2, treeSearchIndex: 3)

        let tab = sut.tabs.first(where: { $0.id == id })
        #expect(tab?.searchText == "query")
        #expect(tab?.beautifySearchIndex == 2)
        #expect(tab?.treeSearchIndex == 3)
    }

    @Test("updateTabViewMode changes view mode")
    func updateTabViewMode() {
        let sut = makeSUT()
        let id = sut.createTab(with: nil)
        sut.updateTabViewMode(id: id, viewMode: .tree)

        let tab = sut.tabs.first(where: { $0.id == id })
        #expect(tab?.viewMode == .tree)
    }

    @Test("updateTabSearchVisibility toggles search bar")
    func updateTabSearchVisibility() {
        let sut = makeSUT()
        let id = sut.createTab(with: nil)
        sut.updateTabSearchVisibility(id: id, isVisible: true)

        let tab = sut.tabs.first(where: { $0.id == id })
        #expect(tab?.isSearchVisible == true)
    }

    @Test("updateTabInputScrollPosition sets position")
    func updateTabInputScrollPosition() {
        let sut = makeSUT()
        let id = sut.createTab(with: nil)
        sut.updateTabInputScrollPosition(id: id, position: 123.5)

        let tab = sut.tabs.first(where: { $0.id == id })
        #expect(tab?.inputScrollPosition == 123.5)
    }

    @Test("updateTabScrollPosition sets beautify scroll")
    func updateTabScrollPosition() {
        let sut = makeSUT()
        let id = sut.createTab(with: nil)
        sut.updateTabScrollPosition(id: id, position: 456.7)

        let tab = sut.tabs.first(where: { $0.id == id })
        #expect(tab?.beautifyScrollPosition == 456.7)
    }

    @Test("updateTabTreeSelectedNodeId sets node id")
    func updateTabTreeSelectedNodeId() {
        let sut = makeSUT()
        let id = sut.createTab(with: nil)
        let nodeId = UUID()
        sut.updateTabTreeSelectedNodeId(id: id, nodeId: nodeId)

        let tab = sut.tabs.first(where: { $0.id == id })
        #expect(tab?.treeSelectedNodeId == nodeId)
    }

    @Test("Update methods are no-op for unknown tab id")
    func updateUnknownTabNoOp() {
        let sut = makeSUT()
        let unknownId = UUID()

        // These should not crash or have any effect
        sut.updateTabInput(id: unknownId, text: "test")
        sut.updateTabViewMode(id: unknownId, viewMode: .tree)
        sut.updateTabSearchVisibility(id: unknownId, isVisible: true)
        sut.updateTabScrollPosition(id: unknownId, position: 100)

        #expect(sut.tabs.isEmpty)
    }

    // MARK: - Horizontal Scroll

    @Test("updateTabTreeHorizontalScroll sets offset")
    func updateTabTreeHorizontalScroll() {
        let sut = makeSUT()
        let id = sut.createTab(with: nil)
        sut.updateTabTreeHorizontalScroll(id: id, offset: 150.5)

        let tab = sut.tabs.first(where: { $0.id == id })
        #expect(tab?.treeHorizontalScrollOffset == 150.5)
    }

    @Test("updateTabTreeHorizontalScroll is no-op for unknown tab id")
    func updateTreeHorizontalScrollUnknownTab() {
        let sut = makeSUT()
        sut.updateTabTreeHorizontalScroll(id: UUID(), offset: 100)
        #expect(sut.tabs.isEmpty)
    }

    // MARK: - updateTabTitle

    @Test("updateTabTitle sets customTitle")
    func updateTabTitleSets() {
        let sut = makeSUT()
        let id = sut.createTab(with: nil)
        sut.updateTabTitle(id: id, customTitle: "My Tab")

        let tab = sut.tabs.first(where: { $0.id == id })
        #expect(tab?.customTitle == "My Tab")
    }

    @Test("updateTabTitle with nil clears customTitle")
    func updateTabTitleClear() {
        let sut = makeSUT()
        let id = sut.createTab(with: nil)
        sut.updateTabTitle(id: id, customTitle: "My Tab")
        sut.updateTabTitle(id: id, customTitle: nil)

        let tab = sut.tabs.first(where: { $0.id == id })
        #expect(tab?.customTitle == nil)
    }

    @Test("updateTabTitle is no-op for unknown tab id")
    func updateTabTitleUnknown() {
        let sut = makeSUT()
        sut.updateTabTitle(id: UUID(), customTitle: "X")
        #expect(sut.tabs.isEmpty)
    }

    @Test("displayTitle reflects customTitle after updateTabTitle")
    func displayTitleAfterUpdate() {
        let sut = makeSUT()
        let id = sut.createTab(with: nil)
        sut.updateTabTitle(id: id, customTitle: "Custom")

        let tab = sut.tabs.first(where: { $0.id == id })
        #expect(tab?.displayTitle == "Custom")
    }

    // MARK: - moveTab

    @Test("moveTab swaps adjacent tabs forward")
    func moveTabSwapsAdjacentForward() {
        let sut = makeSUT()
        let idA = sut.createTab(with: "A")
        let idB = sut.createTab(with: "B")
        let idC = sut.createTab(with: "C")

        sut.moveTab(fromIndex: 0, toIndex: 1)

        #expect(sut.tabs[0].id == idB)
        #expect(sut.tabs[1].id == idA)
        #expect(sut.tabs[2].id == idC)
    }

    @Test("moveTab swaps adjacent tabs backward")
    func moveTabSwapsAdjacentBackward() {
        let sut = makeSUT()
        let idA = sut.createTab(with: "A")
        let idB = sut.createTab(with: "B")
        let idC = sut.createTab(with: "C")

        sut.moveTab(fromIndex: 2, toIndex: 1)

        #expect(sut.tabs[0].id == idA)
        #expect(sut.tabs[1].id == idC)
        #expect(sut.tabs[2].id == idB)
    }

    @Test("moveTab from first to last")
    func moveTabFromFirstToLast() {
        let sut = makeSUT()
        let idA = sut.createTab(with: "A")
        let idB = sut.createTab(with: "B")
        let idC = sut.createTab(with: "C")

        sut.moveTab(fromIndex: 0, toIndex: 2)

        #expect(sut.tabs[0].id == idB)
        #expect(sut.tabs[1].id == idC)
        #expect(sut.tabs[2].id == idA)
    }

    @Test("moveTab from last to first")
    func moveTabFromLastToFirst() {
        let sut = makeSUT()
        let idA = sut.createTab(with: "A")
        let idB = sut.createTab(with: "B")
        let idC = sut.createTab(with: "C")

        sut.moveTab(fromIndex: 2, toIndex: 0)

        #expect(sut.tabs[0].id == idC)
        #expect(sut.tabs[1].id == idA)
        #expect(sut.tabs[2].id == idB)
    }

    @Test("moveTab same index is no-op")
    func moveTabSameIndexIsNoOp() {
        let sut = makeSUT()
        let idA = sut.createTab(with: "A")
        let idB = sut.createTab(with: "B")
        let idC = sut.createTab(with: "C")

        sut.moveTab(fromIndex: 1, toIndex: 1)

        #expect(sut.tabs[0].id == idA)
        #expect(sut.tabs[1].id == idB)
        #expect(sut.tabs[2].id == idC)
    }

    @Test("moveTab out of bounds is no-op")
    func moveTabOutOfBoundsIsNoOp() {
        let sut = makeSUT()
        let idA = sut.createTab(with: "A")
        let idB = sut.createTab(with: "B")

        sut.moveTab(fromIndex: -1, toIndex: 0)
        sut.moveTab(fromIndex: 0, toIndex: 5)

        #expect(sut.tabs[0].id == idA)
        #expect(sut.tabs[1].id == idB)
        #expect(sut.tabs.count == 2)
    }

    @Test("moveTab preserves activeTabId")
    func moveTabPreservesActiveTabId() {
        let sut = makeSUT()
        let idA = sut.createTab(with: "A")
        let _ = sut.createTab(with: "B")
        let _ = sut.createTab(with: "C")
        sut.selectTab(id: idA)

        sut.moveTab(fromIndex: 0, toIndex: 2)

        // activeTabId should still point to idA even after reorder
        #expect(sut.activeTabId == idA)
        #expect(sut.tabs[2].id == idA)
    }

    @Test("selectNextTab respects reordered tabs")
    func selectNextTabRespectsReorderedTabs() {
        let sut = makeSUT()
        let idA = sut.createTab(with: "A")
        let idB = sut.createTab(with: "B")
        let idC = sut.createTab(with: "C")
        // Order: [A, B, C], move C to index 0 → [C, A, B]
        sut.moveTab(fromIndex: 2, toIndex: 0)
        sut.selectTab(id: idC)

        sut.selectNextTab()
        #expect(sut.activeTabId == idA)

        sut.selectNextTab()
        #expect(sut.activeTabId == idB)
    }
}
