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

                // Main Content: Input (35%) | Resizable Divider | Viewer (65%)
                GeometryReader { geometry in
                    let totalWidth = geometry.size.width
                    let effectiveWidth = totalWidth - Layout.dividerHitAreaWidth
                    let inputWidth = max(Layout.minPanelWidth, min(effectiveWidth - Layout.minPanelWidth, effectiveWidth * dividerRatio))
                    HStack(spacing: 0) {
                        // Left: Input Panel
                        InputPanel(
                            text: $viewModel.inputText,
                            onTextChange: viewModel.handleTextChange,
                            onClear: viewModel.clearAll,
                            scrollPosition: $viewModel.inputScrollPosition,
                            isRestoringTabState: viewModel.isRestoringTabState
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
        .withAccessibilityWarning()
        .onAppear {
            setupKeyboardShortcuts()
            viewModel.loadInitialContent()
        }
        .onChange(of: viewModel.activeTabId) { oldId, newId in
            viewModel.onActiveTabChanged(oldId: oldId, newId: newId)
        }
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.syncSearchState()
        }
        .onChange(of: viewModel.beautifySearchIndex) { _, _ in
            viewModel.syncSearchState()
        }
        .onChange(of: viewModel.treeSearchIndex) { _, _ in
            viewModel.syncSearchState()
        }
        .onChange(of: viewModel.selectedNodeId) { _, _ in
            viewModel.syncSelectedNodeId()
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

                // Copy All button - only shown when valid JSON
                if case .success = viewModel.parseResult {
                    Button(action: viewModel.copyAllJSON) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundColor(theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
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
        .alert("alert.large_file.title", isPresented: Bindable(viewModel).showLargeFileWarning) {
            Button("alert.large_file.view_anyway") {
                // Keep current mode (Beautify)
            }
            Button("alert.large_file.switch_to_tree") {
                viewModel.switchViewMode(to: .tree)
            }
        } message: {
            Text("alert.large_file.message")
        }
    }

    // MARK: - View Mode Segmented Control

    private var viewModeSegmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Button(action: {
                    viewModel.switchViewMode(to: mode)
                }) {
                    Text(mode.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(viewModel.viewMode == mode ? theme.primaryText : theme.secondaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            viewModel.viewMode == mode
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

    @ViewBuilder
    private var viewerContent: some View {
        switch viewModel.parseResult {
        case .success(let rootNode):
            Group {
                if viewModel.viewMode == .beautify {
                    if let formatted = viewModel.formattedJSON {
                        BeautifyView(
                            formattedJSON: formatted,
                            searchText: Bindable(viewModel).searchText,
                            currentSearchIndex: currentSearchIndex,
                            scrollPosition: Bindable(viewModel).beautifyScrollPosition,
                            isRestoringTabState: viewModel.isRestoringTabState
                        )
                        .onChange(of: viewModel.searchText) { _, _ in
                            viewModel.updateSearchResultCountForBeautify()
                        }
                    } else {
                        PlaceholderView()
                    }
                } else {
                    TreeView(
                        rootNode: rootNode,
                        searchText: Bindable(viewModel).searchText,
                        selectedNodeId: Bindable(viewModel).selectedNodeId,
                        currentSearchIndex: currentSearchIndex,
                        isRestoringTabState: viewModel.isRestoringTabState
                    )
                    .onChange(of: viewModel.searchText) { _, _ in
                        viewModel.updateSearchResultCount()
                    }
                    .onAppear {
                        viewModel.updateSearchResultCount()
                    }
                }
            }

        case .failure(let error):
            ErrorView(error: error)

        case .none:
            PlaceholderView()
        }
    }

    // MARK: - Keyboard Shortcuts

    private func setupKeyboardShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // ESC to close cheat sheet or search
            if event.keyCode == KeyCode.escape {
                if viewModel.isCheatSheetVisible {
                    withAnimation(.easeInOut(duration: Animation.quick)) {
                        viewModel.isCheatSheetVisible = false
                    }
                    return nil
                } else if viewModel.isSearchVisible {
                    withAnimation(.easeInOut(duration: Animation.quick)) {
                        viewModel.closeSearch()
                    }
                    return nil
                }
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
