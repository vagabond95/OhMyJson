//
//  JSONTab.swift
//  OhMyJson
//
//  Tab model for managing individual JSON editing sessions
//

import Foundation

/// View mode for the right panel
enum ViewMode: String, CaseIterable {
    case beautify = "Beautify"
    case tree = "Tree"

    var displayName: String {
        switch self {
        case .beautify: return String(localized: "viewer.mode.beautify")
        case .tree: return String(localized: "viewer.mode.tree")
        }
    }
}

struct JSONTab: Identifiable, Equatable {
    let id: UUID
    var inputText: String
    var parseResult: JSONParseResult?
    var createdAt: Date
    var lastAccessedAt: Date

    /// Display title for the tab (e.g., "Tab 1", "Tab 2")
    var title: String

    /// Search state for this tab
    var searchText: String
    var beautifySearchIndex: Int
    var treeSearchIndex: Int

    /// Current view mode (Beautify or Tree)
    var viewMode: ViewMode

    /// Whether the search bar is visible
    var isSearchVisible: Bool

    /// Scroll positions
    var inputScrollPosition: CGFloat
    var beautifyScrollPosition: CGFloat

    /// Selected node ID for tree view (user selection)
    var treeSelectedNodeId: UUID?

    /// Scroll anchor node ID for tree view (scroll position tracking)
    var treeScrollAnchorId: UUID?

    /// Horizontal scroll offset for tree view
    var treeHorizontalScrollOffset: CGFloat

    /// Whether search highlights are dismissed in Beautify view
    var beautifySearchDismissed: Bool

    /// Whether search highlights are dismissed in Tree view
    var treeSearchDismissed: Bool

    init(
        id: UUID = UUID(),
        inputText: String = "",
        parseResult: JSONParseResult? = nil,
        createdAt: Date = Date(),
        lastAccessedAt: Date = Date(),
        title: String = "",
        searchText: String = "",
        beautifySearchIndex: Int = 0,
        treeSearchIndex: Int = 0,
        viewMode: ViewMode = .beautify,
        isSearchVisible: Bool = false,
        inputScrollPosition: CGFloat = 0,
        beautifyScrollPosition: CGFloat = 0,
        treeSelectedNodeId: UUID? = nil,
        treeScrollAnchorId: UUID? = nil,
        treeHorizontalScrollOffset: CGFloat = 0,
        beautifySearchDismissed: Bool = false,
        treeSearchDismissed: Bool = false
    ) {
        self.id = id
        self.inputText = inputText
        self.parseResult = parseResult
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
        self.title = title
        self.searchText = searchText
        self.beautifySearchIndex = beautifySearchIndex
        self.treeSearchIndex = treeSearchIndex
        self.viewMode = viewMode
        self.isSearchVisible = isSearchVisible
        self.inputScrollPosition = inputScrollPosition
        self.beautifyScrollPosition = beautifyScrollPosition
        self.treeSelectedNodeId = treeSelectedNodeId
        self.treeScrollAnchorId = treeScrollAnchorId
        self.treeHorizontalScrollOffset = treeHorizontalScrollOffset
        self.beautifySearchDismissed = beautifySearchDismissed
        self.treeSearchDismissed = treeSearchDismissed
    }

    /// Update last accessed time to current
    mutating func markAsAccessed() {
        lastAccessedAt = Date()
    }

    /// Check if tab has any content
    var isEmpty: Bool {
        return inputText.isEmpty
    }

    /// Check if tab has valid JSON
    var hasValidJSON: Bool {
        if case .success = parseResult {
            return true
        }
        return false
    }

    static func == (lhs: JSONTab, rhs: JSONTab) -> Bool {
        return lhs.id == rhs.id
    }
}
