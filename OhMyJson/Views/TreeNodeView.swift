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
    @State private var buttonWasClicked = false

    @ObservedObject private var settings = AppSettings.shared
    private var theme: AppTheme { settings.currentTheme }

    // MARK: - Theme Colors
    private var keyColor: Color { theme.key }
    private var stringColor: Color { theme.string }
    private var numberColor: Color { theme.number }
    private var booleanColor: Color { theme.boolean }
    private var nullColor: Color { theme.null }
    private var structureColor: Color { theme.structure }
    private var searchHighlightColor: Color { theme.searchHighlight }
    private var selectionColor: Color { theme.selectionBg }
    private var hoverColor: Color { theme.hoverBg }

    var body: some View {
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
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    // Only copy on leaf nodes
                    if !node.value.isContainer {
                        copyValue()
                    }
                }
        )
        .simultaneousGesture(
            TapGesture(count: 1)
                .onEnded {
                    // Guard: Skip if button was clicked (prevents double-toggle)
                    guard !buttonWasClicked else { return }

                    if node.value.isContainer && node.value.childCount > 0 {
                        // Container with children → toggle fold/unfold
                        node.toggleExpanded()
                        onToggleExpand?()
                    } else {
                        // Leaf node or empty container → just select
                        onSelect()
                    }
                }
        )
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
                Button(action: {
                    buttonWasClicked = true
                    node.toggleExpanded()
                    onToggleExpand?()

                    // Reset flag after a tiny delay to allow parent gesture to check it
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                        buttonWasClicked = false
                    }
                }) {
                    Text(node.isExpanded ? "▼" : "▶")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(structureColor.opacity(0.7))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(PlainButtonStyle())
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

        var result = Text("")
        var remaining = text
        var remainingLower = lowercasedText

        while let range = remainingLower.range(of: lowercasedSearch) {
            let beforeRange = remaining.startIndex..<remaining.index(remaining.startIndex, offsetBy: remainingLower.distance(from: remainingLower.startIndex, to: range.lowerBound))
            let matchRange = remaining.index(remaining.startIndex, offsetBy: remainingLower.distance(from: remainingLower.startIndex, to: range.lowerBound))..<remaining.index(remaining.startIndex, offsetBy: remainingLower.distance(from: remainingLower.startIndex, to: range.upperBound))

            result = result + Text(String(remaining[beforeRange])).foregroundColor(color)
            result = result + Text(String(remaining[matchRange]))
                .foregroundColor(searchHighlightColor)
                .bold()

            remaining = String(remaining[matchRange.upperBound...])
            remainingLower = String(remainingLower[range.upperBound...])
        }

        result = result + Text(remaining).foregroundColor(color)

        return result
    }

    private var backgroundColor: Color {
        if isCurrentSearchResult {
            return selectionColor
        } else if isHovered {
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
        ToastManager.shared.show("Key-value copied to clipboard")
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
