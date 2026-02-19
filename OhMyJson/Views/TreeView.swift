//
//  TreeView.swift
//  OhMyJson
//

import SwiftUI

#if os(macOS)

/// Preference key to track scroll offset of the tree content
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct TreeView: View {
    var rootNode: JSONNode
    var isActive: Bool = true
    @Binding var searchText: String
    @Binding var selectedNodeId: UUID?
    @Binding var scrollAnchorId: UUID?
    @Binding var currentSearchIndex: Int
    var treeStructureVersion: Int = 0
    var isRestoringTabState: Bool = false
    var onVisibleNodesChanged: (([JSONNode]) -> Void)?

    @State private var visibleNodes: [JSONNode] = []
    @State private var searchResults: [JSONNode] = []
    @State private var ancestorLastMap: [UUID: [Bool]] = [:]
    @State private var currentSearchResultId: UUID?
    @State private var hasRestoredScroll = false
    @State private var isReady = false
    @State private var hasInitialized = false
    @State private var isDirty = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleNodes) { node in
                        TreeNodeView(
                            node: node,
                            searchText: searchText,
                            isCurrentSearchResult: currentSearchResultId == node.id,
                            isSelected: selectedNodeId == node.id,
                            onSelect: { selectedNodeId = node.id },
                            onToggleExpand: {
                                updateVisibleNodes()
                            },
                            ancestorIsLast: ancestorLastMap[node.id] ?? []
                        )
                        .frame(height: TreeLayout.rowHeight)
                        .id(node.id)
                    }
                }
                .padding(.leading, 10).padding(.trailing, 8)
                .padding(.vertical, 4)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geo.frame(in: .named("scrollView")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "scrollView")
            .opacity(isReady ? 1 : 0)
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                // Calculate top visible node index from scroll offset
                guard hasRestoredScroll, !isRestoringTabState, !visibleNodes.isEmpty else { return }
                // offset is negative when scrolled down; account for vertical padding (4pt)
                let adjustedOffset = -(offset - 4)
                let topIndex = max(0, min(visibleNodes.count - 1, Int(adjustedOffset / TreeLayout.rowHeight)))
                scrollAnchorId = visibleNodes[topIndex].id
            }
            .onChange(of: rootNode.id) { _, _ in
                guard isActive else { isDirty = true; return }
                updateVisibleNodes()
                currentSearchResultId = nil
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
                updateSearchResults()
                if !newValue.isEmpty && !searchResults.isEmpty {
                    currentSearchIndex = 0
                    navigateToSearchResult(index: 0, proxy: proxy)
                } else {
                    currentSearchResultId = nil
                }
            }
            .onChange(of: currentSearchIndex) { _, newIndex in
                guard isActive else { return }
                if !searchResults.isEmpty {
                    navigateToSearchResult(index: newIndex, proxy: proxy)
                }
            }
            .onChange(of: treeStructureVersion) { _, _ in
                guard isActive else { isDirty = true; return }
                updateVisibleNodes()
            }
            .onChange(of: selectedNodeId) { _, newId in
                guard isActive else { return }
                if let nodeId = newId {
                    withAnimation(.easeInOut(duration: Animation.quick)) {
                        proxy.scrollTo(nodeId, anchor: nil)
                    }
                }
            }
            .onAppear {
                guard isActive else { return }
                performFullInit(proxy: proxy)
            }
            .onChange(of: isActive) { _, newValue in
                guard newValue else { return }
                if !hasInitialized {
                    performFullInit(proxy: proxy)
                } else if isDirty {
                    updateVisibleNodes()
                    restoreSearchHighlighting()
                    isDirty = false
                }
            }
            .onDisappear {
                hasRestoredScroll = false
                isReady = false
            }
        }
    }

    private func performFullInit(proxy: ScrollViewProxy) {
        hasRestoredScroll = false
        isReady = false
        updateVisibleNodes()
        restoreSearchHighlighting()

        // Validate scrollAnchorId — fallback to nil if node no longer visible
        if let nodeId = scrollAnchorId,
           !visibleNodes.contains(where: { $0.id == nodeId }) {
            scrollAnchorId = nil
        }

        // Delay scroll restoration to ensure LazyVStack layout is complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let nodeId = scrollAnchorId,
               visibleNodes.contains(where: { $0.id == nodeId }) {
                proxy.scrollTo(nodeId, anchor: .top)
            }
            isReady = true

            DispatchQueue.main.asyncAfter(deadline: .now() + Timing.treeRestoreDelay) {
                hasRestoredScroll = true
            }
        }
        hasInitialized = true
        isDirty = false
    }

    private func updateVisibleNodes() {
        let newVisibleNodes = rootNode.allNodes()

        // Only rebuild ancestor map if tree structure changed
        let needsMapUpdate = visibleNodes.count != newVisibleNodes.count ||
                             visibleNodes.map(\.id) != newVisibleNodes.map(\.id)

        visibleNodes = newVisibleNodes

        if needsMapUpdate {
            updateAncestorLastMap()
        }

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

    private func updateSearchResults() {
        guard !searchText.isEmpty else {
            searchResults = []
            return
        }

        searchResults = rootNode.allNodesIncludingCollapsed().filter { $0.matches(searchText: searchText) }
    }

    /// Restores search highlighting without scrolling or changing selectedNodeId.
    /// This ensures the saved scroll position (via selectedNodeId) takes priority over search result position.
    private func restoreSearchHighlighting() {
        guard !searchText.isEmpty else { return }

        // Rebuild search results
        updateSearchResults()

        guard !searchResults.isEmpty else { return }

        // Clamp index to valid range and set highlight — but do NOT scroll or modify selectedNodeId
        let validIndex = min(currentSearchIndex, searchResults.count - 1)
        currentSearchResultId = searchResults[validIndex].id
    }

    private func navigateToSearchResult(index: Int, proxy: ScrollViewProxy) {
        guard index >= 0 && index < searchResults.count else { return }

        let targetNode = searchResults[index]

        // Expand path to make node visible
        rootNode.expandPathTo(node: targetNode)

        // Update visible nodes in case tree structure changed
        updateVisibleNodes()

        // Update highlight immediately
        currentSearchResultId = targetNode.id
        scrollAnchorId = targetNode.id

        // Scroll with animation (use DispatchQueue to ensure layout is updated)
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: Animation.quick)) {
                proxy.scrollTo(targetNode.id, anchor: .center)
            }
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
