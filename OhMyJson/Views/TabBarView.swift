//
//  TabBarView.swift
//  OhMyJson
//
//  Browser-style tab bar with adaptive width tabs
//

import SwiftUI

struct TabBarView: View {
    var tabManager: TabManager
    @Environment(AppSettings.self) var settings
    @Environment(ViewerViewModel.self) var viewModel

    @State private var hoveredTabId: UUID?
    @State private var draggedTabId: UUID?
    @State private var dragOffset: CGFloat = 0
    @State private var dragVisualOrder: [UUID] = []
    @State private var lastSwapOffset: CGFloat = 0

    private var theme: AppTheme { settings.currentTheme }

    private var themeIconName: String {
        switch settings.themeMode {
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    private enum Layout {
        static let fixedTabWidth: CGFloat = 160
        static let tabSpacing: CGFloat = 6
        static let elementPadding: CGFloat = 10
        static let themeButtonWidth: CGFloat = 30
        static let addTabButtonWidth: CGFloat = 30
        static let buttonHeight: CGFloat = 30
        static let trafficLightWidth: CGFloat = 60
    }

    private func maxTabAreaWidth(totalWidth: CGFloat) -> CGFloat {
        let fixedElements = Layout.trafficLightWidth + Layout.themeButtonWidth + Layout.addTabButtonWidth
        let spacers = Layout.elementPadding * 5   // 5 draggable spacers between/around elements
        return max(totalWidth - fixedElements - spacers, 0)
    }

    private func calculatedTabWidth(tabCount: Int, availableWidth: CGFloat) -> CGFloat {
        guard tabCount > 0 else { return Layout.fixedTabWidth }
        let totalSpacing = CGFloat(tabCount) * Layout.tabSpacing
        let requiredWidth = CGFloat(tabCount) * Layout.fixedTabWidth + totalSpacing
        if requiredWidth > availableWidth {
            return max((availableWidth - totalSpacing) / CGFloat(tabCount), 0)
        }
        return Layout.fixedTabWidth
    }

    private func tabBackgroundColor(isActive: Bool, isHovered: Bool) -> Color {
        if isActive { return theme.activeTabBackground }
        else if isHovered { return theme.hoveredTabBackground }
        else { return theme.inactiveTabBackground }
    }

    var body: some View {
        GeometryReader { geo in
            let maxTabWidth = maxTabAreaWidth(totalWidth: geo.size.width)
            let tabWidth = calculatedTabWidth(
                tabCount: tabManager.tabs.count,
                availableWidth: maxTabWidth
            )
            let slotWidth = tabWidth + Layout.tabSpacing
            let isCompressed = tabWidth < Layout.fixedTabWidth

            let actualTabsWidth = min(
                CGFloat(tabManager.tabs.count) * slotWidth,
                maxTabWidth
            )

            VStack(spacing: 0) {
                // Top margin strip (draggable)
                WindowDraggableArea()
                    .frame(maxWidth: .infinity)
                    .frame(height: 5)

                HStack(spacing: 0) {
                    // Left edge padding (draggable)
                    WindowDraggableArea()
                        .frame(width: Layout.elementPadding, height: Layout.buttonHeight)

                    // Traffic light area
                    Color.clear
                        .frame(width: Layout.trafficLightWidth, height: Layout.buttonHeight)

                    // Draggable gap between traffic light and theme button
                    WindowDraggableArea()
                        .frame(width: Layout.elementPadding, height: Layout.buttonHeight)

                    // Theme toggle button
                    Button(action: {
                        settings.toggleTheme()
                    }) {
                        Image(systemName: themeIconName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(theme.secondaryText)
                            .frame(width: Layout.themeButtonWidth, height: Layout.buttonHeight)
                            .contentShape(Rectangle())
                            .hoverHighlight(color: theme.toggleHoverBg)
                    }
                    .buttonStyle(.plain)
                    .instantTooltip(String(localized: "tooltip.toggle_theme"), position: .bottom)

                    // Draggable gap between theme button and tabs
                    WindowDraggableArea()
                        .frame(width: Layout.elementPadding, height: Layout.buttonHeight)

                    // Tab container (weight(1f) equivalent)
                    HStack(spacing: 0) {
                        ForEach(tabManager.tabs) { tab in
                            let isActive = tab.id == tabManager.activeTabId
                            let isHovered = tab.id == hoveredTabId
                            let isDragging = tab.id == draggedTabId
                            HStack(spacing: 0) {
                                TabItemView(
                                    tab: tab,
                                    isActive: isActive,
                                    isHovered: isHovered,
                                    isDragging: isDragging,
                                    tabWidth: tabWidth,
                                    showGradient: isCompressed,
                                    backgroundColor: tabBackgroundColor(
                                        isActive: isActive,
                                        isHovered: isHovered
                                    ),
                                    commitSignal: viewModel.tabRenameCommitSignal,
                                    onSelect: {
                                        tabManager.selectTab(id: tab.id)
                                    },
                                    onClose: {
                                        viewModel.closeTab(id: tab.id)
                                    },
                                    onHover: { isHovering in
                                        hoveredTabId = isHovering ? tab.id : nil
                                    },
                                    onRename: { newTitle in
                                        tabManager.updateTabTitle(id: tab.id, customTitle: newTitle)
                                    },
                                    onStartEditing: {
                                        viewModel.isRenamingTab = true
                                    },
                                    onFinishEditing: {
                                        viewModel.isRenamingTab = false
                                    }
                                )
                                WindowDraggableArea()
                                    .frame(width: Layout.tabSpacing, height: Layout.buttonHeight)
                            }
                            .offset(x: visualOffsetForTab(tab.id, slotWidth: slotWidth))
                            .zIndex(isDragging ? 1 : 0)
                            .opacity(isDragging ? 0.8 : 1.0)
                            .animation(
                                draggedTabId != nil ? .spring(response: 0.3, dampingFraction: 0.7) : nil,
                                value: dragVisualOrder
                            )
                            .gesture(
                                DragGesture(minimumDistance: 10, coordinateSpace: .named("tabContainer"))
                                    .onChanged { value in
                                        guard tabManager.tabs.count > 1 else { return }
                                        guard !viewModel.isRenamingTab else { return }
                                        handleDragChanged(
                                            tabId: tab.id,
                                            translation: value.translation,
                                            slotWidth: slotWidth
                                        )
                                    }
                                    .onEnded { _ in
                                        handleDragEnded()
                                    }
                            )
                        }
                    }
                    .coordinateSpace(name: "tabContainer")
                    .frame(width: actualTabsWidth, alignment: .leading)
                    .clipped()

                    // Draggable gap between tabs and add button
                    WindowDraggableArea()
                        .frame(width: Layout.elementPadding, height: Layout.buttonHeight)

                    // Add Tab Button
                    Button {
                        tabManager.createTab(with: nil)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(theme.secondaryText)
                            .frame(width: Layout.addTabButtonWidth, height: Layout.buttonHeight)
                            .contentShape(Rectangle())
                            .hoverHighlight(color: theme.toggleHoverBg)
                    }
                    .buttonStyle(.plain)
                    .instantTooltip(String(localized: "tooltip.new_tab"), position: .bottom)

                    // Draggable gap between add button and remaining space
                    WindowDraggableArea()
                        .frame(width: Layout.elementPadding, height: Layout.buttonHeight)

                    // Remaining space — allows window dragging from the tab bar gap
                    WindowDraggableArea()
                        .frame(maxWidth: .infinity)
                        .frame(height: Layout.buttonHeight)
                }

                // Bottom margin strip (draggable)
                WindowDraggableArea()
                    .frame(maxWidth: .infinity)
                    .frame(height: 5)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: 40)
        .background(theme.tabBarBackground)
        .contentShape(Rectangle())
        .onTapGesture {
            if viewModel.isRenamingTab {
                viewModel.requestCommitTabRename()
            }
        }
    }

    // MARK: - Drag Reorder

    private func visualOffsetForTab(_ tabId: UUID, slotWidth: CGFloat) -> CGFloat {
        guard draggedTabId != nil else { return 0 }
        if tabId == draggedTabId {
            return dragOffset
        }
        guard let originalIndex = tabManager.tabs.firstIndex(where: { $0.id == tabId }),
              let visualIndex = dragVisualOrder.firstIndex(of: tabId) else { return 0 }
        return CGFloat(visualIndex - originalIndex) * slotWidth
    }

    private func handleDragChanged(tabId: UUID, translation: CGSize, slotWidth: CGFloat) {
        if draggedTabId == nil {
            draggedTabId = tabId
            dragVisualOrder = tabManager.tabs.map(\.id)
            lastSwapOffset = 0
            tabManager.selectTab(id: tabId)
        }

        dragOffset = translation.width

        guard let currentVisualIndex = dragVisualOrder.firstIndex(of: tabId) else { return }
        let relativeOffset = dragOffset - lastSwapOffset
        let hysteresisBuffer = min(slotWidth * 0.15, 12)
        let threshold = slotWidth * 0.5 + hysteresisBuffer

        if currentVisualIndex < dragVisualOrder.count - 1, relativeOffset > threshold {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                dragVisualOrder.swapAt(currentVisualIndex, currentVisualIndex + 1)
            }
            lastSwapOffset += slotWidth
        } else if currentVisualIndex > 0, relativeOffset < -threshold {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                dragVisualOrder.swapAt(currentVisualIndex, currentVisualIndex - 1)
            }
            lastSwapOffset -= slotWidth
        }
    }

    private func handleDragEnded() {
        guard let draggedId = draggedTabId,
              let originalIndex = tabManager.tabs.firstIndex(where: { $0.id == draggedId }),
              let finalIndex = dragVisualOrder.firstIndex(of: draggedId) else {
            draggedTabId = nil
            dragOffset = 0
            dragVisualOrder = []
            lastSwapOffset = 0
            return
        }
        if originalIndex != finalIndex {
            tabManager.moveTab(fromIndex: originalIndex, toIndex: finalIndex)
        }
        draggedTabId = nil
        dragOffset = 0
        dragVisualOrder = []
        lastSwapOffset = 0
    }
}

struct TabItemView: View {
    let tab: JSONTab
    let isActive: Bool
    let isHovered: Bool
    let isDragging: Bool
    let tabWidth: CGFloat
    let showGradient: Bool
    let backgroundColor: Color
    let commitSignal: Int
    let onSelect: () -> Void
    let onClose: () -> Void
    let onHover: (Bool) -> Void
    let onRename: (String?) -> Void
    let onStartEditing: () -> Void
    let onFinishEditing: () -> Void

    @Environment(AppSettings.self) var settings
    private var theme: AppTheme { settings.currentTheme }

    @State private var isEditing = false
    @State private var editingText = ""
    @FocusState private var isTextFieldFocused: Bool

    private enum Layout {
        static let closeButtonWidth: CGFloat = 14
        static let horizontalPadding: CGFloat = 8
        static let spacing: CGFloat = 4
    }

    private var availableTextWidth: CGFloat {
        tabWidth - (Layout.horizontalPadding * 2) - Layout.closeButtonWidth - Layout.spacing
    }

    private var textWithGradient: some View {
        ZStack {
            if isEditing {
                HStack(spacing: 2) {
                    TextField("", text: $editingText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .fontWeight(isActive ? .semibold : .regular)
                        .foregroundColor(theme.primaryText)
                        .multilineTextAlignment(.leading)
                        .focused($isTextFieldFocused)
                        .lineLimit(1)
                        .onChange(of: editingText) { _, newValue in
                            if newValue.count > 16 {
                                editingText = String(newValue.prefix(16))
                            }
                        }
                        .onSubmit { commitRename() }
                        .onKeyPress(.escape) {
                            cancelEditing()
                            return .handled
                        }
                        .onChange(of: isTextFieldFocused) { _, focused in
                            if !focused && isEditing {
                                commitRename()
                            }
                        }
                        .onChange(of: commitSignal) { _, _ in
                            if isEditing { commitRename() }
                        }
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(theme.secondaryText)
                                .frame(height: 1)
                        }

                    if editingText.count >= 20 {
                        Text("20/20")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(theme.secondaryText)
                            .fixedSize()
                    }
                }
            } else {
                Text(tab.displayTitle)
                    .font(.system(size: 12, design: .monospaced))
                    .fontWeight(isActive ? .semibold : .regular)
                    .foregroundColor(isActive ? theme.primaryText : theme.secondaryText)
                    .fixedSize(horizontal: true, vertical: false)
                    .lineLimit(1)
            }
        }
        .frame(width: availableTextWidth, alignment: .center)
        .clipped()
        .overlay(alignment: .leading) {
            if showGradient && !isEditing {
                LinearGradient(
                    colors: [backgroundColor, backgroundColor.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 20)
            }
        }
    }

    var body: some View {
        HStack(spacing: Layout.spacing) {
            textWithGradient
            if !isDragging {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(isActive ? theme.primaryText : theme.secondaryText)
                    .frame(width: Layout.closeButtonWidth, height: Layout.closeButtonWidth)
                    .contentShape(Rectangle())
                    .hoverHighlight(color: theme.toggleHoverBg, cornerRadius: 3)
                    .onTapGesture {
                        onClose()
                    }
            }
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, 6)
        .frame(width: tabWidth)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(backgroundColor)
                .shadow(
                    color: isActive ? Color.black.opacity(theme.shadowOpacity) : Color.clear,
                    radius: 2,
                    x: 0,
                    y: 1
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(strokeColor, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditing { onSelect() }
        }
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    if !isEditing { startEditing() }
                }
        )
        .contextMenu {
            if !isDragging {
                Button(String(localized: "tab.context.rename")) {
                    startEditing()
                }
                Divider()
                Button(String(localized: "tab.context.close")) {
                    onClose()
                }
            }
        }
        .onHover { hovering in
            onHover(hovering)
        }
    }

    private var strokeColor: Color {
        if isActive {
            return theme.activeTabBorder
        } else {
            return theme.inactiveTabBorder
        }
    }

    private func startEditing() {
        editingText = tab.displayTitle
        isEditing = true
        onStartEditing()
        DispatchQueue.main.async {
            isTextFieldFocused = true
        }
    }

    private func commitRename() {
        guard isEditing else { return }
        isEditing = false
        isTextFieldFocused = false
        onFinishEditing()

        let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onRename(trimmed)
        }
    }

    private func cancelEditing() {
        isEditing = false
        isTextFieldFocused = false
        onFinishEditing()
    }
}

/// SwiftUI wrapper for WindowDraggableNSView — placed in empty tab bar space
/// so users can drag the window from there.
private struct WindowDraggableArea: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDraggableNSView { WindowDraggableNSView() }
    func updateNSView(_ nsView: WindowDraggableNSView, context: Context) {}
}

#Preview {
    TabBarView(tabManager: {
        let manager = TabManager.shared
        manager.createTab(with: "{\"test\": 1}")
        manager.createTab(with: "{\"test\": 2}")
        manager.createTab(with: "{\"test\": 3}")
        return manager
    }())
    .environment(AppSettings.shared)
    .frame(width: 600, height: 40)
}
