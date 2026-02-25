//
//  JSONDiffEngineProtocol.swift
//  OhMyJson
//
//  Protocol for JSON structural comparison engine.
//

import Foundation

protocol JSONDiffEngineProtocol {
    func compare(left: JSONValue, right: JSONValue, options: CompareOptions) -> CompareDiffResult
}
