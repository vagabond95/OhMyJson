//
//  MockJSONParser.swift
//  OhMyJsonTests
//

@testable import OhMyJson

final class MockJSONParser: JSONParserProtocol {
    var parseResult: JSONParseResult = .failure(JSONParseError(message: "No mock result set"))
    var formatResult: String?
    var minifyResult: String?

    var parseCallCount = 0
    var lastParsedString: String?

    func parse(_ jsonString: String) -> JSONParseResult {
        parseCallCount += 1
        lastParsedString = jsonString
        return parseResult
    }

    func formatJSON(_ jsonString: String, indentSize: Int) -> String? {
        formatResult
    }

    func minifyJSON(_ jsonString: String) -> String? {
        minifyResult
    }
}
