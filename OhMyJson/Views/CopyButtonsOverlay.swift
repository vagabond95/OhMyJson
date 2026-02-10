//
//  CopyButtonsOverlay.swift
//  OhMyJson
//

import SwiftUI

#if os(macOS)
struct CopyButtonsOverlay: View {
    let node: JSONNode

    @Environment(AppSettings.self) var settings
    private var theme: AppTheme { settings.currentTheme }

    private var isLeaf: Bool { !node.value.isContainer }

    var body: some View {
        HStack(spacing: 4) {
            if isLeaf {
                if node.key != nil {
                    copyButton(label: "K", tooltip: String(localized: "tooltip.copy_key")) {
                        copyKey()
                    }
                }
                copyButton(label: "V", tooltip: String(localized: "tooltip.copy_value")) {
                    copyValueOnly()
                }
                copyButton(label: "{}", tooltip: String(localized: "tooltip.copy_key_value")) {
                    copyKeyValue()
                }
            } else {
                copyButton(label: "{}", tooltip: String(localized: "tooltip.copy_json")) {
                    copyJSON()
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(theme.panelBackground)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(theme.border, lineWidth: 0.5)
        )
    }

    private func copyButton(label: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(theme.secondaryText)
                .frame(minWidth: 18, minHeight: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .instantTooltip(tooltip, position: .top)
    }

    // MARK: - Copy Actions

    private func copyKey() {
        guard let key = node.key else { return }
        ClipboardService.shared.writeText(key)
        ToastManager.shared.show(String(localized: "toast.key_copied"))
    }

    private func copyValueOnly() {
        let text: String
        switch node.value {
        case .string(let s):
            text = s
        case .number(let n):
            text = n.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", n) : String(n)
        case .bool(let b):
            text = b ? "true" : "false"
        case .null:
            text = "null"
        case .object, .array:
            text = node.value.toJSONString(prettyPrinted: true) ?? ""
        }
        ClipboardService.shared.writeText(text)
        ToastManager.shared.show(String(localized: "toast.value_copied"))
    }

    private func copyKeyValue() {
        let text: String
        if let key = node.key {
            text = "\"\(key)\": \(node.copyValue)"
        } else {
            text = node.copyValue
        }
        ClipboardService.shared.writeText(text)
        ToastManager.shared.show(String(localized: "toast.copied"))
    }

    private func copyJSON() {
        let text = node.value.toJSONString(prettyPrinted: true) ?? ""
        ClipboardService.shared.writeText(text)
        ToastManager.shared.show(String(localized: "toast.json_copied"))
    }
}
#endif
