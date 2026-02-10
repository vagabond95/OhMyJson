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

    @State private var hoveredTabId: UUID?

    private var theme: AppTheme { settings.currentTheme }

    private enum Layout {
        static let fixedTabWidth: CGFloat = 150
        static let tabSpacing: CGFloat = 6
        static let elementPadding: CGFloat = 10
        static let themeButtonWidth: CGFloat = 30
        static let addTabButtonWidth: CGFloat = 10
        static let buttonHeight: CGFloat = 28
        static let trafficLightWidth: CGFloat = 60
    }

    private func maxTabAreaWidth(totalWidth: CGFloat) -> CGFloat {
        let fixedElements = Layout.trafficLightWidth + Layout.themeButtonWidth + Layout.addTabButtonWidth
        let gaps = Layout.elementPadding * 3          // 3 gaps between 4 elements
        let edgePadding = Layout.elementPadding * 2   // .padding(.horizontal)
        return max(totalWidth - fixedElements - gaps - edgePadding, 0)
    }

    private func calculatedTabWidth(tabCount: Int, availableWidth: CGFloat) -> CGFloat {
        guard tabCount > 0 else { return Layout.fixedTabWidth }
        let totalSpacing = CGFloat(tabCount - 1) * Layout.tabSpacing
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
            let isCompressed = tabWidth < Layout.fixedTabWidth

            let actualTabsWidth = min(
                        CGFloat(tabManager.tabs.count) * tabWidth + CGFloat(max(0, tabManager.tabs.count - 1)) * Layout.tabSpacing,
                        maxTabWidth
                    )

            HStack(spacing: Layout.elementPadding) {
                // Traffic light area
                Color.clear
                    .frame(width: Layout.trafficLightWidth, height: Layout.buttonHeight)

                // Theme toggle button
                Button(action: {
                    settings.toggleTheme()
                }) {
                    Image(systemName: settings.isDarkMode ? "moon.fill" : "sun.max.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(theme.secondaryText)
                        .frame(width: Layout.themeButtonWidth, height: Layout.buttonHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .instantTooltip(String(localized: "tooltip.toggle_theme"), position: .bottom)

                // Tab container (weight(1f) equivalent)
                HStack(spacing: Layout.tabSpacing) {
                    ForEach(tabManager.tabs) { tab in
                        let isActive = tab.id == tabManager.activeTabId
                        let isHovered = tab.id == hoveredTabId
                        TabItemView(
                            tab: tab,
                            isActive: isActive,
                            isHovered: isHovered,
                            tabWidth: tabWidth,
                            showGradient: isCompressed,
                            backgroundColor: tabBackgroundColor(
                                isActive: isActive,
                                isHovered: isHovered
                            ),
                            onSelect: {
                                tabManager.selectTab(id: tab.id)
                            },
                            onClose: {
                                tabManager.closeTab(id: tab.id)
                            },
                            onHover: { isHovering in
                                hoveredTabId = isHovering ? tab.id : nil
                            }
                        )
                    }
                }
                .frame(width: actualTabsWidth, alignment: .leading)
                .clipped()

                // Add Tab Button
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.secondaryText)
                    .frame(width: Layout.addTabButtonWidth, height: Layout.buttonHeight)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        tabManager.createTab(with: nil)
                    }
                    .instantTooltip(String(localized: "tooltip.new_tab"), position: .bottom)
            }
            .padding(.horizontal, Layout.elementPadding)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
        }
        .frame(height: 40)
        .background(theme.tabBarBackground)
    }
}

struct TabItemView: View {
    let tab: JSONTab
    let isActive: Bool
    let isHovered: Bool
    let tabWidth: CGFloat
    let showGradient: Bool
    let backgroundColor: Color
    let onSelect: () -> Void
    let onClose: () -> Void
    let onHover: (Bool) -> Void

    @Environment(AppSettings.self) var settings
    private var theme: AppTheme { settings.currentTheme }

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
            Text(tab.title)
                .font(.system(size: 12, design: .monospaced))
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundColor(isActive ? theme.primaryText : theme.secondaryText)
                .fixedSize(horizontal: true, vertical: false)
                .lineLimit(1)
        }
        .frame(width: availableTextWidth, alignment: .trailing)
        .clipped()
        .overlay(alignment: .leading) {
            if showGradient {
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

            // Close button
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(isActive ? theme.primaryText : theme.secondaryText)
                .frame(width: Layout.closeButtonWidth, height: Layout.closeButtonWidth)
                .contentShape(Rectangle())
                .onTapGesture {
                    onClose()
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
            onSelect()
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
