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
    var isActive: Bool = true
    @Binding var searchText: String
    @Binding var currentSearchIndex: Int
    @Binding var scrollPosition: CGFloat
    var isRestoringTabState: Bool = false

    @State private var formattedLines: [FormattedLine] = []
    @State private var searchResults: [SearchResult] = []
    @State private var currentSearchResultLocation: SearchResultLocation?
    @State private var hasInitialized = false
    @State private var isDirty = false
    @State private var buildTask: Task<Void, Never>?

    /// Line count threshold for switching to async attributed string building
    private static let asyncBuildThreshold = 1000

    /// Cached attributed strings — rebuilt only when content/search/theme changes, NOT on scroll
    @State private var cachedContentString: NSAttributedString = NSAttributedString()
    @State private var cachedLineNumberString: NSAttributedString = NSAttributedString()

    @Environment(AppSettings.self) var settings
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
            guard isActive else { isDirty = true; return }
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
            guard isActive else { return }
            if !searchResults.isEmpty {
                updateCurrentSearchLocation(index: newIndex)
            }
            rebuildAttributedStrings()
        }
        .onAppear {
            guard isActive else { return }
            performFullInit()
        }
        .onChange(of: isActive) { _, newValue in
            guard newValue else { return }
            if !hasInitialized {
                performFullInit()
            } else if isDirty {
                formatJSON()
                updateSearchResults()
                rebuildAttributedStrings()
                isDirty = false
            }
        }
        .onChange(of: formattedJSON) { _, _ in
            guard isActive else { isDirty = true; return }
            formatJSON()
            updateSearchResults()
            rebuildAttributedStrings()
        }
        .onChange(of: settings.isDarkMode) { _, _ in
            guard isActive else { isDirty = true; return }
            formatJSON()
            rebuildAttributedStrings()
        }
        .background(theme.background)
    }

    // MARK: - Initialization

    private func performFullInit() {
        formatJSON()
        restoreSearchState()
        rebuildAttributedStrings()
        hasInitialized = true
        isDirty = false
    }

    // MARK: - Attributed String Caching

    /// Snapshot of theme colors and fonts for off-main-thread attributed string building.
    /// @unchecked Sendable because NSColor/NSFont are immutable once created.
    private struct BuildSnapshot: @unchecked Sendable {
        let lines: [FormattedLine]
        let searchText: String
        let currentSearchIndex: Int
        let keyColor: NSColor
        let stringColor: NSColor
        let numberColor: NSColor
        let booleanColor: NSColor
        let nullColor: NSColor
        let structureColor: NSColor
        let lineNumberColor: NSColor
        let searchOtherMatchBg: NSColor
        let searchCurrentMatchBg: NSColor
        let searchOtherMatchFg: NSColor
        let searchCurrentMatchFg: NSColor
        let baseFont: NSFont
        let mediumFont: NSFont
        let boldFont: NSFont

        init(lines: [FormattedLine], searchText: String, currentSearchIndex: Int, theme: AppTheme) {
            self.lines = lines
            self.searchText = searchText
            self.currentSearchIndex = currentSearchIndex
            keyColor = NSColor(theme.key)
            stringColor = NSColor(theme.string)
            numberColor = NSColor(theme.number)
            booleanColor = NSColor(theme.boolean)
            nullColor = NSColor(theme.null)
            structureColor = NSColor(theme.structure)
            lineNumberColor = NSColor(theme.secondaryText).withAlphaComponent(0.5)
            searchOtherMatchBg = NSColor(theme.searchOtherMatchBg)
            searchCurrentMatchBg = NSColor(theme.searchCurrentMatchBg)
            searchOtherMatchFg = NSColor(theme.searchOtherMatchFg)
            searchCurrentMatchFg = NSColor(theme.searchCurrentMatchFg)
            baseFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            mediumFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            boldFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .bold)
        }

        func colorForTokenType(_ type: JSONTokenType) -> NSColor {
            switch type {
            case .key: return keyColor
            case .string: return stringColor
            case .number: return numberColor
            case .boolean: return booleanColor
            case .null: return nullColor
            case .structure: return structureColor
            case .whitespace: return .clear
            }
        }
    }

    /// Wrapper for passing NSAttributedString across actor boundaries.
    private struct AttributedStringPair: @unchecked Sendable {
        let content: NSAttributedString
        let lineNumbers: NSAttributedString
    }

    /// Rebuilds both cached attributed strings. Uses async building for large content.
    private func rebuildAttributedStrings() {
        let snapshot = BuildSnapshot(
            lines: formattedLines,
            searchText: searchText,
            currentSearchIndex: currentSearchIndex,
            theme: theme
        )

        if snapshot.lines.count < Self.asyncBuildThreshold {
            buildTask?.cancel()
            cachedContentString = Self.buildContentString(snapshot)
            cachedLineNumberString = Self.buildLineNumberString(snapshot)
            return
        }

        // Large content — build off main thread to avoid UI freezing
        buildTask?.cancel()
        buildTask = Task {
            let pair = await Task.detached(priority: .userInitiated) {
                AttributedStringPair(
                    content: Self.buildContentString(snapshot),
                    lineNumbers: Self.buildLineNumberString(snapshot)
                )
            }.value

            guard !Task.isCancelled else { return }
            cachedContentString = pair.content
            cachedLineNumberString = pair.lineNumbers
        }
    }

    // MARK: - NSAttributedString Building

    /// Builds the line numbers as a separate attributed string for the gutter
    private static func buildLineNumberString(_ snapshot: BuildSnapshot) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let baseFont = snapshot.baseFont
        let lineNumberColor = snapshot.lineNumberColor
        let lines = snapshot.lines

        // Calculate line number width (number of digits in total line count)
        let maxLineNumber = lines.count
        let lineNumberDigits = String(maxLineNumber).count
        let lineNumberPadding = max(lineNumberDigits, 3) // Minimum 3 digits for alignment

        let lineNumberAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: lineNumberColor,
            .font: baseFont
        ]

        for lineIndex in 0..<lines.count {
            let lineNumber = lineIndex + 1
            let lineNumberString = String(format: "%\(lineNumberPadding)d  ", lineNumber)
            result.append(NSAttributedString(string: lineNumberString, attributes: lineNumberAttributes))

            // Add newline (except for last line)
            if lineIndex < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: [.font: baseFont]))
            }
        }

        return result
    }

    /// Builds the JSON content attributed string (without line numbers)
    private static func buildContentString(_ snapshot: BuildSnapshot) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let baseFont = snapshot.baseFont
        let mediumFont = snapshot.mediumFont
        let boldFont = snapshot.boldFont
        let lowercasedSearch = snapshot.searchText.lowercased()
        var globalMatchIndex = 0

        for (lineIndex, line) in snapshot.lines.enumerated() {
            // Add JSON content (no line numbers)
            for token in line.tokens {
                let color = snapshot.colorForTokenType(token.type)
                let font: NSFont = token.type == .key ? mediumFont : baseFont

                if !snapshot.searchText.isEmpty {
                    // Apply search highlighting within token
                    appendHighlightedToken(
                        token: token,
                        to: result,
                        baseColor: color,
                        baseFont: font,
                        boldFont: boldFont,
                        otherMatchBgColor: snapshot.searchOtherMatchBg,
                        currentMatchBgColor: snapshot.searchCurrentMatchBg,
                        otherMatchFgColor: snapshot.searchOtherMatchFg,
                        currentMatchFgColor: snapshot.searchCurrentMatchFg,
                        globalMatchIndex: &globalMatchIndex,
                        currentSearchIndex: snapshot.currentSearchIndex,
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
            if lineIndex < snapshot.lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: [.font: baseFont]))
            }
        }

        return result
    }

    private static func appendHighlightedToken(
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

enum JSONTokenType: Sendable {
    case key
    case string
    case number
    case boolean
    case null
    case structure
    case whitespace
}

struct JSONToken: Sendable {
    let text: String
    let type: JSONTokenType
}

struct FormattedLine: Sendable {
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
