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
    var onVisibleNodesChanged: (([JSONNode]) -> Void)?

    @State private var visibleNodes: [JSONNode] = []
    @State private var searchResults: [TreeSearchOccurrence] = []
    @State private var ancestorLastMap: [UUID: [Bool]] = [:]
    @State private var currentSearchResultId: UUID?
    @State private var currentSearchOccurrenceLocalIndex: Int = 0
    @State private var hasRestoredScroll = false
    @State private var isReady = false
    @State private var hasInitialized = false
    @State private var isDirty = false

    // Scroll command system (replaces ScrollViewReader proxy)
    @State private var scrollCommand: TreeScrollCommand?
    @State private var scrollCommandVersion: Int = 0
    @State private var topVisibleIndex: Int = 0
    @State private var estimatedContentWidth: CGFloat = 0

    // P4: Debounce scrollAnchorId updates
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
            guard isActive else { isDirty = true; return }
            updateVisibleNodes()
            currentSearchResultId = nil
            currentSearchOccurrenceLocalIndex = 0
            if !searchText.isEmpty {
                updateSearchResults()
            }
        }
        .onChange(of: rootNode.isExpanded) { _, _ in
            guard isActive else { isDirty = true; return }
            updateVisibleNodes()
        }
        .onChange(of: searchText) { _, newValue in
            guard isActive else { isDirty = true; return }
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
            guard isActive else { isDirty = true; return }
            updateVisibleNodes()
        }
        .onChange(of: settings.ignoreEscapeSequences) { _, _ in
            guard isActive else { isDirty = true; return }
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
            guard isActive else { return }
            performFullInit()
        }
        .onChange(of: isActive) { _, newValue in
            guard newValue else { return }
            if !hasInitialized {
                performFullInit()
            } else if isDirty {
                updateVisibleNodes()
                restoreSearchHighlighting()
                isDirty = false
            }
        }
        .onDisappear {
            hasRestoredScroll = false
            isReady = false
            scrollDebounceItem?.cancel()
            scrollDebounceItem = nil
            searchTask?.cancel()
        }
    }

    @ViewBuilder
    private func treeContent(viewportWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(visibleNodes) { node in
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
                .frame(height: TreeLayout.rowHeight)
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

    private func updateEstimatedContentWidth() {
        var maxWidth: CGFloat = 0
        for node in visibleNodes {
            // Estimate: depth indentation + expand button + key + ": " + value
            let indentWidth = CGFloat(node.depth) * 2 * TreeLayout.charWidth
            let expandWidth: CGFloat = 16
            let keyWidth = CGFloat(node.key?.count ?? 0) * TreeLayout.charWidth
            let separatorWidth: CGFloat = node.key != nil ? 2 * TreeLayout.charWidth : 0

            let valueLen: Int
            switch node.value {
            case .string(let s):
                var escapedLen = 2 // quotes
                for c in s.unicodeScalars {
                    switch c {
                    case "\n", "\r", "\t", "\\": escapedLen += 2
                    default: escapedLen += 1
                    }
                }
                valueLen = escapedLen
            case .number(let n):
                valueLen = n.truncatingRemainder(dividingBy: 1) == 0
                    ? String(format: "%.0f", n).count
                    : String(n).count
            case .bool(let b): valueLen = b ? 4 : 5
            case .null: valueLen = 4
            case .object(let d): valueLen = String(d.count).count + 4
            case .array(let a): valueLen = String(a.count).count + 4
            }
            let valueWidth = CGFloat(valueLen) * TreeLayout.charWidth

            let totalWidth = indentWidth + expandWidth + keyWidth + separatorWidth + valueWidth + 18 // padding
            maxWidth = max(maxWidth, totalWidth)
        }
        estimatedContentWidth = maxWidth
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

            DispatchQueue.main.asyncAfter(deadline: .now() + Timing.treeRestoreDelay) {
                hasRestoredScroll = true
            }
        }
        hasInitialized = true
        isDirty = false
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
            }
        } else {
            let removeEnd = findDescendantEndIndex(afterNodeAt: nodeIndex)
            if removeEnd > nodeIndex + 1 {
                visibleNodes.removeSubrange((nodeIndex + 1)..<removeEnd)
            }
        }

        updateAncestorLastMap()
        updateEstimatedContentWidth()
        onVisibleNodesChanged?(visibleNodes)
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

        let needsMapUpdate = visibleNodes.count != newVisibleNodes.count ||
                             visibleNodes.map(\.id) != newVisibleNodes.map(\.id)

        visibleNodes = newVisibleNodes

        if needsMapUpdate {
            updateAncestorLastMap()
        }

        updateEstimatedContentWidth()
        onVisibleNodesChanged?(newVisibleNodes)
    }

    private func updateAncestorLastMap() {
        ancestorLastMap = [:]
        buildAncestorLastMap(node: rootNode, ancestors: [])
    }

    private func buildAncestorLastMap(node: JSONNode, ancestors: [Bool]) {
        ancestorLastMap[node.id] = ancestors

        if node.isExpanded {
            for child in node.children {
                var childAncestors = ancestors
                childAncestors.append(node.isLastChild)
                buildAncestorLastMap(node: child, ancestors: childAncestors)
            }
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
