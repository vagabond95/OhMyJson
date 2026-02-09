//
//  BeautifyView.swift
//  OhMyJson
//
//  Formatted JSON text view with line numbers and syntax highlighting
//

import SwiftUI
import AppKit

#if os(macOS)
struct BeautifyView: View {
    let formattedJSON: String
    @Binding var searchText: String
    @Binding var currentSearchIndex: Int
    @Binding var scrollPosition: CGFloat
    var isRestoringTabState: Bool = false

    @State private var formattedLines: [FormattedLine] = []
    @State private var searchResults: [SearchResult] = []
    @State private var currentSearchResultLocation: SearchResultLocation?

    /// Cached attributed strings — rebuilt only when content/search/theme changes, NOT on scroll
    @State private var cachedContentString: NSAttributedString = NSAttributedString()
    @State private var cachedLineNumberString: NSAttributedString = NSAttributedString()

    @ObservedObject private var settings = AppSettings.shared
    private var theme: AppTheme { settings.currentTheme }

    var body: some View {
        SelectableTextView(
            attributedString: cachedContentString,
            lineNumberString: cachedLineNumberString,
            backgroundColor: NSColor(theme.background),
            scrollPosition: $scrollPosition,
            scrollToRange: isRestoringTabState ? nil : currentSearchResultLocation?.characterRange,
            isRestoringTabState: isRestoringTabState
        )
        .onChange(of: searchText) { _, newValue in
            updateSearchResults()
            if !newValue.isEmpty && !searchResults.isEmpty {
                currentSearchIndex = 0
                updateCurrentSearchLocation(index: 0)
            } else {
                currentSearchResultLocation = nil
            }
            rebuildAttributedStrings()
        }
        .onChange(of: currentSearchIndex) { _, newIndex in
            if !searchResults.isEmpty {
                updateCurrentSearchLocation(index: newIndex)
            }
            rebuildAttributedStrings()
        }
        .onAppear {
            formatJSON()
            restoreSearchState()
            rebuildAttributedStrings()
        }
        .onChange(of: formattedJSON) { _, _ in
            formatJSON()
            updateSearchResults()
            rebuildAttributedStrings()
        }
        .onChange(of: settings.isDarkMode) { _, _ in
            formatJSON()
            rebuildAttributedStrings()
        }
        .background(theme.background)
    }

    // MARK: - Attributed String Caching

    /// Rebuilds both cached attributed strings. Call only when content, search, or theme changes.
    private func rebuildAttributedStrings() {
        cachedContentString = buildContentNSAttributedString()
        cachedLineNumberString = buildLineNumbersNSAttributedString()
    }

    // MARK: - Token Colors

    private func nsColorForTokenType(_ type: JSONTokenType) -> NSColor {
        switch type {
        case .key:
            return NSColor(theme.key)
        case .string:
            return NSColor(theme.string)
        case .number:
            return NSColor(theme.number)
        case .boolean:
            return NSColor(theme.boolean)
        case .null:
            return NSColor(theme.null)
        case .structure:
            return NSColor(theme.structure)
        case .whitespace:
            return NSColor.clear
        }
    }

    // MARK: - NSAttributedString Building

    /// Builds the line numbers as a separate attributed string for the gutter
    private func buildLineNumbersNSAttributedString() -> NSAttributedString {
        let result = NSMutableAttributedString()
        let baseFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let lineNumberColor = NSColor(theme.secondaryText).withAlphaComponent(0.5)

        // Calculate line number width (number of digits in total line count)
        let maxLineNumber = formattedLines.count
        let lineNumberDigits = String(maxLineNumber).count
        let lineNumberPadding = max(lineNumberDigits, 3) // Minimum 3 digits for alignment

        let lineNumberAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: lineNumberColor,
            .font: baseFont
        ]

        for lineIndex in 0..<formattedLines.count {
            let lineNumber = lineIndex + 1
            let lineNumberString = String(format: "%\(lineNumberPadding)d  ", lineNumber)
            result.append(NSAttributedString(string: lineNumberString, attributes: lineNumberAttributes))

            // Add newline (except for last line)
            if lineIndex < formattedLines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: [.font: baseFont]))
            }
        }

        return result
    }

    /// Builds the JSON content attributed string (without line numbers)
    private func buildContentNSAttributedString() -> NSAttributedString {
        let result = NSMutableAttributedString()
        let baseFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let mediumFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        let boldFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .bold)
        let otherMatchBgColor = NSColor(theme.searchOtherMatchBg)
        let currentMatchBgColor = NSColor(theme.searchCurrentMatchBg)
        let otherMatchFgColor = NSColor(theme.searchOtherMatchFg)
        let currentMatchFgColor = NSColor(theme.searchCurrentMatchFg)
        let lowercasedSearch = searchText.lowercased()
        var globalMatchIndex = 0

        for (lineIndex, line) in formattedLines.enumerated() {
            // Add JSON content (no line numbers)
            for token in line.tokens {
                let color = nsColorForTokenType(token.type)
                let font: NSFont = token.type == .key ? mediumFont : baseFont

                if !searchText.isEmpty {
                    // Apply search highlighting within token
                    appendHighlightedToken(
                        token: token,
                        to: result,
                        baseColor: color,
                        baseFont: font,
                        boldFont: boldFont,
                        otherMatchBgColor: otherMatchBgColor,
                        currentMatchBgColor: currentMatchBgColor,
                        otherMatchFgColor: otherMatchFgColor,
                        currentMatchFgColor: currentMatchFgColor,
                        globalMatchIndex: &globalMatchIndex,
                        currentSearchIndex: currentSearchIndex,
                        lowercasedSearch: lowercasedSearch
                    )
                } else {
                    // No search - just add styled token
                    var attributes: [NSAttributedString.Key: Any] = [
                        .foregroundColor: color,
                        .font: font
                    ]

                    if token.type == .null {
                        attributes[.obliqueness] = 0.1 // italic effect
                    }

                    result.append(NSAttributedString(string: token.text, attributes: attributes))
                }
            }

            // Add newline (except for last line)
            if lineIndex < formattedLines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: [.font: baseFont]))
            }
        }

        return result
    }

    private func appendHighlightedToken(
        token: JSONToken,
        to result: NSMutableAttributedString,
        baseColor: NSColor,
        baseFont: NSFont,
        boldFont: NSFont,
        otherMatchBgColor: NSColor,
        currentMatchBgColor: NSColor,
        otherMatchFgColor: NSColor,
        currentMatchFgColor: NSColor,
        globalMatchIndex: inout Int,
        currentSearchIndex: Int,
        lowercasedSearch: String
    ) {
        let text = token.text
        let lowercasedText = text.lowercased()

        guard lowercasedText.contains(lowercasedSearch) else {
            // No match - add with base styling
            var attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: baseColor,
                .font: baseFont
            ]
            if token.type == .null {
                attributes[.obliqueness] = 0.1
            }
            result.append(NSAttributedString(string: text, attributes: attributes))
            return
        }

        // Has matches - highlight them with background + foreground + bold
        var remaining = text
        var remainingLower = lowercasedText
        var baseAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: baseColor,
            .font: baseFont
        ]
        if token.type == .null {
            baseAttributes[.obliqueness] = 0.1
        }

        while let range = remainingLower.range(of: lowercasedSearch) {
            let beforeRange = remaining.startIndex..<remaining.index(
                remaining.startIndex,
                offsetBy: remainingLower.distance(from: remainingLower.startIndex, to: range.lowerBound)
            )
            let matchRange = remaining.index(
                remaining.startIndex,
                offsetBy: remainingLower.distance(from: remainingLower.startIndex, to: range.lowerBound)
            )..<remaining.index(
                remaining.startIndex,
                offsetBy: remainingLower.distance(from: remainingLower.startIndex, to: range.upperBound)
            )

            // Add text before match
            if !beforeRange.isEmpty {
                result.append(NSAttributedString(string: String(remaining[beforeRange]), attributes: baseAttributes))
            }

            // Add match with background + foreground color + bold font
            let isCurrent = globalMatchIndex == currentSearchIndex
            let matchAttributes: [NSAttributedString.Key: Any] = [
                .backgroundColor: isCurrent ? currentMatchBgColor : otherMatchBgColor,
                .foregroundColor: isCurrent ? currentMatchFgColor : otherMatchFgColor,
                .font: boldFont
            ]
            result.append(NSAttributedString(string: String(remaining[matchRange]), attributes: matchAttributes))
            globalMatchIndex += 1

            remaining = String(remaining[matchRange.upperBound...])
            remainingLower = String(remainingLower[range.upperBound...])
        }

        // Add remaining text after last match
        if !remaining.isEmpty {
            result.append(NSAttributedString(string: remaining, attributes: baseAttributes))
        }
    }

    // MARK: - JSON Formatting

    private func formatJSON() {
        // formattedJSON is already formatted, just tokenize it
        formattedLines = tokenizeFormattedJSON(formattedJSON)
    }

    private func tokenizeFormattedJSON(_ json: String) -> [FormattedLine] {
        let lines = json.components(separatedBy: "\n")
        return lines.map { line in
            FormattedLine(tokens: tokenizeLine(line))
        }
    }

    private func tokenizeLine(_ line: String) -> [JSONToken] {
        var tokens: [JSONToken] = []
        var remaining = line[...]

        while !remaining.isEmpty {
            // Leading whitespace
            let whitespace = remaining.prefix(while: { $0 == " " || $0 == "\t" })
            if !whitespace.isEmpty {
                tokens.append(JSONToken(text: String(whitespace), type: .whitespace))
                remaining = remaining.dropFirst(whitespace.count)
                continue
            }

            // Structure characters
            if let first = remaining.first, "{}[]:,".contains(first) {
                tokens.append(JSONToken(text: String(first), type: .structure))
                remaining = remaining.dropFirst()
                continue
            }

            // String (key or value)
            if remaining.first == "\"" {
                if let stringEnd = findStringEnd(in: remaining) {
                    let stringContent = String(remaining[...stringEnd])
                    remaining = remaining[remaining.index(after: stringEnd)...]

                    // Check if this is a key (followed by colon)
                    let afterString = remaining.drop(while: { $0 == " " })
                    let isKey = afterString.first == ":"

                    tokens.append(JSONToken(text: stringContent, type: isKey ? .key : .string))
                    continue
                }
            }

            // Number
            if let first = remaining.first, first == "-" || first.isNumber {
                let numberChars = remaining.prefix(while: { char in
                    char.isNumber || char == "." || char == "-" || char == "+" || char == "e" || char == "E"
                })
                if !numberChars.isEmpty {
                    tokens.append(JSONToken(text: String(numberChars), type: .number))
                    remaining = remaining.dropFirst(numberChars.count)
                    continue
                }
            }

            // Boolean
            if remaining.hasPrefix("true") {
                tokens.append(JSONToken(text: "true", type: .boolean))
                remaining = remaining.dropFirst(4)
                continue
            }
            if remaining.hasPrefix("false") {
                tokens.append(JSONToken(text: "false", type: .boolean))
                remaining = remaining.dropFirst(5)
                continue
            }

            // Null
            if remaining.hasPrefix("null") {
                tokens.append(JSONToken(text: "null", type: .null))
                remaining = remaining.dropFirst(4)
                continue
            }

            // Unknown character - add as structure
            if let first = remaining.first {
                tokens.append(JSONToken(text: String(first), type: .structure))
                remaining = remaining.dropFirst()
            }
        }

        return tokens
    }

    private func findStringEnd(in text: Substring) -> String.Index? {
        guard text.first == "\"" else { return nil }

        var index = text.index(after: text.startIndex)
        var escaped = false

        while index < text.endIndex {
            let char = text[index]

            if escaped {
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else if char == "\"" {
                return index
            }

            index = text.index(after: index)
        }

        return nil
    }

    // MARK: - Search

    private func updateSearchResults() {
        guard !searchText.isEmpty else {
            searchResults = []
            return
        }

        searchResults = []
        let lowercasedSearch = searchText.lowercased()

        var currentOffset = 0

        for (lineIndex, line) in formattedLines.enumerated() {
            // No line number offset needed - line numbers are in separate gutter

            for token in line.tokens {
                let lowercasedText = token.text.lowercased()
                var searchStart = lowercasedText.startIndex

                while let range = lowercasedText.range(of: lowercasedSearch, range: searchStart..<lowercasedText.endIndex) {
                    // Calculate the offset within the token for this match
                    let matchOffsetInToken = lowercasedText.distance(from: lowercasedText.startIndex, to: range.lowerBound)
                    let matchOffset = currentOffset + matchOffsetInToken

                    searchResults.append(SearchResult(
                        lineIndex: lineIndex,
                        tokenText: token.text,
                        range: range,
                        characterOffset: matchOffset
                    ))
                    searchStart = range.upperBound
                }

                currentOffset += token.text.count
            }

            // Account for newline (except for last line)
            if lineIndex < formattedLines.count - 1 {
                currentOffset += 1 // newline character
            }
        }
    }

    private func restoreSearchState() {
        guard !searchText.isEmpty else { return }

        updateSearchResults()

        guard !searchResults.isEmpty else { return }

        let validIndex = min(currentSearchIndex, searchResults.count - 1)
        updateCurrentSearchLocation(index: validIndex)
    }

    private func updateCurrentSearchLocation(index: Int) {
        guard index >= 0 && index < searchResults.count else { return }

        let result = searchResults[index]
        let matchLength = result.tokenText.distance(from: result.range.lowerBound, to: result.range.upperBound)

        currentSearchResultLocation = SearchResultLocation(
            lineIndex: result.lineIndex,
            characterRange: NSRange(location: result.characterOffset, length: matchLength)
        )
    }

    var searchResultCount: Int {
        searchResults.count
    }
}

// MARK: - Supporting Types

enum JSONTokenType {
    case key
    case string
    case number
    case boolean
    case null
    case structure
    case whitespace
}

struct JSONToken {
    let text: String
    let type: JSONTokenType
}

struct FormattedLine {
    let tokens: [JSONToken]
}

struct SearchResult {
    let lineIndex: Int
    let tokenText: String
    let range: Range<String.Index>
    var characterOffset: Int = 0  // Character offset in the full attributed string
}

struct SearchResultLocation: Equatable {
    let lineIndex: Int
    let characterRange: NSRange  // Range in the full attributed string for scrolling
}

// MARK: - Preview

struct BeautifyView_Previews: PreviewProvider {
    static var previews: some View {
        BeautifyView(
            formattedJSON: """
            {
              "age" : 30,
              "items" : [
                "apple",
                "banana"
              ],
              "name" : "John"
            }
            """,
            searchText: .constant(""),
            currentSearchIndex: .constant(0),
            scrollPosition: .constant(0)
        )
        .frame(width: 400, height: 300)
    }
}
#endif
