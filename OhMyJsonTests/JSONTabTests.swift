//
//  JSONTabTests.swift
//  OhMyJsonTests
//

import Testing
import Foundation
@testable import OhMyJson

@Suite("JSONTab Tests")
struct JSONTabTests {

    // MARK: - Initialization Defaults

    @Test("Default initialization values")
    func defaultInit() {
        let tab = JSONTab()
        #expect(tab.inputText == "")
        #expect(tab.parseResult == nil)
        #expect(tab.title == "")
        #expect(tab.searchText == "")
        #expect(tab.beautifySearchIndex == 0)
        #expect(tab.treeSearchIndex == 0)
        #expect(tab.viewMode == .beautify)
        #expect(tab.isSearchVisible == false)
        #expect(tab.inputScrollPosition == 0)
        #expect(tab.beautifyScrollPosition == 0)
        #expect(tab.treeSelectedNodeId == nil)
        #expect(tab.treeHorizontalScrollOffset == 0)
    }

    @Test("Custom initialization")
    func customInit() {
        let id = UUID()
        let now = Date()
        let tab = JSONTab(
            id: id,
            inputText: "{\"key\": \"value\"}",
            createdAt: now,
            lastAccessedAt: now,
            title: "Test Tab",
            viewMode: .tree,
            isSearchVisible: true
        )
        #expect(tab.id == id)
        #expect(tab.inputText == "{\"key\": \"value\"}")
        #expect(tab.title == "Test Tab")
        #expect(tab.viewMode == .tree)
        #expect(tab.isSearchVisible == true)
    }

    // MARK: - markAsAccessed

    @Test("markAsAccessed updates lastAccessedAt")
    func markAsAccessed() {
        let oldDate = Date(timeIntervalSince1970: 0)
        var tab = JSONTab(lastAccessedAt: oldDate)

        let beforeMark = Date()
        tab.markAsAccessed()

        #expect(tab.lastAccessedAt >= beforeMark)
    }

    // MARK: - isEmpty

    @Test("isEmpty returns true for empty input")
    func isEmptyTrue() {
        let tab = JSONTab(inputText: "")
        #expect(tab.isEmpty == true)
    }

    @Test("isEmpty returns false for non-empty input")
    func isEmptyFalse() {
        let tab = JSONTab(inputText: "{}")
        #expect(tab.isEmpty == false)
    }

    // MARK: - hasValidJSON

    @Test("hasValidJSON returns true for success result")
    func hasValidJSONTrue() {
        let node = JSONNode(value: .object([:]))
        let tab = JSONTab(parseResult: .success(node))
        #expect(tab.hasValidJSON == true)
    }

    @Test("hasValidJSON returns false for failure result")
    func hasValidJSONFalse() {
        let error = JSONParseError(message: "Error")
        let tab = JSONTab(parseResult: .failure(error))
        #expect(tab.hasValidJSON == false)
    }

    @Test("hasValidJSON returns false for nil result")
    func hasValidJSONNil() {
        let tab = JSONTab()
        #expect(tab.hasValidJSON == false)
    }

    // MARK: - Equatable

    @Test("Equatable is based on id only")
    func equatableById() {
        let id = UUID()
        let tab1 = JSONTab(id: id, inputText: "abc")
        let tab2 = JSONTab(id: id, inputText: "xyz")
        #expect(tab1 == tab2)
    }

    @Test("Different ids are not equal")
    func differentIds() {
        let tab1 = JSONTab(inputText: "same")
        let tab2 = JSONTab(inputText: "same")
        #expect(tab1 != tab2)
    }

    // MARK: - ViewMode

    @Test("ViewMode cases")
    func viewModeCases() {
        #expect(ViewMode.allCases.count == 2)
        #expect(ViewMode.beautify.rawValue == "Beautify")
        #expect(ViewMode.tree.rawValue == "Tree")
    }
}
