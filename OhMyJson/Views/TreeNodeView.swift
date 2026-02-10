//
//  TreeNodeView.swift
//  OhMyJson
//

import SwiftUI

#if os(macOS)
struct TreeNodeView: View {
    @ObservedObject var node: JSONNode
    let searchText: String
    let isCurrentSearchResult: Bool
    let onSelect: () -> Void
    let onToggleExpand: (() -> Void)?
    let ancestorIsLast: [Bool]

    @State private var isHovered = false

    @ObservedObject private var settings = AppSettings.shared
    private var theme: AppTheme { settings.currentTheme }

    // MARK: - Theme Colors
    private var keyColor: Color { theme.key }
    private var stringColor: Color { theme.string }
    private var numberColor: Color { theme.number }
    private var booleanColor: Color { theme.boolean }
    private var nullColor: Color { theme.null }
    private var structureColor: Color { theme.structure }
    private var searchCurrentMatchBgColor: Color { theme.searchCurrentMatchBg }
    private var searchOtherMatchBgColor: Color { theme.searchOtherMatchBg }
    private var searchCurrentMatchFgColor: Color { theme.searchCurrentMatchFg }
    private var searchOtherMatchFgColor: Color { theme.searchOtherMatchFg }
    private var hoverColor: Color { theme.hoverBg }

    var body: some View {
        if node.value.isContainer {
            rowContent
                .onTapGesture {
                    if node.value.childCount > 0 {
                        node.toggleExpanded()
                        onToggleExpand?()
                    }
                }
        } else {
            rowContent
                .onTapGesture(count: 2) { copyValue() }
                .onTapGesture(count: 1) { onSelect() }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 0) {
            treeLines
            expandButton
            keyView
            valueView
            Spacer()
        }
        .padding(.vertical, 2)
        .background(backgroundColor)
        .animation(.easeInOut(duration: 0.15), value: isCurrentSearchResult)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var treeLines: some View {
        HStack(spacing: 0) {
            ForEach(0..<node.depth, id: \.self) { depth in
                Text("  ")
                    .font(.system(.body, design: .monospaced))
            }
        }
    }

    private var expandButton: some View {
        Group {
            if node.value.isContainer && node.value.childCount > 0 {
                Text(node.isExpanded ? "▼" : "▶")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(structureColor.opacity(0.7))
                    .frame(width: 16, height: 16)
            } else {
                Spacer().frame(width: 16)
            }
        }
    }

    private var keyView: some View {
        Group {
            if let key = node.key {
                highlightedText(key, color: keyColor)
                    .fontWeight(.medium)
                Text(": ")
                    .foregroundColor(structureColor)
            }
        }
        .font(.system(.body, design: .monospaced))
    }

    private var valueView: some View {
        Group {
            switch node.value {
            case .string(let s):
                highlightedText("\"\(s)\"", color: stringColor)

            case .number(let n):
                let numStr = n.truncatingRemainder(dividingBy: 1) == 0
                    ? String(format: "%.0f", n)
                    : String(n)
                highlightedText(numStr, color: numberColor)

            case .bool(let b):
                highlightedText(b ? "true" : "false", color: booleanColor)

            case .null:
                Text("null")
                    .foregroundColor(nullColor)
                    .italic()

            case .object(let dict):
                HStack(spacing: 4) {
                    Text("{")
                        .foregroundColor(structureColor)
                    Text("\(dict.count)")
                        .foregroundColor(structureColor.opacity(0.7))
                        .font(.system(.caption, design: .monospaced))
                    Text("}")
                        .foregroundColor(structureColor)
                }

            case .array(let arr):
                HStack(spacing: 4) {
                    Text("[")
                        .foregroundColor(structureColor)
                    Text("\(arr.count)")
                        .foregroundColor(structureColor.opacity(0.7))
                        .font(.system(.caption, design: .monospaced))
                    Text("]")
                        .foregroundColor(structureColor)
                }
            }
        }
        .font(.system(.body, design: .monospaced))
    }

    private func highlightedText(_ text: String, color: Color) -> Text {
        if searchText.isEmpty {
            return Text(text).foregroundColor(color)
        }

        let lowercasedText = text.lowercased()
        let lowercasedSearch = searchText.lowercased()

        guard lowercasedText.contains(lowercasedSearch) else {
            return Text(text).foregroundColor(color)
        }

        var attrStr = AttributedString(text)
        attrStr.foregroundColor = color

        // Find all matches and apply background + foreground color + bold
        let matchFont = Font.system(.body, design: .monospaced).bold()
        var searchStart = attrStr.startIndex
        while searchStart < attrStr.endIndex {
            let remainingRange = searchStart..<attrStr.endIndex
            guard let matchRange = attrStr[remainingRange].range(of: lowercasedSearch, options: .caseInsensitive) else {
                break
            }
            if isCurrentSearchResult {
                attrStr[matchRange].backgroundColor = searchCurrentMatchBgColor
                attrStr[matchRange].foregroundColor = searchCurrentMatchFgColor
            } else {
                attrStr[matchRange].backgroundColor = searchOtherMatchBgColor
                attrStr[matchRange].foregroundColor = searchOtherMatchFgColor
            }
            attrStr[matchRange].font = matchFont
            searchStart = matchRange.upperBound
        }

        return Text(attrStr)
    }

    private var backgroundColor: Color {
        if isHovered {
            return hoverColor
        }
        return Color.clear
    }

    private func copyValue() {
        // Format: "key: value"
        let copyText: String
        if let key = node.key {
            // Has a key → format as "key: value"
            copyText = "\(key): \(node.copyValue)"
        } else {
            // No key (root node) → just copy value
            copyText = node.copyValue
        }

        ClipboardService.shared.writeText(copyText)
        showCopyFeedback()
    }

    private func showCopyFeedback() {
        ToastManager.shared.show(String(localized: "toast.key_value_copied"))
    }
}

struct TreeNodeView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleNode = JSONNode(
            key: "name",
            value: .string("Hello World"),
            depth: 1
        )

        TreeNodeView(
            node: sampleNode,
            searchText: "",
            isCurrentSearchResult: false,
            onSelect: {},
            onToggleExpand: nil,
            ancestorIsLast: [false]
        )
        .padding()
    }
}
#endif
