//
//  TreeView.swift
//  OhMyJson
//

import SwiftUI

#if os(macOS)

private struct TreeSearchOccurrence {
    let node: JSONNode
    let localIndex: Int  // 노드 내 occurrence 인덱스 (0-based)
}

struct TreeView: View {
    var rootNode: JSONNode
    var isActive: Bool = true
    @Binding var searchText: String
    @Binding var selectedNodeId: UUID?
    @Binding var scrollAnchorId: UUID?
    @Binding var currentSearchIndex: Int
    @Binding var horizontalScrollOffset: CGFloat
    var searchNavigationVersion: Int = 0
    var treeStructureVersion: Int = 0
    var isRestoringTabState: Bool = false
    var isSearchDismissed: Bool = false
    /// The most recent bulk tree operation — drives O(1) fast path in onChange(of: treeStructureVersion).
    var treeOperation: ViewerViewModel.TreeOperation = .normal
    /// Pre-built flat list of ALL nodes (including collapsed). Set from ViewModel at parse time.
    var allNodesCache: [JSONNode] = []
    /// Pre-built ancestor isLastChild map for ALL nodes. Set from ViewModel at parse time.
    var allAncestorMapCache: [UUID: [Bool]] = [:]
    /// Pre-computed max content width across ALL nodes. Used instead of O(N) calculation.
    var maxContentWidth: CGFloat = 0
    @Binding var isRendering: Bool
    var onVisibleNodesChanged: (([JSONNode]) -> Void)?

    @State private var visibleNodes: [JSONNode] = []
    @State private var searchResults: [TreeSearchOccurrence] = []
    @State private var ancestorLastMap: [UUID: [Bool]] = [:]
    @State private var currentSearchResultId: UUID?
    @State private var currentSearchOccurrenceLocalIndex: Int = 0
    @State private var hasRestoredScroll = false
    @State private var isReady = false
    @State private var hasInitialized = false
    @State private var isStructureDirty = false  // rootNode.id, isExpanded, treeStructureVersion changes
    @State private var isSearchDirty = false     // searchText changes while inactive
    @State private var isSettingsDirty = false   // ignoreEscapeSequences changes

    // Scroll command system (replaces ScrollViewReader proxy)
    @State private var scrollCommand: TreeScrollCommand?
    @State private var scrollCommandVersion: Int = 0
    @State private var topVisibleIndex: Int = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var estimatedContentWidth: CGFloat = 0

    // Debounce scrollAnchorId updates (tab state persistence)
    @State private var scrollDebounceItem: DispatchWorkItem?

    // Async search task — cancelled when a new search starts
    @State private var searchTask: Task<Void, Never>?

    // P6: Cache search paths keyed by (rootNode.id, searchText)
    @State private var searchPathCache: (rootId: UUID, query: String, paths: [[Int]])?

    @Environment(AppSettings.self) private var settings

    var body: some View {
        GeometryReader { geometry in
            let viewportWidth = geometry.size.width
            TreeNSScrollView(
                treeContent: AnyView(
                    treeContent(viewportWidth: viewportWidth)
                        .environment(settings)
                ),
                nodeCount: visibleNodes.count,
                viewportWidth: viewportWidth,
                estimatedContentWidth: estimatedContentWidth,
                scrollCommand: scrollCommand,
                isActive: isActive,
                isRestoringTabState: isRestoringTabState,
                scrollAnchorId: $scrollAnchorId,
                horizontalScrollOffset: $horizontalScrollOffset,
                topVisibleIndex: $topVisibleIndex
            )
            .onAppear {
                viewportHeight = geometry.size.height
            }
            .onChange(of: geometry.size.height) { _, newHeight in
                viewportHeight = newHeight
            }
        }
        .opacity(isReady ? 1 : 0)
        .onChange(of: topVisibleIndex) { _, newIndex in
            guard hasRestoredScroll, !isRestoringTabState, !visibleNodes.isEmpty else { return }
            scrollDebounceItem?.cancel()
            let item = DispatchWorkItem {
                let clampedIndex = max(0, min(visibleNodes.count - 1, newIndex))
                scrollAnchorId = visibleNodes[clampedIndex].id
            }
            scrollDebounceItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: item)
        }
        .onChange(of: rootNode.id) { _, _ in
            guard isActive else { isStructureDirty = true; isSearchDirty = true; return }
            if isRestoringTabState {
                // Tab switch: full init cycle (isReady=false → 0.05s → isReady=true) for progress overlay
                performFullInit()
            } else {
                // Same-tab re-parse: in-place update
                updateVisibleNodes()
                currentSearchResultId = nil
                currentSearchOccurrenceLocalIndex = 0
                if !searchText.isEmpty {
                    updateSearchResults()
                }
            }
        }
        .onChange(of: rootNode.isExpanded) { _, _ in
            guard isActive else { isStructureDirty = true; return }
            updateVisibleNodes()
        }
        .onChange(of: searchText) { _, newValue in
            guard isActive else { isSearchDirty = true; return }
            updateSearchResults { occurrences in
                if !newValue.isEmpty && !occurrences.isEmpty {
                    selectedNodeId = nil
                    currentSearchIndex = 0
                    currentSearchOccurrenceLocalIndex = 0
                    navigateToSearchResult(index: 0)
                } else {
                    currentSearchResultId = nil
                    currentSearchOccurrenceLocalIndex = 0
                }
            }
        }
        .onChange(of: searchNavigationVersion) { _, _ in
            guard isActive else { return }
            if !searchResults.isEmpty {
                selectedNodeId = nil
                navigateToSearchResult(index: currentSearchIndex)
            }
        }
        .onChange(of: treeStructureVersion) { _, _ in
            guard isActive else { isStructureDirty = true; return }
            switch treeOperation {
            case .expandAll:
                // O(1) fast path: swap pre-built caches — no O(N) traversal needed
                visibleNodes = allNodesCache
                ancestorLastMap = allAncestorMapCache
                estimatedContentWidth = maxContentWidth
                // onVisibleNodesChanged skipped — ViewModel already pre-set cachedVisibleNodes in expandAllNodes()
            case .collapseAll:
                // O(1) fast path: only root is visible after collapseAll
                visibleNodes = [rootNode]
                ancestorLastMap = [rootNode.id: []]
                estimatedContentWidth = maxContentWidth
                // onVisibleNodesChanged skipped — ViewModel already pre-set cachedVisibleNodes in collapseAllNodes()
            case .normal:
                updateVisibleNodes()
            }
        }
        .onChange(of: settings.ignoreEscapeSequences) { _, _ in
            guard isActive else { isSettingsDirty = true; isSearchDirty = true; return }
            searchPathCache = nil
            if !searchText.isEmpty {
                updateSearchResults()
            }
        }
        .onChange(of: selectedNodeId) { _, newId in
            guard isActive else { return }
            if let nodeId = newId {
                if !searchText.isEmpty && !searchResults.isEmpty {
                    currentSearchResultId = nil
                    currentSearchOccurrenceLocalIndex = 0
                }
                emitScrollCommand(nodeId: nodeId, anchor: .visible)
            }
        }
        .onAppear {
            guard isActive else {
                isRendering = false
                return
            }
            performFullInit()
        }
        .onChange(of: isActive) { _, newValue in
            guard newValue else {
                isRendering = false
                return
            }
            if !hasInitialized {
                performFullInit()
            } else if isStructureDirty {
                updateVisibleNodes()
                restoreSearchHighlighting()
                isStructureDirty = false
                isSearchDirty = false
                isSettingsDirty = false
            } else if isSettingsDirty {
                searchPathCache = nil
                restoreSearchHighlighting()
                isSettingsDirty = false
                isSearchDirty = false
            } else if isSearchDirty {
                restoreSearchHighlighting()
                isSearchDirty = false
            }
        }
        .onDisappear {
            hasRestoredScroll = false
            isReady = false
            isRendering = false
            scrollDebounceItem?.cancel()
            scrollDebounceItem = nil
            searchTask?.cancel()
        }
    }

    @ViewBuilder
    private func treeContent(viewportWidth: CGFloat) -> some View {
        let rowHeight = TreeLayout.rowHeight
        let buffer = TreeLayout.virtualizationBuffer
        let visibleRowCount = viewportHeight > 0
            ? Int(ceil(viewportHeight / rowHeight))
            : visibleNodes.count
        let startIndex = max(0, topVisibleIndex - buffer)
        let endIndex = min(visibleNodes.count, topVisibleIndex + visibleRowCount + buffer)
        let topHeight = CGFloat(startIndex) * rowHeight
        let bottomHeight = CGFloat(visibleNodes.count - endIndex) * rowHeight

        VStack(alignment: .leading, spacing: 0) {
            if topHeight > 0 {
                Color.clear.frame(height: topHeight)
            }
            ForEach(visibleNodes[startIndex..<endIndex]) { node in
                TreeNodeView(
                    node: node,
                    searchText: isSearchDismissed ? "" : searchText,
                    currentOccurrenceLocalIndex: isSearchDismissed ? nil : (currentSearchResultId == node.id ? currentSearchOccurrenceLocalIndex : nil),
                    isSelected: selectedNodeId == node.id,
                    onSelect: { selectedNodeId = node.id },
                    onToggleExpand: {
                        handleNodeToggle(node: node)
                    },
                    ancestorIsLast: ancestorLastMap[node.id] ?? []
                )
                .frame(height: rowHeight)
            }
            if bottomHeight > 0 {
                Color.clear.frame(height: bottomHeight)
            }
        }
        .padding(.leading, 10).padding(.trailing, 8)
        .padding(.vertical, 4)
        .frame(minWidth: viewportWidth, alignment: .leading)
    }

    private func emitScrollCommand(nodeId: UUID, anchor: TreeScrollAnchor) {
        guard let index = visibleNodes.firstIndex(where: { $0.id == nodeId }) else { return }
        scrollCommandVersion += 1
        scrollCommand = TreeScrollCommand(
            targetNodeId: nodeId,
            targetIndex: index,
            anchor: anchor,
            version: scrollCommandVersion
        )
    }

    private func performFullInit() {
        hasRestoredScroll = false
        isReady = false
        updateVisibleNodes()
        restoreSearchHighlighting()

        // Validate scrollAnchorId
        if let nodeId = scrollAnchorId,
           !visibleNodes.contains(where: { $0.id == nodeId }) {
            scrollAnchorId = nil
        }

        // Emit scroll command for restoration
        if let nodeId = scrollAnchorId,
           visibleNodes.contains(where: { $0.id == nodeId }) {
            emitScrollCommand(nodeId: nodeId, anchor: .top)
        }

        // Delay to ensure layout is complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isReady = true
            isRendering = false

            DispatchQueue.main.asyncAfter(deadline: .now() + Timing.treeRestoreDelay) {
                hasRestoredScroll = true
            }
        }
        hasInitialized = true
        isStructureDirty = false
        isSearchDirty = false
        isSettingsDirty = false
    }

    // MARK: - Incremental expand/collapse

    private func handleNodeToggle(node: JSONNode) {
        guard let nodeIndex = visibleNodes.firstIndex(where: { $0.id == node.id }) else {
            updateVisibleNodes()
            return
        }

        if node.isExpanded {
            let newDescendants = Array(node.allNodes().dropFirst())
            if !newDescendants.isEmpty {
                visibleNodes.insert(contentsOf: newDescendants, at: nodeIndex + 1)
                // Incrementally add ancestorLastMap entries for new descendants only — O(subtree × depth)
                for descendant in newDescendants {
                    ancestorLastMap[descendant.id] = buildAncestorStackFromParent(for: descendant)
                }
            }
        } else {
            let removeEnd = findDescendantEndIndex(afterNodeAt: nodeIndex)
            if removeEnd > nodeIndex + 1 {
                // Remove ancestorLastMap entries for collapsed descendants
                for i in (nodeIndex + 1)..<removeEnd {
                    ancestorLastMap.removeValue(forKey: visibleNodes[i].id)
                }
                visibleNodes.removeSubrange((nodeIndex + 1)..<removeEnd)
            }
        }

        // Use pre-computed global max width (O(1)) instead of O(N) per-toggle calculation
        estimatedContentWidth = maxContentWidth
        onVisibleNodesChanged?(visibleNodes)
    }

    /// Builds ancestor isLastChild stack by walking parent pointers — O(depth), typically 2-20 levels.
    private func buildAncestorStackFromParent(for node: JSONNode) -> [Bool] {
        var stack: [Bool] = []
        var current: JSONNode? = node.parent
        while let ancestor = current, ancestor.id != rootNode.id {
            stack.insert(ancestor.isLastChild, at: 0)
            current = ancestor.parent
        }
        return stack
    }

    private func findDescendantEndIndex(afterNodeAt index: Int) -> Int {
        let nodeDepth = visibleNodes[index].depth
        var endIndex = index + 1
        while endIndex < visibleNodes.count && visibleNodes[endIndex].depth > nodeDepth {
            endIndex += 1
        }
        return endIndex
    }

    // MARK: - Full rebuild

    private func updateVisibleNodes() {
        let newVisibleNodes = rootNode.allNodes()
        visibleNodes = newVisibleNodes

        // Use pre-computed ancestor map from ViewModel when available (O(V) lookup)
        // instead of rebuilding via recursive traversal (O(V) with stack overhead).
        if !allAncestorMapCache.isEmpty {
            var newMap: [UUID: [Bool]] = [:]
            newMap.reserveCapacity(newVisibleNodes.count)
            for node in newVisibleNodes {
                newMap[node.id] = allAncestorMapCache[node.id] ?? []
            }
            ancestorLastMap = newMap
        } else {
            updateAncestorLastMap()
        }

        estimatedContentWidth = maxContentWidth
        onVisibleNodesChanged?(newVisibleNodes)
    }

    private func updateAncestorLastMap() {
        ancestorLastMap = [:]
        var stack: [Bool] = []
        buildAncestorLastMap(node: rootNode, stack: &stack)
    }

    private func buildAncestorLastMap(node: JSONNode, stack: inout [Bool]) {
        ancestorLastMap[node.id] = stack

        if node.isExpanded {
            stack.append(node.isLastChild)
            for child in node.children {
                buildAncestorLastMap(node: child, stack: &stack)
            }
            stack.removeLast()
        }
    }

    /// Resolves paths to TreeSearchOccurrence list. Must be called on main thread.
    private func resolveOccurrences(paths: [[Int]], query: String) -> [TreeSearchOccurrence] {
        let nodes = paths.compactMap { rootNode.nodeAt(childIndices: $0) }
        var occurrences: [TreeSearchOccurrence] = []
        for node in nodes {
            let count = JSONValue.leafOccurrenceCount(value: node.value, key: node.key, query: query, ignoreEscapeSequences: settings.ignoreEscapeSequences)
            guard count > 0 else { continue }
            for i in 0..<count {
                occurrences.append(TreeSearchOccurrence(node: node, localIndex: i))
            }
        }
        return occurrences
    }

    /// Updates searchResults, calling `onComplete` with the results when done.
    /// For cache hits the call is synchronous; for cache misses, the expensive
    /// `searchMatchPaths()` tree traversal runs on a background thread and
    /// `onComplete` is called once results are ready on the main actor.
    private func updateSearchResults(onComplete: (([TreeSearchOccurrence]) -> Void)? = nil) {
        guard !searchText.isEmpty else {
            searchTask?.cancel()
            searchResults = []
            onComplete?([])
            return
        }

        let query = searchText.lowercased()

        // Fast path: cache hit — resolve synchronously on main
        if let cache = searchPathCache, cache.rootId == rootNode.id, cache.query == query {
            let occurrences = resolveOccurrences(paths: cache.paths, query: query)
            searchResults = occurrences
            onComplete?(occurrences)
            return
        }

        // Slow path: offload expensive tree traversal to a background thread
        let valueSnapshot = rootNode.value
        let keySnapshot = rootNode.key
        let rootId = rootNode.id
        let ignoreEscapes = settings.ignoreEscapeSequences

        searchTask?.cancel()
        searchTask = Task {
            let paths = await Task.detached(priority: .userInitiated) {
                valueSnapshot.searchMatchPaths(key: keySnapshot, query: query, ignoreEscapeSequences: ignoreEscapes)
            }.value
            guard !Task.isCancelled else { return }
            searchPathCache = (rootId: rootId, query: query, paths: paths)
            let occurrences = resolveOccurrences(paths: paths, query: query)
            searchResults = occurrences
            onComplete?(occurrences)
        }
    }

    private func restoreSearchHighlighting() {
        guard !searchText.isEmpty else { return }

        updateSearchResults { occurrences in
            guard !occurrences.isEmpty else { return }
            let validIndex = min(currentSearchIndex, occurrences.count - 1)
            let occurrence = occurrences[validIndex]
            currentSearchResultId = occurrence.node.id
            currentSearchOccurrenceLocalIndex = occurrence.localIndex
        }
    }

    private func navigateToSearchResult(index: Int) {
        guard index >= 0 && index < searchResults.count else { return }

        let occurrence = searchResults[index]
        let targetNode = occurrence.node

        rootNode.expandPathTo(node: targetNode)
        updateVisibleNodes()

        currentSearchResultId = targetNode.id
        currentSearchOccurrenceLocalIndex = occurrence.localIndex
        scrollAnchorId = targetNode.id

        DispatchQueue.main.async {
            emitScrollCommand(nodeId: targetNode.id, anchor: .center)
        }
    }

    var searchResultCount: Int {
        searchResults.count
    }

    func nextSearchResult() {
        guard !searchResults.isEmpty else { return }
        currentSearchIndex = (currentSearchIndex + 1) % searchResults.count
    }

    func previousSearchResult() {
        guard !searchResults.isEmpty else { return }
        currentSearchIndex = (currentSearchIndex - 1 + searchResults.count) % searchResults.count
    }
}
#endif
