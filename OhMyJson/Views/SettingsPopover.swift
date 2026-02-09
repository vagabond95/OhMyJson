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

        if event.keyCode == 53 {
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
    @ObservedObject var settings = AppSettings.shared
    @State private var isRecordingOpenHotKey = false

    private var theme: AppTheme { settings.currentTheme }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Version \(version)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            aboutSection

            Rectangle()
                .fill(theme.border)
                .frame(height: 1)

            hotKeysSection
            jsonIndentSection

        }
        .padding(16)
        .frame(width: 300)
        .background(theme.secondaryBackground)
        .preferredColorScheme(theme.colorScheme)
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(spacing: 6) {
            Text("OhMyJson")
                .font(.system(.title2, design: .monospaced).bold())
                .foregroundColor(theme.primaryText)

            Text(versionString)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(theme.secondaryText)

            Button(action: {
                if let url = URL(string: "https://github.com/vagabond95/OhMyJson") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                HStack(spacing: 4) {
                    Image("github_mark")
                        .resizable()
                        .frame(width: 14, height: 14)
                    Text("GitHub")
                        .font(.system(.caption, design: .monospaced))
                }
                .foregroundColor(theme.secondaryText)
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
        .frame(maxWidth: .infinity)
    }

    // MARK: - Hotkeys Section

    private var hotKeysSection: some View {
        VStack(alignment: .center, spacing: 12) {
            Text("Hotkey")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundColor(theme.secondaryText)

            hotKeyRow(
                label: "",
                isRecording: $isRecordingOpenHotKey,
                hotKeyCombo: $settings.openHotKeyCombo,
                displayString: settings.openHotKeyCombo.displayString
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func hotKeyRow(
        label: String,
        isRecording: Binding<Bool>,
        hotKeyCombo: Binding<HotKeyCombo>,
        displayString: String
    ) -> some View {
        ZStack(alignment: .center) {
            HotKeyRecorderView(
                isRecording: isRecording,
                hotKeyCombo: hotKeyCombo
            )
            .frame(width: 1, height: 1)
            .opacity(0)

            Button(action: {
                isRecording.wrappedValue = true
            }) {
                Text(isRecording.wrappedValue ? "Press keys..." : displayString)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(theme.primaryText)
                    .frame(minWidth: 100)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isRecording.wrappedValue ? theme.accent.opacity(0.2) : theme.panelBackground)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isRecording.wrappedValue ? theme.accent : theme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - JSON Indent Section

    private var jsonIndentSection: some View {
        VStack(alignment: .center, spacing: 8) {
            Text("JSON Indent")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundColor(theme.secondaryText)

            HStack {
                Spacer()
                
                HStack(spacing: 0) {
                    ForEach([2, 4], id: \.self) { size in
                        Button(action: { settings.jsonIndent = size }) {
                            Text("\(size)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(settings.jsonIndent == size ? theme.primaryText : theme.secondaryText)
                                .frame(width: 50)
                                .padding(.vertical, 4)
                                .background(settings.jsonIndent == size ? theme.panelBackground : Color.clear)
                                .cornerRadius(4)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(theme.background)
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.border, lineWidth: 1))

                Spacer()
            }
        }
    }

}

struct SettingsWindowView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsWindowView()
    }
}
#endif
