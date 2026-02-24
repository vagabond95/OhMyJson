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
    var isSearchDismissed: Bool = false
    var isSearchVisible: Bool = false
    var onMouseDown: (() -> Void)?
    @Binding var isRendering: Bool

    @State private var formattedLines: [FormattedLine] = []
    @State private var searchResults: [SearchResult] = []
    @State private var currentSearchResultLocation: SearchResultLocation?
    @State private var hasInitialized = false
    @State private var isContentDirty = false  // formattedJSON or ignoreEscapeSequences changed
    @State private var isSearchDirty = false   // searchText changed while inactive
    @State private var isThemeDirty = false    // isDarkMode changed while inactive
    @State private var buildTask: Task<Void, Never>?
    /// Monotonically increasing version counter for cachedContentString.
    /// Incremented whenever the displayed content attributed string changes,
    /// allowing SelectableTextView to detect updates in O(1) instead of O(n).
    @State private var contentVersion: Int = 0
    /// Monotonically increasing version counter for cachedLineNumberString.
    @State private var gutterVersion: Int = 0

    /// Line count threshold for switching to async attributed string building
    private static let asyncBuildThreshold = 1000

    /// Stage 1 cache: syntax-colored string WITHOUT search highlights.
    /// Rebuilt only when content or theme changes.
    @State private var cachedBaseContentString: NSMutableAttributedString = NSMutableAttributedString()

    /// Stage 2 result: base + search highlights overlaid. Displayed by the view.
    @State private var cachedContentString: NSAttributedString = NSAttributedString()
    @State private var cachedLineNumberString: NSAttributedString = NSAttributedString()

    /// Cached NSRange positions of all search matches in the current content string.
    /// Built once per searchText change; reused on every currentSearchIndex change.
    @State private var cachedMatchRanges: [NSRange] = []
    /// The search index that was last fully highlighted (used to revert it on next navigation).
    @State private var lastHighlightedIndex: Int = -1
    /// Pending incremental attribute patches for SelectableTextView (nil = full rebuild).
    @State private var highlightPatches: [HighlightPatch]? = nil
    /// Monotonically increasing version for highlight patches.
    @State private var highlightVersion: Int = 0
    /// Version counter for search-triggered content updates that should clear selection.
    @State private var clearSelectionVersion: Int = 0

    @Environment(AppSettings.self) var settings
    private var theme: AppTheme { settings.currentTheme }

    var body: some View {
        SelectableTextView(
            attributedString: cachedContentString,
            lineNumberString: cachedLineNumberString,
            backgroundColor: NSColor(theme.background),
            selectedTextForegroundColor: theme.nsSelectedTextColor,
            selectedTextBackgroundColor: theme.nsSelectedTextBackground,
            scrollPosition: $scrollPosition,
            scrollToRange: isRestoringTabState ? nil : (isSearchDismissed ? nil : currentSearchResultLocation?.characterRange),
            isRestoringTabState: isRestoringTabState,
            onMouseDown: onMouseDown,
            contentId: contentVersion,
            gutterContentId: gutterVersion,
            highlightPatches: highlightPatches,
            highlightVersion: highlightVersion,
            preserveSelection: isSearchVisible,
            clearSelectionVersion: clearSelectionVersion
        )
        .onChange(of: searchText) { _, newValue in
            guard isActive else { isSearchDirty = true; return }
            updateSearchResults()
            if !newValue.isEmpty && !searchResults.isEmpty {
                currentSearchIndex = 0
                updateCurrentSearchLocation(index: 0)
            } else {
                currentSearchResultLocation = nil
            }
            applySearchHighlights()
        }
        .onChange(of: currentSearchIndex) { _, newIndex in
            guard isActive else { return }
            if !searchResults.isEmpty {
                updateCurrentSearchLocation(index: newIndex)
            }
            // Use incremental patch when match positions are cached — avoids full string rebuild
            if !cachedMatchRanges.isEmpty && !searchText.isEmpty && !isSearchDismissed {
                updateCurrentHighlight(from: lastHighlightedIndex, to: newIndex)
            } else {
                applySearchHighlights()
            }
            lastHighlightedIndex = newIndex
        }
        .onAppear {
            guard isActive else {
                isRendering = false
                return
            }
            performFullInit()
        }
        .onChange(of: isActive) { _, newValue in
            guard newValue else { return }
            if !hasInitialized {
                performFullInit()
            } else if isContentDirty {
                isRendering = true
                formatJSON {
                    updateSearchResults()
                    rebuildBaseAndHighlights {
                        self.isRendering = false
                    }
                    isContentDirty = false
                    isSearchDirty = false
                    isThemeDirty = false
                }
            } else if isThemeDirty {
                rebuildBaseAndHighlights()
                isThemeDirty = false
                isSearchDirty = false
            } else if isSearchDirty {
                updateSearchResults()
                applySearchHighlights()
                isSearchDirty = false
            }
        }
        .onChange(of: formattedJSON) { _, _ in
            guard isActive else { isContentDirty = true; isRendering = false; return }
            isRendering = true
            formatJSON {
                updateSearchResults()
                rebuildBaseAndHighlights {
                    self.isRendering = false
                }
            }
        }
        .onChange(of: isSearchDismissed) { _, _ in
            guard isActive else { return }
            applySearchHighlights()
        }
        .onChange(of: settings.isDarkMode) { _, _ in
            guard isActive else { isThemeDirty = true; return }
            // Theme change doesn't affect token data — only colors need rebuilding
            rebuildBaseAndHighlights()
        }
        .onChange(of: settings.ignoreEscapeSequences) { _, _ in
            guard isActive else { isContentDirty = true; return }
            isRendering = true
            formatJSON {
                updateSearchResults()
                rebuildBaseAndHighlights {
                    self.isRendering = false
                }
            }
        }
        .background(theme.background)
    }

    // MARK: - Initialization

    private func performFullInit() {
        isRendering = true
        formatJSON {
            restoreSearchState()
            rebuildBaseAndHighlights {
                self.isRendering = false
            }
            hasInitialized = true
            isContentDirty = false
            isSearchDirty = false
            isThemeDirty = false
        }
    }

    // MARK: - Attributed String Building (2-Stage Pipeline)
    //
    // Stage 1 (Base): Builds syntax-colored NSMutableAttributedString from tokens.
    //   Rebuilt only when formattedLines or theme changes.
    //
    // Stage 2 (Search Highlight): Copies base string and overlays search match
    //   attributes (background, foreground, bold). Runs on every search change.
    //   Complexity: O(matches) via NSString.range(of:) instead of O(all_tokens).

    /// Snapshot of theme colors and fonts for off-main-thread base string building.
    /// @unchecked Sendable because NSColor/NSFont are immutable once created.
    private struct BuildSnapshot: @unchecked Sendable {
        let lines: [FormattedLine]
        let keyColor: NSColor
        let stringColor: NSColor
        let numberColor: NSColor
        let booleanColor: NSColor
        let nullColor: NSColor
        let structureColor: NSColor
        let lineNumberColor: NSColor
        let baseFont: NSFont
        let mediumFont: NSFont

        init(lines: [FormattedLine], theme: AppTheme) {
            self.lines = lines
            keyColor = NSColor(theme.key)
            stringColor = NSColor(theme.string)
            numberColor = NSColor(theme.number)
            booleanColor = NSColor(theme.boolean)
            nullColor = NSColor(theme.null)
            structureColor = NSColor(theme.structure)
            lineNumberColor = NSColor(theme.secondaryText).withAlphaComponent(0.5)
            baseFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            mediumFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
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

    /// Wrapper for passing attributed strings across actor boundaries.
    private struct BaseStringPair: @unchecked Sendable {
        let content: NSMutableAttributedString
        let lineNumbers: NSAttributedString
    }

    /// Stage 1 + 2: Rebuilds base content string, then applies search highlights.
    /// Called when content or theme changes.
    private func rebuildBaseAndHighlights(completion: (() -> Void)? = nil) {
        let snapshot = BuildSnapshot(lines: formattedLines, theme: theme)

        if snapshot.lines.count < Self.asyncBuildThreshold {
            buildTask?.cancel()
            cachedBaseContentString = Self.buildBaseContentString(snapshot)
            cachedLineNumberString = Self.buildLineNumberString(snapshot)
            gutterVersion &+= 1
            applySearchHighlights(clearSelection: false)
            completion?()
            return
        }

        // Large content — build base off main thread
        buildTask?.cancel()
        buildTask = Task {
            let pair = await Task.detached(priority: .userInitiated) {
                BaseStringPair(
                    content: Self.buildBaseContentString(snapshot),
                    lineNumbers: Self.buildLineNumberString(snapshot)
                )
            }.value

            guard !Task.isCancelled else { return }
            cachedBaseContentString = pair.content
            cachedLineNumberString = pair.lineNumbers
            gutterVersion &+= 1
            applySearchHighlights(clearSelection: false)
            completion?()
        }
    }

    /// Stage 2 only: Overlays search highlights onto the cached base string.
    /// Called when searchText or currentSearchIndex changes (skips Stage 1).
    /// Also rebuilds `cachedMatchRanges` for subsequent incremental updates.
    /// - Parameter clearSelection: When true, increments `clearSelectionVersion` so
    ///   SelectableTextView clears any drag selection. Pass false for theme/content rebuilds.
    private func applySearchHighlights(clearSelection: Bool = true) {
        guard !searchText.isEmpty, !isSearchDismissed else {
            cachedContentString = cachedBaseContentString
            cachedMatchRanges = []
            highlightPatches = nil
            if clearSelection { clearSelectionVersion &+= 1 }
            contentVersion &+= 1
            return
        }

        let highlighted = cachedBaseContentString.mutableCopy() as! NSMutableAttributedString
        let nsString = highlighted.string as NSString
        let totalLength = nsString.length

        guard totalLength > 0 else {
            cachedContentString = cachedBaseContentString
            cachedMatchRanges = []
            return
        }

        let otherMatchBg = NSColor(theme.searchOtherMatchBg)
        let currentMatchBg = NSColor(theme.searchCurrentMatchBg)
        let otherMatchFg = NSColor(theme.searchOtherMatchFg)
        let currentMatchFg = NSColor(theme.searchCurrentMatchFg)
        let boldFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .bold)

        var searchRange = NSRange(location: 0, length: totalLength)
        var matchRanges: [NSRange] = []
        var matchIndex = 0

        while searchRange.length > 0 {
            let foundRange = nsString.range(of: searchText, options: .caseInsensitive, range: searchRange)
            guard foundRange.location != NSNotFound else { break }

            matchRanges.append(foundRange)

            let isCurrent = matchIndex == currentSearchIndex
            highlighted.addAttribute(.backgroundColor, value: isCurrent ? currentMatchBg : otherMatchBg, range: foundRange)
            highlighted.addAttribute(.foregroundColor, value: isCurrent ? currentMatchFg : otherMatchFg, range: foundRange)
            highlighted.addAttribute(.font, value: boldFont, range: foundRange)

            matchIndex += 1
            let nextLocation = foundRange.location + foundRange.length
            searchRange = NSRange(location: nextLocation, length: totalLength - nextLocation)
        }

        cachedMatchRanges = matchRanges
        cachedContentString = highlighted
        highlightPatches = nil
        lastHighlightedIndex = currentSearchIndex
        if clearSelection { clearSelectionVersion &+= 1 }
        contentVersion &+= 1
    }

    /// Incremental variant: updates only the 2 ranges that change on Cmd+G navigation.
    /// Avoids copying + re-scanning the full string; only touches 1–2 NSRange patches.
    private func updateCurrentHighlight(from oldIndex: Int, to newIndex: Int) {
        guard newIndex >= 0 && newIndex < cachedMatchRanges.count else { return }

        let otherMatchBg = NSColor(theme.searchOtherMatchBg)
        let currentMatchBg = NSColor(theme.searchCurrentMatchBg)
        let otherMatchFg = NSColor(theme.searchOtherMatchFg)
        let currentMatchFg = NSColor(theme.searchCurrentMatchFg)
        let boldFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .bold)

        var patches: [HighlightPatch] = []

        // Revert previous current match → other match color
        if oldIndex >= 0 && oldIndex < cachedMatchRanges.count && oldIndex != newIndex {
            patches.append(HighlightPatch(
                range: cachedMatchRanges[oldIndex],
                backgroundColor: otherMatchBg,
                foregroundColor: otherMatchFg,
                font: boldFont
            ))
        }

        // Promote new current match → current match color
        patches.append(HighlightPatch(
            range: cachedMatchRanges[newIndex],
            backgroundColor: currentMatchBg,
            foregroundColor: currentMatchFg,
            font: boldFont
        ))

        // Apply patches to cachedContentString to keep it consistent with textStorage
        let mutable = cachedContentString.mutableCopy() as! NSMutableAttributedString
        for patch in patches {
            let maxLen = mutable.length
            guard maxLen > 0, patch.range.location < maxLen else { continue }
            let safeLength = min(patch.range.length, maxLen - patch.range.location)
            guard safeLength > 0 else { continue }
            let safeRange = NSRange(location: patch.range.location, length: safeLength)
            mutable.addAttribute(.backgroundColor, value: patch.backgroundColor, range: safeRange)
            mutable.addAttribute(.foregroundColor, value: patch.foregroundColor, range: safeRange)
            mutable.addAttribute(.font, value: patch.font, range: safeRange)
        }
        cachedContentString = mutable
        // Do NOT increment contentVersion — SelectableTextView uses highlightVersion instead

        highlightPatches = patches
        highlightVersion &+= 1
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

    /// Stage 1: Builds syntax-colored content string WITHOUT search highlights
    private static func buildBaseContentString(_ snapshot: BuildSnapshot) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        let baseFont = snapshot.baseFont
        let mediumFont = snapshot.mediumFont

        for (lineIndex, line) in snapshot.lines.enumerated() {
            for token in line.tokens {
                let color = snapshot.colorForTokenType(token.type)
                let font: NSFont = token.type == .key ? mediumFont : baseFont

                var attributes: [NSAttributedString.Key: Any] = [
                    .foregroundColor: color,
                    .font: font
                ]

                if token.type == .null {
                    attributes[.obliqueness] = 0.1 // italic effect
                }

                result.append(NSAttributedString(string: token.text, attributes: attributes))
            }

            // Add newline (except for last line)
            if lineIndex < snapshot.lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: [.font: baseFont]))
            }
        }

        return result
    }

    // MARK: - JSON Formatting

    @State private var formatTask: Task<Void, Never>?

    /// Tokenizes formattedJSON on a background thread to avoid blocking the main thread
    /// for large documents. Calls `completion` on the main actor when done.
    private func formatJSON(completion: (() -> Void)? = nil) {
        formatTask?.cancel()
        let json = formattedJSON
        let strip = settings.ignoreEscapeSequences
        let maxLines = BeautifyLimit.maxDisplayLines
        formatTask = Task {
            let lines = await Task.detached(priority: .userInitiated) {
                Self.tokenizeFormattedJSON(json, stripEscapes: strip, maxLines: maxLines)
            }.value
            guard !Task.isCancelled else { return }
            formattedLines = lines
            completion?()
        }
    }

    private static func tokenizeFormattedJSON(
        _ json: String,
        stripEscapes: Bool = false,
        maxLines: Int? = nil
    ) -> [FormattedLine] {
        let lines = json.components(separatedBy: "\n")
        let totalCount = lines.count
        let isTruncated = maxLines != nil && totalCount > maxLines!
        let linesToProcess = isTruncated ? Array(lines.prefix(maxLines!)) : lines

        var result = linesToProcess.map { line in
            FormattedLine(tokens: tokenizeLine(line, stripEscapes: stripEscapes))
        }

        if isTruncated {
            let notice = "// ---- Showing first \(maxLines!.formatted()) of \(totalCount.formatted()) lines ----\n// Full content parsed. Use Tree mode for complete view."
            result.append(FormattedLine(tokens: [JSONToken(text: notice, type: .structure)]))
        }

        return result
    }

    private static func tokenizeLine(_ line: String, stripEscapes: Bool = false) -> [JSONToken] {
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

                    let tokenText: String
                    if stripEscapes {
                        // Strip escape sequences inside the quoted string, preserve quotes
                        let inner = String(stringContent.dropFirst().dropLast())
                        let stripped = JSONParser.stripEscapeSequencesInJSONString(inner)
                        tokenText = "\"\(stripped)\""
                    } else {
                        tokenText = stringContent
                    }

                    tokens.append(JSONToken(text: tokenText, type: isKey ? .key : .string))
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

    private static func findStringEnd(in text: Substring) -> String.Index? {
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
            scrollPosition: .constant(0),
            isRendering: .constant(false)
        )
        .frame(width: 400, height: 300)
    }
}
#endif
