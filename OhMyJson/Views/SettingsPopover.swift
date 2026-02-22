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
        let wasRecording = nsView.isRecording
        nsView.isRecording = isRecording
        if isRecording && !wasRecording {
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

// MARK: - Settings Window View

struct SettingsWindowView: View {
    @Environment(AppSettings.self) var settings
    @State private var isRecordingHotKey = false
    @State private var lastUpdateCheckDate: Date? = UserDefaults.standard.object(forKey: "SULastCheckTime") as? Date

    private var theme: AppTheme { settings.currentTheme }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Version \(version)"
    }

    var body: some View {
        @Bindable var settings = settings

        VStack(spacing: 0) {
            // Header
            headerSection

            divider

            // General settings
            VStack(alignment: .leading, spacing: 10) {
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

                // Theme
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

                // Default View
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

                // Ignore Escape Sequences
                settingsCard {
                    HStack {
                        Text("Ignore escape sequences on view")
                            .font(.system(size: 13))
                            .foregroundColor(theme.primaryText)
                        Spacer()
                        Toggle("", isOn: $settings.ignoreEscapeSequences)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            divider

            // Hotkey section
            hotKeySection(combo: $settings.openHotKeyCombo)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .zIndex(1)

            divider

            // Updates section
            VStack(alignment: .leading, spacing: 10) {
                settingsCard {
                    HStack {
                        Text(String(localized: "settings.updates.auto_check"))
                            .font(.system(size: 13))
                            .foregroundColor(theme.primaryText)
                        Spacer()
                        Toggle("", isOn: $settings.autoCheckForUpdates)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }

                HStack {
                    checkForUpdatesButton

                    Spacer()

                    if let date = lastUpdateCheckDate {
                        Text("Last checked: \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 11))
                            .foregroundColor(theme.secondaryText)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            divider

            // Footer
            footerSection
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: 500)
        .fixedSize(horizontal: true, vertical: true)
        .background(theme.secondaryBackground)
        .preferredColorScheme(theme.colorScheme)
        .onChange(of: isRecordingHotKey) { oldValue, newValue in
            if newValue {
                HotKeyManager.shared.suspend()
            } else if oldValue {
                HotKeyManager.shared.resume()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .cornerRadius(12)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("OhMyJson")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(theme.primaryText)
                Text(versionString)
                    .font(.system(size: 12))
                    .foregroundColor(theme.secondaryText)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Hotkey Section

    private var hotKeyTooltipContent: some View {
        (
            Text(String(localized: "settings.hotkeys.help.prefix"))
            + Text(String(localized: "settings.hotkeys.help.bold")).bold()
            + Text(String(localized: "settings.hotkeys.help.suffix"))
        )
        .lineSpacing(2)
    }

    private func hotKeySection(combo: Binding<HotKeyCombo>) -> some View {
        settingsCard {
            HStack(spacing: 8) {
                Text(String(localized: "settings.hotkeys.open"))
                    .font(.system(size: 13))
                    .foregroundColor(theme.primaryText)

                InfoTooltipIcon(tooltipPosition: .top) {
                    hotKeyTooltipContent
                }

                Spacer()

                // Hotkey recorder control
                Button(action: {
                    isRecordingHotKey.toggle()
                }) {
                    HStack(spacing: 0) {
                        // Left: content
                        Group {
                            if isRecordingHotKey {
                                shimmerText(String(localized: "settings.hotkeys.type_hotkey"))
                            } else {
                                Text(combo.wrappedValue.displayString)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(theme.primaryText)
                            }
                        }
                        .frame(minWidth: 80)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)

                        // Vertical divider
                        Rectangle()
                            .fill(theme.border)
                            .frame(width: 1)
                            .padding(.vertical, 5)

                        // Right: action icon
                        Image(systemName: isRecordingHotKey ? "arrow.counterclockwise" : "xmark")
                            .font(.system(size: 11))
                            .foregroundColor(theme.secondaryText)
                            .frame(width: 30)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.secondaryBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isRecordingHotKey ? theme.accent : theme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .overlay {
                HotKeyRecorderView(
                    isRecording: $isRecordingHotKey,
                    hotKeyCombo: combo
                )
                .frame(width: 1, height: 1)
                .opacity(0)
            }
        }
    }

    private func shimmerText(_ text: String) -> some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let phase = CGFloat(time.truncatingRemainder(dividingBy: 1.5) / 1.5)

            Text(text)
                .font(.system(size: 12))
                .foregroundColor(theme.secondaryText.opacity(0.3))
                .overlay {
                    GeometryReader { geo in
                        let bandWidth = geo.size.width * 0.5
                        let travel = geo.size.width + bandWidth

                        Text(text)
                            .font(.system(size: 12))
                            .foregroundColor(theme.secondaryText)
                            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                            .mask {
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0),
                                        .init(color: .black, location: 0.3),
                                        .init(color: .black, location: 0.7),
                                        .init(color: .clear, location: 1),
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: bandWidth)
                                .offset(x: -bandWidth + travel * phase)
                            }
                    }
                }
        }
    }
 
    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: 10) {
            aboutButton(title: String(localized: "settings.about.github"), customIcon: "github_mark") {
                if let url = URL(string: "https://github.com/vagabond95/OhMyJson") {
                    NSWorkspace.shared.open(url)
                }
            }

            aboutButton(title: String(localized: "settings.about.chrome_plugin"), customIcon: "chrome_logo") {
                if let url = URL(string: "https://chromewebstore.google.com/detail/ohmyjson-open-in-json-vie/bmfbdagmfcaibmpngdkpdendfonpepde") {
                    NSWorkspace.shared.open(url)
                }
            }

            aboutButton(title: String(localized: "settings.about.report_bug"), icon: "ladybug") {
                if let url = URL(string: "https://github.com/vagabond95/OhMyJson/issues") {
                    NSWorkspace.shared.open(url)
                }
            }

            Spacer()

            aboutButton(title: String(localized: "settings.about.quit"), icon: "power", isDestructive: true) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    // MARK: - Check for Updates Button

    private var checkForUpdatesButton: some View {
        Button {
            NotificationCenter.default.post(name: .checkForUpdates, object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                lastUpdateCheckDate = UserDefaults.standard.object(forKey: "SULastCheckTime") as? Date
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11))
                Text(String(localized: "settings.updates.check_now"))
                    .font(.system(size: 13))
            }
            .foregroundColor(theme.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(theme.panelBackground)
                    .shadow(
                        color: .black.opacity(theme.colorScheme == .dark ? 0.4 : 0.1),
                        radius: theme.colorScheme == .dark ? 2 : 1,
                        x: 0, y: 1
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        LinearGradient(
                            colors: theme.colorScheme == .dark
                                ? [.white.opacity(0.12), .white.opacity(0.04)]
                                : [.white.opacity(0.6), .white.opacity(0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(theme.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var divider: some View {
        Rectangle()
            .fill(theme.border)
            .frame(height: 1)
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
                        .toolbarIconHover(isActive: isSelected)
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
                        .toolbarIconHover(isActive: isSelected)
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

    private func aboutButton(title: String, icon: String? = nil, customIcon: String? = nil, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let customIcon {
                    Image(customIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 11, height: 11)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                }
                Text(title)
                    .font(.system(size: 12))
            }
            .foregroundColor(isDestructive ? theme.accent : theme.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(theme.panelBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isDestructive ? theme.accent.opacity(0.4) : theme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
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
