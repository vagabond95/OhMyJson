//
//  JSONParser.swift
//  OhMyJson
//

import Foundation

struct JSONParseError: Error, LocalizedError {
    let message: String
    let line: Int?
    let column: Int?
    let preview: String?

    var errorDescription: String? {
        var desc = message
        if let line = line, let column = column {
            desc += " at line \(line), column \(column)"
        }
        return desc
    }

    init(message: String, line: Int? = nil, column: Int? = nil, originalText: String? = nil) {
        self.message = message
        self.line = line
        self.column = column
        if let text = originalText {
            let lines = text.components(separatedBy: .newlines)
            self.preview = lines.prefix(5).joined(separator: "\n")
        } else {
            self.preview = nil
        }
    }
}

enum JSONParseResult {
    case success(JSONNode)
    case failure(JSONParseError)
}

class JSONParser {
    static let shared = JSONParser()

    private init() {}

    /// Sanitize common Unicode artifacts from styled/rich text sources
    /// (web browsers, Slack, Notion, IDEs, etc.) that break JSON parsing.
    private func sanitizeForJSON(_ text: String) -> String {
        var result = text

        // Replace smart/curly quotes with straight quotes
        result = result.replacingOccurrences(of: "\u{201C}", with: "\"") // left double
        result = result.replacingOccurrences(of: "\u{201D}", with: "\"") // right double
        result = result.replacingOccurrences(of: "\u{201E}", with: "\"") // double low-9
        result = result.replacingOccurrences(of: "\u{201F}", with: "\"") // double high-reversed-9

        // Replace non-breaking and special spaces with regular space
        result = result.replacingOccurrences(of: "\u{00A0}", with: " ")  // non-breaking space
        result = result.replacingOccurrences(of: "\u{2007}", with: " ")  // figure space
        result = result.replacingOccurrences(of: "\u{202F}", with: " ")  // narrow no-break space

        // Remove zero-width / invisible characters
        result = result.replacingOccurrences(of: "\u{FEFF}", with: "")   // BOM / zero-width no-break space
        result = result.replacingOccurrences(of: "\u{200B}", with: "")   // zero-width space
        result = result.replacingOccurrences(of: "\u{200C}", with: "")   // zero-width non-joiner
        result = result.replacingOccurrences(of: "\u{200D}", with: "")   // zero-width joiner
        result = result.replacingOccurrences(of: "\u{200E}", with: "")   // left-to-right mark
        result = result.replacingOccurrences(of: "\u{200F}", with: "")   // right-to-left mark

        // Replace Unicode line/paragraph separators with newline
        result = result.replacingOccurrences(of: "\u{2028}", with: "\n") // line separator
        result = result.replacingOccurrences(of: "\u{2029}", with: "\n") // paragraph separator

        return result
    }

    func parse(_ jsonString: String) -> JSONParseResult {
        let sanitized = sanitizeForJSON(jsonString)
        let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return .failure(JSONParseError(
                message: "Empty input",
                originalText: jsonString
            ))
        }

        guard let data = trimmed.data(using: .utf8) else {
            return .failure(JSONParseError(
                message: "Invalid UTF-8 encoding",
                originalText: jsonString
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
                originalText: jsonString
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
        let errorDesc = error.localizedDescription

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

    private func extractMessage(from error: NSError) -> String {
        var message = error.localizedDescription

        let cleanupPatterns = [
            "The data couldn.t be read because it isn.t in the correct format\\.",
            "JSON text did not start with array or object and option to allow fragments not set\\."
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

        if message.isEmpty {
            message = "Invalid JSON format"
        }

        return message
    }

    func formatJSON(_ jsonString: String, indentSize: Int = 4) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
              var prettyString = String(data: prettyData, encoding: .utf8) else {
            return nil
        }

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

        return prettyString
    }

    func minifyJSON(_ jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let minifiedData = try? JSONSerialization.data(withJSONObject: jsonObject, options: []),
              let minifiedString = String(data: minifiedData, encoding: .utf8) else {
            return nil
        }

        return minifiedString
    }
}
