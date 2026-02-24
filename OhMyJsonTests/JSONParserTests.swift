//
//  JSONParserTests.swift
//  OhMyJsonTests
//

import Testing
@testable import OhMyJson

@Suite("JSONParser Tests")
struct JSONParserTests {

    let parser = JSONParser.shared

    // MARK: - Basic Parsing

    @Test("Parse simple object")
    func parseSimpleObject() {
        let json = #"{"name": "test", "value": 42}"#
        let result = parser.parse(json)
        guard case .success(let node) = result else {
            Issue.record("Expected success but got failure")
            return
        }
        #expect(node.children.count == 2)
    }

    @Test("Parse simple array")
    func parseSimpleArray() {
        let json = "[1, 2, 3]"
        let result = parser.parse(json)
        guard case .success(let node) = result else {
            Issue.record("Expected success but got failure")
            return
        }
        #expect(node.children.count == 3)
    }

    @Test("Parse nested object")
    func parseNestedObject() {
        let json = #"{"outer": {"inner": "value"}}"#
        let result = parser.parse(json)
        guard case .success(let node) = result else {
            Issue.record("Expected success but got failure")
            return
        }
        #expect(node.children.count == 1)
        let outerChild = node.children[0]
        #expect(outerChild.key == "outer")
        #expect(outerChild.children.count == 1)
    }

    @Test("Parse all JSON value types")
    func parseAllValueTypes() {
        let json = #"{"str": "hello", "num": 3.14, "bool": true, "nil": null, "arr": [1], "obj": {}}"#
        let result = parser.parse(json)
        guard case .success(let node) = result else {
            Issue.record("Expected success but got failure")
            return
        }
        #expect(node.children.count == 6)
    }

    @Test("Parse fragment - bare string")
    func parseFragmentString() {
        let json = #""hello world""#
        let result = parser.parse(json)
        guard case .success(let node) = result else {
            Issue.record("Expected success for fragment")
            return
        }
        if case .string(let s) = node.value {
            #expect(s == "hello world")
        } else {
            Issue.record("Expected string value")
        }
    }

    @Test("Parse fragment - bare number")
    func parseFragmentNumber() {
        let json = "42"
        let result = parser.parse(json)
        guard case .success(let node) = result else {
            Issue.record("Expected success for fragment")
            return
        }
        if case .number(let n) = node.value {
            #expect(n == 42.0)
        } else {
            Issue.record("Expected number value")
        }
    }

    @Test("Parse boolean values")
    func parseBooleans() {
        let jsonTrue = "true"
        let jsonFalse = "false"

        if case .success(let nodeTrue) = parser.parse(jsonTrue),
           case .bool(let bTrue) = nodeTrue.value {
            #expect(bTrue == true)
        } else {
            Issue.record("Expected true")
        }

        if case .success(let nodeFalse) = parser.parse(jsonFalse),
           case .bool(let bFalse) = nodeFalse.value {
            #expect(bFalse == false)
        } else {
            Issue.record("Expected false")
        }
    }

    @Test("Parse null")
    func parseNull() {
        let json = "null"
        if case .success(let node) = parser.parse(json) {
            #expect(node.value == .null)
        } else {
            Issue.record("Expected success for null")
        }
    }

    // MARK: - Error Handling

    @Test("Empty input returns failure with emptyInput category")
    func emptyInput() {
        let result = parser.parse("")
        guard case .failure(let error) = result else {
            Issue.record("Expected failure for empty input")
            return
        }
        #expect(error.message == "")
        #expect(error.category == .emptyInput)
    }

    @Test("Whitespace-only input returns failure with emptyInput category")
    func whitespaceOnlyInput() {
        let result = parser.parse("   \n\t  ")
        guard case .failure(let error) = result else {
            Issue.record("Expected failure for whitespace-only input")
            return
        }
        #expect(error.message == "")
        #expect(error.category == .emptyInput)
    }

    @Test("Invalid JSON returns failure with syntaxError category")
    func invalidJSON() {
        let json = #"{"key": value}"#
        let result = parser.parse(json)
        guard case .failure(let error) = result else {
            Issue.record("Expected failure for invalid JSON")
            return
        }
        #expect(!error.message.isEmpty)
        #expect(error.category == .syntaxError)
    }

    @Test("Syntax error has specific message without position info")
    func syntaxErrorMessage() {
        let json = #"{"key": }"#
        let result = parser.parse(json)
        guard case .failure(let error) = result else {
            Issue.record("Expected failure")
            return
        }
        #expect(error.category == .syntaxError)
        // Message should not contain "around line/column" (stripped by extractMessage)
        #expect(!error.message.lowercased().contains("around line"))
        #expect(!error.message.lowercased().contains("around character"))
    }

    @Test("Category localizedHeader returns non-empty strings")
    func categoryHeaders() {
        let categories: [JSONParseError.Category] = [
            .emptyInput, .encodingError, .syntaxError, .parsingError, .unknownError
        ]
        for cat in categories {
            #expect(!cat.localizedHeader.isEmpty)
            #expect(!cat.iconName.isEmpty)
        }
    }

    @Test("Default category is unknownError")
    func defaultCategory() {
        let error = JSONParseError(message: "test")
        #expect(error.category == .unknownError)
    }

    // MARK: - Unicode Sanitization

    @Test("Smart/curly quotes are sanitized")
    func sanitizeSmartQuotes() {
        // Left/right double quotes → straight quotes
        let json = "{\u{201C}name\u{201D}: \u{201C}value\u{201D}}"
        let result = parser.parse(json)
        guard case .success(let node) = result else {
            Issue.record("Expected success after smart quote sanitization")
            return
        }
        #expect(node.children.count == 1)
    }

    @Test("BOM is removed")
    func sanitizeBOM() {
        let json = "\u{FEFF}{\"key\": \"value\"}"
        let result = parser.parse(json)
        guard case .success = result else {
            Issue.record("Expected success after BOM removal")
            return
        }
    }

    @Test("Zero-width characters are removed")
    func sanitizeZeroWidth() {
        let json = "{\"key\": \"val\u{200B}ue\"}"
        let result = parser.parse(json)
        guard case .success(let node) = result else {
            Issue.record("Expected success after zero-width removal")
            return
        }
        // The zero-width space should be stripped from inside the value
        if let child = node.children.first, case .string(let s) = child.value {
            #expect(s == "value")
        }
    }

    @Test("Non-breaking spaces are replaced")
    func sanitizeNBSP() {
        // \u{00A0} (NBSP) in whitespace should be handled
        let json = "{\u{00A0}\"key\":\u{00A0}\"value\"}"
        let result = parser.parse(json)
        guard case .success = result else {
            Issue.record("Expected success after NBSP sanitization")
            return
        }
    }

    @Test("Unicode line separators are replaced")
    func sanitizeLineSeparators() {
        let json = "{\"key\": \"value\"}\u{2028}"
        let result = parser.parse(json)
        guard case .success = result else {
            Issue.record("Expected success after line separator sanitization")
            return
        }
    }

    @Test("Smart quotes inside straight-quote string are preserved as value characters")
    func smartQuotesInsideStraightQuoteStringPreserved() {
        // Value contains smart quotes but structure uses straight quotes (U+201C/201D)
        let json = "{\"text\": \"\u{201C}hello\u{201D}\"}"
        let result = parser.parse(json)
        guard case .success(let node) = result else {
            Issue.record("Expected success: smart quotes inside straight-quote string should be preserved")
            return
        }
        if let child = node.children.first, case .string(let s) = child.value {
            #expect(s == "\u{201C}hello\u{201D}")
        } else {
            Issue.record("Expected string child with smart quote value")
        }
    }

    @Test("All-smart-quote JSON (rich text paste) is correctly sanitized")
    func allSmartQuoteJSONSanitized() {
        // All structural quotes are smart quotes (e.g. copy-pasted from a web page)
        let json = "{\u{201C}key\u{201D}: \u{201C}value\u{201D}}"
        let result = parser.parse(json)
        guard case .success(let node) = result else {
            Issue.record("Expected success after structural smart quote sanitization")
            return
        }
        if let child = node.children.first {
            #expect(child.key == "key")
            if case .string(let s) = child.value {
                #expect(s == "value")
            } else {
                Issue.record("Expected string value")
            }
        } else {
            Issue.record("Expected at least one child node")
        }
    }

    @Test("Straight-quote key with smart-quote value is sanitized")
    func straightKeySmartValueSanitized() {
        // Key uses straight quotes, value uses smart quotes
        let json = "{\"key\": \u{201C}value\u{201D}}"
        let result = parser.parse(json)
        guard case .success(let node) = result else {
            Issue.record("Expected success after sanitizing smart-quote value")
            return
        }
        if let child = node.children.first, case .string(let s) = child.value {
            #expect(s == "value")
        } else {
            Issue.record("Expected string child with value")
        }
    }

    // MARK: - Formatting

    @Test("formatJSON produces pretty-printed output")
    func formatJSON() {
        let json = #"{"a":1,"b":2}"#
        let formatted = parser.formatJSON(json, indentSize: 4)
        #expect(formatted != nil)
        #expect(formatted!.contains("\n"))
    }

    @Test("formatJSON with custom indent size")
    func formatJSONCustomIndent() {
        let json = #"{"a":{"b":1}}"#
        let formatted2 = parser.formatJSON(json, indentSize: 2)
        let formatted4 = parser.formatJSON(json, indentSize: 4)
        #expect(formatted2 != nil)
        #expect(formatted4 != nil)
        // 4-space indent should be wider
        if let f2 = formatted2, let f4 = formatted4 {
            let f2Lines = f2.components(separatedBy: "\n")
            let f4Lines = f4.components(separatedBy: "\n")
            // Both should have the same number of lines
            #expect(f2Lines.count == f4Lines.count)
        }
    }

    @Test("formatJSON collapses empty arrays and objects")
    func formatJSONCollapsesEmpty() {
        let json = #"{"arr":[],"obj":{}}"#
        let formatted = parser.formatJSON(json, indentSize: 4)
        #expect(formatted != nil)
        #expect(formatted!.contains("[]"))
        #expect(formatted!.contains("{}"))
    }

    @Test("formatJSON returns nil for invalid JSON")
    func formatJSONInvalid() {
        let formatted = parser.formatJSON("not json")
        #expect(formatted == nil)
    }

    // MARK: - Minification

    @Test("minifyJSON removes whitespace")
    func minifyJSON() {
        let json = """
        {
            "key": "value",
            "number": 42
        }
        """
        let minified = parser.minifyJSON(json)
        #expect(minified != nil)
        #expect(!minified!.contains("\n"))
        #expect(!minified!.contains("    "))
    }

    @Test("minifyJSON returns nil for invalid JSON")
    func minifyJSONInvalid() {
        let minified = parser.minifyJSON("not json")
        #expect(minified == nil)
    }

    @Test("minifyJSON roundtrip preserves data")
    func minifyRoundtrip() {
        let json = #"{"a":1,"b":"hello","c":true,"d":null}"#
        let minified = parser.minifyJSON(json)
        #expect(minified != nil)
        // Parse both and compare structure
        if case .success(let original) = parser.parse(json),
           case .success(let roundtripped) = parser.parse(minified!) {
            #expect(original.children.count == roundtripped.children.count)
        }
    }

    // MARK: - Number Precision Preservation

    @Test("formatJSON preserves decimal precision")
    func formatJSONPreservesDecimalPrecision() {
        let json = #"{"version":4.6}"#
        let formatted = parser.formatJSON(json)
        #expect(formatted != nil)
        #expect(formatted!.contains("4.6"))
        #expect(!formatted!.contains("4.5999999999999996"))
    }

    @Test("formatJSON preserves negative decimal")
    func formatJSONPreservesNegativeDecimal() {
        let json = #"{"value":-4.6}"#
        let formatted = parser.formatJSON(json)
        #expect(formatted != nil)
        #expect(formatted!.contains("-4.6"))
        #expect(!formatted!.contains("-4.5999999999999996"))
    }

    @Test("formatJSON preserves multiple precision numbers")
    func formatJSONPreservesMultiplePrecisionNumbers() {
        let json = #"{"a":4.6,"b":0.1,"c":0.3}"#
        let formatted = parser.formatJSON(json)
        #expect(formatted != nil)
        #expect(formatted!.contains("4.6"))
        #expect(formatted!.contains("0.1"))
        #expect(formatted!.contains("0.3"))
    }

    @Test("formatJSON does not modify string numbers")
    func formatJSONDoesNotModifyStringNumbers() {
        let json = #"{"value":"4.6","other":"not a number 4.6"}"#
        let formatted = parser.formatJSON(json)
        #expect(formatted != nil)
        #expect(formatted!.contains("\"4.6\""))
        #expect(formatted!.contains("\"not a number 4.6\""))
    }

    @Test("formatJSON preserves integers")
    func formatJSONPreservesIntegers() {
        let json = #"{"a":1,"b":42,"c":0,"d":-7}"#
        let formatted = parser.formatJSON(json)
        #expect(formatted != nil)
        #expect(formatted!.contains(": 1"))
        #expect(formatted!.contains(": 42"))
        #expect(formatted!.contains(": 0"))
        #expect(formatted!.contains(": -7"))
    }

    @Test("formatJSON handles duplicate values")
    func formatJSONHandlesDuplicateValues() {
        let json = #"{"a":4.6,"b":4.6,"c":4.6}"#
        let formatted = parser.formatJSON(json)
        #expect(formatted != nil)
        // Count occurrences of "4.6" — should be exactly 3 (one per key)
        let occurrences = formatted!.components(separatedBy: "4.6").count - 1
        #expect(occurrences == 3)
        #expect(!formatted!.contains("4.5999999999999996"))
    }

    @Test("formatJSON preserves array numbers")
    func formatJSONPreservesArrayNumbers() {
        let json = #"{"values":[4.6,0.1,0.3,100]}"#
        let formatted = parser.formatJSON(json)
        #expect(formatted != nil)
        #expect(formatted!.contains("4.6"))
        #expect(formatted!.contains("0.1"))
        #expect(formatted!.contains("0.3"))
        #expect(formatted!.contains("100"))
    }

    @Test("formatJSON handles escaped quotes in strings")
    func formatJSONHandlesEscapedQuotes() {
        let json = #"{"msg":"value is \"4.6\" here","num":4.6}"#
        let formatted = parser.formatJSON(json)
        #expect(formatted != nil)
        // The number outside the string should be preserved
        #expect(!formatted!.contains("4.5999999999999996"))
    }

    @Test("minifyJSON preserves decimal precision")
    func minifyJSONPreservesDecimalPrecision() {
        let json = #"{ "version" : 4.6 }"#
        let minified = parser.minifyJSON(json)
        #expect(minified != nil)
        #expect(minified!.contains("4.6"))
        #expect(!minified!.contains("4.5999999999999996"))
    }

    // MARK: - stripControlCharacters

    @Test("stripControlCharacters replaces control chars with space")
    func stripControlCharactersBasic() {
        #expect(JSONParser.stripControlCharacters("hello\nworld") == "hello world")
        #expect(JSONParser.stripControlCharacters("hello\tworld") == "hello world")
        #expect(JSONParser.stripControlCharacters("hello\rworld") == "hello world")
        #expect(JSONParser.stripControlCharacters("hello\u{0C}world") == "hello world")
        #expect(JSONParser.stripControlCharacters("hello\u{08}world") == "hello world")
    }

    @Test("stripControlCharacters collapses consecutive spaces")
    func stripControlCharactersCollapse() {
        #expect(JSONParser.stripControlCharacters("a\n\n\nb") == "a b")
        #expect(JSONParser.stripControlCharacters("a\n \t\rb") == "a b")
        #expect(JSONParser.stripControlCharacters("a   b") == "a b")
    }

    @Test("stripControlCharacters preserves backslashes")
    func stripControlCharactersBackslash() {
        #expect(JSONParser.stripControlCharacters("path\\to\\file") == "path\\to\\file")
    }

    @Test("stripControlCharacters returns same string when no control chars")
    func stripControlCharactersNoOp() {
        #expect(JSONParser.stripControlCharacters("hello world") == "hello world")
        #expect(JSONParser.stripControlCharacters("") == "")
    }

    // MARK: - stripEscapeSequencesInJSONString

    @Test("stripEscapeSequencesInJSONString replaces literal escape sequences")
    func stripEscapeSequencesBasic() {
        #expect(JSONParser.stripEscapeSequencesInJSONString("hello\\nworld") == "hello world")
        #expect(JSONParser.stripEscapeSequencesInJSONString("hello\\tworld") == "hello world")
        #expect(JSONParser.stripEscapeSequencesInJSONString("hello\\rworld") == "hello world")
        #expect(JSONParser.stripEscapeSequencesInJSONString("hello\\fworld") == "hello world")
        #expect(JSONParser.stripEscapeSequencesInJSONString("hello\\bworld") == "hello world")
    }

    @Test("stripEscapeSequencesInJSONString collapses consecutive")
    func stripEscapeSequencesCollapse() {
        #expect(JSONParser.stripEscapeSequencesInJSONString("a\\n\\n\\nb") == "a b")
        #expect(JSONParser.stripEscapeSequencesInJSONString("a\\n \\t\\rb") == "a b")
    }

    @Test("stripEscapeSequencesInJSONString preserves escaped backslash")
    func stripEscapeSequencesPreservesBackslash() {
        #expect(JSONParser.stripEscapeSequencesInJSONString("path\\\\to\\\\file") == "path\\\\to\\\\file")
    }

    @Test("stripEscapeSequencesInJSONString preserves escaped quote")
    func stripEscapeSequencesPreservesQuote() {
        #expect(JSONParser.stripEscapeSequencesInJSONString("say \\\"hello\\\"") == "say \\\"hello\\\"")
    }

    @Test("stripEscapeSequencesInJSONString preserves unicode escapes")
    func stripEscapeSequencesPreservesUnicode() {
        #expect(JSONParser.stripEscapeSequencesInJSONString("\\u0041BC") == "\\u0041BC")
    }

    @Test("minifyJSON preserves precision in complex case")
    func minifyJSONPreservesPrecisionComplex() {
        let json = #"{"name":"Claude","version":4.6,"scores":[0.1,0.3],"nested":{"val":-4.6}}"#
        let minified = parser.minifyJSON(json)
        #expect(minified != nil)
        #expect(minified!.contains("4.6"))
        #expect(minified!.contains("0.1"))
        #expect(minified!.contains("0.3"))
        #expect(minified!.contains("-4.6"))
        #expect(!minified!.contains("4.5999999999999996"))
    }

    // MARK: - Forward Slash Unescape

    @Test("formatJSON unescapes forward slashes")
    func formatJSONUnescapesForwardSlashes() {
        let json = #"{"url":"https://example.com/path"}"#
        let formatted = parser.formatJSON(json)
        #expect(formatted != nil)
        #expect(formatted!.contains("https://example.com/path"))
        #expect(!formatted!.contains("\\/"))
    }

    @Test("minifyJSON unescapes forward slashes")
    func minifyJSONUnescapesForwardSlashes() {
        let json = #"{ "url" : "https://example.com/path" }"#
        let minified = parser.minifyJSON(json)
        #expect(minified != nil)
        #expect(minified!.contains("https://example.com/path"))
        #expect(!minified!.contains("\\/"))
    }
}
