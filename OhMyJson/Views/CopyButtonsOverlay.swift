//
//  CopyButtonsOverlay.swift
//  OhMyJson
//

import SwiftUI

#if os(macOS)
struct CopyButtonsOverlay: View {
    let node: JSONNode
    var onHoverChanged: ((Bool) -> Void)? = nil

    @Environment(AppSettings.self) var settings
    private var theme: AppTheme { settings.currentTheme }

    private var isLeaf: Bool { !node.value.isContainer }
    private var isDark: Bool { theme.colorScheme == .dark }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(theme.secondaryText.opacity(0.6))
                .padding(.trailing, 1)

            if isLeaf {
                if node.key != nil {
                    copyButton(label: "K", tooltip: String(localized: "tooltip.copy_key")) {
                        copyKey()
                    }
                }
                copyButton(label: "V", tooltip: String(localized: "tooltip.copy_value")) {
                    copyValueOnly()
                }
                copyButton(label: "K&V", tooltip: String(localized: "tooltip.copy_key_value")) {
                    copyKeyValue()
                }
            } else {
                copyButton(label: "{}", tooltip: String(localized: "tooltip.copy_json")) {
                    copyJSON()
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.panelBackground)
                .shadow(color: Color.black.opacity(isDark ? 0.5 : 0.18), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isDark ? Color.white.opacity(0.10) : theme.border.opacity(0.8), lineWidth: 0.5)
        )
        .onContinuousHover { phase in
            switch phase {
            case .active:
                onHoverChanged?(true)
            case .ended:
                onHoverChanged?(false)
            }
        }
    }

    private func copyButton(label: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(theme.secondaryText)
                .padding(.horizontal, 4)
                .frame(minWidth: 20, minHeight: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: isDark
                                    ? [Color.white.opacity(0.12), Color.white.opacity(0.04)]
                                    : [theme.secondaryBackground.opacity(0.9), theme.secondaryBackground.opacity(0.5)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: Color.black.opacity(isDark ? 0.5 : 0.12), radius: isDark ? 1 : 0.5, x: 0, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isDark ? Color.white.opacity(0.14) : theme.border.opacity(0.6), lineWidth: 0.5)
                )
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
            text = "[\(key)] : \(node.plainValue)"
        } else {
            text = node.plainValue
        }
        ClipboardService.shared.writeText(text)
        ToastManager.shared.show(String(localized: "toast.key_value_copied"))
    }

    private func copyJSON() {
        let text = node.value.toJSONString(prettyPrinted: true) ?? ""
        ClipboardService.shared.writeText(text)
        ToastManager.shared.show(String(localized: "toast.json_copied"))
    }
}
#endif
