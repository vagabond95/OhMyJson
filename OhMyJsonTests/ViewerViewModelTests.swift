//
//  ViewerViewModelTests.swift
//  OhMyJsonTests
//

import Testing
import Foundation
@testable import OhMyJson

#if os(macOS)
@Suite("ViewerViewModel Tests")
struct ViewerViewModelTests {

    private func makeSUT(
        clipboardText: String? = nil,
        hasText: Bool = false
    ) -> (vm: ViewerViewModel, tabManager: MockTabManager, clipboard: MockClipboardService, parser: MockJSONParser, windowManager: MockWindowManager) {
        let tabManager = MockTabManager()
        let clipboard = MockClipboardService()
        clipboard.storedText = clipboardText
        let parser = MockJSONParser()
        let windowManager = MockWindowManager()

        let vm = ViewerViewModel(
            tabManager: tabManager,
            clipboardService: clipboard,
            jsonParser: parser,
            windowManager: windowManager
        )

        return (vm, tabManager, clipboard, parser, windowManager)
    }

    // MARK: - handleHotKey

    @Test("handleHotKey with empty clipboard creates empty tab")
    func handleHotKeyEmptyClipboard() {
        let (vm, tabManager, _, _, _) = makeSUT(clipboardText: nil)
        var windowShowCalled = false
        vm.onNeedShowWindow = { windowShowCalled = true }

        vm.handleHotKey()

        #expect(tabManager.createTabCallCount == 1)
        #expect(windowShowCalled == true)
    }

    @Test("handleHotKey with whitespace-only clipboard creates empty tab")
    func handleHotKeyWhitespaceClipboard() {
        let (vm, tabManager, _, _, _) = makeSUT(clipboardText: "   \n  ")
        var windowShowCalled = false
        vm.onNeedShowWindow = { windowShowCalled = true }

        vm.handleHotKey()

        #expect(tabManager.createTabCallCount == 1)
    }

    @Test("handleHotKey with valid JSON creates tab with content")
    func handleHotKeyValidJSON() {
        let json = #"{"key": "value"}"#
        let (vm, tabManager, _, parser, _) = makeSUT(clipboardText: json)

        // Configure parser to return success
        let node = JSONNode(value: .object(["key": .string("value")]))
        parser.parseResult = .success(node)

        var windowShowCalled = false
        vm.onNeedShowWindow = { windowShowCalled = true }

        vm.handleHotKey()

        #expect(tabManager.createTabCallCount == 1)
        #expect(windowShowCalled == true)
        #expect(vm.currentJSON == json)
    }

    @Test("handleHotKey with invalid JSON shows toast, no new tab")
    func handleHotKeyInvalidJSON() {
        let (vm, tabManager, _, parser, windowManager) = makeSUT(clipboardText: "not json")

        parser.parseResult = .failure(JSONParseError(message: "Invalid"))

        vm.handleHotKey()

        // Invalid JSON should NOT create a tab
        #expect(tabManager.createTabCallCount == 0)
        // Should bring existing window to front if open
        #expect(vm.currentJSON == nil)
    }

    @Test("handleHotKey with invalid JSON brings window to front if open")
    func handleHotKeyInvalidJSONBringToFront() {
        let (vm, _, _, parser, windowManager) = makeSUT(clipboardText: "not json")
        windowManager.isViewerOpen = true
        parser.parseResult = .failure(JSONParseError(message: "Invalid"))

        vm.handleHotKey()

        #expect(windowManager.bringToFrontCallCount == 1)
    }

    // MARK: - createNewTab

    @Test("createNewTab with JSON parses and sets state")
    func createNewTabWithJSON() {
        let json = #"{"a": 1}"#
        let (vm, tabManager, _, parser, _) = makeSUT()

        let node = JSONNode(value: .object(["a": .number(1)]))
        parser.parseResult = .success(node)
        vm.onNeedShowWindow = {}

        vm.createNewTab(with: json)

        #expect(tabManager.createTabCallCount == 1)
        #expect(vm.currentJSON == json)
        if case .success = vm.parseResult {
            // OK
        } else {
            Issue.record("Expected success parse result")
        }
    }

    @Test("createNewTab with nil creates empty tab")
    func createNewTabWithNil() {
        let (vm, tabManager, _, _, _) = makeSUT()
        vm.onNeedShowWindow = {}

        vm.createNewTab(with: nil)

        #expect(tabManager.createTabCallCount == 1)
        #expect(vm.currentJSON == nil)
        #expect(vm.parseResult == nil)
    }

    @Test("createNewTab LRU eviction when at max")
    func createNewTabLRU() {
        let (vm, tabManager, _, _, _) = makeSUT()
        tabManager.maxTabs = 2
        vm.onNeedShowWindow = {}

        // Fill to max
        let _ = tabManager.createTab(with: "1")
        let _ = tabManager.createTab(with: "2")

        // Now createNewTab should trigger LRU eviction
        vm.createNewTab(with: "3")

        #expect(tabManager.closeTabCallCount >= 1) // oldest should be closed
    }

    @Test("createNewTab brings to front when window already open")
    func createNewTabBringsToFront() {
        let (vm, _, _, _, windowManager) = makeSUT()
        windowManager.isViewerOpen = true

        vm.createNewTab(with: nil)

        #expect(windowManager.bringToFrontCallCount == 1)
    }

    // MARK: - createNewTab (reuse empty last tab)

    @Test("createNewTab reuses last tab when its input is empty")
    func createNewTabReusesEmptyLastTab() {
        let json = #"{"a": 1}"#
        let (vm, tabManager, _, parser, _) = makeSUT()
        vm.onNeedShowWindow = {}

        // Create an empty tab first
        let emptyTabId = tabManager.createTab(with: nil)
        let initialCreateCount = tabManager.createTabCallCount

        // Configure parser for the new JSON
        let node = JSONNode(value: .object(["a": .number(1)]))
        parser.parseResult = .success(node)

        // createNewTab should reuse the empty tab, not create a new one
        vm.createNewTab(with: json)

        #expect(tabManager.createTabCallCount == initialCreateCount) // no new tab created
        #expect(tabManager.tabs.count == 1) // still just one tab

        // The existing tab should now have the JSON content
        let tab = tabManager.tabs.first(where: { $0.id == emptyTabId })
        #expect(tab?.inputText == json)
        #expect(vm.currentJSON == json)
    }

    @Test("createNewTab reuses last tab with whitespace-only input")
    func createNewTabReusesWhitespaceLastTab() {
        let json = #"{"b": 2}"#
        let (vm, tabManager, _, parser, _) = makeSUT()
        vm.onNeedShowWindow = {}

        // Create a tab with whitespace-only input
        let tabId = tabManager.createTab(with: "   \n  ")
        let initialCreateCount = tabManager.createTabCallCount

        let node = JSONNode(value: .object(["b": .number(2)]))
        parser.parseResult = .success(node)

        vm.createNewTab(with: json)

        #expect(tabManager.createTabCallCount == initialCreateCount)
        #expect(tabManager.tabs.count == 1)

        let tab = tabManager.tabs.first(where: { $0.id == tabId })
        #expect(tab?.inputText == json)
    }

    @Test("createNewTab does not reuse last tab when it has content")
    func createNewTabDoesNotReuseNonEmptyTab() {
        let (vm, tabManager, _, parser, _) = makeSUT()
        vm.onNeedShowWindow = {}

        // Create a tab with content
        let _ = tabManager.createTab(with: #"{"existing": true}"#)
        let initialCreateCount = tabManager.createTabCallCount

        let node = JSONNode(value: .null)
        parser.parseResult = .success(node)

        vm.createNewTab(with: #"{"new": true}"#)

        // Should create a new tab since last tab has content
        #expect(tabManager.createTabCallCount == initialCreateCount + 1)
        #expect(tabManager.tabs.count == 2)
    }

    @Test("createNewTab with nil reuses empty last tab without changing content")
    func createNewTabNilReusesEmptyTab() {
        let (vm, tabManager, _, _, _) = makeSUT()
        vm.onNeedShowWindow = {}

        // Create an empty tab
        let emptyTabId = tabManager.createTab(with: nil)
        let initialCreateCount = tabManager.createTabCallCount

        vm.createNewTab(with: nil)

        #expect(tabManager.createTabCallCount == initialCreateCount) // no new tab
        #expect(tabManager.tabs.count == 1)
        #expect(tabManager.activeTabId == emptyTabId)
        #expect(vm.currentJSON == nil)
    }

    @Test("createNewTab reuses empty last tab and updates inputText when tab is already active")
    func createNewTabReusesActiveEmptyTab() {
        let json = #"{"c": 3}"#
        let (vm, tabManager, _, parser, _) = makeSUT()
        vm.onNeedShowWindow = {}

        // Create empty tab (it becomes active)
        let _ = tabManager.createTab(with: nil)

        let node = JSONNode(value: .object(["c": .number(3)]))
        parser.parseResult = .success(node)

        vm.createNewTab(with: json)

        // inputText should be updated directly since tab was already active
        #expect(vm.inputText == json)
        #expect(vm.currentJSON == json)
    }

    // MARK: - closeTab

    @Test("closeTab with last tab closes viewer")
    func closeTabLastTab() {
        let (vm, tabManager, _, _, windowManager) = makeSUT()
        let id = tabManager.createTab(with: nil)

        vm.closeTab(id: id)

        #expect(windowManager.closeViewerCallCount == 1)
    }

    @Test("closeTab with multiple tabs removes tab")
    func closeTabMultipleTabs() {
        let (vm, tabManager, _, _, windowManager) = makeSUT()
        let _ = tabManager.createTab(with: "1")
        let id2 = tabManager.createTab(with: "2")

        vm.closeTab(id: id2)

        #expect(windowManager.closeViewerCallCount == 0) // not last tab
        #expect(tabManager.closeTabCallCount >= 1)
    }

    // MARK: - handleTextChange

    @Test("handleTextChange with empty text clears parse result")
    func handleTextChangeEmpty() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: "old")
        tabManager.activeTabId = id

        vm.handleTextChange("")

        #expect(vm.currentJSON == nil)
        #expect(vm.parseResult == nil)
    }

    @Test("handleTextChange skipped during tab restoration")
    func handleTextChangeSkippedDuringRestore() {
        let (vm, tabManager, _, parser, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id
        vm.isRestoringTabState = true

        vm.handleTextChange("some text")

        // Parser should NOT be called during restore
        #expect(parser.parseCallCount == 0)
    }

    // MARK: - clearAll

    @Test("clearAll resets all state")
    func clearAll() {
        let (vm, tabManager, _, parser, _) = makeSUT()
        let node = JSONNode(value: .null)
        parser.parseResult = .success(node)
        vm.onNeedShowWindow = {}
        vm.createNewTab(with: #"{"key":"value"}"#)

        vm.clearAll()

        #expect(vm.inputText == "")
        #expect(vm.currentJSON == nil)
        #expect(vm.parseResult == nil)
        #expect(vm.searchText == "")
        #expect(vm.searchResultCount == 0)
    }

    // MARK: - closeSearch

    @Test("closeSearch resets search state")
    func closeSearch() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id

        vm.searchText = "test"
        vm.isSearchVisible = true
        vm.beautifySearchIndex = 3
        vm.searchResultCount = 10

        vm.closeSearch()

        #expect(vm.searchText == "")
        #expect(vm.isSearchVisible == false)
        #expect(vm.beautifySearchIndex == 0)
        #expect(vm.treeSearchIndex == 0)
        #expect(vm.searchResultCount == 0)
    }

    // MARK: - switchViewMode

    @Test("switchViewMode changes mode")
    func switchViewMode() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id

        #expect(vm.viewMode == .beautify) // default

        vm.switchViewMode(to: .tree)
        #expect(vm.viewMode == .tree)

        vm.switchViewMode(to: .beautify)
        #expect(vm.viewMode == .beautify)
    }

    @Test("switchViewMode to same mode is no-op")
    func switchViewModeSameMode() {
        let (vm, _, _, _, _) = makeSUT()
        vm.switchViewMode(to: .beautify) // already beautify
        // No crash, no state change
        #expect(vm.viewMode == .beautify)
    }

    // MARK: - Search

    @Test("updateSearchResultCount with tree mode")
    func updateSearchResultCountTree() {
        let (vm, _, _, _, _) = makeSUT()

        let root = JSONNode(value: .object([
            "name": .string("test"),
            "value": .number(42)
        ]))
        vm.parseResult = .success(root)
        vm.searchText = "test"
        vm.viewMode = .tree

        vm.updateSearchResultCount()

        #expect(vm.searchResultCount == 1)
    }

    @Test("updateSearchResultCount with empty search")
    func updateSearchResultCountEmpty() {
        let (vm, _, _, _, _) = makeSUT()

        let root = JSONNode(value: .object(["key": .string("val")]))
        vm.parseResult = .success(root)
        vm.searchText = ""

        vm.updateSearchResultCount()

        #expect(vm.searchResultCount == 0)
    }

    @Test("nextSearchResult wraps around")
    func nextSearchResultWraps() {
        let (vm, _, _, _, _) = makeSUT()
        vm.searchResultCount = 3
        vm.viewMode = .beautify
        vm.beautifySearchIndex = 2

        vm.nextSearchResult()

        #expect(vm.beautifySearchIndex == 0) // wrapped
    }

    @Test("previousSearchResult wraps around")
    func previousSearchResultWraps() {
        let (vm, _, _, _, _) = makeSUT()
        vm.searchResultCount = 3
        vm.viewMode = .beautify
        vm.beautifySearchIndex = 0

        vm.previousSearchResult()

        #expect(vm.beautifySearchIndex == 2) // wrapped
    }

    // MARK: - copyAllJSON

    @Test("copyAllJSON copies formatted JSON to clipboard")
    func copyAllJSON() {
        let (vm, _, clipboard, parser, _) = makeSUT()
        vm.currentJSON = #"{"key":"value"}"#
        parser.formatResult = #"{"key": "value"}"#

        vm.copyAllJSON()

        #expect(clipboard.storedText == #"{"key": "value"}"#)
    }

    @Test("copyAllJSON copies raw JSON if format fails")
    func copyAllJSONRawFallback() {
        let (vm, _, clipboard, parser, _) = makeSUT()
        vm.currentJSON = #"{"key":"value"}"#
        parser.formatResult = nil // formatting fails

        vm.copyAllJSON()

        #expect(clipboard.storedText == #"{"key":"value"}"#)
    }

    // MARK: - Tab State Management

    @Test("saveTabState saves all state fields to TabManager")
    func saveTabState() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: nil)

        vm.searchText = "query"
        vm.beautifySearchIndex = 2
        vm.treeSearchIndex = 1
        vm.viewMode = .tree
        vm.isSearchVisible = true
        vm.inputScrollPosition = 100
        vm.beautifyScrollPosition = 200
        let nodeId = UUID()
        vm.selectedNodeId = nodeId

        vm.saveTabState(for: id)

        let tab = tabManager.tabs.first(where: { $0.id == id })
        #expect(tab?.searchText == "query")
        #expect(tab?.beautifySearchIndex == 2)
        #expect(tab?.treeSearchIndex == 1)
        #expect(tab?.viewMode == .tree)
        #expect(tab?.isSearchVisible == true)
        #expect(tab?.inputScrollPosition == 100)
        #expect(tab?.beautifyScrollPosition == 200)
        #expect(tab?.treeSelectedNodeId == nodeId)
    }

    // MARK: - Confetti

    @Test("triggerConfetti increments counter")
    func triggerConfetti() {
        let (vm, _, _, _, _) = makeSUT()
        #expect(vm.confettiCounter == 0)

        vm.triggerConfetti()
        #expect(vm.confettiCounter == 1)

        vm.triggerConfetti()
        #expect(vm.confettiCounter == 2)
    }

    // MARK: - Tree Keyboard Navigation

    @Test("moveSelectionDown moves to next visible node")
    func moveSelectionDown() {
        let (vm, _, _, _, _) = makeSUT()
        let root = JSONNode(value: .object([
            "a": .string("1"),
            "b": .string("2")
        ]), defaultFoldDepth: 10)
        vm.parseResult = .success(root)

        // Select root
        vm.selectedNodeId = root.id
        vm.moveSelectionDown()

        // Should move to first child ("a" - sorted)
        #expect(vm.selectedNodeId == root.children[0].id)

        vm.moveSelectionDown()
        // Should move to second child ("b")
        #expect(vm.selectedNodeId == root.children[1].id)
    }

    @Test("moveSelectionDown at last node stays put")
    func moveSelectionDownAtEnd() {
        let (vm, _, _, _, _) = makeSUT()
        let root = JSONNode(value: .object(["a": .string("1")]), defaultFoldDepth: 10)
        vm.parseResult = .success(root)

        let lastNode = root.children[0]
        vm.selectedNodeId = lastNode.id

        vm.moveSelectionDown()
        #expect(vm.selectedNodeId == lastNode.id)
    }

    @Test("moveSelectionUp moves to previous visible node")
    func moveSelectionUp() {
        let (vm, _, _, _, _) = makeSUT()
        let root = JSONNode(value: .object([
            "a": .string("1"),
            "b": .string("2")
        ]), defaultFoldDepth: 10)
        vm.parseResult = .success(root)

        // Select last child ("b")
        vm.selectedNodeId = root.children[1].id
        vm.moveSelectionUp()
        #expect(vm.selectedNodeId == root.children[0].id)

        vm.moveSelectionUp()
        #expect(vm.selectedNodeId == root.id)
    }

    @Test("moveSelectionUp at first node stays put")
    func moveSelectionUpAtStart() {
        let (vm, _, _, _, _) = makeSUT()
        let root = JSONNode(value: .object(["a": .string("1")]), defaultFoldDepth: 10)
        vm.parseResult = .success(root)

        vm.selectedNodeId = root.id
        vm.moveSelectionUp()
        #expect(vm.selectedNodeId == root.id)
    }

    @Test("expandOrMoveRight expands collapsed container")
    func expandOrMoveRightExpands() {
        let (vm, _, _, _, _) = makeSUT()
        let root = JSONNode(value: .object([
            "a": .object(["nested": .string("val")])
        ]), defaultFoldDepth: 10)
        vm.parseResult = .success(root)

        let containerNode = root.children[0] // "a"
        containerNode.isExpanded = false
        vm.selectedNodeId = containerNode.id

        vm.expandOrMoveRight()

        #expect(containerNode.isExpanded == true)
        #expect(vm.selectedNodeId == containerNode.id) // stays on same node
    }

    @Test("expandOrMoveRight moves to first child when expanded")
    func expandOrMoveRightMovesToChild() {
        let (vm, _, _, _, _) = makeSUT()
        let root = JSONNode(value: .object([
            "a": .object(["nested": .string("val")])
        ]), defaultFoldDepth: 10)
        vm.parseResult = .success(root)

        let containerNode = root.children[0] // "a" - already expanded
        vm.selectedNodeId = containerNode.id

        vm.expandOrMoveRight()

        #expect(vm.selectedNodeId == containerNode.children[0].id)
    }

    @Test("expandOrMoveRight on leaf does nothing")
    func expandOrMoveRightOnLeaf() {
        let (vm, _, _, _, _) = makeSUT()
        let root = JSONNode(value: .object(["a": .string("1")]), defaultFoldDepth: 10)
        vm.parseResult = .success(root)

        let leaf = root.children[0]
        vm.selectedNodeId = leaf.id

        vm.expandOrMoveRight()
        #expect(vm.selectedNodeId == leaf.id) // unchanged
    }

    @Test("collapseOrMoveLeft collapses expanded container")
    func collapseOrMoveLeftCollapses() {
        let (vm, _, _, _, _) = makeSUT()
        let root = JSONNode(value: .object([
            "a": .object(["nested": .string("val")])
        ]), defaultFoldDepth: 10)
        vm.parseResult = .success(root)

        let containerNode = root.children[0] // "a" - expanded
        vm.selectedNodeId = containerNode.id

        vm.collapseOrMoveLeft()

        #expect(containerNode.isExpanded == false)
        #expect(vm.selectedNodeId == containerNode.id) // stays
    }

    @Test("collapseOrMoveLeft moves to parent when collapsed or leaf")
    func collapseOrMoveLeftMovesToParent() {
        let (vm, _, _, _, _) = makeSUT()
        let root = JSONNode(value: .object([
            "a": .object(["nested": .string("val")])
        ]), defaultFoldDepth: 10)
        vm.parseResult = .success(root)

        let leaf = root.children[0].children[0] // "nested"
        vm.selectedNodeId = leaf.id

        vm.collapseOrMoveLeft()
        #expect(vm.selectedNodeId == root.children[0].id) // moved to parent "a"
    }

    @Test("selectedNodeId and treeScrollAnchorId are independent")
    func selectedAndScrollAnchorIndependent() {
        let (vm, _, _, _, _) = makeSUT()
        let nodeId1 = UUID()
        let nodeId2 = UUID()

        vm.selectedNodeId = nodeId1
        vm.treeScrollAnchorId = nodeId2

        #expect(vm.selectedNodeId == nodeId1)
        #expect(vm.treeScrollAnchorId == nodeId2)
    }

    @Test("moveSelectionDown with no selection selects first node")
    func moveSelectionDownNoSelection() {
        let (vm, _, _, _, _) = makeSUT()
        let root = JSONNode(value: .object(["a": .string("1")]), defaultFoldDepth: 10)
        vm.parseResult = .success(root)
        vm.selectedNodeId = nil

        vm.moveSelectionDown()
        #expect(vm.selectedNodeId == root.id)
    }

    // MARK: - handleTextChange (debounced path)

    @Test("handleTextChange with new JSON replaces parseResult and resets selection")
    func handleTextChangeReplacesParseResult() async throws {
        let (vm, tabManager, _, parser, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id

        // Set initial state: parsed JSON with selected node
        let initialNode = JSONNode(value: .object(["a": .string("1")]))
        vm.parseResult = .success(initialNode)
        vm.selectedNodeId = initialNode.children.first?.id

        // Configure parser to return a different node
        let newNode = JSONNode(value: .object(["b": .string("2")]))
        parser.parseResult = .success(newNode)

        // Trigger text change (debounced — fires after 0.3s)
        vm.handleTextChange(#"{"b": "2"}"#)

        // Wait for debounce to fire
        try await Task.sleep(nanoseconds: 500_000_000)

        // parseResult should have the new root node with a different id
        guard case .success(let resultNode) = vm.parseResult else {
            Issue.record("Expected success parse result after text change")
            return
        }
        #expect(resultNode.id == newNode.id)
        #expect(resultNode.id != initialNode.id)

        // Selection and scroll should be reset
        #expect(vm.selectedNodeId == nil)
        #expect(vm.beautifyScrollPosition == 0)
    }

    // MARK: - onWindowWillClose

    @Test("onWindowWillClose clears state and tabs")
    func onWindowWillClose() {
        let (vm, tabManager, _, parser, _) = makeSUT()
        parser.parseResult = .success(JSONNode(value: .null))
        vm.onNeedShowWindow = {}
        vm.createNewTab(with: "test")

        vm.onWindowWillClose()

        #expect(vm.currentJSON == nil)
        #expect(vm.parseResult == nil)
        #expect(tabManager.tabs.isEmpty)
    }
}
#endif
