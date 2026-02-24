//
//  MockTabPersistenceService.swift
//  OhMyJsonTests
//

import Foundation
@testable import OhMyJson

final class MockTabPersistenceService: TabPersistenceServiceProtocol {
    var savedTabs: [JSONTab] = []
    var savedActiveId: UUID?

    var saveAllCallCount = 0
    var deleteTabCallCount = 0
    var deleteAllTabsCallCount = 0
    var flushCallCount = 0
    var loadTabsCallCount = 0

    func loadTabs() -> (tabs: [JSONTab], activeTabId: UUID?) {
        loadTabsCallCount += 1
        return (savedTabs, savedActiveId)
    }

    func saveAll(tabs: [JSONTab], activeTabId: UUID?) {
        savedTabs = tabs
        savedActiveId = activeTabId
        saveAllCallCount += 1
    }

    func deleteTab(id: UUID) {
        deleteTabCallCount += 1
        savedTabs.removeAll { $0.id == id }
        if savedActiveId == id { savedActiveId = nil }
    }

    func deleteAllTabs() {
        deleteAllTabsCallCount += 1
        savedTabs = []
        savedActiveId = nil
    }

    func flush() {
        flushCallCount += 1
    }

    func databaseSize() -> Int64? {
        return nil
    }

    func loadTabContent(id: UUID) -> (inputText: String, fullInputText: String?)? {
        return savedTabs.first(where: { $0.id == id }).map { ($0.inputText, $0.fullInputText) }
    }
}
