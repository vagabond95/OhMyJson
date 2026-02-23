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

        // Configure lightweight validation to pass
        parser.validateResult = true
        // Configure parser for background parse
        let node = JSONNode(value: .object(["key": .string("value")]))
        parser.parseResult = .success(node)

        var windowShowCalled = false
        vm.onNeedShowWindow = { windowShowCalled = true }

        vm.handleHotKey()

        #expect(tabManager.createTabCallCount == 1)
        #expect(windowShowCalled == true)
        #expect(vm.currentJSON == json)
    }

    @Test("handleHotKey with invalid JSON creates tab with error view")
    func handleHotKeyInvalidJSON() {
        let (vm, tabManager, _, _, _) = makeSUT(clipboardText: "not json")

        vm.handleHotKey()

        // Invalid JSON always creates a tab — ErrorView shows parse error details
        #expect(tabManager.createTabCallCount == 1)
        #expect(vm.currentJSON == "not json")
    }

    @Test("handleHotKey with invalid JSON brings window to front if open")
    func handleHotKeyInvalidJSONBringToFront() {
        let (vm, _, _, _, windowManager) = makeSUT(clipboardText: "not json")
        windowManager.isViewerOpen = true

        vm.handleHotKey()

        // createNewTab calls bringToFront when window is already open
        #expect(windowManager.bringToFrontCallCount == 1)
    }

    // MARK: - createNewTab

    @MainActor @Test("createNewTab with JSON parses and sets state")
    func createNewTabWithJSON() async throws {
        let json = #"{"a": 1}"#
        let (vm, tabManager, _, parser, _) = makeSUT()

        let node = JSONNode(value: .object(["a": .number(1)]))
        parser.parseResult = .success(node)
        vm.onNeedShowWindow = {}

        vm.createNewTab(with: json)

        #expect(tabManager.createTabCallCount == 1)
        #expect(vm.currentJSON == json)
        // parseResult is now set asynchronously via background parse
        #expect(vm.isParsing == true)

        // Wait for background parse to complete
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(vm.isParsing == false)
        if case .success = vm.parseResult {
            // OK
        } else {
            Issue.record("Expected success parse result after background parse")
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
        #expect(vm.isParsing == false)
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

    // MARK: - Expand / Collapse All

    @Test("expandAllNodes expands all nodes and resets selection")
    func expandAllNodes() {
        let (vm, _, _, _, _) = makeSUT()
        let root = JSONNode(value: .object([
            "a": .object(["nested": .string("val")]),
            "b": .array([.number(1), .number(2)])
        ]), defaultFoldDepth: 1)
        vm.parseResult = .success(root)

        // Collapse some nodes first
        root.children[0].isExpanded = false
        root.children[1].isExpanded = false
        vm.selectedNodeId = root.id
        let initialVersion = vm.treeStructureVersion

        vm.expandAllNodes()

        #expect(root.isExpanded == true)
        #expect(root.children[0].isExpanded == true)
        #expect(root.children[1].isExpanded == true)
        #expect(vm.selectedNodeId == nil)
        #expect(vm.treeScrollAnchorId == nil)
        #expect(vm.treeStructureVersion == initialVersion + 1)
    }

    @Test("collapseAllNodes collapses all nodes including root and resets selection")
    func collapseAllNodes() {
        let (vm, _, _, _, _) = makeSUT()
        let root = JSONNode(value: .object([
            "a": .object(["nested": .string("val")]),
            "b": .array([.number(1), .number(2)])
        ]), defaultFoldDepth: 10)
        vm.parseResult = .success(root)

        vm.selectedNodeId = root.children[0].id
        let initialVersion = vm.treeStructureVersion

        vm.collapseAllNodes()

        #expect(root.isExpanded == false)
        #expect(root.children[0].isExpanded == false)
        #expect(root.children[1].isExpanded == false)
        #expect(vm.selectedNodeId == nil)
        #expect(vm.treeScrollAnchorId == nil)
        #expect(vm.treeStructureVersion == initialVersion + 1)
    }

    @Test("expandAllNodes is no-op when no parse result")
    func expandAllNodesNoParseResult() {
        let (vm, _, _, _, _) = makeSUT()
        vm.parseResult = nil
        let initialVersion = vm.treeStructureVersion

        vm.expandAllNodes()

        #expect(vm.treeStructureVersion == initialVersion)
    }

    @Test("collapseAllNodes is no-op when no parse result")
    func collapseAllNodesNoParseResult() {
        let (vm, _, _, _, _) = makeSUT()
        vm.parseResult = nil
        let initialVersion = vm.treeStructureVersion

        vm.collapseAllNodes()

        #expect(vm.treeStructureVersion == initialVersion)
    }

    @Test("expandAllNodes is no-op on parse failure")
    func expandAllNodesParseFailure() {
        let (vm, _, _, _, _) = makeSUT()
        vm.parseResult = .failure(JSONParseError(message: "Bad JSON"))
        let initialVersion = vm.treeStructureVersion

        vm.expandAllNodes()

        #expect(vm.treeStructureVersion == initialVersion)
    }

    @Test("collapseAllNodes is no-op on parse failure")
    func collapseAllNodesParseFailure() {
        let (vm, _, _, _, _) = makeSUT()
        vm.parseResult = .failure(JSONParseError(message: "Bad JSON"))
        let initialVersion = vm.treeStructureVersion

        vm.collapseAllNodes()

        #expect(vm.treeStructureVersion == initialVersion)
    }

    // MARK: - handleTextChange (debounced path)

    @MainActor @Test("handleTextChange with new JSON replaces parseResult and resets selection")
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

        // Trigger text change (debounced — fires after 0.3s, then background parse)
        vm.handleTextChange(#"{"b": "2"}"#)

        // Wait for debounce + background parse to complete
        try await Task.sleep(nanoseconds: 800_000_000)

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

    // MARK: - Background Parsing

    @MainActor @Test("isParsing becomes true during background parse and false after completion")
    func isParsingDuringBackgroundParse() async throws {
        let (vm, tabManager, _, parser, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id

        let node = JSONNode(value: .object(["a": .number(1)]))
        parser.parseResult = .success(node)
        parser.formatResult = #"{"a": 1}"#

        vm.handleTextChange(#"{"a": 1}"#)

        // Wait for debounce + background parse to complete
        try await Task.sleep(nanoseconds: 800_000_000)

        #expect(vm.isParsing == false)
        #expect(vm.parseResult != nil)
        #expect(vm.formattedJSON == #"{"a": 1}"#)
    }

    @Test("isParsing observation triggers view update")
    func isParsingObservation() {
        let (vm, _, _, _, _) = makeSUT()

        var observed = false
        withObservationTracking {
            _ = vm.isParsing
        } onChange: {
            observed = true
        }

        vm.isParsing = true
        #expect(observed == true)
    }

    @MainActor @Test("clearAll cancels in-flight background parse")
    func clearAllCancelsParse() async throws {
        let (vm, tabManager, _, parser, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id

        let node = JSONNode(value: .object(["a": .number(1)]))
        parser.parseResult = .success(node)

        vm.handleTextChange(#"{"a": 1}"#)
        // Immediately clear before debounce fires
        vm.clearAll()

        #expect(vm.isParsing == false)
        #expect(vm.parseResult == nil)

        // Wait to ensure cancelled parse doesn't apply results
        try await Task.sleep(nanoseconds: 800_000_000)
        #expect(vm.parseResult == nil)
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

    // MARK: - Node Cache

    @Test("rebuildNodeCache populates cache from parseResult")
    func rebuildNodeCacheFromParseResult() {
        let (vm, _, _, _, _) = makeSUT()
        let root = JSONNode(value: .object([
            "a": .string("1"),
            "b": .string("2")
        ]), defaultFoldDepth: 10)

        // Setting parseResult triggers rebuildNodeCache via didSet
        vm.parseResult = .success(root)

        // Keyboard nav should work immediately after setting parseResult
        vm.selectedNodeId = root.id
        vm.moveSelectionDown()
        #expect(vm.selectedNodeId == root.children[0].id)
    }

    @Test("rebuildNodeCache clears cache on nil parseResult")
    func rebuildNodeCacheClearsOnNil() {
        let (vm, _, _, _, _) = makeSUT()
        let root = JSONNode(value: .object(["a": .string("1")]), defaultFoldDepth: 10)
        vm.parseResult = .success(root)

        // Clear
        vm.parseResult = nil

        // moveSelectionDown should be no-op (no crash, no change)
        vm.selectedNodeId = nil
        vm.moveSelectionDown()
        #expect(vm.selectedNodeId == nil)
    }

    @Test("rebuildNodeCache clears cache on failure parseResult")
    func rebuildNodeCacheClearsOnFailure() {
        let (vm, _, _, _, _) = makeSUT()
        let root = JSONNode(value: .object(["a": .string("1")]), defaultFoldDepth: 10)
        vm.parseResult = .success(root)

        // Set failure
        vm.parseResult = .failure(JSONParseError(message: "Bad JSON"))

        vm.selectedNodeId = nil
        vm.moveSelectionDown()
        #expect(vm.selectedNodeId == nil)
    }

    @Test("updateNodeCache from external source enables keyboard nav")
    func updateNodeCacheExternal() {
        let (vm, _, _, _, _) = makeSUT()
        let root = JSONNode(value: .object([
            "x": .string("1"),
            "y": .string("2")
        ]), defaultFoldDepth: 10)

        // Set parseResult first so guard checks pass
        vm.parseResult = .success(root)

        // Simulate TreeView providing expanded visible nodes
        let nodes = root.allNodes()
        vm.updateNodeCache(nodes)

        vm.selectedNodeId = root.id
        vm.moveSelectionDown()
        #expect(vm.selectedNodeId == root.children[0].id)
    }

    // MARK: - Tree Horizontal Scroll Offset

    @Test("treeHorizontalScrollOffset default is 0")
    func treeHorizontalScrollOffsetDefault() {
        let (vm, _, _, _, _) = makeSUT()
        #expect(vm.treeHorizontalScrollOffset == 0)
    }

    @Test("saveTabState saves treeHorizontalScrollOffset")
    func saveTabStateSavesHorizontalScroll() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id

        vm.treeHorizontalScrollOffset = 42.5
        vm.saveTabState(for: id)

        let tab = tabManager.tabs.first(where: { $0.id == id })
        #expect(tab?.treeHorizontalScrollOffset == 42.5)
    }

    @Test("restoreTabState restores treeHorizontalScrollOffset")
    func restoreTabStateRestoresHorizontalScroll() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id
        tabManager.updateTabTreeHorizontalScroll(id: id, offset: 99.0)

        vm.restoreTabState()

        #expect(vm.treeHorizontalScrollOffset == 99.0)
    }

    @Test("restoreTabState resets treeHorizontalScrollOffset when no active tab")
    func restoreTabStateResetsHorizontalScrollNoTab() {
        let (vm, _, _, _, _) = makeSUT()
        vm.treeHorizontalScrollOffset = 50.0

        vm.restoreTabState()

        #expect(vm.treeHorizontalScrollOffset == 0)
    }

    @Test("syncTreeHorizontalScroll saves to tab manager")
    func syncTreeHorizontalScroll() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id
        vm.viewMode = .tree
        vm.treeHorizontalScrollOffset = 75.0

        vm.syncTreeHorizontalScroll()

        let tab = tabManager.tabs.first(where: { $0.id == id })
        #expect(tab?.treeHorizontalScrollOffset == 75.0)
    }

    @Test("syncTreeHorizontalScroll skips during tab state restoration")
    func syncTreeHorizontalScrollSkipsDuringRestore() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id
        vm.viewMode = .tree
        vm.isRestoringTabState = true
        vm.treeHorizontalScrollOffset = 75.0

        vm.syncTreeHorizontalScroll()

        let tab = tabManager.tabs.first(where: { $0.id == id })
        #expect(tab?.treeHorizontalScrollOffset == 0)
    }

    @Test("treeHorizontalScrollOffset observation triggers view update")
    func treeHorizontalScrollOffsetObservation() {
        let (vm, _, _, _, _) = makeSUT()

        var observed = false
        withObservationTracking {
            _ = vm.treeHorizontalScrollOffset
        } onChange: {
            observed = true
        }

        vm.treeHorizontalScrollOffset = 100.0
        #expect(observed == true)
    }

    // MARK: - Search Highlight Dismiss

    @Test("dismissBeautifySearchHighlights sets beautifySearchDismissed and leaves treeSearchDismissed independent")
    func dismissBeautifySearchHighlights() {
        let (vm, _, _, _, _) = makeSUT()
        vm.searchText = "test"
        vm.searchResultCount = 3

        vm.dismissBeautifySearchHighlights()

        #expect(vm.beautifySearchDismissed == true)
        #expect(vm.treeSearchDismissed == false)
    }

    @Test("dismissTreeSearchHighlights sets treeSearchDismissed and leaves beautifySearchDismissed independent")
    func dismissTreeSearchHighlights() {
        let (vm, _, _, _, _) = makeSUT()
        vm.searchText = "test"
        vm.searchResultCount = 3

        vm.dismissTreeSearchHighlights()

        #expect(vm.treeSearchDismissed == true)
        #expect(vm.beautifySearchDismissed == false)
    }

    @Test("dismiss is no-op when searchText is empty")
    func dismissNoOpWhenSearchEmpty() {
        let (vm, _, _, _, _) = makeSUT()
        vm.searchText = ""

        vm.dismissBeautifySearchHighlights()
        vm.dismissTreeSearchHighlights()

        #expect(vm.beautifySearchDismissed == false)
        #expect(vm.treeSearchDismissed == false)
    }

    @Test("dismiss is no-op when already dismissed")
    func dismissNoOpWhenAlreadyDismissed() {
        let (vm, _, _, _, _) = makeSUT()
        vm.searchText = "test"
        vm.beautifySearchDismissed = true
        vm.treeSearchDismissed = true

        // Should not crash or change state
        vm.dismissBeautifySearchHighlights()
        vm.dismissTreeSearchHighlights()

        #expect(vm.beautifySearchDismissed == true)
        #expect(vm.treeSearchDismissed == true)
    }

    @Test("nextSearchResult restores dismiss flag for current view mode (beautify)")
    func nextSearchResultRestoresDismissBeautify() {
        let (vm, _, _, _, _) = makeSUT()
        vm.searchResultCount = 3
        vm.viewMode = .beautify
        vm.beautifySearchDismissed = true

        vm.nextSearchResult()

        #expect(vm.beautifySearchDismissed == false)
        #expect(vm.treeSearchDismissed == false) // independent
    }

    @Test("nextSearchResult restores dismiss flag for current view mode (tree)")
    func nextSearchResultRestoresDismissTree() {
        let (vm, _, _, _, _) = makeSUT()
        vm.searchResultCount = 3
        vm.viewMode = .tree
        vm.treeSearchDismissed = true

        vm.nextSearchResult()

        #expect(vm.treeSearchDismissed == false)
        #expect(vm.beautifySearchDismissed == false) // independent
    }

    @Test("previousSearchResult restores dismiss flag for current view mode")
    func previousSearchResultRestoresDismiss() {
        let (vm, _, _, _, _) = makeSUT()
        vm.searchResultCount = 3
        vm.viewMode = .beautify
        vm.beautifySearchDismissed = true
        vm.beautifySearchIndex = 1

        vm.previousSearchResult()

        #expect(vm.beautifySearchDismissed == false)
    }

    @Test("closeSearch resets both dismiss flags")
    func closeSearchResetsDismiss() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id
        vm.beautifySearchDismissed = true
        vm.treeSearchDismissed = true

        vm.closeSearch()

        #expect(vm.beautifySearchDismissed == false)
        #expect(vm.treeSearchDismissed == false)
    }

    @Test("clearAll resets both dismiss flags")
    func clearAllResetsDismiss() {
        let (vm, tabManager, _, parser, _) = makeSUT()
        parser.parseResult = .success(JSONNode(value: .null))
        vm.onNeedShowWindow = {}
        vm.createNewTab(with: #"{"key":"value"}"#)
        vm.beautifySearchDismissed = true
        vm.treeSearchDismissed = true

        vm.clearAll()

        #expect(vm.beautifySearchDismissed == false)
        #expect(vm.treeSearchDismissed == false)
    }

    @Test("saveTabState saves dismiss state to tab")
    func saveTabStateSavesDismiss() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id

        vm.beautifySearchDismissed = true
        vm.treeSearchDismissed = false

        vm.saveTabState(for: id)

        let tab = tabManager.tabs.first(where: { $0.id == id })
        #expect(tab?.beautifySearchDismissed == true)
        #expect(tab?.treeSearchDismissed == false)
    }

    @Test("restoreTabState restores dismiss state from tab")
    func restoreTabStateRestoresDismiss() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id
        tabManager.updateTabSearchDismissState(id: id, beautifyDismissed: true, treeDismissed: true)

        vm.restoreTabState()

        #expect(vm.beautifySearchDismissed == true)
        #expect(vm.treeSearchDismissed == true)
    }

    @Test("restoreTabState resets dismiss state when no active tab")
    func restoreTabStateResetsDismissNoTab() {
        let (vm, _, _, _, _) = makeSUT()
        vm.beautifySearchDismissed = true
        vm.treeSearchDismissed = true

        vm.restoreTabState()

        #expect(vm.beautifySearchDismissed == false)
        #expect(vm.treeSearchDismissed == false)
    }

    @Test("dismissed state preserves navigation position — nextSearchResult continues from last index")
    func dismissedNavigationContinuesFromLastIndex() {
        let (vm, _, _, _, _) = makeSUT()
        vm.searchText = "test"
        vm.searchResultCount = 5
        vm.viewMode = .beautify
        vm.beautifySearchIndex = 2

        vm.dismissBeautifySearchHighlights()
        #expect(vm.beautifySearchDismissed == true)

        vm.nextSearchResult()
        #expect(vm.beautifySearchDismissed == false)
        #expect(vm.beautifySearchIndex == 3) // continues from 2 → 3
    }

    @Test("beautifySearchDismissed observation triggers view update")
    func beautifySearchDismissedObservation() {
        let (vm, _, _, _, _) = makeSUT()

        var observed = false
        withObservationTracking {
            _ = vm.beautifySearchDismissed
        } onChange: {
            observed = true
        }

        vm.beautifySearchDismissed = true
        #expect(observed == true)
    }

    @Test("treeSearchDismissed observation triggers view update")
    func treeSearchDismissedObservation() {
        let (vm, _, _, _, _) = makeSUT()

        var observed = false
        withObservationTracking {
            _ = vm.treeSearchDismissed
        } onChange: {
            observed = true
        }

        vm.treeSearchDismissed = true
        #expect(observed == true)
    }

    @Test("keyboard nav uses cached nodes after expand/collapse")
    func keyboardNavAfterExpandCollapse() {
        let (vm, _, _, _, _) = makeSUT()
        let root = JSONNode(value: .object([
            "a": .object(["nested": .string("val")])
        ]), defaultFoldDepth: 10)
        vm.parseResult = .success(root)

        let containerNode = root.children[0] // "a"

        // Collapse "a" — cache should reflect this after updateNodeCache
        containerNode.isExpanded = false
        let collapsed = root.allNodes()
        vm.updateNodeCache(collapsed)

        // Only root and "a" visible (nested is hidden)
        vm.selectedNodeId = root.id
        vm.moveSelectionDown()
        #expect(vm.selectedNodeId == containerNode.id)

        // Next move should stay at "a" (no more visible nodes)
        vm.moveSelectionDown()
        #expect(vm.selectedNodeId == containerNode.id)
    }

    // MARK: - Large Text Paste Handling

    private func makeLargeText() -> String {
        // Generate text that exceeds InputSize.displayThreshold (512KB)
        return String(repeating: "x", count: InputSize.displayThreshold + 1)
    }

    @Test("handleLargeTextPaste sets truncated inputText and stores fullInputText")
    func handleLargeTextPasteSetsState() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id

        let largeText = makeLargeText()
        vm.handleLargeTextPaste(largeText)

        // inputText should be truncated (shorter than original)
        #expect(vm.inputText.utf8.count < largeText.utf8.count)
        // fullInputText should hold the original
        #expect(vm.fullInputText == largeText)
        // Tab should store truncated display text
        let tab = tabManager.tabs.first(where: { $0.id == id })
        #expect(tab?.inputText.utf8.count ?? 0 < largeText.utf8.count)
        // Tab should store full text
        #expect(tab?.fullInputText == largeText)
    }

    @Test("handleLargeTextPaste starts background parse with full text")
    func handleLargeTextPasteStartsParse() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id

        let largeText = makeLargeText()
        vm.handleLargeTextPaste(largeText)

        // Background parse should be in progress
        #expect(vm.isParsing == true)
    }

    @Test("handleTextChange clears fullInputText when user edits")
    func handleTextChangeClearsFullInputText() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id

        // Simulate fullInputText was set (e.g. from a previous large paste)
        vm.fullInputText = "original full text"
        tabManager.updateTabFullInput(id: id, fullText: "original full text")

        vm.handleTextChange("edited text")

        #expect(vm.fullInputText == nil)
        #expect(tabManager.activeTab?.fullInputText == nil)
    }

    @Test("handleTextChange does not clear fullInputText during tab restoration")
    func handleTextChangeSkipsClearDuringRestore() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id
        vm.fullInputText = "original full text"
        vm.isRestoringTabState = true

        vm.handleTextChange("some text")

        // Should be a no-op during restore
        #expect(vm.fullInputText == "original full text")
    }

    @Test("restoreTabState restores fullInputText from tab")
    func restoreTabStateRestoresFullInputText() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: "truncated preview")
        tabManager.activeTabId = id
        tabManager.updateTabFullInput(id: id, fullText: "full original text")

        vm.restoreTabState()

        #expect(vm.fullInputText == "full original text")
        #expect(vm.inputText == "truncated preview")
    }

    @Test("restoreTabState uses fullInputText for currentJSON")
    func restoreTabStateUsesfullInputTextForCurrentJSON() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: "truncated")
        tabManager.activeTabId = id
        tabManager.updateTabFullInput(id: id, fullText: "full json content")

        vm.restoreTabState()

        #expect(vm.currentJSON == "full json content")
    }

    @Test("restoreTabState with no fullInputText uses inputText for currentJSON")
    func restoreTabStateNoFullInputText() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: "small json")
        tabManager.activeTabId = id

        vm.restoreTabState()

        #expect(vm.fullInputText == nil)
        #expect(vm.currentJSON == "small json")
    }

    @Test("clearAll resets fullInputText")
    func clearAllResetsFullInputText() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id
        vm.fullInputText = "some full text"
        tabManager.updateTabFullInput(id: id, fullText: "some full text")

        vm.clearAll()

        #expect(vm.fullInputText == nil)
        #expect(tabManager.activeTab?.fullInputText == nil)
    }

    @Test("saveTabState saves fullInputText to tab")
    func saveTabStateSavesFullInputText() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id
        vm.fullInputText = "full content"

        vm.saveTabState(for: id)

        #expect(tabManager.activeTab?.fullInputText == "full content")
    }

    @Test("buildTruncatedPreview returns prefix with annotation")
    func buildTruncatedPreviewReturnsPrefix() {
        let text = String(repeating: "a", count: 20_000)
        let preview = ViewerViewModel.buildTruncatedPreview(text)

        // Preview should start with first characters
        #expect(preview.hasPrefix(String(repeating: "a", count: 10_000)))
        // Preview should contain truncation notice
        #expect(preview.contains("Large input"))
        #expect(preview.contains("truncated"))
        // Preview should be shorter than original
        #expect(preview.count < text.count)
    }

    @Test("createNewTab with large JSON stores truncated display and full text")
    func createNewTabLargeJSONStoresTruncated() {
        let largeText = makeLargeText()
        let (vm, tabManager, _, _, _) = makeSUT()
        vm.onNeedShowWindow = {}

        vm.createNewTab(with: largeText)

        // Tab inputText should be truncated
        let tab = tabManager.activeTab
        #expect(tab?.inputText.utf8.count ?? 0 < largeText.utf8.count)
        // Tab fullInputText should hold original
        #expect(tab?.fullInputText == largeText)
        // ViewModel fullInputText should be set
        #expect(vm.fullInputText == largeText)
        // currentJSON should be full text (for parsing)
        #expect(vm.currentJSON == largeText)
    }

    // MARK: - isBeautifyRendering

    @Test("isBeautifyRendering defaults to false")
    func isBeautifyRenderingDefaultsFalse() {
        let (vm, _, _, _, _) = makeSUT()
        #expect(vm.isBeautifyRendering == false)
    }

    @Test("clearAll resets isBeautifyRendering")
    func clearAllResetsIsBeautifyRendering() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id
        vm.isBeautifyRendering = true

        vm.clearAll()

        #expect(vm.isBeautifyRendering == false)
    }

    @Test("isBeautifyRendering observation triggers view update")
    func isBeautifyRenderingObservation() {
        let (vm, _, _, _, _) = makeSUT()

        var observed = false
        withObservationTracking {
            _ = vm.isBeautifyRendering
        } onChange: {
            observed = true
        }

        vm.isBeautifyRendering = true
        #expect(observed == true)
    }
}

// Serialized suite to avoid UserDefaults race conditions in parallel test execution
@Suite("Update Banner Tests", .serialized)
struct UpdateBannerTests {

    private func makeSUT() -> ViewerViewModel {
        let tabManager = MockTabManager()
        let clipboard = MockClipboardService()
        let parser = MockJSONParser()
        let windowManager = MockWindowManager()
        return ViewerViewModel(
            tabManager: tabManager,
            clipboardService: clipboard,
            jsonParser: parser,
            windowManager: windowManager
        )
    }

    private func cleanUp() {
        UserDefaults.standard.removeObject(forKey: "bannerSkippedVersion")
    }

    @Test("setUpdateAvailable sets availableVersion and isUpdateAvailable")
    func setUpdateAvailableSetsState() {
        cleanUp()
        let vm = makeSUT()

        vm.setUpdateAvailable(version: "2.0.0")

        #expect(vm.availableVersion == "2.0.0")
        #expect(vm.isUpdateAvailable == true)
        cleanUp()
    }

    @Test("dismissUpdateBanner saves skippedVersion and clears availableVersion")
    func dismissUpdateBannerSkipsVersion() {
        cleanUp()
        let vm = makeSUT()

        vm.setUpdateAvailable(version: "2.0.0")
        vm.dismissUpdateBanner()

        #expect(vm.isUpdateAvailable == false)
        #expect(vm.availableVersion == nil)
        #expect(vm.skippedVersion == "2.0.0")
        cleanUp()
    }

    @Test("setUpdateAvailable with already-skipped version keeps banner hidden")
    func setUpdateAvailableSkippedVersionHidden() {
        cleanUp()
        let vm = makeSUT()

        vm.setUpdateAvailable(version: "2.0.0")
        vm.dismissUpdateBanner()

        // Same version again
        vm.setUpdateAvailable(version: "2.0.0")

        #expect(vm.availableVersion == nil)
        #expect(vm.isUpdateAvailable == false)
        cleanUp()
    }

    @Test("setUpdateAvailable with newer version after skip shows banner")
    func setUpdateAvailableNewerVersionAfterSkip() {
        cleanUp()
        let vm = makeSUT()

        vm.setUpdateAvailable(version: "2.0.0")
        vm.dismissUpdateBanner()

        // Newer version
        vm.setUpdateAvailable(version: "2.1.0")

        #expect(vm.availableVersion == "2.1.0")
        #expect(vm.isUpdateAvailable == true)
        cleanUp()
    }

    @Test("isUpdateAvailable is false when availableVersion is nil")
    func isUpdateAvailableFalseWhenNil() {
        cleanUp()
        let vm = makeSUT()

        #expect(vm.availableVersion == nil)
        #expect(vm.isUpdateAvailable == false)
        cleanUp()
    }

    @Test("availableVersion observation triggers view update")
    func availableVersionObservation() {
        let vm = makeSUT()

        var observed = false
        withObservationTracking {
            _ = vm.availableVersion
        } onChange: {
            observed = true
        }

        vm.availableVersion = "2.0.0"
        #expect(observed == true)
    }

    @Test("isUpdateAvailable observation chain triggered by availableVersion change")
    func isUpdateAvailableObservationChain() {
        cleanUp()
        let vm = makeSUT()

        var observed = false
        withObservationTracking {
            _ = vm.isUpdateAvailable
        } onChange: {
            observed = true
        }

        vm.availableVersion = "2.0.0"
        #expect(observed == true)
        cleanUp()
    }
}
#endif
