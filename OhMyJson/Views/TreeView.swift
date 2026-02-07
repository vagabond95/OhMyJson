//
//  TreeView.swift
//  OhMyJson
//

import SwiftUI

#if os(macOS)

/// Preference key to track the topmost visible node
struct TopVisibleNodePreferenceKey: PreferenceKey {
    static var defaultValue: UUID? = nil

    static func reduce(value: inout UUID?, nextValue: () -> UUID?) {
        // Keep the first (topmost) node
        if value == nil {
            value = nextValue()
        }
    }
}

struct TreeView: View {
    @ObservedObject var rootNode: JSONNode
    @Binding var searchText: String
    @Binding var selectedNodeId: UUID?
    @Binding var currentSearchIndex: Int
    var isRestoringTabState: Bool = false

    @State private var visibleNodes: [JSONNode] = []
    @State private var searchResults: [JSONNode] = []
    @State private var ancestorLastMap: [UUID: [Bool]] = [:]
    @State private var currentSearchResultId: UUID?
    @State private var hasRestoredScroll = false
    @State private var isReady = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleNodes) { node in
                        TreeNodeView(
                            node: node,
                            searchText: searchText,
                            isCurrentSearchResult: currentSearchResultId == node.id,
                            onSelect: { },
                            onToggleExpand: {
                                updateVisibleNodes()
                            },
                            ancestorIsLast: ancestorLastMap[node.id] ?? []
                        )
                        .id(node.id)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: TopVisibleNodePreferenceKey.self,
                                    value: isNodeVisible(geo: geo) ? node.id : nil
                                )
                            }
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .coordinateSpace(name: "scrollView")
            .opacity(isReady ? 1 : 0)
            .onPreferenceChange(TopVisibleNodePreferenceKey.self) { topNodeId in
                // Only update after initial scroll restoration is done, not during tab restore
                if hasRestoredScroll, !isRestoringTabState, let nodeId = topNodeId {
                    selectedNodeId = nodeId
                }
            }
            .onChange(of: rootNode.isExpanded) { _, _ in
                updateVisibleNodes()
            }
            .onChange(of: searchText) { _, newValue in
                updateSearchResults()
                if !newValue.isEmpty && !searchResults.isEmpty {
                    currentSearchIndex = 0
                    navigateToSearchResult(index: 0, proxy: proxy)
                } else {
                    currentSearchResultId = nil
                }
            }
            .onChange(of: currentSearchIndex) { _, newIndex in
                if !searchResults.isEmpty {
                    navigateToSearchResult(index: newIndex, proxy: proxy)
                }
            }
            .onAppear {
                hasRestoredScroll = false
                isReady = false
                updateVisibleNodes()
                // Restore search highlighting (without scrolling) when returning to tab
                restoreSearchHighlighting()

                // Validate selectedNodeId — fallback to nil if node no longer exists
                if let nodeId = selectedNodeId,
                   !visibleNodes.contains(where: { $0.id == nodeId }) {
                    // Also check all nodes (including collapsed) in case it's just not visible
                    let allNodes = rootNode.allNodesIncludingCollapsed()
                    if !allNodes.contains(where: { $0.id == nodeId }) {
                        selectedNodeId = nil
                    }
                }

                // Delay scroll restoration slightly to ensure binding is updated
                DispatchQueue.main.async {
                    if let nodeId = selectedNodeId {
                        proxy.scrollTo(nodeId, anchor: .top)
                    }
                    // Reveal the view after scroll is positioned
                    isReady = true

                    // Mark restoration complete after a brief delay to prevent position tracking during initial render
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        hasRestoredScroll = true
                    }
                }
            }
            .onDisappear {
                hasRestoredScroll = false
                isReady = false
            }
        }
    }

    /// Check if a node is visible in the scroll view (near the top)
    private func isNodeVisible(geo: GeometryProxy) -> Bool {
        let frame = geo.frame(in: .named("scrollView"))
        // Consider visible if the node is within the top portion of the viewport
        return frame.minY >= 0 && frame.minY < 100
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
        selectedNodeId = targetNode.id

        // Scroll with animation (use DispatchQueue to ensure layout is updated)
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.15)) {
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
