//
//  SettingsPopover.swift
//  OhMyJson
//

import SwiftUI
import Carbon.HIToolbox
import AppKit

#if os(macOS)

// MARK: - HotKey Recorder View

struct HotKeyRecorderView: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var hotKeyCombo: HotKeyCombo

    func makeNSView(context: Context) -> HotKeyRecorderNSView {
        let view = HotKeyRecorderNSView()
        view.onKeyRecorded = { keyCode, modifiers in
            hotKeyCombo = HotKeyCombo(keyCode: keyCode, modifiers: modifiers)
            isRecording = false
        }
        view.onCancel = {
            isRecording = false
        }
        return view
    }

    func updateNSView(_ nsView: HotKeyRecorderNSView, context: Context) {
        nsView.isRecording = isRecording
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

class HotKeyRecorderNSView: NSView {
    var isRecording = false
    var onKeyRecorded: ((UInt32, UInt32) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == KeyCode.escape {
            onCancel?()
            return
        }

        let keyCode = UInt32(event.keyCode)
        var modifiers: UInt32 = 0

        if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }

        if modifiers != 0 {
            onKeyRecorded?(keyCode, modifiers)
        }
    }
}

// MARK: - Settings Tab Enum

private enum SettingsTab: String, CaseIterable {
    case general = "General"
    case hotkeys = "Hotkeys"
    case about = "About"

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .hotkeys: return "keyboard"
        case .about: return "info.circle"
        }
    }

    var localizedName: String {
        switch self {
        case .general: return String(localized: "settings.tab.general")
        case .hotkeys: return String(localized: "settings.tab.hotkeys")
        case .about: return String(localized: "settings.tab.about")
        }
    }
}

// MARK: - Settings Window View

struct SettingsWindowView: View {
    @Environment(AppSettings.self) var settings
    @State private var selectedTab: SettingsTab = .general

    private var theme: AppTheme { settings.currentTheme }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            SettingsSidebar(selectedTab: $selectedTab)

            // Divider
            Rectangle()
                .fill(theme.border)
                .frame(width: 1)

            // Content area
            VStack(alignment: .leading, spacing: 0) {
                // Tab content
                ScrollView {
                    Group {
                        switch selectedTab {
                        case .general:
                            GeneralSettingsView()
                        case .hotkeys:
                            HotkeysSettingsView()
                        case .about:
                            AboutSettingsView()
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.secondaryBackground)
        }
        .frame(width: 600, height: 440)
        .background(theme.secondaryBackground)
        .preferredColorScheme(theme.colorScheme)
    }
}

// MARK: - Settings Sidebar

private struct SettingsSidebar: View {
    @Binding var selectedTab: SettingsTab
    @Environment(AppSettings.self) var settings
    @State private var hoveredTab: SettingsTab?

    private var theme: AppTheme { settings.currentTheme }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("OhMyJson")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(theme.primaryText)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            // Tab list
            VStack(spacing: 2) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    sidebarItem(tab)
                }
            }
            .padding(.horizontal, 8)

            Spacer()
        }
        .frame(width: 180)
        .background(theme.background)
    }

    private func sidebarItem(_ tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab
        let isHovered = hoveredTab == tab

        return Button(action: { selectedTab = tab }) {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                Text(tab.localizedName)
                    .font(.system(size: 13))
                Spacer()
            }
            .foregroundColor(theme.primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? theme.selectionBg : (isHovered ? theme.hoverBg : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredTab = hovering ? tab : nil
        }
    }
}

// MARK: - General Settings View

private struct GeneralSettingsView: View {
    @Environment(AppSettings.self) var settings

    private var theme: AppTheme { settings.currentTheme }

    var body: some View {
        @Bindable var settings = settings

        VStack(alignment: .leading, spacing: 16) {
            // Launch at Login
            settingsCard {
                HStack {
                    Text(String(localized: "settings.general.launch_at_login"))
                        .font(.system(size: 13))
                        .foregroundColor(theme.primaryText)
                    Spacer()
                    Toggle("", isOn: $settings.launchAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            // Appearance
            settingsCard {
                HStack {
                    Text(String(localized: "settings.general.appearance"))
                        .font(.system(size: 13))
                        .foregroundColor(theme.primaryText)
                    Spacer()
                    segmentedControl(
                        options: ThemeMode.allCases,
                        selection: $settings.themeMode,
                        label: { mode in
                            switch mode {
                            case .light: return String(localized: "settings.general.appearance.light")
                            case .dark: return String(localized: "settings.general.appearance.dark")
                            }
                        }
                    )
                }
            }

            // Default View Mode
            settingsCard {
                HStack {
                    Text(String(localized: "settings.general.default_view"))
                        .font(.system(size: 13))
                        .foregroundColor(theme.primaryText)
                    Spacer()
                    segmentedControl(
                        options: ViewMode.allCases,
                        selection: $settings.defaultViewMode,
                        label: { mode in mode.rawValue }
                    )
                }
            }

            // JSON Indent
            settingsCard {
                HStack {
                    Text(String(localized: "settings.general.json_indent"))
                        .font(.system(size: 13))
                        .foregroundColor(theme.primaryText)
                    Spacer()
                    indentSegment
                }
            }
        }
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.panelBackground)
            )
    }

    private func segmentedControl<T: Hashable>(
        options: [T],
        selection: Binding<T>,
        label: @escaping (T) -> String
    ) -> some View {
        HStack(spacing: 1) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let isSelected = selection.wrappedValue == option
                Button(action: { selection.wrappedValue = option }) {
                    Text(label(option))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(isSelected ? theme.primaryText : theme.secondaryText)
                        .frame(minWidth: 54)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(isSelected ? theme.panelBackground : Color.clear)
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(isSelected ? theme.border : Color.clear, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(theme.background)
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.border, lineWidth: 1))
    }

    private var indentSegment: some View {
        HStack(spacing: 1) {
            ForEach([2, 4], id: \.self) { size in
                let isSelected = settings.jsonIndent == size
                Button(action: { settings.jsonIndent = size }) {
                    Text("\(size)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(isSelected ? theme.primaryText : theme.secondaryText)
                        .frame(width: 40)
                        .padding(.vertical, 4)
                        .background(isSelected ? theme.panelBackground : Color.clear)
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(isSelected ? theme.border : Color.clear, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(theme.background)
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.border, lineWidth: 1))
    }
}

// MARK: - Hotkeys Settings View

private struct HotkeysSettingsView: View {
    @Environment(AppSettings.self) var settings

    // Recording state — only one hotkey can be recorded at a time
    @State private var recordingAction: String?
    @State private var conflictMessage: String?

    private var theme: AppTheme { settings.currentTheme }

    var body: some View {
        @Bindable var settings = settings

        VStack(alignment: .leading, spacing: 16) {
            // Global group
            hotKeyGroup(title: String(localized: "settings.hotkeys.group.global")) {
                hotKeyRow(
                    action: "Open OhMyJson",
                    displayName: String(localized: "settings.hotkeys.open"),
                    combo: $settings.openHotKeyCombo,
                    defaultCombo: .defaultOpen
                )
            }

            // Tabs group
            hotKeyGroup(title: String(localized: "settings.hotkeys.group.tabs")) {
                hotKeyRow(
                    action: "New Tab",
                    displayName: String(localized: "settings.hotkeys.new_tab"),
                    combo: $settings.newTabHotKey,
                    defaultCombo: .defaultNewTab
                )
                hotKeyRow(
                    action: "Close Tab",
                    displayName: String(localized: "settings.hotkeys.close_tab"),
                    combo: $settings.closeTabHotKey,
                    defaultCombo: .defaultCloseTab
                )
                hotKeyRow(
                    action: "Previous Tab",
                    displayName: String(localized: "settings.hotkeys.previous_tab"),
                    combo: $settings.previousTabHotKey,
                    defaultCombo: .defaultPreviousTab
                )
                hotKeyRow(
                    action: "Next Tab",
                    displayName: String(localized: "settings.hotkeys.next_tab"),
                    combo: $settings.nextTabHotKey,
                    defaultCombo: .defaultNextTab
                )
            }

            // View group
            hotKeyGroup(title: String(localized: "settings.hotkeys.group.view")) {
                hotKeyRow(
                    action: "Beautify Mode",
                    displayName: String(localized: "settings.hotkeys.beautify_mode"),
                    combo: $settings.beautifyModeHotKey,
                    defaultCombo: .defaultBeautifyMode
                )
                hotKeyRow(
                    action: "Tree Mode",
                    displayName: String(localized: "settings.hotkeys.tree_mode"),
                    combo: $settings.treeModeHotKey,
                    defaultCombo: .defaultTreeMode
                )
                hotKeyRow(
                    action: "Find Next",
                    displayName: String(localized: "settings.hotkeys.find_next"),
                    combo: $settings.findNextHotKey,
                    defaultCombo: .defaultFindNext
                )
                hotKeyRow(
                    action: "Find Previous",
                    displayName: String(localized: "settings.hotkeys.find_previous"),
                    combo: $settings.findPreviousHotKey,
                    defaultCombo: .defaultFindPrevious
                )
            }

            // Conflict message
            if let message = conflictMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
            }
        }
    }

    private func hotKeyGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(theme.secondaryText)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.panelBackground)
            )
        }
    }

    private func hotKeyRow(
        action: String,
        displayName: String,
        combo: Binding<HotKeyCombo>,
        defaultCombo: HotKeyCombo
    ) -> some View {
        let isRecording = recordingAction == action

        return HStack(spacing: 8) {
            // Hidden HotKey recorder
            HotKeyRecorderView(
                isRecording: .init(
                    get: { isRecording },
                    set: { newValue in
                        if !newValue { recordingAction = nil }
                    }
                ),
                hotKeyCombo: .init(
                    get: { combo.wrappedValue },
                    set: { newCombo in
                        // Check for conflicts
                        if let conflict = settings.conflictingAction(for: newCombo, excluding: action) {
                            conflictMessage = String(format: String(localized: "settings.hotkeys.conflict"), newCombo.displayString, conflict)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                conflictMessage = nil
                            }
                            recordingAction = nil
                            return
                        }
                        conflictMessage = nil
                        combo.wrappedValue = newCombo
                        recordingAction = nil
                    }
                )
            )
            .frame(width: 1, height: 1)
            .opacity(0)

            // Action name
            Text(displayName)
                .font(.system(size: 13))
                .foregroundColor(theme.primaryText)

            Spacer()

            // Hotkey display button
            Button(action: {
                if isRecording {
                    recordingAction = nil
                } else {
                    recordingAction = action
                }
            }) {
                Text(isRecording ? String(localized: "settings.hotkeys.press_keys") : combo.wrappedValue.displayString)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(isRecording ? .white : theme.primaryText)
                    .frame(minWidth: 80)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isRecording ? theme.accent : theme.secondaryBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(isRecording ? theme.accent : theme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            // Reset button
            if combo.wrappedValue != defaultCombo {
                Button(action: {
                    combo.wrappedValue = defaultCombo
                    conflictMessage = nil
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(theme.secondaryText)
                }
                .buttonStyle(.plain)
                .instantTooltip(String(localized: "settings.hotkeys.reset_to_default"), position: .bottom)
            } else {
                Color.clear.frame(width: 14, height: 14)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - About Settings View

private struct AboutSettingsView: View {
    @Environment(AppSettings.self) var settings

    private var theme: AppTheme { settings.currentTheme }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Version \(version)"
    }

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // App icon
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 128, height: 128)
                    .cornerRadius(24)
            }

            // App info
            VStack(spacing: 4) {
                Text("OhMyJson")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(theme.primaryText)

                Text(versionString)
                    .font(.system(size: 13))
                    .foregroundColor(theme.secondaryText)

                Text(String(localized: "settings.about.copyright"))
                    .font(.system(size: 11))
                    .foregroundColor(theme.secondaryText)
                    .padding(.top, 2)
            }.padding(.bottom, 10)

            Spacer()

            // Bottom buttons
            HStack(spacing: 12) {
                aboutButton(title: String(localized: "settings.about.quit"), icon: "power") {
                    NSApplication.shared.terminate(nil)
                }

                aboutButton(title: String(localized: "settings.about.github"), icon: "link") {
                    if let url = URL(string: "https://github.com/vagabond95/OhMyJson") {
                        NSWorkspace.shared.open(url)
                    }
                }

                aboutButton(title: String(localized: "settings.about.report_bug"), icon: "ladybug") {
                    if let url = URL(string: "https://github.com/vagabond95/OhMyJson/issues") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func aboutButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 12))
            }
            .foregroundColor(theme.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(theme.panelBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Preview

struct SettingsWindowView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsWindowView()
            .environment(AppSettings.shared)
    }
}
#endif
