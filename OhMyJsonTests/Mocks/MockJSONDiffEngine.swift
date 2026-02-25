//
//  MockJSONDiffEngine.swift
//  OhMyJsonTests
//

import Foundation
@testable import OhMyJson

final class MockJSONDiffEngine: JSONDiffEngineProtocol {
    var compareCallCount = 0
    var lastOptions: CompareOptions?
    var stubResult: CompareDiffResult?

    func compare(left: JSONValue, right: JSONValue, options: CompareOptions) -> CompareDiffResult {
        compareCallCount += 1
        lastOptions = options
        if let stub = stubResult { return stub }
        // Default: delegate to real engine
        return JSONDiffEngine.shared.compare(left: left, right: right, options: options)
    }
}
