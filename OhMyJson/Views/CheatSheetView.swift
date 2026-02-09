//
//  CheatSheetView.swift
//  OhMyJson
//

import SwiftUI

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
            ShortcutItem(action: "Settings", keys: "⌘,"),
            ShortcutItem(action: "Quit", keys: "⌘Q"),
        ]),
        ShortcutGroup(title: "Tabs", items: [
            ShortcutItem(action: "New Tab", keys: "⌘N"),
            ShortcutItem(action: "Close Tab", keys: "⌘W"),
            ShortcutItem(action: "Previous Tab", keys: "⇧⌘["),
            ShortcutItem(action: "Next Tab", keys: "⇧⌘]"),
        ]),
        ShortcutGroup(title: "View", items: [
            ShortcutItem(action: "Beautify Mode", keys: "⌘1"),
            ShortcutItem(action: "Tree Mode", keys: "⌘2"),
        ]),
        ShortcutGroup(title: "Search", items: [
            ShortcutItem(action: "Find", keys: "⌘F"),
            ShortcutItem(action: "Close Search", keys: "ESC"),
            ShortcutItem(action: "Navigate Results", keys: "↑/↓"),
        ]),
        ShortcutGroup(title: "Edit", items: [
            ShortcutItem(action: "Undo", keys: "⌘Z"),
            ShortcutItem(action: "Redo", keys: "⇧⌘Z"),
            ShortcutItem(action: "Copy / Paste / Cut", keys: "⌘C / ⌘V / ⌘X"),
        ]),
    ]
}

// MARK: - Cheat Sheet Button

struct CheatSheetButton: View {
    @Binding var isVisible: Bool

    @ObservedObject private var settings = AppSettings.shared
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
                withAnimation(.easeInOut(duration: 0.15)) {
                    isVisible.toggle()
                }
            }) {
                Image(systemName: "keyboard")
                    .font(.system(size: 14))
                    .foregroundColor(theme.secondaryText)
                    .frame(width: 32, height: 32)
                    .background(theme.secondaryBackground)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(theme.border, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(theme.shadowOpacity), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
        }
    }

    private func dismiss() {
        withAnimation(.easeInOut(duration: 0.15)) {
            isVisible = false
        }
    }
}

// MARK: - Cheat Sheet Panel

private struct CheatSheetPanel: View {
    let onDismiss: () -> Void

    @ObservedObject private var settings = AppSettings.shared
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
            ScrollView(.vertical, showsIndicators: false) {
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

#endif
