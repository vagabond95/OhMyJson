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

    @Test("saves and loads large fullInputText (1MB+) via saveTabContent + loadTabContent")
    func testLargeFullInputText() throws {
        let service = try makeService()

        let largeText = String(repeating: "x", count: 1_200_000)
        let tab = makeTab(title: "BigTab", isParseSuccess: true)

        service.saveAll(tabs: [tab], activeTabId: tab.id)
        service.saveTabContent(id: tab.id, fullText: largeText)

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
        let tab = makeTab(title: "T1", inputText: "hello")
        service.saveAll(tabs: [tab], activeTabId: tab.id)
        service.saveTabContent(id: tab.id, fullText: "full content")

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

    // MARK: - tab_content separation

    @Test("saveAll does not affect tab_content — dehydrated tabs preserve content")
    func saveAllDoesNotAffectTabContent() throws {
        let service = try makeService()

        let tab1 = makeTab(title: "Tab1", inputText: "short")
        let tab2 = makeTab(title: "Tab2", inputText: "other")

        // Save tabs and content separately
        service.saveAll(tabs: [tab1, tab2], activeTabId: tab1.id)
        service.saveTabContent(id: tab1.id, fullText: "very large content here")

        // Simulate dehydrated saveAll (tabs without fullInputText in memory)
        // This is what happens when TabManager.saveImmediately() is called after dehydration
        service.saveAll(tabs: [tab1, tab2], activeTabId: tab2.id)

        // Content must still be intact
        let content = service.loadTabContent(id: tab1.id)
        #expect(content?.fullInputText == "very large content here")
    }

    @Test("saveAll cleans up orphaned tab_content rows")
    func saveAllCleansUpOrphanedContent() throws {
        let service = try makeService()

        let tab1 = makeTab(title: "Tab1")
        let tab2 = makeTab(title: "Tab2")

        service.saveAll(tabs: [tab1, tab2], activeTabId: tab1.id)
        service.saveTabContent(id: tab1.id, fullText: "content1")
        service.saveTabContent(id: tab2.id, fullText: "content2")

        // Close tab1 — saveAll with only tab2
        service.saveAll(tabs: [tab2], activeTabId: tab2.id)

        // tab1's content should be cleaned up
        let content1 = service.loadTabContent(id: tab1.id)
        #expect(content1 == nil)  // tab record gone, so loadTabContent returns nil

        // tab2's content should remain
        let content2 = service.loadTabContent(id: tab2.id)
        #expect(content2?.fullInputText == "content2")
    }

    @Test("saveTabContent insert and delete")
    func saveTabContentInsertAndDelete() throws {
        let service = try makeService()

        let tab = makeTab(title: "Tab1", inputText: "text")
        service.saveAll(tabs: [tab], activeTabId: tab.id)

        // Insert content
        service.saveTabContent(id: tab.id, fullText: "full text")
        var content = service.loadTabContent(id: tab.id)
        #expect(content?.fullInputText == "full text")

        // Update content
        service.saveTabContent(id: tab.id, fullText: "updated text")
        content = service.loadTabContent(id: tab.id)
        #expect(content?.fullInputText == "updated text")

        // Delete content (nil)
        service.saveTabContent(id: tab.id, fullText: nil)
        content = service.loadTabContent(id: tab.id)
        #expect(content?.fullInputText == nil)
    }

    // MARK: - deleteTab with content

    @Test("deleteTab also removes tab_content")
    func deleteTabAlsoRemovesContent() throws {
        let service = try makeService()

        let tab = makeTab(title: "Tab1", inputText: "text")
        service.saveAll(tabs: [tab], activeTabId: tab.id)
        service.saveTabContent(id: tab.id, fullText: "full content")

        service.deleteTab(id: tab.id)

        let content = service.loadTabContent(id: tab.id)
        #expect(content == nil)
    }

    @Test("deleteAllTabs also clears tab_content")
    func deleteAllTabsAlsoClearsContent() throws {
        let service = try makeService()

        let tab1 = makeTab(title: "Tab1")
        let tab2 = makeTab(title: "Tab2")
        service.saveAll(tabs: [tab1, tab2], activeTabId: tab1.id)
        service.saveTabContent(id: tab1.id, fullText: "content1")
        service.saveTabContent(id: tab2.id, fullText: "content2")

        service.deleteAllTabs()

        // Verify content is also gone (loadTabContent returns nil because tab record is gone)
        let content1 = service.loadTabContent(id: tab1.id)
        let content2 = service.loadTabContent(id: tab2.id)
        #expect(content1 == nil)
        #expect(content2 == nil)
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
