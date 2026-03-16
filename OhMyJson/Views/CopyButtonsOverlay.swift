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
                    copyButton(label: "K", tooltip: "Copy Key") {
                        copyKey()
                    }
                }
                copyButton(label: "V", tooltip: "Copy Value") {
                    copyValueOnly()
                }
                copyButton(label: "K&V", tooltip: "Copy Key  & Value") {
                    copyKeyValue()
                }
            } else {
                copyButton(label: "{}", tooltip: "Copy JSON") {
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
        ToastManager.shared.show("Key copied to clipboard")
    }

    private func copyValueOnly() {
        switch node.value {
        case .string(let s):
            ClipboardService.shared.writeText(s)
            ToastManager.shared.show("Value copied to clipboard")
        case .number(let n):
            ClipboardService.shared.writeText(
                n.truncatingRemainder(dividingBy: 1) == 0
                    ? String(format: "%.0f", n) : String(n)
            )
            ToastManager.shared.show("Value copied to clipboard")
        case .bool(let b):
            ClipboardService.shared.writeText(b ? "true" : "false")
            ToastManager.shared.show("Value copied to clipboard")
        case .null:
            ClipboardService.shared.writeText("null")
            ToastManager.shared.show("Value copied to clipboard")
        case .object, .array:
            let value = node.value
            ToastManager.shared.show("Copying...")
            Task.detached {
                let text = value.toJSONString(prettyPrinted: true) ?? ""
                await MainActor.run {
                    ClipboardService.shared.writeText(text)
                    ToastManager.shared.show("Value copied to clipboard")
                }
            }
        }
    }

    private func copyKeyValue() {
        let text: String
        if let key = node.key {
            text = "[\(key)] : \(node.plainValue)"
        } else {
            text = node.plainValue
        }
        ClipboardService.shared.writeText(text)
        ToastManager.shared.show("Key & Value copied to clipboard")
    }

    private func copyJSON() {
        let value = node.value
        ToastManager.shared.show("Copying...")
        Task.detached {
            let text = value.toJSONString(prettyPrinted: true) ?? ""
            await MainActor.run {
                ClipboardService.shared.writeText(text)
                ToastManager.shared.show("JSON copied!")
            }
        }
    }
}
#endif
