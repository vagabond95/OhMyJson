//
//  CompareDiffRenderer.swift
//  OhMyJson
//
//  Builds NSAttributedString pairs for Compare mode diff visualization.
//  Reuses BeautifyView.tokenizeLine for syntax coloring.
//

import Foundation
import AppKit
import SwiftUI

#if os(macOS)
enum CompareDiffRenderer {

    // MARK: - Public API

    static func buildRenderResult(
        leftJSON: String,
        rightJSON: String,
        diffResult: CompareDiffResult,
        expandedSections: Set<Int> = [],
        indentSize: Int = 4
    ) -> CompareRenderResult {
        // 1. Pretty-print both sides
        let leftFormatted = formatJSON(leftJSON, indentSize: indentSize)
        let rightFormatted = formatJSON(rightJSON, indentSize: indentSize)

        let leftLines = leftFormatted.components(separatedBy: "\n")
        let rightLines = rightFormatted.components(separatedBy: "\n")

        // 2. Build line-level diff type annotations
        let leftLineDiffs = assignLineDiffs(lines: leftLines, diffResult: diffResult, side: .left)
        let rightLineDiffs = assignLineDiffs(lines: rightLines, diffResult: diffResult, side: .right)

        // 3. Build paired render lines with padding
        let (pairedLeft, pairedRight) = buildPairedLines(
            leftLines: leftLines, leftDiffs: leftLineDiffs,
            rightLines: rightLines, rightDiffs: rightLineDiffs
        )

        // 4. Apply collapse for unchanged sections
        let (collapsedLeft, collapsedRight) = applyCollapse(
            leftLines: pairedLeft, rightLines: pairedRight,
            expandedSections: expandedSections
        )

        // 5. Truncate if needed
        let maxLines = CompareLimit.maxDisplayLines
        let finalLeft = Array(collapsedLeft.prefix(maxLines))
        let finalRight = Array(collapsedRight.prefix(maxLines))

        // 6. Build diff locations for navigation
        let diffLocations = buildDiffLocations(lines: finalLeft)

        // 7. Build NSAttributedStrings
        let theme = AppSettings.shared.currentTheme
        let leftAttrStr = buildAttributedString(lines: finalLeft, theme: theme)
        let rightAttrStr = buildAttributedString(lines: finalRight, theme: theme)

        return CompareRenderResult(
            leftContent: leftAttrStr,
            rightContent: rightAttrStr,
            leftLines: finalLeft,
            rightLines: finalRight,
            diffLocations: diffLocations,
            totalLines: finalLeft.count
        )
    }

    // MARK: - JSON Formatting

    private static func formatJSON(_ text: String, indentSize: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              var result = String(data: prettyData, encoding: .utf8) else {
            return text
        }

        // Normalize indent width
        let lines = result.components(separatedBy: "\n")
        var nativeIndent = 0
        for line in lines {
            let stripped = line.drop(while: { $0 == " " })
            let leading = line.count - stripped.count
            if leading > 0 { nativeIndent = leading; break }
        }
        if nativeIndent > 0 && nativeIndent != indentSize {
            result = lines.map { line -> String in
                let stripped = line.drop(while: { $0 == " " })
                let leading = line.count - stripped.count
                guard leading > 0 else { return line }
                let level = leading / nativeIndent
                return String(repeating: " ", count: level * indentSize) + stripped
            }.joined(separator: "\n")
        }

        return result
    }

    // MARK: - Line Diff Assignment

    private static func assignLineDiffs(lines: [String], diffResult: CompareDiffResult, side: CompareSide) -> [DiffType] {
        // Simple approach: pretty-print, then use diff items to mark lines
        // For now, use a line-by-line comparison approach
        var diffs = [DiffType](repeating: .unchanged, count: lines.count)

        let flattened = diffResult.flattenedDiffItems
        for item in flattened {
            switch item.type {
            case .added:
                if side == .right {
                    // Mark lines in right that correspond to added content
                    markLinesForValue(item.rightValue, in: lines, diffs: &diffs, type: .added)
                }
            case .removed:
                if side == .left {
                    markLinesForValue(item.leftValue, in: lines, diffs: &diffs, type: .removed)
                }
            case .modified:
                if side == .left {
                    markLinesForValue(item.leftValue, in: lines, diffs: &diffs, type: .modified)
                } else {
                    markLinesForValue(item.rightValue, in: lines, diffs: &diffs, type: .modified)
                }
            case .unchanged:
                break
            }
        }

        return diffs
    }

    private static func markLinesForValue(_ value: JSONValue?, in lines: [String], diffs: inout [DiffType], type: DiffType) {
        guard let value else { return }
        // Get string representation of the value
        let valueStr: String
        switch value {
        case .string(let s): valueStr = "\"\(s)\""
        case .number(let n):
            valueStr = n.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", n) : String(n)
        case .bool(let b): valueStr = b ? "true" : "false"
        case .null: valueStr = "null"
        case .object, .array:
            // For containers, we'd need to search for the key/structure — simplified approach
            return
        }

        // Find matching lines
        let trimmedValue = valueStr.trimmingCharacters(in: .whitespaces)
        for (i, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.contains(trimmedValue) && diffs[i] == .unchanged {
                diffs[i] = type
                break // Only mark first occurrence
            }
        }
    }

    // MARK: - Paired Lines with Padding

    private static func buildPairedLines(
        leftLines: [String], leftDiffs: [DiffType],
        rightLines: [String], rightDiffs: [DiffType]
    ) -> ([RenderLine], [RenderLine]) {
        var result_left: [RenderLine] = []
        var result_right: [RenderLine] = []

        let maxCount = max(leftLines.count, rightLines.count)

        for i in 0..<maxCount {
            if i < leftLines.count && i < rightLines.count {
                let ld = i < leftDiffs.count ? leftDiffs[i] : .unchanged
                let rd = i < rightDiffs.count ? rightDiffs[i] : .unchanged

                result_left.append(RenderLine(lineIndex: i, type: .content(ld), text: leftLines[i]))
                result_right.append(RenderLine(lineIndex: i, type: .content(rd), text: rightLines[i]))
            } else if i < leftLines.count {
                let ld = i < leftDiffs.count ? leftDiffs[i] : .unchanged
                result_left.append(RenderLine(lineIndex: i, type: .content(ld), text: leftLines[i]))
                result_right.append(RenderLine(lineIndex: -1, type: .padding, text: ""))
            } else if i < rightLines.count {
                let rd = i < rightDiffs.count ? rightDiffs[i] : .unchanged
                result_left.append(RenderLine(lineIndex: -1, type: .padding, text: ""))
                result_right.append(RenderLine(lineIndex: i, type: .content(rd), text: rightLines[i]))
            }
        }

        return (result_left, result_right)
    }

    // MARK: - Collapse Unchanged

    private static func applyCollapse(
        leftLines: [RenderLine], rightLines: [RenderLine],
        expandedSections: Set<Int>
    ) -> ([RenderLine], [RenderLine]) {
        guard leftLines.count == rightLines.count else {
            return (leftLines, rightLines)
        }

        let context = CompareLayout.collapseContext
        var isDiff = [Bool](repeating: false, count: leftLines.count)

        // Mark lines that have diffs
        for i in 0..<leftLines.count {
            switch leftLines[i].type {
            case .content(let dt) where dt != .unchanged: isDiff[i] = true
            default: break
            }
            switch rightLines[i].type {
            case .content(let dt) where dt != .unchanged: isDiff[i] = true
            default: break
            }
        }

        // Mark context lines around diffs
        var isVisible = [Bool](repeating: false, count: leftLines.count)
        for i in 0..<leftLines.count {
            if isDiff[i] {
                let start = max(0, i - context)
                let end = min(leftLines.count - 1, i + context)
                for j in start...end {
                    isVisible[j] = true
                }
            }
        }

        // Build result with collapse markers
        var resultLeft: [RenderLine] = []
        var resultRight: [RenderLine] = []
        var sectionIndex = 0
        var i = 0

        while i < leftLines.count {
            if isVisible[i] {
                resultLeft.append(leftLines[i])
                resultRight.append(rightLines[i])
                i += 1
            } else {
                // Count consecutive hidden lines
                var hiddenCount = 0
                let sectionStart = i
                while i < leftLines.count && !isVisible[i] {
                    hiddenCount += 1
                    i += 1
                }

                if expandedSections.contains(sectionIndex) {
                    // Section is expanded — show all lines
                    for j in sectionStart..<(sectionStart + hiddenCount) {
                        resultLeft.append(leftLines[j])
                        resultRight.append(rightLines[j])
                    }
                } else {
                    // Collapse marker
                    let collapseText = "··· \(hiddenCount) unchanged lines ···"
                    resultLeft.append(RenderLine(lineIndex: sectionStart, type: .collapse(sectionIndex), text: collapseText))
                    resultRight.append(RenderLine(lineIndex: sectionStart, type: .collapse(sectionIndex), text: collapseText))
                }

                sectionIndex += 1
            }
        }

        return (resultLeft, resultRight)
    }

    // MARK: - Diff Locations

    private static func buildDiffLocations(lines: [RenderLine]) -> [DiffLocation] {
        var locations: [DiffLocation] = []
        for (i, line) in lines.enumerated() {
            if case .content(let dt) = line.type, dt != .unchanged {
                locations.append(DiffLocation(renderLineIndex: i, diffType: dt))
            }
        }
        return locations
    }

    // MARK: - NSAttributedString Building

    static func buildAttributedString(lines: [RenderLine], theme: AppTheme) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let baseFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let collapseFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular)

        let keyColor = NSColor(theme.key)
        let stringColor = NSColor(theme.string)
        let numberColor = NSColor(theme.number)
        let booleanColor = NSColor(theme.boolean)
        let nullColor = NSColor(theme.null)
        let structureColor = NSColor(theme.structure)

        for (index, line) in lines.enumerated() {
            switch line.type {
            case .content(let diffType):
                let bgColor = nsColorForDiffType(diffType, theme: theme)
                let tokens = BeautifyView.tokenizeLine(line.text)

                for token in tokens {
                    let color: NSColor
                    switch token.type {
                    case .key: color = keyColor
                    case .string: color = stringColor
                    case .number: color = numberColor
                    case .boolean: color = booleanColor
                    case .null: color = nullColor
                    case .structure: color = structureColor
                    case .whitespace: color = .clear
                    }

                    var attrs: [NSAttributedString.Key: Any] = [
                        .font: baseFont,
                        .foregroundColor: color,
                    ]
                    if let bg = bgColor {
                        attrs[.backgroundColor] = bg
                    }
                    result.append(NSAttributedString(string: token.text, attributes: attrs))
                }

            case .padding:
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: baseFont,
                    .backgroundColor: theme.nsDiffPaddingBg,
                ]
                result.append(NSAttributedString(string: " ", attributes: attrs))

            case .collapse(let sectionIdx):
                let collapseColor = NSColor(theme.secondaryText).withAlphaComponent(0.6)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: collapseFont,
                    .foregroundColor: collapseColor,
                ]
                result.append(NSAttributedString(string: line.text, attributes: attrs))
            }

            // Add newline (except for last line)
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: [.font: baseFont]))
            }
        }

        return result
    }

    // MARK: - Gutter Building

    static func buildGutterString(lines: [RenderLine], theme: AppTheme) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        for (index, line) in lines.enumerated() {
            let gutterChar: String
            let gutterColor: NSColor

            switch line.type {
            case .content(let diffType):
                switch diffType {
                case .added:
                    gutterChar = "▎"
                    gutterColor = NSColor(theme.diffAddedGutter)
                case .removed:
                    gutterChar = "▎"
                    gutterColor = NSColor(theme.diffRemovedGutter)
                case .modified:
                    gutterChar = "▎"
                    gutterColor = NSColor(theme.diffModifiedGutter)
                case .unchanged:
                    gutterChar = " "
                    gutterColor = .clear
                }
            case .padding, .collapse:
                gutterChar = " "
                gutterColor = .clear
            }

            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: gutterColor,
            ]
            result.append(NSAttributedString(string: gutterChar, attributes: attrs))

            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: [.font: font]))
            }
        }

        return result
    }

    // MARK: - Helpers

    private static func nsColorForDiffType(_ type: DiffType, theme: AppTheme) -> NSColor? {
        switch type {
        case .added: return theme.nsDiffAddedBg
        case .removed: return theme.nsDiffRemovedBg
        case .modified: return theme.nsDiffModifiedBg
        case .unchanged: return nil
        }
    }
}
#endif
