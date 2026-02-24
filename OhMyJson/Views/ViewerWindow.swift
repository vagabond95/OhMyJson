//
//  ViewerWindow.swift
//  OhMyJson
//
//  Pure rendering view. Business logic is in ViewerViewModel (Phase 3).
//

import SwiftUI
import Combine
import ConfettiSwiftUI

#if os(macOS)
struct ViewerWindow: View {
    @Environment(ViewerViewModel.self) var viewModel
    @Environment(AppSettings.self) var settings

    // Resizable divider (pure UI state — stays in View)
    @State private var dividerRatio: CGFloat = AppSettings.shared.dividerRatio
    @State private var isDraggingDivider = false
    @State private var dragStartRatio: CGFloat = 0
    @State private var keyMonitor: Any?
    @State private var dragStartX: CGFloat = 0
    private enum Layout {
        static let minPanelWidth: CGFloat = 200
        static let dividerHitAreaWidth: CGFloat = 9
        static let defaultDividerRatio: CGFloat = 0.35
    }

    @FocusState private var isSearchFocused: Bool

    private var theme: AppTheme { settings.currentTheme }

    /// Computed binding for current search index based on active view mode
    private var currentSearchIndex: Binding<Int> {
        Binding(
            get: { viewModel.viewMode == .beautify ? viewModel.beautifySearchIndex : viewModel.treeSearchIndex },
            set: { newValue in
                if viewModel.viewMode == .beautify {
                    viewModel.beautifySearchIndex = newValue
                } else {
                    viewModel.treeSearchIndex = newValue
                }
            }
        )
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                // Tab Bar (always show - serves as unified titlebar)
                TabBarView(tabManager: TabManager.shared)
                    .zIndex(1)
                Rectangle()
                    .fill(theme.border)
                    .frame(height: 1)

                // Update Banner
                if viewModel.isUpdateAvailable {
                    UpdateBannerView()
                    Rectangle()
                        .fill(theme.border)
                        .frame(height: 1)
                }

                // Main Content: Input (35%) | Resizable Divider | Viewer (65%)
                GeometryReader { geometry in
                    let totalWidth = geometry.size.width
                    let effectiveWidth = totalWidth - Layout.dividerHitAreaWidth
                    let inputWidth = max(Layout.minPanelWidth, min(effectiveWidth - Layout.minPanelWidth, effectiveWidth * dividerRatio))
                    ZStack {
                        HStack(spacing: 0) {
                            // Left: Input Panel
                            InputPanel(
                                text: $viewModel.inputText,
                                onTextChange: viewModel.handleTextChange,
                                onClear: viewModel.clearAll,
                                scrollPosition: $viewModel.inputScrollPosition,
                                isRestoringTabState: viewModel.isRestoringTabState,
                                onLargeTextPaste: viewModel.handleLargeTextPaste,
                                isLargeJSON: viewModel.isLargeJSON,
                                isLargeJSONContentLost: viewModel.isLargeJSONContentLost,
                                tabGeneration: viewModel.tabGeneration
                            )
                            .frame(width: inputWidth)
                            .allowsHitTesting(!isDraggingDivider)

                            // Resizable Divider
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: Layout.dividerHitAreaWidth)
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
                                            dividerRatio = Layout.defaultDividerRatio
                                            settings.dividerRatio = Layout.defaultDividerRatio
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
                                            let clampedWidth = max(Layout.minPanelWidth, min(effectiveWidth - Layout.minPanelWidth, newInputWidth))
                                            let newRatio = clampedWidth / effectiveWidth
                                            if abs(newRatio - dividerRatio) * effectiveWidth > Timing.dividerDragThreshold {
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

                        // Transparent overlay: commits active tab rename on tap outside TabBarView
                        if viewModel.isRenamingTab {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.requestCommitTabRename()
                                }
                                .allowsHitTesting(!isDraggingDivider)
                        }
                    }
                }
            }
            .background(theme.background)

            // Floating Search Bar (Command+F to toggle)
            if viewModel.isSearchVisible {
                FloatingSearchBar(
                    searchText: $viewModel.searchText,
                    currentIndex: currentSearchIndex,
                    totalCount: viewModel.searchResultCount,
                    onNext: viewModel.nextSearchResult,
                    onPrevious: viewModel.previousSearchResult,
                    onClose: { withAnimation(.easeInOut(duration: Animation.quick)) { viewModel.closeSearch() } },
                    shouldAutoFocus: !viewModel.isRestoringTabState
                )
                .padding(.top, 80)
                .padding(.trailing, 12)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                    removal: .opacity
                ))
            }

            // Keyboard Shortcuts Cheat Sheet
            CheatSheetButton(isVisible: $viewModel.isCheatSheetVisible)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 12)
                .padding(.bottom, 12)
        }
        .frame(minWidth: WindowSize.minWidth, minHeight: WindowSize.minHeight)
        .ignoresSafeArea(edges: .top)
        .preferredColorScheme(theme.colorScheme)
        .confettiCannon(
            counter: $viewModel.confettiCounter,
            num: 50,
            openingAngle: Angle(degrees: 0),
            closingAngle: Angle(degrees: 360),
            radius: 500
        )
        .withToast()
        .onAppear {
            setupKeyboardShortcuts()
            viewModel.loadInitialContent()
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
        .onChange(of: viewModel.activeTabId) { oldId, newId in
            NSApp.keyWindow?.makeFirstResponder(nil)
            viewModel.onActiveTabChanged(oldId: oldId, newId: newId)
        }
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.syncSearchState()
            viewModel.beautifySearchDismissed = false
            viewModel.treeSearchDismissed = false
        }
        .onChange(of: viewModel.beautifySearchIndex) { _, _ in
            viewModel.syncSearchState()
        }
        .onChange(of: viewModel.treeSearchIndex) { _, _ in
            viewModel.syncSearchState()
        }
        .onChange(of: viewModel.selectedNodeId) { _, newId in
            viewModel.syncSelectedNodeId()
            // Resign input view focus when a tree node is selected
            if newId != nil, !viewModel.isRestoringTabState {
                NSApp.keyWindow?.makeFirstResponder(nil)
                viewModel.dismissTreeSearchHighlights()
            }
        }
        .onChange(of: viewModel.treeScrollAnchorId) { _, _ in
            viewModel.syncTreeScrollAnchor()
        }
        .onChange(of: viewModel.treeHorizontalScrollOffset) { _, _ in
            viewModel.syncTreeHorizontalScroll()
        }
        .onChange(of: viewModel.isSearchVisible) { _, _ in
            viewModel.syncSearchVisibility()
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

                // Search & Copy All buttons - only shown when valid JSON
                if case .success = viewModel.parseResult {
                    // Expand All / Collapse All (Tree mode only)
                    Button { viewModel.expandAllNodes() } label: {
                        Image(systemName: "chevron.down.2")
                            .font(.system(size: 12))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                            .toolbarIconHover()
                    }
                    .buttonStyle(.plain)
                    .opacity(viewModel.viewMode != .tree ? 0 : (viewModel.isLargeJSON ? 0.35 : 1))
                    .disabled(viewModel.viewMode != .tree || viewModel.isLargeJSON)
                    .instantTooltip(
                        viewModel.isLargeJSON && viewModel.viewMode == .tree
                            ? String(localized: "tooltip.expand_all_unavailable_large")
                            : String(localized: "tooltip.expand_all"),
                        position: .bottom
                    )

                    Button { viewModel.collapseAllNodes() } label: {
                        Image(systemName: "chevron.up.2")
                            .font(.system(size: 12))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                            .toolbarIconHover()
                    }
                    .buttonStyle(.plain)
                    .instantTooltip(String(localized: "tooltip.collapse_all"), position: .bottom)
                    .opacity(viewModel.viewMode == .tree ? 1 : 0)
                    .disabled(viewModel.viewMode != .tree)

                    Button {
                        withAnimation(.easeInOut(duration: Animation.quick)) {
                            viewModel.isSearchVisible.toggle()
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                            .toolbarIconHover(isActive: viewModel.isSearchVisible)
                    }
                    .buttonStyle(.plain)
                    .instantTooltip(String(localized: "tooltip.search"), position: .bottom)

                    Button(action: viewModel.copyAllJSON) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                            .toolbarIconHover()
                    }
                    .buttonStyle(.plain)
                    .instantTooltip(String(localized: "tooltip.copy_all"), position: .bottom)
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
    }

    // MARK: - View Mode Segmented Control

    private var viewModeSegmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                let isDisabled = mode == .beautify && viewModel.isLargeJSON
                Button(action: {
                    viewModel.switchViewMode(to: mode)
                }) {
                    Text(mode.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .toolbarIconHover(isActive: viewModel.viewMode == mode && !isDisabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            viewModel.viewMode == mode && !isDisabled
                                ? theme.panelBackground
                                : Color.clear
                        )
                        .cornerRadius(4)
                        .contentShape(Rectangle())
                        .opacity(isDisabled ? 0.35 : 1.0)
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
                .instantTooltip(
                    isDisabled
                        ? String(localized: "tooltip.beautify_unavailable_large")
                        : mode.tooltipText,
                    position: .bottom
                )
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

    @ViewBuilder
    private var viewerContent: some View {
        ZStack(alignment: .top) {
            switch viewModel.parseResult {
            case .success(let rootNode):
                ZStack {
                    if let formatted = viewModel.formattedJSON {
                        BeautifyView(
                            formattedJSON: formatted,
                            isActive: viewModel.viewMode == .beautify,
                            searchText: Bindable(viewModel).searchText,
                            currentSearchIndex: currentSearchIndex,
                            scrollPosition: Bindable(viewModel).beautifyScrollPosition,
                            isRestoringTabState: viewModel.isRestoringTabState,
                            isSearchDismissed: viewModel.beautifySearchDismissed,
                            isSearchVisible: viewModel.isSearchVisible,
                            onMouseDown: { viewModel.dismissBeautifySearchHighlights() },
                            isRendering: Bindable(viewModel).isBeautifyRendering
                        )
                        .opacity(viewModel.viewMode == .beautify ? 1 : 0)
                        .allowsHitTesting(viewModel.viewMode == .beautify)
                        .onChange(of: viewModel.searchText) { _, _ in
                            guard viewModel.viewMode == .beautify else { return }
                            viewModel.updateSearchResultCountForBeautify()
                        }
                    }

                    if viewModel.formattedJSON == nil && viewModel.viewMode == .beautify {
                        PlaceholderView()
                    }

                    TreeView(
                        rootNode: rootNode,
                        isActive: viewModel.viewMode == .tree,
                        searchText: Bindable(viewModel).searchText,
                        selectedNodeId: Bindable(viewModel).selectedNodeId,
                        scrollAnchorId: Bindable(viewModel).treeScrollAnchorId,
                        currentSearchIndex: currentSearchIndex,
                        horizontalScrollOffset: Bindable(viewModel).treeHorizontalScrollOffset,
                        searchNavigationVersion: viewModel.searchNavigationVersion,
                        treeStructureVersion: viewModel.treeStructureVersion,
                        isRestoringTabState: viewModel.isRestoringTabState,
                        isSearchDismissed: viewModel.treeSearchDismissed,
                        treeOperation: viewModel.lastTreeOperation,
                        allNodesCache: viewModel.cachedAllNodes,
                        allAncestorMapCache: viewModel.cachedAllAncestorMap,
                        maxContentWidth: viewModel.cachedMaxContentWidth,
                        isRendering: Bindable(viewModel).isTreeRendering,
                        onVisibleNodesChanged: { nodes in
                            viewModel.updateNodeCache(nodes)
                        }
                    )
                    .opacity(viewModel.viewMode == .tree ? 1 : 0)
                    .allowsHitTesting(viewModel.viewMode == .tree)
                    .onChange(of: viewModel.searchText) { _, _ in
                        guard viewModel.viewMode == .tree else { return }
                        viewModel.updateSearchResultCount()
                    }
                    .onAppear {
                        guard viewModel.viewMode == .tree else { return }
                        viewModel.updateSearchResultCount()
                    }
                }

            case .failure(let error):
                ErrorView(error: error)

            case .none:
                if viewModel.isParsing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    PlaceholderView()
                }
            }

            if (viewModel.isParsing || (viewModel.isBeautifyRendering && viewModel.viewMode == .beautify) || (viewModel.isTreeRendering && viewModel.viewMode == .tree)), viewModel.parseResult != nil {
                if viewModel.isInitialLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 8)
                }
            }
        }
    }

    // MARK: - Keyboard Shortcuts

    private func setupKeyboardShortcuts() {
        // Remove existing monitor to prevent accumulation
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        let vm = viewModel
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Tab rename in progress — pass all events through to the TextField
            if vm.isRenamingTab {
                return event
            }

            // ESC to close cheat sheet or search
            if event.keyCode == KeyCode.escape {
                if vm.isCheatSheetVisible {
                    withAnimation(.easeInOut(duration: Animation.quick)) {
                        vm.isCheatSheetVisible = false
                    }
                    return nil
                } else if vm.isSearchVisible {
                    withAnimation(.easeInOut(duration: Animation.quick)) {
                        vm.closeSearch()
                    }
                    return nil
                }
            }

            // ↑/↓: tree mode + selection exists → always handle (even when search bar focused)
            if vm.viewMode == .tree, vm.selectedNodeId != nil {
                if event.keyCode == KeyCode.downArrow {
                    vm.moveSelectionDown()
                    return nil
                }
                if event.keyCode == KeyCode.upArrow {
                    vm.moveSelectionUp()
                    return nil
                }
            }

            // ←/→: tree mode + selection + NOT in TextField focus
            let isTextFieldFocused = NSApp.keyWindow?.firstResponder is NSText
            if vm.viewMode == .tree, vm.selectedNodeId != nil, !isTextFieldFocused {
                if event.keyCode == KeyCode.rightArrow {
                    vm.expandOrMoveRight()
                    return nil
                }
                if event.keyCode == KeyCode.leftArrow {
                    vm.collapseOrMoveLeft()
                    return nil
                }
            }

            // Cmd+G / Cmd+Shift+G: search navigation (when search bar is visible)
            if event.modifierFlags.contains(AppShortcut.findNext.modifiers),
               event.keyCode == KeyCode.gKey,
               vm.isSearchVisible {
                if event.modifierFlags.contains(AppShortcut.findPrevious.modifiers) {
                    vm.previousSearchResult()
                } else {
                    vm.nextSearchResult()
                }
                return nil
            }

            return event
        }
    }
}

// MARK: - Native cursor rect for reliable resize cursor
private struct ResizeCursorView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = CursorView()
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        // Only invalidate when the view has a valid window and bounds
        if nsView.window != nil {
            nsView.window?.invalidateCursorRects(for: nsView)
        }
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
            .environment(
                ViewerViewModel(
                    tabManager: TabManager.shared,
                    clipboardService: ClipboardService.shared,
                    jsonParser: JSONParser.shared,
                    windowManager: WindowManager.shared
                )
            )
            .environment(AppSettings.shared)
    }
}
#endif
