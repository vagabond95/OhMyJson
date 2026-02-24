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

    var tooltipText: String {
        switch self {
        case .beautify: return String(localized: "tooltip.beautify_mode")
        case .tree: return String(localized: "tooltip.tree_mode")
        }
    }
}

struct JSONTab: Identifiable, Equatable {
    let id: UUID
    var inputText: String
    /// Full original text when inputText is a truncated preview (large input > 512KB).
    /// nil means inputText is the complete content.
    var fullInputText: String?
    var parseResult: JSONParseResult?
    var createdAt: Date
    var lastAccessedAt: Date

    /// Display title for the tab (e.g., "Tab 1", "Tab 2")
    var title: String

    /// User-provided custom title. nil = use auto-generated timestamp title.
    var customTitle: String?

    /// Display title: returns customTitle if non-empty, otherwise falls back to auto-generated title.
    var displayTitle: String {
        if let custom = customTitle, !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return custom
        }
        return title
    }

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

    /// Whether the last parse attempt succeeded — used to decide what to restore from DB
    var isParseSuccess: Bool

    /// Whether this tab's `fullInputText` and `parseResult` are currently held in memory.
    /// `false` (dehydrated) means content was offloaded to DB; `true` means content is in memory.
    var isHydrated: Bool

    /// Set to `true` during hydration when `fullInputText` is missing for a large-JSON tab.
    /// Not persisted — set only at app launch by `hydrateTabContent()`.
    var isLargeJSONContentLost: Bool

    init(
        id: UUID = UUID(),
        inputText: String = "",
        fullInputText: String? = nil,
        parseResult: JSONParseResult? = nil,
        createdAt: Date = Date(),
        lastAccessedAt: Date = Date(),
        title: String = "",
        customTitle: String? = nil,
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
        treeSearchDismissed: Bool = false,
        isParseSuccess: Bool = false,
        isHydrated: Bool = true,
        isLargeJSONContentLost: Bool = false
    ) {
        self.id = id
        self.inputText = inputText
        self.fullInputText = fullInputText
        self.parseResult = parseResult
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
        self.title = title
        self.customTitle = customTitle
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
        self.isParseSuccess = isParseSuccess
        self.isHydrated = isHydrated
        self.isLargeJSONContentLost = isLargeJSONContentLost
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

// MARK: - TabRecord Conversion

extension JSONTab {
    /// Restore a JSONTab from a persisted TabRecord.
    /// `parseResult` is always nil and `isHydrated` is `false` —
    /// content is loaded on-demand when the tab becomes active.
    init(from record: TabRecord) {
        self.init(
            id: UUID(uuidString: record.id) ?? UUID(),
            inputText: record.inputText,
            fullInputText: nil,
            parseResult: nil,
            createdAt: Date(timeIntervalSinceReferenceDate: record.createdAt),
            lastAccessedAt: Date(timeIntervalSinceReferenceDate: record.lastAccessedAt),
            title: record.title,
            customTitle: record.customTitle,
            searchText: record.searchText,
            beautifySearchIndex: record.beautifySearchIndex,
            treeSearchIndex: record.treeSearchIndex,
            viewMode: ViewMode(rawValue: record.viewMode) ?? .beautify,
            isSearchVisible: record.isSearchVisible,
            inputScrollPosition: CGFloat(record.inputScrollPosition),
            beautifyScrollPosition: CGFloat(record.beautifyScrollPosition),
            treeHorizontalScrollOffset: CGFloat(record.treeHorizontalScrollOffset),
            beautifySearchDismissed: record.beautifySearchDismissed,
            treeSearchDismissed: record.treeSearchDismissed,
            isParseSuccess: record.isParseSuccess,
            isHydrated: false
        )
    }
}

extension TabRecord {
    init(from tab: JSONTab, sortOrder: Int, isActive: Bool) {
        self.id = tab.id.uuidString
        self.sortOrder = sortOrder
        self.inputText = tab.inputText
        self.title = tab.title
        self.customTitle = tab.customTitle
        self.viewMode = tab.viewMode.rawValue
        self.searchText = tab.searchText
        self.beautifySearchIndex = tab.beautifySearchIndex
        self.treeSearchIndex = tab.treeSearchIndex
        self.isSearchVisible = tab.isSearchVisible
        self.inputScrollPosition = Double(tab.inputScrollPosition)
        self.beautifyScrollPosition = Double(tab.beautifyScrollPosition)
        self.treeHorizontalScrollOffset = Double(tab.treeHorizontalScrollOffset)
        self.beautifySearchDismissed = tab.beautifySearchDismissed
        self.treeSearchDismissed = tab.treeSearchDismissed
        self.createdAt = tab.createdAt.timeIntervalSinceReferenceDate
        self.lastAccessedAt = tab.lastAccessedAt.timeIntervalSinceReferenceDate
        self.isActive = isActive
        self.isParseSuccess = tab.isParseSuccess
    }
}
