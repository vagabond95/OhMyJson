//
//  ViewerViewModel.swift
//  OhMyJson
//
//  Extracted from ViewerWindow.swift — owns active tab UI state and business logic.
//  Created by AppDelegate, injected into Views via .environmentObject().
//

#if os(macOS)
import Foundation
import SwiftUI
import Combine

@Observable
class ViewerViewModel {

    // MARK: - Service Dependencies

    private let tabManager: TabManagerProtocol
    private let clipboardService: ClipboardServiceProtocol
    private let jsonParser: JSONParserProtocol
    private let windowManager: WindowManagerProtocol

    // MARK: - Active Tab UI State (moved from ViewerWindow @State)

    var inputText: String = ""
    var searchText: String = ""
    var selectedNodeId: UUID?
    var treeScrollAnchorId: UUID?
    var beautifySearchIndex: Int = 0
    var treeSearchIndex: Int = 0
    var searchResultCount: Int = 0
    var searchNavigationVersion: Int = 0
    var isSearchVisible: Bool = false
    var viewMode: ViewMode = .beautify
    var beautifySearchDismissed: Bool = false
    var treeSearchDismissed: Bool = false

    var inputScrollPosition: CGFloat = 0
    var beautifyScrollPosition: CGFloat = 0
    var treeHorizontalScrollOffset: CGFloat = 0

    // MARK: - Transient UI State (moved from ViewerWindow @State)

    var showLargeFileWarning: Bool = false
    var isRestoringTabState: Bool = false
    var isCheatSheetVisible: Bool = false

    // MARK: - Tree Structure Version (incremented on expand/collapse from ViewModel)

    var treeStructureVersion: Int = 0

    // MARK: - Confetti

    var confettiCounter: Int = 0

    // MARK: - Data State (moved from WindowManager)

    var currentJSON: String? {
        didSet {
            guard !suppressFormatOnSet else { return }
            if let json = currentJSON {
                _formattedJSONCache = jsonParser.formatJSON(json, indentSize: AppSettings.shared.jsonIndent)
            } else {
                _formattedJSONCache = nil
            }
        }
    }
    var parseResult: JSONParseResult? {
        didSet {
            rebuildNodeCache()
        }
    }
    var isParsing: Bool = false

    private var _formattedJSONCache: String?
    var formattedJSON: String? { _formattedJSONCache }

    // MARK: - Internal State

    @ObservationIgnored private var debounceTask: DispatchWorkItem?
    @ObservationIgnored private let debounceInterval: TimeInterval = Timing.parseDebounce
    @ObservationIgnored private var parseTask: Task<Void, Never>?
    @ObservationIgnored private var suppressFormatOnSet: Bool = false

    @ObservationIgnored private var restoreTask: DispatchWorkItem?
    @ObservationIgnored private var hasRestoredCurrentTab: Bool = false
    @ObservationIgnored private let restoreDebounceInterval: TimeInterval = Timing.tabRestoreDebounce

    @ObservationIgnored private let largeFileSizeThreshold = FileSize.largeThreshold

    @ObservationIgnored private var indentCancellable: AnyCancellable?

    // MARK: - Node Cache (for O(1) keyboard navigation)

    @ObservationIgnored private var cachedVisibleNodes: [JSONNode] = []
    @ObservationIgnored private var nodeIndexMap: [UUID: Int] = [:]

    /// Callback for when ViewModel needs to show the window (set by AppDelegate)
    @ObservationIgnored var onNeedShowWindow: (() -> Void)?

    deinit {
        debounceTask?.cancel()
        restoreTask?.cancel()
        parseTask?.cancel()
        indentCancellable = nil
        onNeedShowWindow = nil
    }

    // MARK: - Computed

    var currentSearchIndex: Int {
        get { viewMode == .beautify ? beautifySearchIndex : treeSearchIndex }
        set {
            if viewMode == .beautify {
                beautifySearchIndex = newValue
            } else {
                treeSearchIndex = newValue
            }
        }
    }

    /// Expose tabs for View binding
    var tabs: [JSONTab] {
        tabManager.tabs
    }

    var activeTabId: UUID? {
        get { tabManager.activeTabId }
        set { tabManager.activeTabId = newValue }
    }

    var activeTab: JSONTab? {
        tabManager.activeTab
    }

    var maxTabs: Int { tabManager.maxTabs }
    var warningThreshold: Int { tabManager.warningThreshold }

    // MARK: - Init

    init(
        tabManager: TabManagerProtocol,
        clipboardService: ClipboardServiceProtocol,
        jsonParser: JSONParserProtocol,
        windowManager: WindowManagerProtocol
    ) {
        self.tabManager = tabManager
        self.clipboardService = clipboardService
        self.jsonParser = jsonParser
        self.windowManager = windowManager

        // Observe indent changes via Combine to refresh formatted JSON cache
        indentCancellable = AppSettings.shared.jsonIndentChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newIndent in
                guard let self, let json = self.currentJSON else { return }
                self._formattedJSONCache = self.jsonParser.formatJSON(json, indentSize: newIndent)
            }
    }

    // MARK: - HotKey Handling (moved from AppDelegate)

    func handleHotKey() {
        guard let clipboardText = clipboardService.readText(), !clipboardText.isEmpty else {
            createNewTab(with: nil)
            return
        }

        let trimmed = clipboardText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            createNewTab(with: nil)
            return
        }

        // Check size (5MB limit)
        let sizeInBytes = trimmed.utf8.count
        let sizeInMB = Double(sizeInBytes) / Double(FileSize.megabyte)

        if sizeInMB > 5.0 {
            showSizeConfirmationDialog(size: sizeInMB, text: trimmed)
            return
        }

        // Lightweight validation (no JSONNode tree construction)
        if jsonParser.validateJSON(trimmed) {
            createNewTab(with: trimmed)
        } else {
            ToastManager.shared.show(String(localized: "toast.invalid_json"), duration: Duration.toastLong)
            if windowManager.isViewerOpen {
                windowManager.bringToFront()
            }
        }
    }

    private func showSizeConfirmationDialog(size: Double, text: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "alert.large_json.title")
        alert.informativeText = String(format: String(localized: "alert.large_json.message"), size)
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "alert.large_json.continue"))
        alert.addButton(withTitle: String(localized: "alert.large_json.cancel"))

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            createNewTab(with: text)
        }
    }

    // MARK: - Tab Creation (mediator: TabManager + WindowManager + Toast)

    func createNewTab(with jsonString: String?) {
        // If the last tab has an empty input, reuse it instead of creating a new tab
        if let lastTab = tabManager.tabs.last,
           lastTab.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reuseEmptyTab(lastTab, with: jsonString)
            return
        }

        // LRU check — ViewModel mediates
        if tabManager.tabs.count >= tabManager.maxTabs {
            if let oldestTabId = tabManager.getOldestTab() {
                tabManager.closeTab(id: oldestTabId)
                ToastManager.shared.show("Oldest tab auto-closed", duration: Duration.toastLong)
            }
        } else if tabManager.tabs.count >= tabManager.warningThreshold {
            ToastManager.shared.show("Too many tabs open. Please close unused tabs", duration: Duration.toastLong)
        }

        // Create tab immediately (no synchronous parse)
        let tabId = tabManager.createTab(with: jsonString)

        // Show / bring window to front
        if !windowManager.isViewerOpen {
            onNeedShowWindow?()
        } else {
            windowManager.bringToFront()
        }

        // Update ViewModel data state (suppress formatJSON — background parse will provide it)
        suppressFormatOnSet = true
        currentJSON = jsonString
        suppressFormatOnSet = false
        parseResult = nil

        // Start background parse if JSON provided
        if let json = jsonString {
            parseInBackground(json: json, tabId: tabId)
        }
    }

    private func reuseEmptyTab(_ tab: JSONTab, with jsonString: String?) {
        let wasAlreadyActive = (activeTabId == tab.id)

        // Update tab input if JSON provided (no synchronous parse)
        if let json = jsonString {
            tabManager.updateTabInput(id: tab.id, text: json)
        }

        // Select the tab (marks as accessed, triggers tab change if needed)
        tabManager.selectTab(id: tab.id)

        // Show / bring window to front
        if !windowManager.isViewerOpen {
            onNeedShowWindow?()
        } else {
            windowManager.bringToFront()
        }

        // Update ViewModel data state (suppress formatJSON — background parse will provide it)
        suppressFormatOnSet = true
        currentJSON = jsonString
        suppressFormatOnSet = false
        parseResult = nil

        // If this tab was already active, manually restore inputText
        // (selectTab won't trigger onActiveTabChanged for same tab)
        if wasAlreadyActive {
            isRestoringTabState = true
            inputText = jsonString ?? ""
            DispatchQueue.main.async { [weak self] in
                self?.isRestoringTabState = false
            }
        }

        // Start background parse if JSON provided
        if let json = jsonString {
            parseInBackground(json: json, tabId: tab.id)
        }
    }

    // MARK: - Tab Close (mediator: TabManager + WindowManager)

    func closeTab(id: UUID) {
        // If this is the last tab, close the window
        if tabManager.tabs.count == 1 {
            windowManager.closeViewer()
            return
        }

        tabManager.closeTab(id: id)
    }

    // MARK: - Tab Navigation

    func selectTab(id: UUID) {
        tabManager.selectTab(id: id)
    }

    func selectPreviousTab() {
        tabManager.selectPreviousTab()
    }

    func selectNextTab() {
        tabManager.selectNextTab()
    }

    func closeAllTabs() {
        tabManager.closeAllTabs()
    }

    func getTabIndex(id: UUID) -> Int {
        tabManager.getTabIndex(id: id)
    }

    // MARK: - Text Change Handling (moved from ViewerWindow)

    func handleTextChange(_ text: String) {
        guard !isRestoringTabState else { return }
        guard let activeTabId = tabManager.activeTabId else { return }

        tabManager.updateTabInput(id: activeTabId, text: text)

        debounceTask?.cancel()
        parseTask?.cancel()

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty {
            isParsing = false
            tabManager.updateTabParseResult(id: activeTabId, result: .success(JSONNode(key: nil, value: .null)))
            parseResult = nil
            currentJSON = nil
            return
        }

        let task = DispatchWorkItem { [weak self] in
            self?.parseAndUpdateJSON(text: text, activeTabId: activeTabId)
        }
        debounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: task)
    }

    private func parseAndUpdateJSON(text: String, activeTabId: UUID) {
        parseInBackground(json: text, tabId: activeTabId, resetScrollState: true)
    }

    /// Shared background parsing: runs parse + formatJSON off the main thread,
    /// then applies results on MainActor.
    private func parseInBackground(json: String, tabId: UUID, resetScrollState: Bool = false) {
        parseTask?.cancel()
        isParsing = true

        let parser = self.jsonParser
        let indentSize = AppSettings.shared.jsonIndent

        parseTask = Task.detached { [weak self] in
            let result = parser.parse(json)
            guard !Task.isCancelled else { return }

            let formatted: String?
            if case .success = result {
                formatted = parser.formatJSON(json, indentSize: indentSize)
            } else {
                formatted = nil
            }
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self else { return }
                guard !Task.isCancelled else {
                    self.isParsing = false
                    return
                }
                guard self.tabManager.activeTabId == tabId else {
                    self.isParsing = false
                    return
                }

                self.tabManager.updateTabParseResult(id: tabId, result: result)

                switch result {
                case .success(let node):
                    self.parseResult = .success(node)
                    self.suppressFormatOnSet = true
                    self.currentJSON = json
                    self._formattedJSONCache = formatted
                    self.suppressFormatOnSet = false
                case .failure(let error):
                    self.parseResult = .failure(error)
                    self.suppressFormatOnSet = true
                    self.currentJSON = nil
                    self.suppressFormatOnSet = false
                }

                self.isParsing = false

                if resetScrollState {
                    self.beautifyScrollPosition = 0
                    self.treeHorizontalScrollOffset = 0
                    self.selectedNodeId = nil
                    self.treeScrollAnchorId = nil
                    self.tabManager.updateTabScrollPosition(id: tabId, position: 0)
                    self.tabManager.updateTabTreeSelectedNodeId(id: tabId, nodeId: nil)
                    self.tabManager.updateTabTreeScrollAnchor(id: tabId, nodeId: nil)
                    self.tabManager.updateTabTreeHorizontalScroll(id: tabId, offset: 0)
                }

                if self.viewMode == .beautify {
                    self.updateSearchResultCountForBeautify()
                } else {
                    self.updateSearchResultCount()
                }
            }
        }
    }

    // MARK: - Tab State Management (moved from ViewerWindow)

    func loadInitialContent() {
        restoreTabState()
        hasRestoredCurrentTab = true
    }

    func onActiveTabChanged(oldId: UUID?, newId: UUID?) {
        if let oldId = oldId, hasRestoredCurrentTab {
            saveTabState(for: oldId)
        }
        hasRestoredCurrentTab = false

        restoreTask?.cancel()

        let task = DispatchWorkItem { [weak self] in
            self?.restoreTabState()
            self?.hasRestoredCurrentTab = true
        }
        restoreTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDebounceInterval, execute: task)
    }

    func saveTabState(for tabId: UUID) {
        tabManager.updateTabSearchState(
            id: tabId,
            searchText: searchText,
            beautifySearchIndex: beautifySearchIndex,
            treeSearchIndex: treeSearchIndex
        )
        tabManager.updateTabViewMode(id: tabId, viewMode: viewMode)
        tabManager.updateTabSearchVisibility(id: tabId, isVisible: isSearchVisible)
        tabManager.updateTabInputScrollPosition(id: tabId, position: inputScrollPosition)
        tabManager.updateTabScrollPosition(id: tabId, position: beautifyScrollPosition)
        tabManager.updateTabTreeSelectedNodeId(id: tabId, nodeId: selectedNodeId)
        tabManager.updateTabTreeScrollAnchor(id: tabId, nodeId: treeScrollAnchorId)
        tabManager.updateTabTreeHorizontalScroll(id: tabId, offset: treeHorizontalScrollOffset)
        tabManager.updateTabSearchDismissState(id: tabId, beautifyDismissed: beautifySearchDismissed, treeDismissed: treeSearchDismissed)
    }

    func restoreTabState() {
        isRestoringTabState = true

        guard let activeTab = tabManager.activeTab else {
            inputText = ""
            parseResult = nil
            currentJSON = nil
            searchText = ""
            beautifySearchIndex = 0
            treeSearchIndex = 0
            searchResultCount = 0
            isSearchVisible = false
            viewMode = .beautify
            inputScrollPosition = 0
            beautifyScrollPosition = 0
            treeHorizontalScrollOffset = 0
            selectedNodeId = nil
            treeScrollAnchorId = nil
            beautifySearchDismissed = false
            treeSearchDismissed = false
            isRestoringTabState = false
            return
        }

        inputText = activeTab.inputText
        parseResult = activeTab.parseResult
        currentJSON = activeTab.inputText.isEmpty ? nil : activeTab.inputText

        searchText = activeTab.searchText
        beautifySearchIndex = activeTab.beautifySearchIndex
        treeSearchIndex = activeTab.treeSearchIndex

        isSearchVisible = activeTab.isSearchVisible
        viewMode = activeTab.viewMode

        inputScrollPosition = activeTab.inputScrollPosition
        beautifyScrollPosition = activeTab.beautifyScrollPosition
        treeHorizontalScrollOffset = activeTab.treeHorizontalScrollOffset
        selectedNodeId = activeTab.treeSelectedNodeId
        treeScrollAnchorId = activeTab.treeScrollAnchorId
        beautifySearchDismissed = activeTab.beautifySearchDismissed
        treeSearchDismissed = activeTab.treeSearchDismissed

        if viewMode == .beautify {
            updateSearchResultCountForBeautify()
        } else {
            updateSearchResultCount()
        }

        DispatchQueue.main.async { [weak self] in
            self?.isRestoringTabState = false
        }
    }

    // MARK: - Search (moved from ViewerWindow)

    func updateSearchResultCount() {
        guard case .success(let rootNode) = parseResult else {
            searchResultCount = 0
            return
        }

        if searchText.isEmpty {
            searchResultCount = 0
        } else {
            // Count matches at JSONValue level — no JSONNode materialization needed
            searchResultCount = rootNode.value.countMatches(
                key: rootNode.key,
                query: searchText.lowercased(),
                ignoreEscapeSequences: AppSettings.shared.ignoreEscapeSequences
            )
        }
    }

    func updateSearchResultCountForBeautify() {
        guard !searchText.isEmpty else {
            searchResultCount = 0
            return
        }

        guard let formatted = formattedJSON else {
            searchResultCount = 0
            return
        }

        let lowercasedSearch = searchText.lowercased()
        let lowercasedFormatted = formatted.lowercased()

        var count = 0
        var searchStart = lowercasedFormatted.startIndex

        while let range = lowercasedFormatted.range(of: lowercasedSearch, range: searchStart..<lowercasedFormatted.endIndex) {
            count += 1
            searchStart = range.upperBound
        }

        searchResultCount = count
    }

    func nextSearchResult() {
        guard searchResultCount > 0 else { return }
        if viewMode == .beautify { beautifySearchDismissed = false }
        else { treeSearchDismissed = false }
        currentSearchIndex = (currentSearchIndex + 1) % searchResultCount
        searchNavigationVersion += 1
    }

    func previousSearchResult() {
        guard searchResultCount > 0 else { return }
        if viewMode == .beautify { beautifySearchDismissed = false }
        else { treeSearchDismissed = false }
        currentSearchIndex = (currentSearchIndex - 1 + searchResultCount) % searchResultCount
        searchNavigationVersion += 1
    }

    func closeSearch() {
        searchText = ""
        beautifySearchIndex = 0
        treeSearchIndex = 0
        searchResultCount = 0
        isSearchVisible = false
        beautifySearchDismissed = false
        treeSearchDismissed = false

        if let activeTabId = tabManager.activeTabId {
            tabManager.updateTabSearchState(
                id: activeTabId,
                searchText: "",
                beautifySearchIndex: 0,
                treeSearchIndex: 0
            )
            tabManager.updateTabSearchVisibility(id: activeTabId, isVisible: false)
        }
    }

    // MARK: - Search Highlight Dismiss

    func dismissBeautifySearchHighlights() {
        guard !searchText.isEmpty, !beautifySearchDismissed else { return }
        beautifySearchDismissed = true
    }

    func dismissTreeSearchHighlights() {
        guard !searchText.isEmpty, !treeSearchDismissed else { return }
        treeSearchDismissed = true
    }

    // MARK: - View Mode (moved from ViewerWindow)

    func switchViewMode(to mode: ViewMode) {
        guard mode != viewMode else { return }

        if mode == .beautify, let json = currentJSON {
            let dataSize = json.data(using: .utf8)?.count ?? 0
            if dataSize > largeFileSizeThreshold {
                showLargeFileWarning = true
                return
            }
        }

        // Save scroll position of previous mode
        if let activeTabId = tabManager.activeTabId {
            if viewMode == .beautify {
                tabManager.updateTabScrollPosition(id: activeTabId, position: beautifyScrollPosition)
            } else {
                tabManager.updateTabTreeSelectedNodeId(id: activeTabId, nodeId: selectedNodeId)
                tabManager.updateTabTreeScrollAnchor(id: activeTabId, nodeId: treeScrollAnchorId)
                tabManager.updateTabTreeHorizontalScroll(id: activeTabId, offset: treeHorizontalScrollOffset)
            }
        }

        viewMode = mode
        if let activeTabId = tabManager.activeTabId {
            tabManager.updateTabViewMode(id: activeTabId, viewMode: mode)
        }

        // Restore scroll position for new mode
        if let activeTab = tabManager.activeTab {
            isRestoringTabState = true
            if mode == .beautify {
                beautifyScrollPosition = activeTab.beautifyScrollPosition
            } else {
                selectedNodeId = activeTab.treeSelectedNodeId
                treeScrollAnchorId = activeTab.treeScrollAnchorId
                treeHorizontalScrollOffset = activeTab.treeHorizontalScrollOffset
            }
            DispatchQueue.main.async { [weak self] in
                self?.isRestoringTabState = false
            }
        }

        if mode == .beautify {
            updateSearchResultCountForBeautify()
        } else {
            updateSearchResultCount()
        }
    }

    // MARK: - Actions (moved from ViewerWindow)

    func clearAll() {
        guard let activeTabId = tabManager.activeTabId else { return }

        debounceTask?.cancel()
        parseTask?.cancel()
        isParsing = false

        tabManager.updateTabInput(id: activeTabId, text: "")
        tabManager.updateTabParseResult(id: activeTabId, result: .success(JSONNode(key: nil, value: .null)))
        tabManager.updateTabSearchState(id: activeTabId, searchText: "", beautifySearchIndex: 0, treeSearchIndex: 0)

        inputText = ""
        parseResult = nil
        currentJSON = nil
        searchText = ""
        searchResultCount = 0
        beautifySearchIndex = 0
        treeSearchIndex = 0
        beautifySearchDismissed = false
        treeSearchDismissed = false
    }

    func copyAllJSON() {
        guard let json = currentJSON else { return }

        if let formatted = jsonParser.formatJSON(json, indentSize: AppSettings.shared.jsonIndent) {
            clipboardService.writeText(formatted)
            ToastManager.shared.show(String(localized: "toast.copied"))
        } else {
            clipboardService.writeText(json)
            ToastManager.shared.show(String(localized: "toast.copied"))
        }
    }

    // MARK: - Search State Sync (called from View onChange handlers)

    func syncSearchState() {
        guard !isRestoringTabState else { return }
        if let activeTabId = tabManager.activeTabId {
            tabManager.updateTabSearchState(
                id: activeTabId,
                searchText: searchText,
                beautifySearchIndex: beautifySearchIndex,
                treeSearchIndex: treeSearchIndex
            )
        }
    }

    func syncSelectedNodeId() {
        guard !isRestoringTabState else { return }
        if let activeTabId = tabManager.activeTabId, viewMode == .tree {
            tabManager.updateTabTreeSelectedNodeId(id: activeTabId, nodeId: selectedNodeId)
        }
    }

    func syncTreeScrollAnchor() {
        guard !isRestoringTabState else { return }
        if let activeTabId = tabManager.activeTabId, viewMode == .tree {
            tabManager.updateTabTreeScrollAnchor(id: activeTabId, nodeId: treeScrollAnchorId)
        }
    }

    func syncTreeHorizontalScroll() {
        guard !isRestoringTabState else { return }
        if let activeTabId = tabManager.activeTabId, viewMode == .tree {
            tabManager.updateTabTreeHorizontalScroll(id: activeTabId, offset: treeHorizontalScrollOffset)
        }
    }

    func syncSearchVisibility() {
        guard !isRestoringTabState else { return }
        if let activeTabId = tabManager.activeTabId {
            tabManager.updateTabSearchVisibility(id: activeTabId, isVisible: isSearchVisible)
        }
    }

    // MARK: - Node Cache

    /// Rebuild the node cache from the current parse result.
    /// Called when parseResult changes (new JSON parsed).
    func rebuildNodeCache() {
        guard case .success(let rootNode) = parseResult else {
            cachedVisibleNodes = []
            nodeIndexMap = [:]
            return
        }
        cachedVisibleNodes = rootNode.allNodes()
        nodeIndexMap = Dictionary(uniqueKeysWithValues: cachedVisibleNodes.enumerated().map { ($1.id, $0) })
    }

    /// Update the node cache from externally computed visible nodes.
    /// Called by TreeView's onVisibleNodesChanged callback.
    func updateNodeCache(_ nodes: [JSONNode]) {
        cachedVisibleNodes = nodes
        nodeIndexMap = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.id, $0) })
    }

    // MARK: - Tree Keyboard Navigation

    func moveSelectionDown() {
        guard case .success = parseResult else { return }
        guard !cachedVisibleNodes.isEmpty else { return }

        guard let currentId = selectedNodeId,
              let currentIndex = nodeIndexMap[currentId] else {
            selectedNodeId = cachedVisibleNodes.first?.id
            return
        }

        let nextIndex = currentIndex + 1
        guard nextIndex < cachedVisibleNodes.count else { return }
        selectedNodeId = cachedVisibleNodes[nextIndex].id
    }

    func moveSelectionUp() {
        guard case .success = parseResult else { return }
        guard !cachedVisibleNodes.isEmpty else { return }

        guard let currentId = selectedNodeId,
              let currentIndex = nodeIndexMap[currentId] else {
            selectedNodeId = cachedVisibleNodes.first?.id
            return
        }

        let prevIndex = currentIndex - 1
        guard prevIndex >= 0 else { return }
        selectedNodeId = cachedVisibleNodes[prevIndex].id
    }

    func expandOrMoveRight() {
        guard case .success = parseResult else { return }

        guard let currentId = selectedNodeId,
              let currentIndex = nodeIndexMap[currentId] else { return }
        let node = cachedVisibleNodes[currentIndex]

        if node.value.isContainer && node.value.childCount > 0 {
            if !node.isExpanded {
                node.isExpanded = true
                treeStructureVersion += 1
            } else if let firstChild = node.children.first {
                selectedNodeId = firstChild.id
            }
        }
    }

    func collapseOrMoveLeft() {
        guard case .success = parseResult else { return }

        guard let currentId = selectedNodeId,
              let currentIndex = nodeIndexMap[currentId] else { return }
        let node = cachedVisibleNodes[currentIndex]

        if node.value.isContainer && node.isExpanded {
            node.isExpanded = false
            treeStructureVersion += 1
        } else if let parentNode = node.parent {
            selectedNodeId = parentNode.id
        }
    }

    // MARK: - Expand / Collapse All

    func expandAllNodes() {
        guard case .success(let rootNode) = parseResult else { return }
        rootNode.expandAll()
        selectedNodeId = nil
        treeScrollAnchorId = nil
        treeStructureVersion += 1
    }

    func collapseAllNodes() {
        guard case .success(let rootNode) = parseResult else { return }
        rootNode.collapseAll()
        selectedNodeId = nil
        treeScrollAnchorId = nil
        treeStructureVersion += 1
    }

    // MARK: - Confetti

    func triggerConfetti() {
        confettiCounter += 1
    }

    // MARK: - Window Lifecycle Helpers

    /// Called by WindowManager.windowWillClose
    func onWindowWillClose() {
        parseTask?.cancel()
        isParsing = false
        currentJSON = nil
        parseResult = nil
        tabManager.closeAllTabs()
    }
}
#endif
