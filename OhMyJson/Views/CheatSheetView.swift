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
        ShortcutGroup(title: String(localized: "shortcuts.group.general"), items: [
            ShortcutItem(action: String(localized: "shortcuts.import_json"), keys: openHotKey),
            ShortcutItem(action: String(localized: "shortcuts.settings"), keys: AppShortcut.settings.displayString),
            ShortcutItem(action: String(localized: "shortcuts.quit"), keys: AppShortcut.quit.displayString),
        ]),
        ShortcutGroup(title: String(localized: "shortcuts.group.tabs"), items: [
            ShortcutItem(action: String(localized: "shortcuts.new_tab"), keys: AppShortcut.newTab.displayString),
            ShortcutItem(action: String(localized: "shortcuts.close_tab"), keys: AppShortcut.closeTab.displayString),
            ShortcutItem(action: String(localized: "shortcuts.previous_tab"), keys: AppShortcut.previousTab.displayString),
            ShortcutItem(action: String(localized: "shortcuts.next_tab"), keys: AppShortcut.nextTab.displayString),
        ]),
        ShortcutGroup(title: String(localized: "shortcuts.group.view"), items: [
            ShortcutItem(action: String(localized: "shortcuts.beautify_mode"), keys: AppShortcut.beautifyMode.displayString),
            ShortcutItem(action: String(localized: "shortcuts.tree_mode"), keys: AppShortcut.treeMode.displayString),
        ]),
        ShortcutGroup(title: String(localized: "shortcuts.group.search"), items: [
            ShortcutItem(action: String(localized: "shortcuts.find"), keys: AppShortcut.find.displayString),
            ShortcutItem(action: String(localized: "shortcuts.find_next"), keys: AppShortcut.findNext.displayString),
            ShortcutItem(action: String(localized: "shortcuts.find_previous"), keys: AppShortcut.findPrevious.displayString),
            ShortcutItem(action: String(localized: "shortcuts.close_search"), keys: "ESC"),
        ]),
        ShortcutGroup(title: String(localized: "shortcuts.group.tree"), items: [
            ShortcutItem(action: String(localized: "shortcuts.move_up"), keys: "↑"),
            ShortcutItem(action: String(localized: "shortcuts.move_down"), keys: "↓"),
            ShortcutItem(action: String(localized: "shortcuts.expand_node"), keys: "→"),
            ShortcutItem(action: String(localized: "shortcuts.collapse_node"), keys: "←"),
            ShortcutItem(action: String(localized: "shortcuts.expand_all"), keys: AppShortcut.expandAll.displayString),
            ShortcutItem(action: String(localized: "shortcuts.collapse_all"), keys: AppShortcut.collapseAll.displayString),
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
                    .toolbarIconHover()
                    .instantTooltip("Shortcuts")
                    .frame(width: 32, height: 32)
                    .background(theme.secondaryBackground)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(theme.border, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(theme.shadowOpacity), radius: 4, x: 0, y: 2)
                    .contentShape(Rectangle())
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
                Text("shortcuts.title")
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
