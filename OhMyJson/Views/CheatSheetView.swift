//
//  CheatSheetView.swift
//  OhMyJson
//

import SwiftUI
import AppKit

#if os(macOS)

// MARK: - Shortcut Data

private struct ShortcutItem {
    let action: String
    let keys: String
}

private struct ShortcutGroup {
    let title: String
    let items: [ShortcutItem]
}

private func makeShortcutGroups(openHotKey: String) -> [ShortcutGroup] {
    [
        ShortcutGroup(title: "General", items: [
            ShortcutItem(action: "Import JSON from clipboard", keys: openHotKey),
            ShortcutItem(action: "Settings", keys: AppShortcut.settings.displayString),
            ShortcutItem(action: "Quit", keys: AppShortcut.quit.displayString),
        ]),
        ShortcutGroup(title: "Tab", items: [
            ShortcutItem(action: "New Tab", keys: AppShortcut.newTab.displayString),
            ShortcutItem(action: "Close Tab", keys: AppShortcut.closeTab.displayString),
            ShortcutItem(action: "Rename Tab", keys: "Double-click"),
            ShortcutItem(action: "Previous Tab", keys: AppShortcut.previousTab.displayString),
            ShortcutItem(action: "Next Tab", keys: AppShortcut.nextTab.displayString),
        ]),
        ShortcutGroup(title: "View", items: [
            ShortcutItem(action: "Beautify Mode", keys: AppShortcut.beautifyMode.displayString),
            ShortcutItem(action: "Tree Mode", keys: AppShortcut.treeMode.displayString),
            ShortcutItem(action: "Compare Mode", keys: AppShortcut.compareMode.displayString),
        ]),
        ShortcutGroup(title: "Search", items: [
            ShortcutItem(action: "Find", keys: AppShortcut.find.displayString),
            ShortcutItem(action: "Find Next", keys: AppShortcut.findNext.displayString),
            ShortcutItem(action: "Find Previous", keys: AppShortcut.findPrevious.displayString),
            ShortcutItem(action: "Close Search", keys: "ESC"),
        ]),
        ShortcutGroup(title: "Tree", items: [
            ShortcutItem(action: "Move Up", keys: "↑"),
            ShortcutItem(action: "Move Down", keys: "↓"),
            ShortcutItem(action: "Expand / Move Right", keys: "→"),
            ShortcutItem(action: "Collapse / Move Left", keys: "←"),
            ShortcutItem(action: "Expand All", keys: AppShortcut.expandAll.displayString),
            ShortcutItem(action: "Collapse All", keys: AppShortcut.collapseAll.displayString),
        ]),
    ]
}

// MARK: - Cheat Sheet Button

struct CheatSheetButton: View {
    @Binding var isVisible: Bool

    @Environment(AppSettings.self) var settings
    private var theme: AppTheme { settings.currentTheme }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Cheat sheet panel
            if isVisible {
                CheatSheetPanel(onDismiss: { dismiss() })
                    .padding(.bottom, 44)
                    .transition(.opacity)
            }

            // Floating ? button
            Button(action: {
                withAnimation(.easeInOut(duration: Animation.quick)) {
                    isVisible.toggle()
                }
            }) {
                Image(systemName: "keyboard")
                    .font(.system(size: 14))
                    .frame(width: 32, height: 32)
                    .background(theme.secondaryBackground)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(theme.border, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(theme.shadowOpacity), radius: 4, x: 0, y: 2)
                    .contentShape(Rectangle())
                    .toolbarIconHover()
                    .instantTooltip("Shortcuts")
            }
            .buttonStyle(.plain)
        }
    }

    private func dismiss() {
        withAnimation(.easeInOut(duration: Animation.quick)) {
            isVisible = false
        }
    }
}

// MARK: - Cheat Sheet Panel

private struct CheatSheetPanel: View {
    let onDismiss: () -> Void

    @Environment(AppSettings.self) var settings
    private var theme: AppTheme { settings.currentTheme }

    private var groups: [ShortcutGroup] {
        makeShortcutGroups(openHotKey: settings.openHotKeyCombo.displayString)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.primaryText)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(theme.secondaryText)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // Groups
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(groups.indices, id: \.self) { index in
                        if index > 0 {
                            Rectangle()
                                .fill(theme.border)
                                .frame(height: 1)
                        }
                        shortcutGroupView(groups[index])
                    }
                }
                .padding(.trailing, 10)
                .background(AlwaysVisibleScrollBar())
            }
            .frame(maxHeight: 340)
        }
        .padding(12)
        .frame(width: 280)
        .background(theme.secondaryBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(theme.shadowOpacity), radius: 8, x: 0, y: 4)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }

    private func shortcutGroupView(_ group: ShortcutGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(theme.secondaryText)
                .textCase(.uppercase)

            VStack(spacing: 2) {
                ForEach(group.items.indices, id: \.self) { index in
                    shortcutRow(group.items[index])
                }
            }
        }
    }

    private func shortcutRow(_ item: ShortcutItem) -> some View {
        HStack {
            Text(item.action)
                .font(.system(size: 11))
                .foregroundColor(theme.primaryText)
            Spacer()
            Text(item.keys)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(theme.secondaryText)
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Always Visible Scroll Bar

/// NSViewRepresentable that finds the enclosing NSScrollView and sets legacy scroller style
/// so the scrollbar is always visible, making it clear that content is scrollable.
private struct AlwaysVisibleScrollBar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let scrollView = view.enclosingScrollView {
                scrollView.scrollerStyle = .legacy
                scrollView.hasVerticalScroller = true
                scrollView.autohidesScrollers = false
                scrollView.verticalScroller = ClearTrackScroller()
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

#endif
