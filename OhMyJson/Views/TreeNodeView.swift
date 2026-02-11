//
//  TreeNodeView.swift
//  OhMyJson
//

import SwiftUI

#if os(macOS)
struct TreeNodeView: View {
    var node: JSONNode
    let searchText: String
    let isCurrentSearchResult: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleExpand: (() -> Void)?
    let ancestorIsLast: [Bool]

    @State private var isHovered = false
    @State private var isOverlayHovered = false
    @State private var dismissWorkItem: DispatchWorkItem?
    @State private var hoverStartX: CGFloat?

    @Environment(AppSettings.self) var settings
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
    private var selectionColor: Color { theme.selectionBg }

    var body: some View {
        rowContent
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
        .animation(.easeInOut(duration: Animation.quick), value: isCurrentSearchResult)
        .contentShape(Rectangle())
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
            onSelect()
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                dismissWorkItem?.cancel()
                dismissWorkItem = nil
                if !isHovered {
                    hoverStartX = location.x
                }
                isHovered = true
            case .ended:
                scheduleDismissIfNeeded()
            }
        }
        .overlay(alignment: .leading) {
            if shouldShowOverlay, let startX = hoverStartX {
                CopyButtonsOverlay(node: node) { hovering in
                    if hovering {
                        dismissWorkItem?.cancel()
                        dismissWorkItem = nil
                        isOverlayHovered = true
                    } else {
                        isOverlayHovered = false
                        scheduleDismissIfNeeded()
                    }
                }
                .fixedSize()
                .frame(width: max(startX - 4, 0), alignment: .trailing)
                .allowsHitTesting(true)
            }
        }
        .zIndex(shouldShowOverlay ? 1 : 0)
        .onDisappear {
            dismissWorkItem?.cancel()
            dismissWorkItem = nil
            hoverStartX = nil
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
                    .contentShape(Rectangle())
                    .onTapGesture {
                        node.toggleExpanded()
                        onToggleExpand?()
                    }
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

    private var shouldShowOverlay: Bool {
        isSelected && (isHovered || isOverlayHovered)
    }

    private func scheduleDismissIfNeeded() {
        dismissWorkItem?.cancel()
        let item = DispatchWorkItem {
            if !self.isOverlayHovered {
                self.isHovered = false
                self.hoverStartX = nil
            }
        }
        dismissWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.hoverDismissGrace, execute: item)
    }

    private var backgroundColor: Color {
        if isSelected { return selectionColor }
        return Color.clear
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
            isSelected: false,
            onSelect: {},
            onToggleExpand: nil,
            ancestorIsLast: [false]
        )
        .padding()
    }
}
#endif
