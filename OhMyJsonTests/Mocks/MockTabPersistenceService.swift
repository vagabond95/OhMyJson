//
//  MockTabPersistenceService.swift
//  OhMyJsonTests
//

import Foundation
@testable import OhMyJson

final class MockTabPersistenceService: TabPersistenceServiceProtocol {
    var savedTabs: [JSONTab] = []
    var savedActiveId: UUID?
    var savedContent: [UUID: String] = [:]

    var saveAllCallCount = 0
    var deleteTabCallCount = 0
    var deleteAllTabsCallCount = 0
    var flushCallCount = 0
    var loadTabsCallCount = 0
    var saveTabContentCallCount = 0
    var saveAllWithContentCallCount = 0

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
        savedContent.removeValue(forKey: id)
        if savedActiveId == id { savedActiveId = nil }
    }

    func deleteAllTabs() {
        deleteAllTabsCallCount += 1
        savedTabs = []
        savedContent = [:]
        savedActiveId = nil
    }

    func flush() {
        flushCallCount += 1
    }

    func databaseSize() -> Int64? {
        return nil
    }

    func saveTabContent(id: UUID, fullText: String?) {
        saveTabContentCallCount += 1
        if let text = fullText {
            savedContent[id] = text
        } else {
            savedContent.removeValue(forKey: id)
        }
    }

    func saveAllWithContent(tabs: [JSONTab], activeTabId: UUID?, contentId: UUID, fullText: String?) {
        saveAllWithContentCallCount += 1
        // saveAll logic
        savedTabs = tabs
        savedActiveId = activeTabId
        // saveTabContent logic
        if let text = fullText {
            savedContent[contentId] = text
        } else {
            savedContent.removeValue(forKey: contentId)
        }
    }

    func loadTabContent(id: UUID) -> (inputText: String, fullInputText: String?)? {
        guard let tab = savedTabs.first(where: { $0.id == id }) else { return nil }
        return (tab.inputText, savedContent[id])
    }
}
