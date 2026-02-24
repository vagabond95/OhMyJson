//
//  JSONParser.swift
//  OhMyJson
//

import Foundation

struct JSONParseError: Error, LocalizedError {

    enum Category {
        case emptyInput       // 빈/공백 입력
        case encodingError    // UTF-8 인코딩 실패
        case syntaxError      // JSON 구문 규칙 위반
        case parsingError     // 구문은 맞지만 파싱 문제 (깊은 중첩 등)
        case unknownError     // 기타

        var localizedHeader: String {
            switch self {
            case .emptyInput:    return String(localized: "error.header.empty_input")
            case .encodingError: return String(localized: "error.header.encoding_error")
            case .syntaxError:   return String(localized: "error.header.syntax_error")
            case .parsingError:  return String(localized: "error.header.parsing_error")
            case .unknownError:  return String(localized: "error.header.unknown_error")
            }
        }

        var iconName: String {
            switch self {
            case .emptyInput:    return "doc"
            case .encodingError: return "textformat.characters.dottedunderline"
            case .syntaxError:   return "curlybraces"
            case .parsingError:  return "exclamationmark.triangle"
            case .unknownError:  return "questionmark.circle"
            }
        }
    }

    let message: String
    let line: Int?
    let column: Int?
    let category: Category

    var errorDescription: String? {
        var desc = message
        if let line = line, let column = column {
            desc += " at line \(line), column \(column)"
        }
        return desc
    }

    init(message: String, line: Int? = nil, column: Int? = nil, category: Category = .unknownError) {
        self.message = message
        self.line = line
        self.column = column
        self.category = category
    }
}

enum JSONParseResult {
    case success(JSONNode)
    case failure(JSONParseError)
}

class JSONParser: JSONParserProtocol {
    static let shared = JSONParser()

    private init() {}

    /// Sanitize common Unicode artifacts from styled/rich text sources
    /// (web browsers, Slack, Notion, IDEs, etc.) that break JSON parsing.
    /// Single-pass O(n) scan over unicode scalars — no intermediate string copies.
    private func sanitizeForJSON(_ text: String) -> String {
        let scalars = text.unicodeScalars

        // Fast path: scan for any problematic scalar before allocating
        for scalar in scalars {
            switch scalar.value {
            case 0x201C, 0x201D, 0x201E, 0x201F, // smart/curly quotes
                 0x00A0, 0x2007, 0x202F,          // special spaces
                 0xFEFF, 0x200B, 0x200C, 0x200D, 0x200E, 0x200F, // zero-width / invisible
                 0x2028, 0x2029:                   // line/paragraph separators
                return sanitizeForJSONSlow(scalars)
            default:
                continue
            }
        }

        return text
    }

    /// Slow path: builds a new string replacing/removing problematic unicode scalars.
    /// Context-aware: tracks whether we are inside a JSON string to avoid corrupting
    /// smart quotes that appear as value characters inside straight-quote strings.
    private func sanitizeForJSONSlow(_ scalars: String.UnicodeScalarView) -> String {
        var result: [UnicodeScalar] = []
        result.reserveCapacity(scalars.underestimatedCount)

        var insideString = false
        var openedWithStraightQuote = false
        var prevWasBackslash = false

        for scalar in scalars {
            // Character after \ is escaped — append verbatim without state change
            if prevWasBackslash {
                result.append(scalar)
                prevWasBackslash = false
                continue
            }

            switch scalar.value {
            case 0x5C: // backslash
                result.append(scalar)
                if insideString { prevWasBackslash = true }

            case 0x22: // straight double quote "
                result.append(scalar)
                if insideString && openedWithStraightQuote {
                    insideString = false
                    openedWithStraightQuote = false
                } else if !insideString {
                    insideString = true
                    openedWithStraightQuote = true
                }
                // An unmatched " inside a smart-quote string is left as-is

            // Opening smart quotes: " (201C), „ (201E)
            case 0x201C, 0x201E:
                if insideString && openedWithStraightQuote {
                    // Inside a straight-quote JSON string: preserve — JSONSerialization handles it
                    result.append(scalar)
                } else if !insideString {
                    // Structural smart quote (e.g. rich-text paste): replace with "
                    result.append("\"")
                    insideString = true
                    openedWithStraightQuote = false
                } else {
                    // Nested opening inside a smart-quote string: replace with "
                    result.append("\"")
                }

            // Closing smart quotes: " (201D), ‟ (201F)
            case 0x201D, 0x201F:
                if insideString && openedWithStraightQuote {
                    // Inside a straight-quote JSON string: preserve
                    result.append(scalar)
                } else if insideString && !openedWithStraightQuote {
                    // Closes a smart-quote string
                    result.append("\"")
                    insideString = false
                    openedWithStraightQuote = false
                } else {
                    // Outside any string: replace with "
                    result.append("\"")
                }

            // Special spaces → regular space
            case 0x00A0, 0x2007, 0x202F:
                result.append(" ")

            // Zero-width / invisible → remove
            case 0xFEFF, 0x200B, 0x200C, 0x200D, 0x200E, 0x200F:
                break

            // Line/paragraph separator: escape inside strings (JSON spec), newline outside
            case 0x2028, 0x2029:
                if insideString {
                    result.append("\\")
                    result.append("u")
                    result.append("2")
                    result.append("0")
                    result.append("2")
                    result.append(scalar.value == 0x2028 ? "8" : "9")
                } else {
                    result.append("\n")
                }

            default:
                result.append(scalar)
            }
        }

        var output = ""
        output.unicodeScalars.append(contentsOf: result)
        return output
    }

    // MARK: - Escape Sequence Stripping

    /// Strip decoded control characters (\n, \t, \r, \f, \b) from a Swift String.
    /// Used by TreeView where Foundation has already decoded escape sequences into actual characters.
    /// Each control character is replaced with a space; consecutive spaces are collapsed to one.
    static func stripControlCharacters(_ s: String) -> String {
        var result: [Character] = []
        result.reserveCapacity(s.count)
        var lastWasSpace = false

        for char in s {
            switch char {
            case "\n", "\t", "\r", "\u{0C}", "\u{08}":
                if !lastWasSpace {
                    result.append(" ")
                    lastWasSpace = true
                }
            case " ":
                if !lastWasSpace {
                    result.append(" ")
                    lastWasSpace = true
                }
            default:
                result.append(char)
                lastWasSpace = false
            }
        }

        return String(result)
    }

    /// Strip literal escape sequences (backslash+char) from a JSON-encoded string.
    /// Used by BeautifyView where text contains literal `\n`, `\t`, etc. (two-character sequences).
    /// Preserves `\\` (escaped backslash) and `\"` (escaped quote). Collapses consecutive spaces.
    static func stripEscapeSequencesInJSONString(_ s: String) -> String {
        var result: [Character] = []
        result.reserveCapacity(s.count)
        var lastWasSpace = false
        var i = s.startIndex

        while i < s.endIndex {
            let char = s[i]

            if char == "\\" {
                let next = s.index(after: i)
                if next < s.endIndex {
                    let nextChar = s[next]
                    switch nextChar {
                    case "n", "t", "r", "f", "b":
                        // Replace escape sequence with space
                        if !lastWasSpace {
                            result.append(" ")
                            lastWasSpace = true
                        }
                        i = s.index(after: next)
                        continue
                    default:
                        // Keep \\ , \" , \uXXXX, etc. — append both characters
                        result.append(char)
                        result.append(nextChar)
                        lastWasSpace = false
                        i = s.index(after: next)
                        continue
                    }
                }
            }

            if char == " " {
                if !lastWasSpace {
                    result.append(" ")
                    lastWasSpace = true
                }
            } else {
                result.append(char)
                lastWasSpace = false
            }

            i = s.index(after: i)
        }

        return String(result)
    }

    func validateJSON(_ jsonString: String) -> Bool {
        let sanitized = sanitizeForJSON(jsonString)
        let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    }

    func parse(_ jsonString: String) -> JSONParseResult {
        let sanitized = sanitizeForJSON(jsonString)
        let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return .failure(JSONParseError(
                message: "",
                category: .emptyInput
            ))
        }

        guard let data = trimmed.data(using: .utf8) else {
            return .failure(JSONParseError(
                message: "Invalid UTF-8 encoding",
                category: .encodingError
            ))
        }

        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            let jsonValue = convertToJSONValue(jsonObject)
            let rootNode = JSONNode(value: jsonValue)
            return .success(rootNode)
        } catch let error as NSError {
            let (line, column) = extractPosition(from: error, text: jsonString)
            return .failure(JSONParseError(
                message: extractMessage(from: error),
                line: line,
                column: column,
                category: classifyNSError(error)
            ))
        }
    }

    private func convertToJSONValue(_ any: Any) -> JSONValue {
        switch any {
        case let string as String:
            return .string(string)

        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            return .number(number.doubleValue)

        case let array as [Any]:
            return .array(array.map { convertToJSONValue($0) })

        case let dict as [String: Any]:
            var result: [String: JSONValue] = [:]
            for (key, value) in dict {
                result[key] = convertToJSONValue(value)
            }
            return .object(result)

        case is NSNull:
            return .null

        default:
            return .null
        }
    }

    private func extractPosition(from error: NSError, text: String) -> (line: Int?, column: Int?) {
        // Use NSDebugDescription which contains position info; fall back to localizedDescription
        let errorDesc = (error.userInfo["NSDebugDescription"] as? String) ?? error.localizedDescription

        let patterns = [
            "line (\\d+), column (\\d+)",
            "character (\\d+)"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: errorDesc, options: [], range: NSRange(errorDesc.startIndex..., in: errorDesc)) {

                if match.numberOfRanges == 3 {
                    let lineRange = Range(match.range(at: 1), in: errorDesc)!
                    let columnRange = Range(match.range(at: 2), in: errorDesc)!
                    let line = Int(errorDesc[lineRange])
                    let column = Int(errorDesc[columnRange])
                    return (line, column)
                } else if match.numberOfRanges == 2 {
                    let charRange = Range(match.range(at: 1), in: errorDesc)!
                    if let charPos = Int(errorDesc[charRange]) {
                        return calculateLineColumn(from: charPos, in: text)
                    }
                }
            }
        }

        return (nil, nil)
    }

    private func calculateLineColumn(from charPosition: Int, in text: String) -> (line: Int?, column: Int?) {
        guard charPosition > 0 else { return (1, 1) }

        var currentLine = 1
        var currentColumn = 1
        var currentChar = 0

        for char in text {
            if currentChar >= charPosition {
                break
            }

            if char == "\n" {
                currentLine += 1
                currentColumn = 1
            } else {
                currentColumn += 1
            }
            currentChar += 1
        }

        return (currentLine, currentColumn)
    }

    private func classifyNSError(_ error: NSError) -> JSONParseError.Category {
        let desc = ((error.userInfo["NSDebugDescription"] as? String) ?? error.localizedDescription).lowercased()

        // Syntax errors: structural JSON violations
        let syntaxKeywords = [
            "invalid value", "badly formed", "unexpected character",
            "unterminated string", "invalid escape", "no value",
            "unescaped control", "number is not representable",
            "did not start with"
        ]
        for keyword in syntaxKeywords {
            if desc.contains(keyword) { return .syntaxError }
        }

        // Parsing errors: valid structure but too complex
        let parsingKeywords = ["too deeply nested", "too large", "too many keys"]
        for keyword in parsingKeywords {
            if desc.contains(keyword) { return .parsingError }
        }

        // Fallback: NSCocoaErrorDomain is almost always a syntax issue
        if error.domain == NSCocoaErrorDomain {
            return .syntaxError
        }

        return .unknownError
    }

    private func extractMessage(from error: NSError) -> String {
        // Prefer NSDebugDescription (contains the actual diagnostic) over localizedDescription
        // (which is often just "The data couldn't be read because it isn't in the correct format.")
        var message = (error.userInfo["NSDebugDescription"] as? String) ?? error.localizedDescription

        let cleanupPatterns = [
            "The data couldn.t be read because it isn.t in the correct format\\.",
            "JSON text did not start with array or object and option to allow fragments not set\\.",
            "around line \\d+, column \\d+\\.?",
            "around character \\d+\\.?"
        ]

        for pattern in cleanupPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                message = regex.stringByReplacingMatches(
                    in: message,
                    options: [],
                    range: NSRange(message.startIndex..., in: message),
                    withTemplate: ""
                ).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Remove trailing period if present
        if message.hasSuffix(".") {
            message = String(message.dropLast()).trimmingCharacters(in: .whitespaces)
        }

        return message
    }

    func formatJSON(_ jsonString: String, indentSize: Int = 4) -> String? {
        let numberMapping = extractNumberLiterals(jsonString)

        guard let data = jsonString.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
              var prettyString = String(data: prettyData, encoding: .utf8) else {
            return nil
        }

        prettyString = patchNumbers(prettyString, with: numberMapping)

        // Collapse empty arrays to single line: [\n  ...  ] → []
        prettyString = prettyString.replacingOccurrences(
            of: "\\[\\s*\\]",
            with: "[]",
            options: .regularExpression
        )

        // Collapse empty objects to single line: {\n  ...  } → {}
        prettyString = prettyString.replacingOccurrences(
            of: "\\{\\s*\\}",
            with: "{}",
            options: .regularExpression
        )

        // Re-indent if needed (Apple's prettyPrinted uses 2-space indent on macOS 15+, 4-space on older)
        // Detect the native indent unit by finding the first indented line
        let lines = prettyString.components(separatedBy: "\n")
        var nativeIndent = 0
        for line in lines {
            let stripped = line.drop(while: { $0 == " " })
            let leadingSpaces = line.count - stripped.count
            if leadingSpaces > 0 {
                nativeIndent = leadingSpaces
                break
            }
        }

        if nativeIndent > 0 && nativeIndent != indentSize {
            let reindented = lines.map { line -> String in
                let stripped = line.drop(while: { $0 == " " })
                let leadingSpaces = line.count - stripped.count
                if leadingSpaces == 0 { return line }
                let level = leadingSpaces / nativeIndent
                return String(repeating: " ", count: level * indentSize) + stripped
            }
            prettyString = reindented.joined(separator: "\n")
        }

        // Unescape forward slashes: \/ → / (JSONSerialization escapes them unnecessarily)
        prettyString = prettyString.replacingOccurrences(of: "\\/", with: "/")

        return prettyString
    }

    func minifyJSON(_ jsonString: String) -> String? {
        let numberMapping = extractNumberLiterals(jsonString)

        guard let data = jsonString.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let minifiedData = try? JSONSerialization.data(withJSONObject: jsonObject, options: []),
              var minifiedString = String(data: minifiedData, encoding: .utf8) else {
            return nil
        }

        minifiedString = patchNumbers(minifiedString, with: numberMapping)

        // Unescape forward slashes: \/ → / (JSONSerialization escapes them unnecessarily)
        minifiedString = minifiedString.replacingOccurrences(of: "\\/", with: "/")

        return minifiedString
    }

    // MARK: - Number Precision Patch

    /// Serialize a Double using JSONSerialization to get the exact string representation it would produce.
    private func serializeNumber(_ value: Double) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "\(value)"
    }

    /// Scan the original JSON string and build a mapping from JSONSerialization's output form to the original literal,
    /// for any number where the round-trip produces a different string.
    private func extractNumberLiterals(_ jsonString: String) -> [String: String] {
        var mapping: [String: String] = [:]
        let chars = Array(jsonString.unicodeScalars)
        let count = chars.count
        var i = 0

        while i < count {
            let c = chars[i]

            // Skip string literals (including escaped quotes)
            if c == "\"" {
                i += 1
                while i < count {
                    if chars[i] == "\\" {
                        i += 2 // skip escaped character
                        continue
                    }
                    if chars[i] == "\"" {
                        i += 1
                        break
                    }
                    i += 1
                }
                continue
            }

            // Detect start of a number literal: digit or minus followed by digit
            let isNumberStart = (c >= "0" && c <= "9") || (c == "-" && i + 1 < count && chars[i + 1] >= "0" && chars[i + 1] <= "9")
            guard isNumberStart else {
                i += 1
                continue
            }

            // Extract the full number literal
            let start = i
            if c == "-" { i += 1 }
            // Integer part
            while i < count && chars[i] >= "0" && chars[i] <= "9" { i += 1 }
            var hasDecimalOrExp = false
            // Fractional part
            if i < count && chars[i] == "." {
                hasDecimalOrExp = true
                i += 1
                while i < count && chars[i] >= "0" && chars[i] <= "9" { i += 1 }
            }
            // Exponent part
            if i < count && (chars[i] == "e" || chars[i] == "E") {
                hasDecimalOrExp = true
                i += 1
                if i < count && (chars[i] == "+" || chars[i] == "-") { i += 1 }
                while i < count && chars[i] >= "0" && chars[i] <= "9" { i += 1 }
            }

            var original = ""
            original.unicodeScalars.append(contentsOf: chars[start..<i])

            // Optimization: skip integers in safe integer range (no precision loss possible)
            if !hasDecimalOrExp, let intVal = Int64(original), intVal >= -9007199254740991 && intVal <= 9007199254740991 {
                continue
            }

            guard let doubleVal = Double(original) else { continue }

            let serialized = serializeNumber(doubleVal)
            guard serialized != original else { continue }

            // First occurrence wins
            if mapping[serialized] == nil {
                mapping[serialized] = original
            }
        }

        return mapping
    }

    /// Replace serialized number literals in formatted JSON with their original forms using the mapping.
    private func patchNumbers(_ formattedJSON: String, with mapping: [String: String]) -> String {
        guard !mapping.isEmpty else { return formattedJSON }

        let chars = Array(formattedJSON.unicodeScalars)
        var result: [UnicodeScalar] = []
        result.reserveCapacity(chars.count)
        let count = chars.count
        var i = 0

        while i < count {
            let c = chars[i]

            // Copy string literals verbatim
            if c == "\"" {
                result.append(c)
                i += 1
                while i < count {
                    if chars[i] == "\\" {
                        result.append(chars[i])
                        if i + 1 < count {
                            result.append(chars[i + 1])
                        }
                        i += 2
                        continue
                    }
                    result.append(chars[i])
                    if chars[i] == "\"" {
                        i += 1
                        break
                    }
                    i += 1
                }
                continue
            }

            // Detect number start
            let isNumberStart = (c >= "0" && c <= "9") || (c == "-" && i + 1 < count && chars[i + 1] >= "0" && chars[i + 1] <= "9")
            guard isNumberStart else {
                result.append(c)
                i += 1
                continue
            }

            // Extract number literal from formatted output
            let start = i
            if c == "-" { i += 1 }
            while i < count && chars[i] >= "0" && chars[i] <= "9" { i += 1 }
            if i < count && chars[i] == "." {
                i += 1
                while i < count && chars[i] >= "0" && chars[i] <= "9" { i += 1 }
            }
            if i < count && (chars[i] == "e" || chars[i] == "E") {
                i += 1
                if i < count && (chars[i] == "+" || chars[i] == "-") { i += 1 }
                while i < count && chars[i] >= "0" && chars[i] <= "9" { i += 1 }
            }

            var numStr = ""
            numStr.unicodeScalars.append(contentsOf: chars[start..<i])

            if let replacement = mapping[numStr] {
                result.append(contentsOf: replacement.unicodeScalars)
            } else {
                result.append(contentsOf: numStr.unicodeScalars)
            }
        }

        var output = ""
        output.unicodeScalars.append(contentsOf: result)
        return output
    }
}
