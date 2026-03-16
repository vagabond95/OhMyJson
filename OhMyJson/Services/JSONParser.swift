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
            case .emptyInput:    return "Empty Input"
            case .encodingError: return "Encoding Error"
            case .syntaxError:   return "JSON Syntax Error"
            case .parsingError:  return "JSON Parsing Error"
            case .unknownError:  return "Invalid JSON"
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

        guard trimmed.data(using: .utf8) != nil else {
            return .failure(JSONParseError(
                message: "Invalid UTF-8 encoding",
                category: .encodingError
            ))
        }

        // 1차: 커스텀 재귀 하강 파서 (키 순서 보존)
        do {
            let jsonValue = try parseOrderPreserving(trimmed)
            let rootNode = JSONNode(value: jsonValue)
            return .success(rootNode)
        } catch {
            // 커스텀 파서 실패 시 fallback이 아닌 에러 리포팅
        }

        // 2차: JSONSerialization fallback (키 순서 미보장이지만 더 관대한 파서)
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
            var result = OrderedJSONObject()
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
        let sanitized = sanitizeForJSON(jsonString)
        let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1차: 커스텀 파서+포맷터 (키 순서 보존)
        if let value = try? parseOrderPreserving(trimmed) {
            var result = formatJSONValue(value, indent: indentSize, currentIndent: 0)
            result = patchNumbers(result, with: numberMapping)
            return result
        }

        // 2차: JSONSerialization fallback (키 순서 미보장)
        guard let data = trimmed.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted]),
              var prettyString = String(data: prettyData, encoding: .utf8) else {
            return nil
        }

        prettyString = patchNumbers(prettyString, with: numberMapping)

        // Collapse empty arrays/objects
        prettyString = prettyString.replacingOccurrences(of: "\\[\\s*\\]", with: "[]", options: .regularExpression)
        prettyString = prettyString.replacingOccurrences(of: "\\{\\s*\\}", with: "{}", options: .regularExpression)

        // Re-indent if needed
        let lines = prettyString.components(separatedBy: "\n")
        var nativeIndent = 0
        for line in lines {
            let stripped = line.drop(while: { $0 == " " })
            let leadingSpaces = line.count - stripped.count
            if leadingSpaces > 0 { nativeIndent = leadingSpaces; break }
        }
        if nativeIndent > 0 && nativeIndent != indentSize {
            prettyString = lines.map { line -> String in
                let stripped = line.drop(while: { $0 == " " })
                let leadingSpaces = line.count - stripped.count
                if leadingSpaces == 0 { return line }
                let level = leadingSpaces / nativeIndent
                return String(repeating: " ", count: level * indentSize) + stripped
            }.joined(separator: "\n")
        }

        prettyString = prettyString.replacingOccurrences(of: "\\/", with: "/")
        return prettyString
    }

    func minifyJSON(_ jsonString: String) -> String? {
        let numberMapping = extractNumberLiterals(jsonString)
        let sanitized = sanitizeForJSON(jsonString)
        let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1차: 커스텀 파서+포맷터 (키 순서 보존)
        if let value = try? parseOrderPreserving(trimmed) {
            var result = minifyJSONValue(value)
            result = patchNumbers(result, with: numberMapping)
            return result
        }

        // 2차: JSONSerialization fallback
        guard let data = trimmed.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let minifiedData = try? JSONSerialization.data(withJSONObject: jsonObject, options: []),
              var minifiedString = String(data: minifiedData, encoding: .utf8) else {
            return nil
        }

        minifiedString = patchNumbers(minifiedString, with: numberMapping)
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

    // MARK: - Order-Preserving Recursive Descent Parser

    /// Parse JSON text with key-order preservation using a recursive descent parser.
    func parseOrderPreserving(_ text: String) throws -> JSONValue {
        var parser = OrderPreservingJSONParser(text)
        let value = try parser.parseValue()
        parser.skipWhitespace()
        guard parser.isAtEnd else {
            throw JSONParseError(message: "Unexpected trailing content", category: .syntaxError)
        }
        return value
    }

    // MARK: - Custom JSON Formatter

    /// Pretty-print a JSONValue with key-order preservation.
    func formatJSONValue(_ value: JSONValue, indent: Int, currentIndent: Int) -> String {
        switch value {
        case .string(let s):
            return "\"\(escapeJSONString(s))\""
        case .number(let n):
            if n.truncatingRemainder(dividingBy: 1) == 0 && !n.isInfinite && !n.isNaN {
                let i = Int64(n)
                return String(i)
            }
            return String(n)
        case .bool(let b):
            return b ? "true" : "false"
        case .null:
            return "null"
        case .object(let obj):
            if obj.isEmpty { return "{}" }
            let nextIndent = currentIndent + indent
            let indentStr = String(repeating: " ", count: nextIndent)
            let closingIndent = String(repeating: " ", count: currentIndent)
            var parts: [String] = []
            for (key, val) in obj {
                let formattedVal = formatJSONValue(val, indent: indent, currentIndent: nextIndent)
                parts.append("\(indentStr)\"\(escapeJSONString(key))\": \(formattedVal)")
            }
            return "{\n\(parts.joined(separator: ",\n"))\n\(closingIndent)}"
        case .array(let arr):
            if arr.isEmpty { return "[]" }
            let nextIndent = currentIndent + indent
            let indentStr = String(repeating: " ", count: nextIndent)
            let closingIndent = String(repeating: " ", count: currentIndent)
            var parts: [String] = []
            for val in arr {
                let formattedVal = formatJSONValue(val, indent: indent, currentIndent: nextIndent)
                parts.append("\(indentStr)\(formattedVal)")
            }
            return "[\n\(parts.joined(separator: ",\n"))\n\(closingIndent)]"
        }
    }

    /// Minify a JSONValue to compact form with key-order preservation.
    func minifyJSONValue(_ value: JSONValue) -> String {
        switch value {
        case .string(let s):
            return "\"\(escapeJSONString(s))\""
        case .number(let n):
            if n.truncatingRemainder(dividingBy: 1) == 0 && !n.isInfinite && !n.isNaN {
                let i = Int64(n)
                return String(i)
            }
            return String(n)
        case .bool(let b):
            return b ? "true" : "false"
        case .null:
            return "null"
        case .object(let obj):
            let parts = obj.map { (key, val) in
                "\"\(escapeJSONString(key))\":\(minifyJSONValue(val))"
            }
            return "{\(parts.joined(separator: ","))}"
        case .array(let arr):
            let parts = arr.map { minifyJSONValue($0) }
            return "[\(parts.joined(separator: ","))]"
        }
    }

    /// Escape a string for JSON output.
    func escapeJSONString(_ s: String) -> String {
        var result = ""
        result.reserveCapacity(s.count)
        for char in s.unicodeScalars {
            switch char {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case "\u{08}": result += "\\b"
            case "\u{0C}": result += "\\f"
            default:
                if char.value < 0x20 {
                    result += String(format: "\\u%04x", char.value)
                } else {
                    result.unicodeScalars.append(char)
                }
            }
        }
        return result
    }
}

// MARK: - Recursive Descent JSON Parser

/// A simple recursive descent JSON parser that preserves object key order.
private struct OrderPreservingJSONParser {
    private let scalars: [UnicodeScalar]
    private var index: Int

    init(_ text: String) {
        self.scalars = Array(text.unicodeScalars)
        self.index = 0
    }

    var isAtEnd: Bool { index >= scalars.count }

    private var current: UnicodeScalar? {
        index < scalars.count ? scalars[index] : nil
    }

    mutating func skipWhitespace() {
        while index < scalars.count {
            switch scalars[index] {
            case " ", "\t", "\n", "\r": index += 1
            default: return
            }
        }
    }

    mutating func parseValue() throws -> JSONValue {
        skipWhitespace()
        guard let ch = current else {
            throw JSONParseError(message: "Unexpected end of input", category: .syntaxError)
        }
        switch ch {
        case "{": return try parseObject()
        case "[": return try parseArray()
        case "\"": return try .string(parseString())
        case "t", "f": return try parseBool()
        case "n": return try parseNull()
        case "-", "0"..."9": return try parseNumber()
        default:
            throw JSONParseError(message: "Unexpected character '\(ch)'", category: .syntaxError)
        }
    }

    mutating func parseObject() throws -> JSONValue {
        index += 1 // skip '{'
        skipWhitespace()
        var obj = OrderedJSONObject()
        if current == "}" {
            index += 1
            return .object(obj)
        }
        while true {
            skipWhitespace()
            guard current == "\"" else {
                throw JSONParseError(message: "Expected string key in object", category: .syntaxError)
            }
            let key = try parseString()
            skipWhitespace()
            guard current == ":" else {
                throw JSONParseError(message: "Expected ':' after key", category: .syntaxError)
            }
            index += 1 // skip ':'
            let value = try parseValue()
            obj[key] = value
            skipWhitespace()
            guard let sep = current else {
                throw JSONParseError(message: "Unexpected end of object", category: .syntaxError)
            }
            if sep == "}" { index += 1; return .object(obj) }
            if sep == "," { index += 1; continue }
            throw JSONParseError(message: "Expected ',' or '}' in object", category: .syntaxError)
        }
    }

    mutating func parseArray() throws -> JSONValue {
        index += 1 // skip '['
        skipWhitespace()
        var arr: [JSONValue] = []
        if current == "]" {
            index += 1
            return .array(arr)
        }
        while true {
            let value = try parseValue()
            arr.append(value)
            skipWhitespace()
            guard let sep = current else {
                throw JSONParseError(message: "Unexpected end of array", category: .syntaxError)
            }
            if sep == "]" { index += 1; return .array(arr) }
            if sep == "," { index += 1; continue }
            throw JSONParseError(message: "Expected ',' or ']' in array", category: .syntaxError)
        }
    }

    mutating func parseString() throws -> String {
        index += 1 // skip opening '"'
        var result: [UnicodeScalar] = []
        while index < scalars.count {
            let ch = scalars[index]
            if ch == "\"" {
                index += 1
                var s = ""
                s.unicodeScalars.append(contentsOf: result)
                return s
            }
            if ch == "\\" {
                index += 1
                guard index < scalars.count else {
                    throw JSONParseError(message: "Unexpected end of string escape", category: .syntaxError)
                }
                let esc = scalars[index]
                switch esc {
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "/": result.append("/")
                case "b": result.append("\u{08}")
                case "f": result.append("\u{0C}")
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                case "u":
                    index += 1
                    let codepoint = try parseUnicodeEscape()
                    // Handle surrogate pairs
                    if codepoint >= 0xD800 && codepoint <= 0xDBFF {
                        // High surrogate — expect \uXXXX low surrogate
                        guard index + 1 < scalars.count,
                              scalars[index] == "\\", scalars[index + 1] == "u" else {
                            result.append(UnicodeScalar(0xFFFD)!)
                            continue
                        }
                        index += 2 // skip \u
                        let low = try parseUnicodeEscape()
                        if low >= 0xDC00 && low <= 0xDFFF {
                            let combined = 0x10000 + (codepoint - 0xD800) * 0x400 + (low - 0xDC00)
                            if let scalar = UnicodeScalar(combined) {
                                result.append(scalar)
                            } else {
                                result.append(UnicodeScalar(0xFFFD)!)
                            }
                        } else {
                            result.append(UnicodeScalar(0xFFFD)!)
                        }
                    } else if let scalar = UnicodeScalar(codepoint) {
                        result.append(scalar)
                    } else {
                        result.append(UnicodeScalar(0xFFFD)!)
                    }
                    continue
                default:
                    throw JSONParseError(message: "Invalid escape sequence '\\(esc)'", category: .syntaxError)
                }
                index += 1
            } else {
                result.append(ch)
                index += 1
            }
        }
        throw JSONParseError(message: "Unterminated string", category: .syntaxError)
    }

    private mutating func parseUnicodeEscape() throws -> UInt32 {
        guard index + 3 < scalars.count else {
            throw JSONParseError(message: "Invalid unicode escape", category: .syntaxError)
        }
        var hex: UInt32 = 0
        for _ in 0..<4 {
            let ch = scalars[index]
            hex <<= 4
            switch ch {
            case "0"..."9": hex |= ch.value - 0x30
            case "a"..."f": hex |= ch.value - 0x61 + 10
            case "A"..."F": hex |= ch.value - 0x41 + 10
            default:
                throw JSONParseError(message: "Invalid hex digit in unicode escape", category: .syntaxError)
            }
            index += 1
        }
        return hex
    }

    mutating func parseNumber() throws -> JSONValue {
        let start = index
        if current == "-" { index += 1 }
        guard index < scalars.count, scalars[index] >= "0" && scalars[index] <= "9" else {
            throw JSONParseError(message: "Invalid number", category: .syntaxError)
        }
        // Integer part
        if scalars[index] == "0" {
            index += 1
        } else {
            while index < scalars.count && scalars[index] >= "0" && scalars[index] <= "9" { index += 1 }
        }
        // Fraction
        if index < scalars.count && scalars[index] == "." {
            index += 1
            guard index < scalars.count && scalars[index] >= "0" && scalars[index] <= "9" else {
                throw JSONParseError(message: "Invalid number: expected digit after decimal point", category: .syntaxError)
            }
            while index < scalars.count && scalars[index] >= "0" && scalars[index] <= "9" { index += 1 }
        }
        // Exponent
        if index < scalars.count && (scalars[index] == "e" || scalars[index] == "E") {
            index += 1
            if index < scalars.count && (scalars[index] == "+" || scalars[index] == "-") { index += 1 }
            guard index < scalars.count && scalars[index] >= "0" && scalars[index] <= "9" else {
                throw JSONParseError(message: "Invalid number: expected digit in exponent", category: .syntaxError)
            }
            while index < scalars.count && scalars[index] >= "0" && scalars[index] <= "9" { index += 1 }
        }
        var numStr = ""
        numStr.unicodeScalars.append(contentsOf: scalars[start..<index])
        guard let d = Double(numStr) else {
            throw JSONParseError(message: "Invalid number literal '\(numStr)'", category: .syntaxError)
        }
        return .number(d)
    }

    mutating func parseBool() throws -> JSONValue {
        if matchLiteral("true") { return .bool(true) }
        if matchLiteral("false") { return .bool(false) }
        throw JSONParseError(message: "Invalid boolean value", category: .syntaxError)
    }

    mutating func parseNull() throws -> JSONValue {
        guard matchLiteral("null") else {
            throw JSONParseError(message: "Invalid null value", category: .syntaxError)
        }
        return .null
    }

    private mutating func matchLiteral(_ literal: String) -> Bool {
        let literalScalars = Array(literal.unicodeScalars)
        guard index + literalScalars.count <= scalars.count else { return false }
        for (i, s) in literalScalars.enumerated() {
            guard scalars[index + i] == s else { return false }
        }
        index += literalScalars.count
        return true
    }
}
