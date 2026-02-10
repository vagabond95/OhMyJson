//
//  JSONParserProtocol.swift
//  OhMyJson
//

import Foundation

protocol JSONParserProtocol {
    func parse(_ jsonString: String) -> JSONParseResult
    func formatJSON(_ jsonString: String, indentSize: Int) -> String?
    func minifyJSON(_ jsonString: String) -> String?
}
