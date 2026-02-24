//
//  TabPersistenceServiceTests.swift
//  OhMyJsonTests
//
//  Tests for TabPersistenceService using an in-memory GRDB database.
//

import Testing
import Foundation
import GRDB
@testable import OhMyJson

@Suite("TabPersistenceService")
struct TabPersistenceServiceTests {

    // MARK: - Helpers

    /// Creates an isolated in-memory TabPersistenceService for each test.
    private func makeService() throws -> TabPersistenceService {
        let queue = try DatabaseQueue()   // in-memory
        return TabPersistenceService(testing: queue)
    }

    private func makeTab(
        title: String = "Tab",
        inputText: String = "",
        isParseSuccess: Bool = false
    ) -> JSONTab {
        JSONTab(
            id: UUID(),
            inputText: inputText,
            createdAt: Date(),
            lastAccessedAt: Date(),
            title: title,
            isParseSuccess: isParseSuccess
        )
    }

    // MARK: - Migration

    @Test("v1 migration creates tab table")
    func testMigration() throws {
        let service = try makeService()
        // If migration ran correctly, loadTabs() returns no error
        let result = service.loadTabs()
        #expect(result.tabs.isEmpty)
        #expect(result.activeTabId == nil)
    }

    // MARK: - Round-trip

    @Test("saveAll → loadTabs round-trip preserves metadata")
    func testRoundTrip() throws {
        let service = try makeService()

        let tab1 = makeTab(title: "Tab 1", inputText: "{\"a\":1}", isParseSuccess: true)
        let tab2 = makeTab(title: "Tab 2", inputText: "")
        let activeId = tab1.id

        service.saveAll(tabs: [tab1, tab2], activeTabId: activeId)
        let (loaded, loadedActiveId) = service.loadTabs()

        #expect(loaded.count == 2)
        #expect(loadedActiveId == activeId)
        #expect(loaded[0].id == tab1.id)
        #expect(loaded[0].title == "Tab 1")
        #expect(loaded[0].inputText == "{\"a\":1}")
        #expect(loaded[0].isParseSuccess == true)
        #expect(loaded[1].id == tab2.id)
        #expect(loaded[1].isParseSuccess == false)
    }

    @Test("sortOrder is preserved after save")
    func testSortOrderPreserved() throws {
        let service = try makeService()

        let tabs = (1...5).map { i in makeTab(title: "Tab \(i)") }
        service.saveAll(tabs: tabs, activeTabId: tabs[2].id)

        let (loaded, _) = service.loadTabs()
        #expect(loaded.map(\.id) == tabs.map(\.id))
    }

    @Test("isActive flag matches activeTabId")
    func testIsActiveFlag() throws {
        let service = try makeService()

        let tab1 = makeTab(title: "A")
        let tab2 = makeTab(title: "B")
        service.saveAll(tabs: [tab1, tab2], activeTabId: tab2.id)

        let (loaded, loadedActiveId) = service.loadTabs()
        #expect(loadedActiveId == tab2.id)
        #expect(loaded.first(where: { $0.id == tab2.id }) != nil)
    }

    // MARK: - Large Text

    @Test("saves and loads large fullInputText (1MB+) via loadTabContent")
    func testLargeFullInputText() throws {
        let service = try makeService()

        let largeText = String(repeating: "x", count: 1_200_000)
        var tab = makeTab(title: "BigTab", isParseSuccess: true)
        tab.fullInputText = largeText

        service.saveAll(tabs: [tab], activeTabId: tab.id)

        // loadTabs() returns dehydrated tabs (fullInputText == nil); use loadTabContent for full text.
        let (loaded, _) = service.loadTabs()
        #expect(loaded.first?.fullInputText == nil)

        let content = service.loadTabContent(id: tab.id)
        #expect(content?.fullInputText?.count == largeText.count)
    }

    // MARK: - Delete

    @Test("deleteTab removes only the specified tab")
    func testDeleteTab() throws {
        let service = try makeService()

        let tab1 = makeTab(title: "A")
        let tab2 = makeTab(title: "B")
        service.saveAll(tabs: [tab1, tab2], activeTabId: tab1.id)

        service.deleteTab(id: tab1.id)
        let (loaded, _) = service.loadTabs()

        #expect(loaded.count == 1)
        #expect(loaded[0].id == tab2.id)
    }

    @Test("deleteAllTabs clears everything")
    func testDeleteAllTabs() throws {
        let service = try makeService()

        let tabs = (1...3).map { _ in makeTab() }
        service.saveAll(tabs: tabs, activeTabId: tabs[0].id)

        service.deleteAllTabs()
        let (loaded, loadedActiveId) = service.loadTabs()

        #expect(loaded.isEmpty)
        #expect(loadedActiveId == nil)
    }

    // MARK: - isParseSuccess filtering

    @Test("tab with isParseSuccess=false is stored with empty inputText restoration intent")
    func testIsParseSuccessFalseStoredAsIs() throws {
        let service = try makeService()

        // A tab that has unfinished/invalid JSON — isParseSuccess=false
        let tab = makeTab(title: "Draft", inputText: "{invalid", isParseSuccess: false)
        service.saveAll(tabs: [tab], activeTabId: tab.id)

        let (loaded, _) = service.loadTabs()
        #expect(loaded[0].isParseSuccess == false)
    }

    // MARK: - Multiple saves overwrite

    @Test("subsequent saveAll replaces all previous records")
    func testSaveAllReplaces() throws {
        let service = try makeService()

        let oldTabs = (1...5).map { i in makeTab(title: "Old \(i)") }
        service.saveAll(tabs: oldTabs, activeTabId: oldTabs[0].id)

        let newTabs = [makeTab(title: "New 1"), makeTab(title: "New 2")]
        service.saveAll(tabs: newTabs, activeTabId: newTabs[1].id)

        let (loaded, activeId) = service.loadTabs()
        #expect(loaded.count == 2)
        #expect(loaded[0].title == "New 1")
        #expect(activeId == newTabs[1].id)
    }

    // MARK: - loadTabContent

    @Test("loadTabContent returns correct inputText and fullInputText for a saved tab")
    func loadTabContentReturnsCorrectContent() throws {
        let service = try makeService()
        var tab = makeTab(title: "T1", inputText: "hello")
        tab.fullInputText = "full content"
        service.saveAll(tabs: [tab], activeTabId: tab.id)

        let content = service.loadTabContent(id: tab.id)

        #expect(content?.inputText == "hello")
        #expect(content?.fullInputText == "full content")
    }

    @Test("loadTabContent returns nil for a non-existent tab ID")
    func loadTabContentReturnsNilForMissingTab() throws {
        let service = try makeService()

        let content = service.loadTabContent(id: UUID())

        #expect(content == nil)
    }

    @Test("loadTabContent preserves nil fullInputText")
    func loadTabContentPreservesNilFullInputText() throws {
        let service = try makeService()
        let tab = makeTab(title: "T1", inputText: "content")
        // fullInputText not set → nil
        service.saveAll(tabs: [tab], activeTabId: tab.id)

        let content = service.loadTabContent(id: tab.id)

        #expect(content?.inputText == "content")
        #expect(content?.fullInputText == nil)
    }

    // MARK: - databaseSize

    @Test("databaseSize does not throw for in-memory database")
    func testDatabaseSizeInMemory() throws {
        let service = try makeService()
        // databaseSize() reads from the disk path regardless of in-memory mode.
        // It may return nil (no file) or a file size if one exists on disk.
        // The important thing is it doesn't throw.
        let _ = service.databaseSize()
    }
}
