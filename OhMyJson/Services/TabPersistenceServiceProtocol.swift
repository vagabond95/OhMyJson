//
//  TabPersistenceServiceProtocol.swift
//  OhMyJson
//

import Foundation

protocol TabPersistenceServiceProtocol: AnyObject {
    /// Load all persisted tabs sorted by sortOrder, plus the active tab ID.
    func loadTabs() -> (tabs: [JSONTab], activeTabId: UUID?)

    /// Atomically replace the entire tab store with the provided snapshot.
    func saveAll(tabs: [JSONTab], activeTabId: UUID?)

    /// Delete a single tab by ID.
    func deleteTab(id: UUID)

    /// Delete all tabs (called when the user explicitly closes all tabs).
    func deleteAllTabs()

    /// Cancel any pending debounce and flush pending saves synchronously.
    func flush()

    /// Returns the current database file size in bytes, or nil on error.
    func databaseSize() -> Int64?

    /// Save or delete fullInputText for a tab in the separate content table.
    func saveTabContent(id: UUID, fullText: String?)

    /// Load only `inputText` and `fullInputText` for a single tab (used during hydration).
    /// Returns nil if the tab does not exist in the database.
    func loadTabContent(id: UUID) -> (inputText: String, fullInputText: String?)?
}
