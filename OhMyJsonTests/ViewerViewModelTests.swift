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

    @Test("handleHotKey with invalid JSON does not create tab")
    func handleHotKeyInvalidJSON() {
        let (vm, tabManager, _, parser, _) = makeSUT(clipboardText: "not json")
        parser.validateResult = false

        vm.handleHotKey()

        #expect(tabManager.createTabCallCount == 0)
        #expect(parser.validateCallCount == 1)
        #expect(ToastManager.shared.message == String(localized: "toast.invalid_json"))
    }

    @Test("handleHotKey with invalid JSON shows existing tabs")
    func handleHotKeyInvalidJSONShowsExistingTabs() {
        let (vm, _, _, parser, windowManager) = makeSUT(clipboardText: "not json")
        parser.validateResult = false
        windowManager.isViewerOpen = true

        vm.handleHotKey()

        #expect(windowManager.bringToFrontCallCount == 1)
        #expect(ToastManager.shared.message == String(localized: "toast.invalid_json"))
    }

    @Test("handleHotKey with invalid JSON opens window when no viewer is open")
    func handleHotKeyInvalidJSONOpensWindow() {
        let (vm, _, _, parser, _) = makeSUT(clipboardText: "not json")
        parser.validateResult = false
        var windowShowCalled = false
        vm.onNeedShowWindow = { windowShowCalled = true }

        vm.handleHotKey()

        #expect(windowShowCalled)
        #expect(ToastManager.shared.message == String(localized: "toast.invalid_json"))
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

    @Test("createNewTab with large JSON increments tabGeneration so updateNSView fires")
    func createNewTabLargeJSONIncrementsTabGeneration() {
        let (vm, tabManager, _, _, _) = makeSUT()
        vm.onNeedShowWindow = {}

        // Create empty tab (it becomes active)
        let _ = tabManager.createTab(with: nil)

        let before = vm.tabGeneration
        let largeJson = String(repeating: "x", count: InputSize.displayThreshold + 1)
        vm.createNewTab(with: largeJson)

        // tabGeneration must have increased by at least 2:
        // once in createNewTab, once in the wasAlreadyActive block
        #expect(vm.tabGeneration >= before + 2)
    }

    // MARK: - closeTab

    @Test("closeTab with last tab shows quit confirmation instead of closing viewer")
    func closeTabLastTab() {
        let (vm, tabManager, _, _, windowManager) = makeSUT()
        let id = tabManager.createTab(with: nil)

        var quitConfirmationShown = false
        vm.quitConfirmationHandler = { quitConfirmationShown = true }

        vm.closeTab(id: id)

        #expect(quitConfirmationShown == true)
        #expect(windowManager.closeViewerCallCount == 0)
        #expect(tabManager.closeTabCallCount == 0)
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

    @Test("switchViewMode to beautify succeeds even with large JSON")
    func switchViewModeBeautifyWithLargeJSON() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id

        // Simulate a large JSON string (>2MB)
        let largeJSON = String(repeating: "a", count: 3 * 1024 * 1024)
        vm.currentJSON = largeJSON
        vm.switchViewMode(to: .tree)
        #expect(vm.viewMode == .tree)

        // Switching back to beautify must not be blocked
        vm.switchViewMode(to: .beautify)
        #expect(vm.viewMode == .beautify)
    }

    // MARK: - Search

    @Test("updateSearchResultCount with tree mode")
    func updateSearchResultCountTree() async throws {
        let (vm, _, _, _, _) = makeSUT()

        let root = JSONNode(value: .object([
            "name": .string("test"),
            "value": .number(42)
        ]))
        vm.parseResult = .success(root)
        vm.searchText = "test"
        vm.viewMode = .tree

        vm.updateSearchResultCount()

        // Count is computed on a background thread; give it time to complete
        try await Task.sleep(nanoseconds: 200_000_000)

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

    @MainActor @Test("cachedAllNodes populated after background parse")
    func cachedAllNodesPopulatedAfterParse() async throws {
        let (vm, tabManager, _, parser, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id

        let root = JSONNode(value: .object([
            "a": .object(["nested": .string("val")]),
            "b": .array([.number(1), .number(2)])
        ]))
        parser.parseResult = .success(root)
        parser.formatResult = "{}"
        vm.onNeedShowWindow = {}

        vm.handleTextChange(#"{"a":{},"b":[]}"#)
        try await Task.sleep(nanoseconds: 800_000_000)

        // After parse, cachedAllNodes must contain ALL nodes (including collapsed subtrees)
        #expect(!vm.cachedAllNodes.isEmpty)
        #expect(vm.cachedMaxContentWidth > 0)
        #expect(vm.cachedAllNodeIndexMap.count == vm.cachedAllNodes.count)
    }

    @Test("expandAllNodes sets keyboard nav cache to all visible nodes")
    func expandAllNodesSetsVisibleCache() {
        let (vm, _, _, _, _) = makeSUT()
        // defaultFoldDepth=1: root expanded, children collapsed initially
        let root = JSONNode(value: .object([
            "a": .object(["nested": .string("val")]),
            "b": .array([.number(1), .number(2)])
        ]), defaultFoldDepth: 1)
        vm.parseResult = .success(root)

        vm.expandAllNodes()

        // After expandAll, keyboard nav should reach deep nested nodes.
        // expandAllNodes() rebuilds stale caches inline and pre-sets cachedVisibleNodes.
        vm.selectedNodeId = root.id
        var iterations = 0
        var lastId = root.id
        while iterations < 20 {
            vm.moveSelectionDown()
            guard let current = vm.selectedNodeId else { break }
            if current == lastId { break }
            lastId = current
            iterations += 1
        }
        // Should reach nested nodes (root, "a", nested, "b", [0], [1] = 5 moves minimum)
        #expect(iterations >= 2)
        #expect(vm.lastTreeOperation == .expandAll)
        #expect(vm.treeStructureVersion > 0)
    }

    @Test("collapseAllNodes sets keyboard nav cache to root only")
    func collapseAllNodesSetsVisibleCache() {
        let (vm, _, _, _, _) = makeSUT()
        let root = JSONNode(value: .object([
            "a": .object(["nested": .string("val")])
        ]), defaultFoldDepth: 10)
        vm.parseResult = .success(root)

        vm.collapseAllNodes()

        // After collapseAll, cachedVisibleNodes = [root], so keyboard nav stays at root
        vm.selectedNodeId = nil
        vm.moveSelectionDown()
        #expect(vm.selectedNodeId == root.id)  // first (and only) visible node

        vm.moveSelectionDown()
        #expect(vm.selectedNodeId == root.id)  // still root (no more visible)
        #expect(vm.lastTreeOperation == .collapseAll)
    }

    @Test("expandOrMoveRight resets lastTreeOperation to normal")
    func expandOrMoveRightResetsTreeOperation() {
        let (vm, _, _, _, _) = makeSUT()
        let root = JSONNode(value: .object([
            "a": .object(["nested": .string("val")])
        ]), defaultFoldDepth: 10)
        vm.parseResult = .success(root)

        // Use expandAllNodes() to set lastTreeOperation = .expandAll via public API
        vm.expandAllNodes()
        #expect(vm.lastTreeOperation == .expandAll)

        // Collapse "a" so expandOrMoveRight has something to expand
        let containerNode = root.children[0]
        containerNode.isExpanded = false
        vm.selectedNodeId = containerNode.id
        vm.updateNodeCache(root.allNodes())  // [root, containerNode]

        let versionBefore = vm.treeStructureVersion
        vm.expandOrMoveRight()

        // lastTreeOperation should be reset to .normal before treeStructureVersion increments
        #expect(vm.lastTreeOperation == .normal)
        #expect(vm.treeStructureVersion == versionBefore + 1)
    }

    @Test("collapseOrMoveLeft resets lastTreeOperation to normal")
    func collapseOrMoveLeftResetsTreeOperation() {
        let (vm, _, _, _, _) = makeSUT()
        let root = JSONNode(value: .object([
            "a": .object(["nested": .string("val")])
        ]), defaultFoldDepth: 10)
        vm.parseResult = .success(root)

        // Use collapseAllNodes() to set lastTreeOperation = .collapseAll via public API
        vm.collapseAllNodes()
        #expect(vm.lastTreeOperation == .collapseAll)

        // Re-expand root and "a" so collapseOrMoveLeft has something to collapse
        root.isExpanded = true
        let containerNode = root.children[0]
        containerNode.isExpanded = true
        vm.selectedNodeId = containerNode.id
        vm.updateNodeCache(root.allNodes())  // [root, containerNode, nested]

        let versionBefore = vm.treeStructureVersion
        vm.collapseOrMoveLeft()

        // lastTreeOperation should be reset to .normal
        #expect(vm.lastTreeOperation == .normal)
        #expect(vm.treeStructureVersion == versionBefore + 1)
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

    @Test("onWindowWillClose clears parse state but preserves tabs for session restore")
    func onWindowWillClose() {
        let (vm, tabManager, _, parser, _) = makeSUT()
        parser.parseResult = .success(JSONNode(value: .null))
        vm.onNeedShowWindow = {}
        vm.createNewTab(with: "test")

        vm.onWindowWillClose()

        #expect(vm.currentJSON == nil)
        #expect(vm.parseResult == nil)
        // Tabs are preserved — ⌘Q triggers flush() via AppDelegate, not closeAllTabs()
        #expect(!tabManager.tabs.isEmpty)
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

    // MARK: - Memory Offload (Dehydration / Hydration)

    @Test("dehydrateAfterTabSwitch is called when switching tabs after initial restore")
    func dehydrateAfterTabSwitchCalledOnTabChange() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id1 = tabManager.createTab(with: "tab1")
        let id2 = tabManager.createTab(with: "tab2")
        tabManager.activeTabId = id1

        // Simulate initial load so hasRestoredCurrentTab becomes true
        vm.loadInitialContent()

        // Switch to the second tab
        vm.onActiveTabChanged(oldId: id1, newId: id2)

        #expect(tabManager.dehydrateAfterTabSwitchCallCount == 1)
    }

    @MainActor @Test("restoreTabState calls hydrateTabContent when active tab is dehydrated")
    func restoreTabStateHydratesDehydratedTab() async throws {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: "some json")
        tabManager.activeTabId = id
        // Mark as dehydrated
        tabManager.tabs[0].isHydrated = false

        vm.restoreTabState()
        // Async hydration via Task — wait for completion
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(tabManager.hydrateTabContentCallCount == 1)
    }

    @Test("restoreTabState skips hydrateTabContent when active tab is already hydrated")
    func restoreTabStateSkipsHydrationForHydratedTab() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: "some json")
        tabManager.activeTabId = id
        // Tab is hydrated by default

        vm.restoreTabState()

        #expect(tabManager.hydrateTabContentCallCount == 0)
    }

    @MainActor @Test("restoreTabState triggers background parse for dehydrated tab with prior parse success")
    func restoreTabStateParsesAfterHydration() async throws {
        let (vm, tabManager, _, parser, _) = makeSUT()
        let node = JSONNode(value: .null)
        parser.parseResult = .success(node)

        let id = tabManager.createTab(with: "{}")
        tabManager.activeTabId = id
        // Simulate dehydrated state: no parseResult, but previously succeeded
        tabManager.tabs[0].isHydrated = false
        tabManager.tabs[0].isParseSuccess = true
        tabManager.tabs[0].parseResult = nil

        let parseCountBefore = parser.parseCallCount
        vm.restoreTabState()
        // Async hydration via Task — wait for hydration + parse completion
        try await Task.sleep(nanoseconds: 500_000_000)

        // Background parse should have been triggered
        #expect(parser.parseCallCount > parseCountBefore)
    }

    @MainActor @Test("restoreTabState increments tabGeneration after async hydration so NSTextView updates")
    func restoreTabStateIncrementsTabGenerationAfterHydration() async throws {
        let (vm, tabManager, _, parser, _) = makeSUT()
        let node = JSONNode(value: .null)
        parser.parseResult = .success(node)

        let id = tabManager.createTab(with: "{}")
        tabManager.activeTabId = id
        tabManager.tabs[0].isHydrated = false
        tabManager.tabs[0].isParseSuccess = true
        tabManager.tabs[0].parseResult = nil

        let generationBefore = vm.tabGeneration
        vm.restoreTabState()
        // Wait for async hydration Task to complete
        try await Task.sleep(nanoseconds: 500_000_000)

        // tabGeneration must have increased beyond the initial restoreTabState bump,
        // ensuring NSTextView picks up the restored inputText.
        #expect(vm.tabGeneration > generationBefore + 1)
    }

    @Test("restoreTabState triggers background parse for failed tab with non-empty content")
    func restoreTabStateParsesFailedTabWithContent() {
        let (vm, tabManager, _, parser, _) = makeSUT()
        parser.parseResult = .failure(JSONParseError(message: "bad json"))

        let id = tabManager.createTab(with: "{invalid")
        tabManager.activeTabId = id
        // Simulate previously-failed tab (isParseSuccess == false, no runtime parseResult)
        tabManager.tabs[0].isParseSuccess = false
        tabManager.tabs[0].parseResult = nil

        vm.restoreTabState()

        // Background parse must be triggered so ErrorView is shown (not PlaceholderView).
        // isParsing is set synchronously inside parseInBackground before the detached task runs.
        #expect(vm.isParsing == true)
    }

    @Test("restoreTabState does not parse empty tab regardless of isParseSuccess")
    func restoreTabStateSkipsParseForEmptyTab() {
        let (vm, tabManager, _, _, _) = makeSUT()

        let id = tabManager.createTab(with: "")
        tabManager.activeTabId = id
        tabManager.tabs[0].isParseSuccess = false
        tabManager.tabs[0].parseResult = nil

        vm.restoreTabState()

        // Empty input → no parse triggered, PlaceholderView is correct
        #expect(vm.isParsing == false)
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

    @Test("handleLargeTextPaste increments tabGeneration so updateNSView fires")
    func handleLargeTextPasteIncrementsTabGeneration() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id

        let before = vm.tabGeneration
        let largeText = makeLargeText()
        vm.handleLargeTextPaste(largeText)

        #expect(vm.tabGeneration > before)
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

    @Test("buildLargeInputNotice returns notice without JSON content")
    func buildLargeInputNoticeReturnsNotice() {
        let text = String(repeating: "a", count: 20_000)
        let notice = ViewerViewModel.buildLargeInputNotice(text)

        // Notice should contain size info
        #expect(notice.contains("too large to display"))
        // Notice should not contain the original JSON content
        #expect(!notice.hasPrefix("a"))
        // Notice should be much shorter than original
        #expect(notice.count < text.count)
    }

    @Test("buildLargeInputNotice contains Input editing and Beautify mentions")
    func buildLargeInputNoticeContainsKeywords() {
        let text = String(repeating: "x", count: InputSize.displayThreshold + 1)
        let notice = ViewerViewModel.buildLargeInputNotice(text)

        #expect(notice.contains("Input editing"))
        #expect(notice.contains("Beautify"))
        #expect(notice.contains("Tree view"))
    }

    // MARK: - isLargeJSON

    @Test("isLargeJSON is false initially")
    func isLargeJSONDefaultsFalse() {
        let (vm, _, _, _, _) = makeSUT()
        #expect(vm.isLargeJSON == false)
    }

    @Test("isLargeJSON becomes true after handleLargeTextPaste")
    func isLargeJSONTrueAfterLargeTextPaste() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id

        let largeText = makeLargeText()
        vm.handleLargeTextPaste(largeText)

        #expect(vm.isLargeJSON == true)
    }

    @Test("isLargeJSON becomes false after clearAll")
    func isLargeJSONFalseAfterClearAll() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id

        let largeText = makeLargeText()
        vm.handleLargeTextPaste(largeText)
        #expect(vm.isLargeJSON == true)

        vm.clearAll()
        #expect(vm.isLargeJSON == false)
    }

    @Test("isLargeJSON observation triggers view update")
    func isLargeJSONObservation() {
        let (vm, _, _, _, _) = makeSUT()

        var observed = false
        withObservationTracking {
            _ = vm.isLargeJSON
        } onChange: {
            observed = true
        }

        vm.isLargeJSON = true
        #expect(observed == true)
    }

    @Test("createNewTab with large JSON forces Tree viewMode")
    func createNewTabLargeJSONForcesTreeMode() {
        let largeText = makeLargeText()
        let (vm, _, _, _, _) = makeSUT()
        vm.onNeedShowWindow = {}

        vm.createNewTab(with: largeText)

        #expect(vm.viewMode == .tree)
        #expect(vm.isLargeJSON == true)
    }

    @Test("handleLargeTextPaste forces Tree viewMode")
    func handleLargeTextPasteForcesTreeMode() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id

        // Start in beautify mode
        vm.viewMode = .beautify

        let largeText = makeLargeText()
        vm.handleLargeTextPaste(largeText)

        #expect(vm.viewMode == .tree)
    }

    @Test("restoreTabState forces Tree mode for large JSON tab saved in Beautify mode")
    func restoreTabStateForcesTreeModeForLargeJSON() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let largeText = makeLargeText()
        let truncated = ViewerViewModel.buildLargeInputNotice(largeText)

        // Create a tab that simulates a large JSON tab saved in Beautify mode
        let id = tabManager.createTab(with: truncated)
        tabManager.activeTabId = id
        tabManager.updateTabFullInput(id: id, fullText: largeText)
        tabManager.updateTabViewMode(id: id, viewMode: .beautify)

        vm.restoreTabState()

        #expect(vm.viewMode == .tree)
        #expect(vm.isLargeJSON == true)
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

    // MARK: - isInitialLoading

    @Test("isInitialLoading defaults to false")
    func isInitialLoadingDefaultsFalse() {
        let (vm, _, _, _, _) = makeSUT()
        #expect(vm.isInitialLoading == false)
    }

    @MainActor @Test("isInitialLoading becomes true on first parse success (nil → success)")
    func isInitialLoadingTrueOnFirstParseSuccess() async throws {
        let (vm, tabManager, _, parser, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id

        let node = JSONNode(value: .object(["a": .number(1)]))
        parser.parseResult = .success(node)
        parser.formatResult = #"{"a": 1}"#

        // parseResult is nil before the parse
        #expect(vm.parseResult == nil)

        vm.handleTextChange(#"{"a": 1}"#)

        // Wait for debounce + background parse to complete
        try await Task.sleep(nanoseconds: 800_000_000)

        // isBeautifyRendering is still true (BeautifyView hasn't rendered yet in tests)
        // isInitialLoading should be true while isBeautifyRendering is true after first load
        #expect(vm.isInitialLoading == true)
        #expect(vm.isBeautifyRendering == true)
    }

    @Test("isInitialLoading becomes false when isBeautifyRendering is set to false")
    func isInitialLoadingFalseWhenBeautifyRenderingClears() {
        let (vm, _, _, _, _) = makeSUT()
        vm.isBeautifyRendering = true
        vm.isInitialLoading = true

        vm.isBeautifyRendering = false

        #expect(vm.isInitialLoading == false)
    }

    @MainActor @Test("isInitialLoading stays false on re-parse when parseResult already exists")
    func isInitialLoadingFalseOnReParse() async throws {
        let (vm, tabManager, _, parser, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id

        // Seed an existing parse result (simulates already-loaded tab)
        let existingNode = JSONNode(value: .object(["a": .string("1")]))
        vm.parseResult = .success(existingNode)

        let newNode = JSONNode(value: .object(["b": .string("2")]))
        parser.parseResult = .success(newNode)
        parser.formatResult = #"{"b": "2"}"#

        vm.handleTextChange(#"{"b": "2"}"#)

        try await Task.sleep(nanoseconds: 800_000_000)

        // Re-parse with existing content → isInitialLoading must be false
        #expect(vm.isInitialLoading == false)
    }

    @Test("clearAll resets isInitialLoading")
    func clearAllResetsIsInitialLoading() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id
        vm.isInitialLoading = true
        vm.isBeautifyRendering = true

        vm.clearAll()

        #expect(vm.isInitialLoading == false)
    }

    @Test("onWindowWillClose resets isInitialLoading")
    func onWindowWillCloseResetsIsInitialLoading() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let _ = tabManager.createTab(with: nil)
        vm.isInitialLoading = true

        vm.onWindowWillClose()

        #expect(vm.isInitialLoading == false)
    }

    @Test("restoreTabState resets isInitialLoading")
    func restoreTabStateResetsIsInitialLoading() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id
        vm.isInitialLoading = true

        vm.restoreTabState()

        #expect(vm.isInitialLoading == false)
    }

    @Test("isInitialLoading observation triggers view update")
    func isInitialLoadingObservation() {
        let (vm, _, _, _, _) = makeSUT()

        var observed = false
        withObservationTracking {
            _ = vm.isInitialLoading
        } onChange: {
            observed = true
        }

        vm.isInitialLoading = true
        #expect(observed == true)
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

    // MARK: - isTreeRendering

    @Test("isTreeRendering defaults to false")
    func isTreeRenderingDefaultsFalse() {
        let (vm, _, _, _, _) = makeSUT()
        #expect(vm.isTreeRendering == false)
    }

    @Test("clearAll resets isTreeRendering")
    func clearAllResetsIsTreeRendering() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id
        vm.isTreeRendering = true

        vm.clearAll()

        #expect(vm.isTreeRendering == false)
    }

    @Test("isTreeRendering clears isInitialLoading when set to false")
    func isTreeRenderingClearsIsInitialLoading() {
        let (vm, _, _, _, _) = makeSUT()
        vm.isTreeRendering = true
        vm.isInitialLoading = true

        vm.isTreeRendering = false

        #expect(vm.isInitialLoading == false)
    }

    @Test("isTreeRendering observation triggers view update")
    func isTreeRenderingObservation() {
        let (vm, _, _, _, _) = makeSUT()

        var observed = false
        withObservationTracking {
            _ = vm.isTreeRendering
        } onChange: {
            observed = true
        }

        vm.isTreeRendering = true
        #expect(observed == true)
    }

    // MARK: - isRenamingTab

    @Test("isRenamingTab defaults to false")
    func isRenamingTabDefault() {
        let (vm, _, _, _, _) = makeSUT()
        #expect(vm.isRenamingTab == false)
    }

    @Test("isRenamingTab can be set to true and back to false")
    func isRenamingTabMutable() {
        let (vm, _, _, _, _) = makeSUT()
        vm.isRenamingTab = true
        #expect(vm.isRenamingTab == true)
        vm.isRenamingTab = false
        #expect(vm.isRenamingTab == false)
    }

    // MARK: - tabRenameCommitSignal

    @Test("tabRenameCommitSignal defaults to 0")
    func tabRenameCommitSignalDefault() {
        let (vm, _, _, _, _) = makeSUT()
        #expect(vm.tabRenameCommitSignal == 0)
    }

    @Test("requestCommitTabRename increments signal when renaming")
    func requestCommitTabRenameIncrementsSignal() {
        let (vm, _, _, _, _) = makeSUT()
        vm.isRenamingTab = true

        vm.requestCommitTabRename()

        #expect(vm.tabRenameCommitSignal == 1)
    }

    @Test("requestCommitTabRename is noop when not renaming")
    func requestCommitTabRenameNoopWhenNotRenaming() {
        let (vm, _, _, _, _) = makeSUT()
        // isRenamingTab is false by default

        vm.requestCommitTabRename()

        #expect(vm.tabRenameCommitSignal == 0)
    }

    @Test("tabRenameCommitSignal observation triggers view update")
    func tabRenameCommitSignalObservation() {
        let (vm, _, _, _, _) = makeSUT()
        vm.isRenamingTab = true

        var observed = false
        withObservationTracking {
            _ = vm.tabRenameCommitSignal
        } onChange: {
            observed = true
        }

        vm.requestCommitTabRename()
        #expect(observed == true)
    }

    // MARK: - Tab Generation (Korean IME crash fix)

    @Test("tabGeneration starts at 0")
    func tabGenerationStartsAtZero() {
        let (vm, _, _, _, _) = makeSUT()
        #expect(vm.tabGeneration == 0)
    }

    @Test("createNewTab increments tabGeneration")
    func createNewTabIncrementsGeneration() {
        let (vm, _, _, parser, _) = makeSUT()
        parser.parseResult = .success(JSONNode(value: .null))
        vm.onNeedShowWindow = {}

        let genBefore = vm.tabGeneration
        vm.createNewTab(with: #"{"a":1}"#)

        #expect(vm.tabGeneration == genBefore + 1)
    }

    @Test("createNewTab cancels pending debounce and parse tasks")
    func createNewTabCancelsPendingWork() {
        let (vm, tabManager, _, parser, _) = makeSUT()
        parser.parseResult = .success(JSONNode(value: .null))
        vm.onNeedShowWindow = {}

        // Create a tab and trigger a debounced parse
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id
        vm.handleTextChange(#"{"key":"value"}"#)

        // isParsing should be false (debounce hasn't fired yet)
        // Now create a new tab — should cancel the pending debounce
        vm.createNewTab(with: nil)

        #expect(vm.isParsing == false)
        #expect(vm.isInitialLoading == false)
    }

    @Test("reuseEmptyTab increments tabGeneration")
    func reuseEmptyTabIncrementsGeneration() {
        let (vm, tabManager, _, parser, _) = makeSUT()
        parser.parseResult = .success(JSONNode(value: .null))
        vm.onNeedShowWindow = {}

        // Create an empty tab first
        vm.createNewTab(with: nil)
        let genAfterFirst = vm.tabGeneration

        // Create another tab — should reuse the empty one.
        // tabGeneration increments twice: once in createNewTab, once in the wasAlreadyActive block.
        vm.createNewTab(with: #"{"b":2}"#)

        #expect(vm.tabGeneration == genAfterFirst + 2)
    }

    @Test("onActiveTabChanged increments tabGeneration")
    func onActiveTabChangedIncrementsGeneration() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id1 = tabManager.createTab(with: "tab1")
        let id2 = tabManager.createTab(with: "tab2")
        tabManager.activeTabId = id1
        vm.loadInitialContent()

        let genBefore = vm.tabGeneration
        vm.onActiveTabChanged(oldId: id1, newId: id2)

        #expect(vm.tabGeneration == genBefore + 1)
    }

    @Test("onActiveTabChanged immediately clears parseResult, sets isParsing, and clears currentJSON")
    func onActiveTabChangedClearsContentImmediately() {
        let (vm, tabManager, _, parser, _) = makeSUT()
        parser.parseResult = .success(JSONNode(value: .null))
        let id1 = tabManager.createTab(with: #"{"a":1}"#)
        let id2 = tabManager.createTab(with: #"{"b":2}"#)
        tabManager.activeTabId = id1
        vm.loadInitialContent()

        // Verify state before tab switch
        vm.parseResult = .success(JSONNode(value: .object(["a": .number(1)])))
        vm.currentJSON = #"{"a":1}"#

        vm.onActiveTabChanged(oldId: id1, newId: id2)

        #expect(vm.parseResult == nil)
        #expect(vm.isParsing == true)
        #expect(vm.currentJSON == nil)
        #expect(vm.inputText == "")
        #expect(vm.isTreeRendering == false)
        #expect(vm.isBeautifyRendering == false)
    }

    @Test("restoreTabState increments tabGeneration so updateNSView applies restored inputText")
    func restoreTabStateIncrementsTabGeneration() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: #"{"a":1}"#)
        tabManager.activeTabId = id

        let genBefore = vm.tabGeneration
        vm.restoreTabState()

        #expect(vm.tabGeneration == genBefore + 1)
    }

    @Test("restoreTabState clears isParsing for hydrated tab with parseResult")
    func restoreTabStateClearsIsParsingForHydratedTab() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let node = JSONNode(value: .object(["key": .string("val")]))
        let id = tabManager.createTab(with: #"{"key":"val"}"#)
        tabManager.activeTabId = id
        tabManager.tabs[0].parseResult = .success(node)

        // Simulate state after onActiveTabChanged
        vm.isParsing = true
        vm.parseResult = nil

        vm.restoreTabState()

        #expect(vm.isParsing == false)
        #expect(vm.parseResult != nil)
    }

    @Test("restoreTabState clears isParsing when no active tab")
    func restoreTabStateClearsIsParsingNoTab() {
        let (vm, _, _, _, _) = makeSUT()

        // Simulate state after onActiveTabChanged
        vm.isParsing = true

        vm.restoreTabState()

        #expect(vm.isParsing == false)
    }

    @Test("restoreTabState sets isInitialLoading for large JSON in tree mode")
    func restoreTabStateSetsIsInitialLoadingForLargeJSONTree() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let largeText = String(repeating: "x", count: InputSize.displayThreshold + 1)
        let truncated = ViewerViewModel.buildLargeInputNotice(largeText)
        let node = JSONNode(value: .object(["key": .string("val")]))

        let id = tabManager.createTab(with: truncated)
        tabManager.activeTabId = id
        tabManager.updateTabFullInput(id: id, fullText: largeText)
        tabManager.updateTabViewMode(id: id, viewMode: .tree)
        tabManager.tabs[0].parseResult = .success(node)

        // Simulate state after onActiveTabChanged
        vm.isParsing = true
        vm.parseResult = nil

        vm.restoreTabState()

        #expect(vm.isTreeRendering == true)
        #expect(vm.isInitialLoading == true)
        #expect(vm.isParsing == false)
    }

    @Test("restoreTabState keeps isParsing true for dehydrated tab with content")
    func restoreTabStateKeepsIsParsingForDehydratedTab() {
        let (vm, tabManager, _, parser, _) = makeSUT()
        parser.parseResult = .success(JSONNode(value: .null))

        let id = tabManager.createTab(with: #"{"key":"val"}"#)
        tabManager.activeTabId = id
        tabManager.tabs[0].isHydrated = false
        tabManager.tabs[0].parseResult = nil

        // Simulate state after onActiveTabChanged
        vm.isParsing = true

        vm.restoreTabState()

        // parseInBackground should keep isParsing true
        #expect(vm.isParsing == true)
    }

    // MARK: - isLargeJSONContentLost

    @Test("isLargeJSONContentLost defaults to false")
    func isLargeJSONContentLostDefaultsFalse() {
        let (vm, _, _, _, _) = makeSUT()
        #expect(vm.isLargeJSONContentLost == false)
    }

    @MainActor @Test("restoreTabState sets isLargeJSONContentLost from tab when content is lost")
    func restoreTabStateSetsContentLostFlag() async throws {
        let (vm, tabManager, _, _, _) = makeSUT()
        let largeText = makeLargeText()
        let truncated = ViewerViewModel.buildLargeInputNotice(largeText)

        // Create a tab that simulates lost content: inputText is notice prefix, but no fullInputText
        let id = tabManager.createTab(with: truncated)
        tabManager.activeTabId = id
        tabManager.tabs[0].isParseSuccess = true
        tabManager.tabs[0].isHydrated = false
        // fullInputText is nil — content was lost

        vm.restoreTabState()
        // Async hydration via Task — wait for completion
        try await Task.sleep(nanoseconds: 100_000_000)

        // hydrateTabContent detects lost content and sets isLargeJSONContentLost
        #expect(vm.isLargeJSONContentLost == true)
        #expect(vm.inputText == "")
    }

    @Test("restoreTabState does not set isLargeJSONContentLost for normal tabs")
    func restoreTabStateNoContentLostForNormalTab() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: #"{"key":"val"}"#)
        tabManager.activeTabId = id

        vm.restoreTabState()

        #expect(vm.isLargeJSONContentLost == false)
    }

    @Test("isLargeJSONContentLost resets to false when restoring tab without content loss")
    func isLargeJSONContentLostResetsOnNormalRestore() {
        let (vm, tabManager, _, _, _) = makeSUT()

        // Set up content-lost state
        vm.isLargeJSONContentLost = true

        let id = tabManager.createTab(with: #"{"key":"val"}"#)
        tabManager.activeTabId = id

        vm.restoreTabState()

        // Normal tab restore should clear the flag
        #expect(vm.isLargeJSONContentLost == false)
    }

    @Test("isLargeJSONContentLost resets when no active tab")
    func isLargeJSONContentLostResetsWhenNoTab() {
        let (vm, _, _, _, _) = makeSUT()
        vm.isLargeJSONContentLost = true

        vm.restoreTabState()

        #expect(vm.isLargeJSONContentLost == false)
    }

    @Test("isLargeJSONContentLost observation triggers view update")
    func isLargeJSONContentLostObservation() {
        let (vm, _, _, _, _) = makeSUT()

        var observed = false
        withObservationTracking {
            _ = vm.isLargeJSONContentLost
        } onChange: {
            observed = true
        }

        vm.isLargeJSONContentLost = true
        #expect(observed == true)
    }

    @Test("multiple createNewTab calls monotonically increase tabGeneration")
    func multipleCreateNewTabIncrementsGeneration() {
        let (vm, _, _, parser, _) = makeSUT()
        parser.parseResult = .success(JSONNode(value: .null))
        vm.onNeedShowWindow = {}

        vm.createNewTab(with: #"{"a":1}"#)
        let gen1 = vm.tabGeneration

        vm.createNewTab(with: #"{"b":2}"#)
        let gen2 = vm.tabGeneration

        vm.createNewTab(with: #"{"c":3}"#)
        let gen3 = vm.tabGeneration

        #expect(gen1 < gen2)
        #expect(gen2 < gen3)
    }

    // MARK: - Large JSON SBBOD Fixes

    @MainActor @Test("parseInBackground sets formattedJSON to nil for large JSON")
    func parseInBackgroundSkipsFormatForLargeJSON() async throws {
        let (vm, _, _, parser, _) = makeSUT()
        let largeJSON = String(repeating: "{\"key\":\"value\"}", count: 50_000)  // > 512KB
        let node = JSONNode(value: .object(["key": .string("value")]))
        parser.parseResult = .success(node)
        vm.onNeedShowWindow = {}

        vm.createNewTab(with: largeJSON)

        // Wait for background parse to complete
        try await Task.sleep(nanoseconds: 300_000_000)

        #expect(vm.isLargeJSON == true)
        #expect(vm.formattedJSON == nil)
    }

    @MainActor @Test("restoreTabState sets formattedJSON to nil for large JSON tab")
    func restoreTabStateNilsFormattedJSONForLargeJSON() {
        let (vm, tabManager, _, _, _) = makeSUT()
        let largeText = makeLargeText()
        let truncated = ViewerViewModel.buildLargeInputNotice(largeText)

        let id = tabManager.createTab(with: truncated)
        tabManager.activeTabId = id
        tabManager.updateTabFullInput(id: id, fullText: largeText)
        tabManager.updateTabParseResult(id: id, result: .success(JSONNode(value: .object([:]))))

        vm.restoreTabState()

        #expect(vm.isLargeJSON == true)
        #expect(vm.formattedJSON == nil)
    }

    @MainActor @Test("restoreTabState rebuilds formattedJSON asynchronously for normal JSON tab")
    func restoreTabStateRebuildsFormattedJSONForNormalJSON() async throws {
        let (vm, tabManager, _, parser, _) = makeSUT()
        let json = #"{"name": "test"}"#
        let node = JSONNode(value: .object(["name": .string("test")]))
        parser.formatResult = "formatted output"

        let id = tabManager.createTab(with: json)
        tabManager.activeTabId = id
        tabManager.updateTabParseResult(id: id, result: .success(node))

        vm.restoreTabState()

        // formattedJSON may be nil initially (async rebuild)
        // Wait for async format task to complete
        try await Task.sleep(nanoseconds: 300_000_000)

        #expect(vm.formattedJSON == "formatted output")
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

// MARK: - Compare Mode Tests

@Suite("ViewerViewModel Compare Tests")
@MainActor
struct ViewerViewModelCompareTests {

    private func makeSUT(
        clipboardText: String? = nil
    ) -> (vm: ViewerViewModel, tabManager: MockTabManager, clipboard: MockClipboardService, parser: MockJSONParser, windowManager: MockWindowManager, diffEngine: MockJSONDiffEngine) {
        let tabManager = MockTabManager()
        let clipboard = MockClipboardService()
        clipboard.storedText = clipboardText
        let parser = MockJSONParser()
        let windowManager = MockWindowManager()
        let diffEngine = MockJSONDiffEngine()

        let vm = ViewerViewModel(
            tabManager: tabManager,
            clipboardService: clipboard,
            jsonParser: parser,
            windowManager: windowManager,
            diffEngine: diffEngine
        )

        return (vm, tabManager, clipboard, parser, windowManager, diffEngine)
    }

    @Test("switchViewMode to compare sets viewMode")
    func switchToCompare() {
        let (vm, tabManager, _, _, _, _) = makeSUT()
        tabManager.activeTabId = UUID()
        vm.switchViewMode(to: .compare)
        #expect(vm.viewMode == .compare)
    }

    @Test("switchViewMode to compare copies inputText to left panel when empty")
    func switchToCompareCopiesInput() {
        let (vm, tabManager, _, _, _, _) = makeSUT()
        tabManager.activeTabId = UUID()
        vm.inputText = "{\"key\": \"value\"}"
        vm.switchViewMode(to: .compare)
        #expect(vm.compareLeftText == "{\"key\": \"value\"}")
    }

    @Test("switchViewMode to compare does not overwrite existing left text")
    func switchToComparePreservesExistingLeft() {
        let (vm, tabManager, _, _, _, _) = makeSUT()
        tabManager.activeTabId = UUID()
        vm.compareLeftText = "{\"existing\": true}"
        vm.inputText = "{\"new\": false}"
        vm.switchViewMode(to: .compare)
        #expect(vm.compareLeftText == "{\"existing\": true}")
    }

    @Test("switchViewMode from compare to beautify preserves compare state")
    func switchFromComparePreservesState() {
        let (vm, tabManager, _, _, _, _) = makeSUT()
        tabManager.activeTabId = UUID()
        vm.switchViewMode(to: .compare)
        vm.compareLeftText = "{\"left\": 1}"
        vm.compareRightText = "{\"right\": 2}"
        vm.switchViewMode(to: .beautify)
        #expect(vm.viewMode == .beautify)
        // Compare text should still be retained for when user switches back
        #expect(vm.compareLeftText == "{\"left\": 1}")
        #expect(vm.compareRightText == "{\"right\": 2}")
    }

    @Test("clearCompareLeft clears left text and parse result")
    func clearCompareLeft() {
        let (vm, _, _, _, _, _) = makeSUT()
        vm.compareLeftText = "{\"test\": 1}"
        vm.clearCompareLeft()
        #expect(vm.compareLeftText == "")
        #expect(vm.compareLeftParseResult == nil)
    }

    @Test("clearCompareLeft increments compareLeftGeneration")
    func clearCompareLeftIncrementsGeneration() {
        let (vm, _, _, _, _, _) = makeSUT()
        let before = vm.compareLeftGeneration
        vm.compareLeftText = "{\"test\": 1}"
        vm.clearCompareLeft()
        #expect(vm.compareLeftGeneration == before + 1)
    }

    @Test("clearCompareRight clears right text and parse result")
    func clearCompareRight() {
        let (vm, _, _, _, _, _) = makeSUT()
        vm.compareRightText = "{\"test\": 1}"
        vm.clearCompareRight()
        #expect(vm.compareRightText == "")
        #expect(vm.compareRightParseResult == nil)
    }

    @Test("clearCompareRight increments compareRightGeneration")
    func clearCompareRightIncrementsGeneration() {
        let (vm, _, _, _, _, _) = makeSUT()
        let before = vm.compareRightGeneration
        vm.compareRightText = "{\"test\": 1}"
        vm.clearCompareRight()
        #expect(vm.compareRightGeneration == before + 1)
    }

    @Test("updateCompareOption toggles ignoreKeyOrder")
    func updateCompareOptionIgnoreKeyOrder() {
        let (vm, _, _, _, _, _) = makeSUT()
        let initial = vm.compareIgnoreKeyOrder
        vm.updateCompareOption(ignoreKeyOrder: !initial)
        #expect(vm.compareIgnoreKeyOrder == !initial)
    }

    @Test("updateCompareOption toggles ignoreArrayOrder")
    func updateCompareOptionIgnoreArrayOrder() {
        let (vm, _, _, _, _, _) = makeSUT()
        let initial = vm.compareIgnoreArrayOrder
        vm.updateCompareOption(ignoreArrayOrder: !initial)
        #expect(vm.compareIgnoreArrayOrder == !initial)
    }

    @Test("updateCompareOption toggles strictType")
    func updateCompareOptionStrictType() {
        let (vm, _, _, _, _, _) = makeSUT()
        let initial = vm.compareStrictType
        vm.updateCompareOption(strictType: !initial)
        #expect(vm.compareStrictType == !initial)
    }

    @Test("handleHotKey in compare mode routes text to left panel when empty")
    func handleHotKeyCompareLeftEmpty() {
        let (vm, tabManager, clipboard, _, windowManager, _) = makeSUT(clipboardText: "{\"hot\": \"key\"}")
        tabManager.activeTabId = UUID()
        windowManager.isViewerOpen = true
        vm.switchViewMode(to: .compare)

        vm.handleHotKey()

        #expect(vm.compareLeftText == "{\"hot\": \"key\"}")
    }

    @Test("handleHotKey in compare mode routes text to right panel when left is filled")
    func handleHotKeyCompareRightEmpty() {
        let (vm, tabManager, clipboard, _, windowManager, _) = makeSUT(clipboardText: "{\"right\": true}")
        tabManager.activeTabId = UUID()
        windowManager.isViewerOpen = true
        vm.switchViewMode(to: .compare)
        vm.compareLeftText = "{\"left\": true}"

        vm.handleHotKey()

        #expect(vm.compareRightText == "{\"right\": true}")
    }

    @Test("handleHotKey in compare mode stores pending text when both panels filled")
    func handleHotKeyCompareBothFilled() {
        let (vm, tabManager, _, _, windowManager, _) = makeSUT(clipboardText: "{\"pending\": true}")
        tabManager.activeTabId = UUID()
        windowManager.isViewerOpen = true
        vm.switchViewMode(to: .compare)
        vm.compareLeftText = "{\"left\": true}"
        vm.compareRightText = "{\"right\": true}"

        vm.handleHotKey()

        // Both panels still have original text
        #expect(vm.compareLeftText == "{\"left\": true}")
        #expect(vm.compareRightText == "{\"right\": true}")
    }

    @Test("compareLeftText observation triggers view update")
    func compareLeftTextObservation() {
        let (vm, _, _, _, _, _) = makeSUT()

        var observed = false
        withObservationTracking {
            _ = vm.compareLeftText
        } onChange: {
            observed = true
        }

        vm.compareLeftText = "{\"new\": 1}"
        #expect(observed == true)
    }

    @Test("compareRightText observation triggers view update")
    func compareRightTextObservation() {
        let (vm, _, _, _, _, _) = makeSUT()

        var observed = false
        withObservationTracking {
            _ = vm.compareRightText
        } onChange: {
            observed = true
        }

        vm.compareRightText = "{\"new\": 2}"
        #expect(observed == true)
    }

    @Test("compareDiffResult observation triggers view update")
    func compareDiffResultObservation() {
        let (vm, _, _, _, _, _) = makeSUT()

        var observed = false
        withObservationTracking {
            _ = vm.compareDiffResult
        } onChange: {
            observed = true
        }

        vm.compareDiffResult = CompareDiffResult(items: [])
        #expect(observed == true)
    }

    @Test("restoreTabState increments both compare generations")
    func restoreTabStateIncrementsCompareGenerations() {
        let (vm, tabManager, _, _, _, _) = makeSUT()
        tabManager.activeTabId = UUID()
        let leftBefore = vm.compareLeftGeneration
        let rightBefore = vm.compareRightGeneration

        vm.restoreTabState()

        #expect(vm.compareLeftGeneration == leftBefore + 1)
        #expect(vm.compareRightGeneration == rightBefore + 1)
    }

    @Test("handleHotKeyInCompareMode increments left generation when left is empty")
    func handleHotKeyInCompareModeLeftGeneration() {
        let (vm, _, _, _, _, _) = makeSUT()
        vm.compareLeftText = ""
        vm.compareRightText = ""
        let leftBefore = vm.compareLeftGeneration
        let rightBefore = vm.compareRightGeneration

        vm.handleHotKeyInCompareMode("{\"a\": 1}")

        #expect(vm.compareLeftGeneration == leftBefore + 1)
        #expect(vm.compareRightGeneration == rightBefore)
    }

    @Test("handleHotKeyInCompareMode increments right generation when left is filled")
    func handleHotKeyInCompareModeRightGeneration() {
        let (vm, _, _, _, _, _) = makeSUT()
        vm.compareLeftText = "{\"a\": 1}"
        vm.compareRightText = ""
        let leftBefore = vm.compareLeftGeneration
        let rightBefore = vm.compareRightGeneration

        vm.handleHotKeyInCompareMode("{\"b\": 2}")

        #expect(vm.compareLeftGeneration == leftBefore)
        #expect(vm.compareRightGeneration == rightBefore + 1)
    }

    // MARK: - Compare Large JSON Blocking

    private func makeLargeJSON() -> String {
        // Valid JSON that exceeds InputSize.displayThreshold (512KB)
        let value = String(repeating: "x", count: InputSize.displayThreshold + 1)
        return "{\"key\": \"\(value)\"}"
    }

    @Test("switchViewMode to compare is blocked when isLargeJSON")
    func switchViewModeToCompareBlockedForLargeJSON() {
        let (vm, tabManager, _, _, _, _) = makeSUT()
        let tabId = tabManager.createTab(with: "large")
        tabManager.updateTabFullInput(id: tabId, fullText: makeLargeJSON())
        vm.restoreTabState()
        vm.viewMode = .tree

        vm.switchViewMode(to: .compare)

        #expect(vm.viewMode == .tree)
    }

    @Test("handleCompareLargeTextPaste shows alert")
    func handleCompareLargeTextPasteShowsAlert() {
        let (vm, _, _, _, _, _) = makeSUT()

        vm.handleCompareLargeTextPaste(makeLargeJSON())

        #expect(vm.showCompareLargeJSONAlert == true)
    }

    @Test("confirmCompareLargeJSONNewTab creates tab and dismisses alert")
    func confirmCompareLargeJSONNewTabCreatesTab() {
        let (vm, tabManager, _, _, _, _) = makeSUT()
        let initialCount = tabManager.tabs.count
        vm.handleCompareLargeTextPaste(makeLargeJSON())

        vm.confirmCompareLargeJSONNewTab()

        #expect(tabManager.tabs.count == initialCount + 1)
        #expect(vm.showCompareLargeJSONAlert == false)
    }

    @Test("cancelCompareLargeJSONAlert dismisses without changes")
    func cancelCompareLargeJSONAlertDismissesCleanly() {
        let (vm, tabManager, _, _, _, _) = makeSUT()
        let initialCount = tabManager.tabs.count
        vm.handleCompareLargeTextPaste(makeLargeJSON())

        vm.cancelCompareLargeJSONAlert()

        #expect(tabManager.tabs.count == initialCount)
    }

    @Test("handleHotKeyInCompareMode with large JSON opens new tab")
    func handleHotKeyInCompareModeLargeOpensNewTab() {
        let (vm, tabManager, _, _, _, _) = makeSUT()
        vm.compareLeftText = ""
        vm.compareRightText = ""
        let initialCount = tabManager.tabs.count
        let largeJSON = makeLargeJSON()

        vm.handleHotKeyInCompareMode(largeJSON)

        // Large JSON should create a new tab, not fill compare panels
        #expect(tabManager.tabs.count == initialCount + 1)
        #expect(vm.compareLeftText == "")
        #expect(vm.compareRightText == "")
    }

    @Test("restoreTabState forces tree mode for large JSON in compare")
    func restoreTabStateForcesTreeForLargeCompare() {
        let (vm, tabManager, _, _, _, _) = makeSUT()
        let largeJSON = makeLargeJSON()
        let tabId = tabManager.createTab(with: "display")
        tabManager.updateTabFullInput(id: tabId, fullText: largeJSON)
        tabManager.updateTabViewMode(id: tabId, viewMode: .compare)

        vm.restoreTabState()

        #expect(vm.viewMode == .tree)
    }

    @Test("showCompareLargeJSONAlert triggers observation")
    func showCompareLargeJSONAlertTriggersObservation() {
        let (vm, _, _, _, _, _) = makeSUT()
        var observed = false

        withObservationTracking {
            _ = vm.showCompareLargeJSONAlert
        } onChange: {
            observed = true
        }

        vm.showCompareLargeJSONAlert = true
        #expect(observed)
    }

    // MARK: - suppressNodeCacheRebuild

    @MainActor @Test("restoreTabState skips rebuildNodeCache for hydrated tabs")
    func restoreTabStateSkipsRebuildNodeCache() async throws {
        let (vm, tabManager, _, _, _, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id

        // Set up a parsed tab with a known root node
        let root = JSONNode(value: .object([
            "a": .string("1"),
            "b": .string("2")
        ]), defaultFoldDepth: 10)
        vm.parseResult = .success(root)
        vm.inputText = #"{"a":"1","b":"2"}"#
        // saveTabState doesn't save parseResult — must set it on tab directly
        tabManager.updateTabParseResult(id: id, result: .success(root))
        vm.saveTabState(for: id)

        // Create and switch to a second tab
        let _ = tabManager.createTab(with: nil)
        vm.parseResult = nil

        // Switch back to the first tab
        tabManager.activeTabId = id
        vm.restoreTabState()
        // Allow DispatchQueue.main.async to complete
        try await Task.sleep(nanoseconds: 100_000_000)

        // parseResult should be restored from tab
        #expect(vm.parseResult != nil, "parseResult should be restored after restoreTabState")

        // Keyboard nav should NOT work because suppressNodeCacheRebuild skipped
        // rebuildNodeCache — cachedVisibleNodes is empty until TreeView populates it.
        vm.selectedNodeId = nil
        vm.moveSelectionDown()
        #expect(vm.selectedNodeId == nil)

        // After TreeView provides visible nodes via updateNodeCache, nav should work
        if case .success(let restoredRoot) = vm.parseResult {
            vm.updateNodeCache(restoredRoot.allNodes())
            vm.moveSelectionDown()
            #expect(vm.selectedNodeId == restoredRoot.id)
        }
    }

    @MainActor @Test("parseInBackground pre-computes visible nodes on background thread")
    func parseInBackgroundPreComputesVisibleNodes() async throws {
        let (vm, tabManager, _, parser, _, _) = makeSUT()
        let id = tabManager.createTab(with: nil)
        tabManager.activeTabId = id

        let root = JSONNode(value: .object([
            "a": .object(["nested": .string("val")]),
            "b": .array([.number(1), .number(2)])
        ]))
        parser.parseResult = .success(root)
        parser.formatResult = "{}"
        vm.onNeedShowWindow = {}

        vm.handleTextChange(#"{"a":{},"b":[]}"#)
        try await Task.sleep(nanoseconds: 800_000_000)

        // After background parse, keyboard nav should work immediately because
        // parseInBackground pre-computed visible nodes and set cachedVisibleNodes directly.
        if case .success(let parsedRoot) = vm.parseResult {
            vm.selectedNodeId = parsedRoot.id
            vm.moveSelectionDown()
            #expect(vm.selectedNodeId != parsedRoot.id)
        }
    }
}
#endif
