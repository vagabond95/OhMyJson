//
//  ViewerWindow.swift
//  OhMyJson
//

import SwiftUI
import Combine
import ConfettiSwiftUI

#if os(macOS)
struct ViewerWindow: View {
    @EnvironmentObject var windowManager: WindowManager
    @EnvironmentObject var settings: AppSettings
    @ObservedObject var tabManager = TabManager.shared

    @State private var inputText = ""
    @State private var searchText = ""
    @State private var selectedNodeId: UUID?
    @State private var beautifySearchIndex = 0
    @State private var treeSearchIndex = 0
    @State private var searchResultCount = 0
    @State private var isSearchVisible = false
    @State private var viewMode: ViewMode = .beautify

    /// Computed binding for current search index based on active view mode
    private var currentSearchIndex: Binding<Int> {
        Binding(
            get: { viewMode == .beautify ? beautifySearchIndex : treeSearchIndex },
            set: { newValue in
                if viewMode == .beautify {
                    beautifySearchIndex = newValue
                } else {
                    treeSearchIndex = newValue
                }
            }
        )
    }
    @State private var showLargeFileWarning = false
    @State private var inputScrollPosition: CGFloat = 0
    @State private var beautifyScrollPosition: CGFloat = 0

    // Resizable divider
    @State private var dividerRatio: CGFloat = AppSettings.shared.dividerRatio
    @State private var isDraggingDivider = false
    @State private var dragStartRatio: CGFloat = 0
    @State private var dragStartX: CGFloat = 0
    private let minPanelWidth: CGFloat = 200
    private let dividerHitAreaWidth: CGFloat = 9
    private let defaultDividerRatio: CGFloat = 0.35

    @State private var debounceTask: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.3
    private let largeFileSizeThreshold = 5 * 1024 * 1024 // 5MB

    // Confetti
    @State private var confettiCounter: Int = 0

    // Tab state restoration
    @State private var isRestoringTabState: Bool = false
    @State private var restoreTask: DispatchWorkItem? = nil
    @State private var hasRestoredCurrentTab: Bool = false
    private let restoreDebounceInterval: TimeInterval = 0.2

    @State private var isCheatSheetVisible = false

    @FocusState private var isSearchFocused: Bool

    private var theme: AppTheme { settings.currentTheme }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                // Tab Bar (always show - serves as unified titlebar)
                TabBarView(tabManager: tabManager)
                    .zIndex(1)
                Rectangle()
                    .fill(theme.border)
                    .frame(height: 1)

                // Main Content: Input (35%) | Resizable Divider | Viewer (65%)
                GeometryReader { geometry in
                    let totalWidth = geometry.size.width
                    let effectiveWidth = totalWidth - dividerHitAreaWidth
                    let inputWidth = max(minPanelWidth, min(effectiveWidth - minPanelWidth, effectiveWidth * dividerRatio))
                    HStack(spacing: 0) {
                        // Left: Input Panel
                        InputPanel(
                            text: $inputText,
                            onTextChange: handleTextChange,
                            onClear: clearAll,
                            scrollPosition: $inputScrollPosition,
                            isRestoringTabState: isRestoringTabState
                        )
                        .frame(width: inputWidth)
                        .allowsHitTesting(!isDraggingDivider)

                        // Resizable Divider
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 9)
                            .overlay(alignment: .top) {
                                VStack(spacing: 0) {
                                    Rectangle()
                                        .fill(theme.secondaryBackground)
                                        .frame(height: 36)
                                    Rectangle()
                                        .fill(theme.border)
                                        .frame(height: 1)
                                }
                                .allowsHitTesting(false)
                            }
                            .overlay(
                                Rectangle()
                                    .fill(theme.border)
                                    .frame(width: 1)
                                    .allowsHitTesting(false)
                            )
                            .background(ResizeCursorView())
                            .contentShape(Rectangle())
                            .simultaneousGesture(
                                TapGesture(count: 2)
                                    .onEnded {
                                        dividerRatio = defaultDividerRatio
                                        settings.dividerRatio = defaultDividerRatio
                                    }
                            )
                            .gesture(
                                DragGesture(minimumDistance: 2, coordinateSpace: .named("contentArea"))
                                    .onChanged { value in
                                        if !isDraggingDivider {
                                            isDraggingDivider = true
                                            dragStartRatio = dividerRatio
                                            dragStartX = value.startLocation.x
                                            NSCursor.resizeLeftRight.push()
                                        }
                                        let deltaX = value.location.x - dragStartX
                                        let newInputWidth = effectiveWidth * dragStartRatio + deltaX
                                        let clampedWidth = max(minPanelWidth, min(effectiveWidth - minPanelWidth, newInputWidth))
                                        let newRatio = clampedWidth / effectiveWidth
                                        if abs(newRatio - dividerRatio) * effectiveWidth > 0.5 {
                                            dividerRatio = newRatio
                                        }
                                    }
                                    .onEnded { _ in
                                        isDraggingDivider = false
                                        settings.dividerRatio = dividerRatio
                                        NSCursor.pop()
                                    }
                            )

                        // Right: TreeViewer Panel
                        viewerPanel
                            .frame(maxWidth: .infinity)
                            .allowsHitTesting(!isDraggingDivider)
                    }
                    .coordinateSpace(name: "contentArea")
                }
            }
            .background(theme.background)

            // Floating Search Bar (Command+F to toggle)
            if isSearchVisible {
                FloatingSearchBar(
                    searchText: $searchText,
                    currentIndex: currentSearchIndex,
                    totalCount: searchResultCount,
                    onNext: nextSearchResult,
                    onPrevious: previousSearchResult,
                    onClose: { withAnimation(.easeInOut(duration: 0.15)) { closeSearch() } },
                    shouldAutoFocus: !isRestoringTabState
                )
                .padding(.top, 80)
                .padding(.trailing, 12)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                    removal: .opacity
                ))
            }

            // Keyboard Shortcuts Cheat Sheet
            CheatSheetButton(isVisible: $isCheatSheetVisible)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 12)
                .padding(.bottom, 12)
        }
        .frame(minWidth: 800, minHeight: 400)
        .ignoresSafeArea(edges: .top)
        .preferredColorScheme(theme.colorScheme)
        .confettiCannon(
            counter: $confettiCounter,
            num: 50,
            openingAngle: Angle(degrees: 0),
            closingAngle: Angle(degrees: 360),
            radius: 500
        )
        .withToast()
        .withAccessibilityWarning()
        .onAppear {
            setupKeyboardShortcuts()
            loadInitialContent()
        }
        .onReceive(NotificationCenter.default.publisher(for: .clearInputRequested)) { _ in
            clearAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .onboardingCompleted)) { _ in
            confettiCounter += 1
        }
        .onChange(of: tabManager.activeTabId) { oldId, newId in
            // Save previous tab state immediately (only if it was fully restored)
            if let oldId = oldId, hasRestoredCurrentTab {
                saveTabState(for: oldId)
            }
            hasRestoredCurrentTab = false

            // Cancel any pending restore from rapid switching
            restoreTask?.cancel()

            // Debounce restore — only final tab gets restored
            let task = DispatchWorkItem { [self] in
                restoreTabState()
                hasRestoredCurrentTab = true
            }
            restoreTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + restoreDebounceInterval, execute: task)
        }
        .onChange(of: searchText) { _, newText in
            guard !isRestoringTabState else { return }
            if let activeTabId = tabManager.activeTabId {
                tabManager.updateTabSearchState(
                    id: activeTabId,
                    searchText: newText,
                    beautifySearchIndex: beautifySearchIndex,
                    treeSearchIndex: treeSearchIndex
                )
            }
        }
        .onChange(of: beautifySearchIndex) { _, _ in
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
        .onChange(of: treeSearchIndex) { _, _ in
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
        .onChange(of: selectedNodeId) { _, newNodeId in
            guard !isRestoringTabState else { return }
            if let activeTabId = tabManager.activeTabId, viewMode == .tree {
                tabManager.updateTabTreeSelectedNodeId(id: activeTabId, nodeId: newNodeId)
            }
        }
        .onChange(of: isSearchVisible) { _, newValue in
            guard !isRestoringTabState else { return }
            if let activeTabId = tabManager.activeTabId {
                tabManager.updateTabSearchVisibility(id: activeTabId, isVisible: newValue)
            }
        }
        .onChange(of: viewMode) { oldMode, newMode in
            // Don't save/restore scroll during tab state restoration (handled by restoreTabState)
            if !isRestoringTabState {
                // Save scroll position of previous mode
                if let activeTabId = tabManager.activeTabId {
                    if oldMode == .beautify {
                        tabManager.updateTabScrollPosition(id: activeTabId, position: beautifyScrollPosition)
                    } else {
                        tabManager.updateTabTreeSelectedNodeId(id: activeTabId, nodeId: selectedNodeId)
                    }
                }

                // Restore scroll position for new mode with restoration flag
                if let activeTab = tabManager.activeTab {
                    isRestoringTabState = true
                    if newMode == .beautify {
                        beautifyScrollPosition = activeTab.beautifyScrollPosition
                    } else {
                        selectedNodeId = activeTab.treeSelectedNodeId
                    }
                    DispatchQueue.main.async {
                        isRestoringTabState = false
                    }
                }
            }

            // Update search result count when view mode changes
            if newMode == .beautify {
                updateSearchResultCountForBeautify()
            } else {
                updateSearchResultCount()
            }
        }
    }

    // MARK: - Viewer Panel

    private var viewerPanel: some View {
        VStack(spacing: 0) {
            // Viewer Toolbar with Segmented Control
            HStack(spacing: 12) {
                // View Mode Segmented Control (left-aligned)
                viewModeSegmentedControl

                Spacer()

                // Copy All button - only shown when valid JSON
                if case .success = windowManager.parseResult {
                    Button(action: copyAllJSON) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundColor(theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                    .instantTooltip("Copy All", position: .bottom)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(height: 36)
            .background(theme.secondaryBackground)
            .zIndex(1)

            Rectangle()
                .fill(theme.border)
                .frame(height: 1)

            // Content based on view mode
            viewerContent
                .padding(8)
        }
        .background(theme.background)
        .alert("Large File Warning", isPresented: $showLargeFileWarning) {
            Button("View Anyway") {
                // Keep current mode (Beautify)
            }
            Button("Switch to Tree") {
                viewMode = .tree
                if let activeTabId = tabManager.activeTabId {
                    tabManager.updateTabViewMode(id: activeTabId, viewMode: .tree)
                }
            }
        } message: {
            Text("This JSON exceeds 5MB. Beautify mode may be slow.")
        }
    }

    // MARK: - View Mode Segmented Control

    private var viewModeSegmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Button(action: {
                    switchViewMode(to: mode)
                }) {
                    Text(mode.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(viewMode == mode ? theme.primaryText : theme.secondaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            viewMode == mode
                                ? theme.panelBackground
                                : Color.clear
                        )
                        .cornerRadius(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(theme.background)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    private func switchViewMode(to mode: ViewMode) {
        guard mode != viewMode else { return }

        // Check for large file when switching to Beautify
        if mode == .beautify, let json = windowManager.currentJSON {
            let dataSize = json.data(using: .utf8)?.count ?? 0
            if dataSize > largeFileSizeThreshold {
                showLargeFileWarning = true
                return
            }
        }

        viewMode = mode
        if let activeTabId = tabManager.activeTabId {
            tabManager.updateTabViewMode(id: activeTabId, viewMode: mode)
        }
    }

    @ViewBuilder
    private var viewerContent: some View {
        switch windowManager.parseResult {
        case .success(let rootNode):
            Group {
                if viewMode == .beautify {
                    if let formatted = windowManager.formattedJSON {
                        BeautifyView(
                            formattedJSON: formatted,
                            searchText: $searchText,
                            currentSearchIndex: currentSearchIndex,
                            scrollPosition: $beautifyScrollPosition,
                            isRestoringTabState: isRestoringTabState
                        )
                        .onChange(of: searchText) { _, _ in
                            updateSearchResultCountForBeautify()
                        }
                    } else {
                        PlaceholderView()
                    }
                } else {
                    TreeView(
                        rootNode: rootNode,
                        searchText: $searchText,
                        selectedNodeId: $selectedNodeId,
                        currentSearchIndex: currentSearchIndex,
                        isRestoringTabState: isRestoringTabState
                    )
                    .onChange(of: searchText) { _, _ in
                        updateSearchResultCount()
                    }
                    .onAppear {
                        updateSearchResultCount()
                    }
                }
            }

        case .failure(let error):
            ErrorView(error: error)

        case .none:
            // Empty state with placeholder
            PlaceholderView()
        }
    }

    // MARK: - Actions

    private func loadInitialContent() {
        // Load content from active tab (no debounce for initial load)
        restoreTabState()
        hasRestoredCurrentTab = true
    }

    private func saveTabState(for tabId: UUID) {
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
    }

    private func restoreTabState() {
        isRestoringTabState = true

        guard let activeTab = tabManager.activeTab else {
            // No active tab - clear everything
            inputText = ""
            windowManager.parseResult = nil
            windowManager.currentJSON = nil
            searchText = ""
            beautifySearchIndex = 0
            treeSearchIndex = 0
            searchResultCount = 0
            isSearchVisible = false
            viewMode = .beautify
            inputScrollPosition = 0
            beautifyScrollPosition = 0
            selectedNodeId = nil
            isRestoringTabState = false
            return
        }

        // Load tab's content
        inputText = activeTab.inputText
        windowManager.parseResult = activeTab.parseResult
        windowManager.currentJSON = activeTab.inputText.isEmpty ? nil : activeTab.inputText

        // Load tab's search state
        searchText = activeTab.searchText
        beautifySearchIndex = activeTab.beautifySearchIndex
        treeSearchIndex = activeTab.treeSearchIndex

        // Load tab's search bar visibility (no animation — instant on tab switch)
        isSearchVisible = activeTab.isSearchVisible

        // Load tab's view mode
        viewMode = activeTab.viewMode

        // Load tab's scroll positions
        inputScrollPosition = activeTab.inputScrollPosition
        beautifyScrollPosition = activeTab.beautifyScrollPosition
        selectedNodeId = activeTab.treeSelectedNodeId

        if viewMode == .beautify {
            updateSearchResultCountForBeautify()
        } else {
            updateSearchResultCount()
        }

        // Clear restoration flag after SwiftUI processes the batch state update
        DispatchQueue.main.async {
            isRestoringTabState = false
        }
    }

    private func handleTextChange(_ text: String) {
        guard !isRestoringTabState else { return }
        guard let activeTabId = tabManager.activeTabId else { return }

        // Update tab's input text immediately
        tabManager.updateTabInput(id: activeTabId, text: text)

        // Cancel previous debounce task
        debounceTask?.cancel()

        // Handle empty text immediately (treat whitespace-only as empty)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty {
            tabManager.updateTabParseResult(id: activeTabId, result: .success(JSONNode(key: nil, value: .null)))
            windowManager.parseResult = nil
            windowManager.currentJSON = nil
            return
        }

        // Debounce JSON parsing for non-empty text
        let task = DispatchWorkItem { [self] in
            parseAndUpdateJSON(text: text, activeTabId: activeTabId)
        }
        debounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: task)
    }

    private func parseAndUpdateJSON(text: String, activeTabId: UUID) {
        let result = JSONParser.shared.parse(text)

        // Update tab's parse result
        tabManager.updateTabParseResult(id: activeTabId, result: result)

        switch result {
        case .success(let node):
            windowManager.parseResult = .success(node)
            windowManager.currentJSON = text

        case .failure(let error):
            windowManager.parseResult = .failure(error)
            windowManager.currentJSON = nil
        }

        // Reset Beautify/Tree scroll positions on content change
        beautifyScrollPosition = 0
        selectedNodeId = nil
        tabManager.updateTabScrollPosition(id: activeTabId, position: 0)
        tabManager.updateTabTreeSelectedNodeId(id: activeTabId, nodeId: nil)

        if viewMode == .beautify {
            updateSearchResultCountForBeautify()
        } else {
            updateSearchResultCount()
        }
    }

    private func clearAll() {
        guard let activeTabId = tabManager.activeTabId else { return }

        // Clear active tab's content and search state
        tabManager.updateTabInput(id: activeTabId, text: "")
        tabManager.updateTabParseResult(id: activeTabId, result: .success(JSONNode(key: nil, value: .null)))
        tabManager.updateTabSearchState(id: activeTabId, searchText: "", beautifySearchIndex: 0, treeSearchIndex: 0)

        // Clear local state
        inputText = ""
        windowManager.parseResult = nil
        windowManager.currentJSON = nil
        searchText = ""
        searchResultCount = 0
        beautifySearchIndex = 0
        treeSearchIndex = 0
    }

    private func closeSearch() {
        searchText = ""
        beautifySearchIndex = 0
        treeSearchIndex = 0
        searchResultCount = 0
        isSearchVisible = false

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

    private func setupKeyboardShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // ESC to close cheat sheet or search
            if event.keyCode == 53 {
                if isCheatSheetVisible {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isCheatSheetVisible = false
                    }
                } else if isSearchVisible {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        closeSearch()
                    }
                }
            }

            // ⌘ shortcuts: F (search), 1 (beautify), 2 (tree)
            if event.modifierFlags.contains(.command),
               let chars = event.charactersIgnoringModifiers {
                switch chars {
                case "f":
                    if !isSearchVisible {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isSearchVisible = true
                        }
                    }
                case "1":
                    switchViewMode(to: .beautify)
                case "2":
                    switchViewMode(to: .tree)
                default:
                    break
                }
            }

            return event
        }
    }

    private func updateSearchResultCount() {
        guard case .success(let rootNode) = windowManager.parseResult else {
            searchResultCount = 0
            return
        }

        if searchText.isEmpty {
            searchResultCount = 0
        } else {
            searchResultCount = rootNode.allNodesIncludingCollapsed()
                .filter { $0.matches(searchText: searchText) }
                .count
        }
    }

    private func updateSearchResultCountForBeautify() {
        // Early return if no search - avoid expensive operations
        guard !searchText.isEmpty else {
            searchResultCount = 0
            return
        }

        // Use cached formatted JSON
        guard let formatted = windowManager.formattedJSON else {
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

    private func nextSearchResult() {
        guard searchResultCount > 0 else { return }
        currentSearchIndex.wrappedValue = (currentSearchIndex.wrappedValue + 1) % searchResultCount
    }

    private func previousSearchResult() {
        guard searchResultCount > 0 else { return }
        currentSearchIndex.wrappedValue = (currentSearchIndex.wrappedValue - 1 + searchResultCount) % searchResultCount
    }

    private func copyAllJSON() {
        guard let json = windowManager.currentJSON else { return }

        if let formatted = JSONParser.shared.formatJSON(json, indentSize: AppSettings.shared.jsonIndent) {
            ClipboardService.shared.writeText(formatted)
            ToastManager.shared.show("Copied to clipboard")
        } else {
            ClipboardService.shared.writeText(json)
            ToastManager.shared.show("Copied to clipboard")
        }
    }

}

// Notification for clear action from menu/hotkey
extension Notification.Name {
    static let clearInputRequested = Notification.Name("clearInputRequested")
}

// MARK: - Native cursor rect for reliable resize cursor
private struct ResizeCursorView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = CursorView()
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.invalidateCursorRects(for: nsView)
    }
    private class CursorView: NSView {
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }
    }
}

struct ViewerWindow_Previews: PreviewProvider {
    static var previews: some View {
        ViewerWindow()
            .environmentObject(WindowManager.shared)
            .environmentObject(AppSettings.shared)
    }
}
#endif
