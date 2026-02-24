//
//  TabPersistenceService.swift
//  OhMyJson
//
//  GRDB-backed SQLite persistence for tab sessions.
//  Uses WAL mode for safe concurrent reads and DatabaseMigrator for schema evolution.
//

import Foundation
import GRDB

final class TabPersistenceService: TabPersistenceServiceProtocol {

    // MARK: - Singleton

    static let shared = TabPersistenceService()

    // MARK: - Private

    private var db: DatabaseQueue?

    private init() {
        db = makeDatabase()
    }

    /// Internal initializer for testing with a pre-created DatabaseQueue (e.g. in-memory).
    init(testing databaseQueue: DatabaseQueue) {
        do {
            try migrate(databaseQueue)
            self.db = databaseQueue
        } catch {
            print("[TabPersistenceService] Test init migration failed: \(error)")
            self.db = nil
        }
    }

    // MARK: - Database Setup

    private func makeDatabase() -> DatabaseQueue? {
        do {
            let url = try databaseURL()
            var config = Configuration()
            config.journalMode = .wal
            let queue = try DatabaseQueue(path: url.path, configuration: config)
            try migrate(queue)
            return queue
        } catch {
            print("[TabPersistenceService] Failed to open DB: \(error). Attempting silent reset.")
            return silentReset()
        }
    }

    private func silentReset() -> DatabaseQueue? {
        guard let url = try? databaseURL() else { return nil }
        try? FileManager.default.removeItem(at: url)
        // Also remove WAL/SHM sidecar files
        let walURL = URL(fileURLWithPath: url.path + "-wal")
        let shmURL = URL(fileURLWithPath: url.path + "-shm")
        try? FileManager.default.removeItem(at: walURL)
        try? FileManager.default.removeItem(at: shmURL)
        do {
            var config = Configuration()
            config.journalMode = .wal
            let queue = try DatabaseQueue(path: url.path, configuration: config)
            try migrate(queue)
            print("[TabPersistenceService] Silent reset succeeded.")
            return queue
        } catch {
            print("[TabPersistenceService] Silent reset failed: \(error)")
            return nil
        }
    }

    private func databaseURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent(Persistence.directoryName)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(Persistence.databaseFileName)
    }

    private func migrate(_ queue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "tab", ifNotExists: true) { t in
                t.column("id", .text).primaryKey().notNull()
                t.column("sortOrder", .integer).notNull()
                t.column("inputText", .text).notNull().defaults(to: "")
                t.column("fullInputText", .text)
                t.column("title", .text).notNull().defaults(to: "")
                t.column("customTitle", .text)
                t.column("viewMode", .text).notNull().defaults(to: "Beautify")
                t.column("searchText", .text).notNull().defaults(to: "")
                t.column("beautifySearchIndex", .integer).notNull().defaults(to: 0)
                t.column("treeSearchIndex", .integer).notNull().defaults(to: 0)
                t.column("isSearchVisible", .integer).notNull().defaults(to: false)
                t.column("inputScrollPosition", .double).notNull().defaults(to: 0)
                t.column("beautifyScrollPosition", .double).notNull().defaults(to: 0)
                t.column("treeHorizontalScrollOffset", .double).notNull().defaults(to: 0)
                t.column("beautifySearchDismissed", .integer).notNull().defaults(to: false)
                t.column("treeSearchDismissed", .integer).notNull().defaults(to: false)
                t.column("createdAt", .double).notNull()
                t.column("lastAccessedAt", .double).notNull()
                t.column("isActive", .integer).notNull().defaults(to: false)
                t.column("isParseSuccess", .integer).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("v2-separate-content") { db in
            try db.create(table: "tab_content") { t in
                t.column("id", .text).primaryKey().notNull()
                t.column("fullInputText", .text).notNull()
            }
            // Migrate existing data
            try db.execute(sql: """
                INSERT INTO tab_content (id, fullInputText)
                SELECT id, fullInputText FROM tab WHERE fullInputText IS NOT NULL
            """)
            // Drop column from tab table (SQLite 3.35+, macOS 14+)
            try db.execute(sql: "ALTER TABLE tab DROP COLUMN fullInputText")
        }

        try migrator.migrate(queue)
    }

    // MARK: - TabPersistenceServiceProtocol

    func loadTabs() -> (tabs: [JSONTab], activeTabId: UUID?) {
        guard let db else { return ([], nil) }
        do {
            let records = try db.read { db in
                try TabRecord.order(Column("sortOrder")).fetchAll(db)
            }
            var activeId: UUID?
            let tabs = records.map { record -> JSONTab in
                if record.isActive {
                    activeId = UUID(uuidString: record.id)
                }
                return JSONTab(from: record)
            }
            return (tabs, activeId)
        } catch {
            print("[TabPersistenceService] loadTabs error: \(error)")
            return ([], nil)
        }
    }

    func saveAll(tabs: [JSONTab], activeTabId: UUID?) {
        guard let db else { return }
        do {
            _ = try db.write { db in
                try TabRecord.deleteAll(db)
                for (index, tab) in tabs.enumerated() {
                    let record = TabRecord(
                        from: tab,
                        sortOrder: index,
                        isActive: tab.id == activeTabId
                    )
                    try record.insert(db)
                }
                // Clean up orphaned tab_content rows (closed tabs)
                let liveIds = tabs.map { $0.id.uuidString }
                if liveIds.isEmpty {
                    try db.execute(sql: "DELETE FROM tab_content")
                } else {
                    let placeholders = liveIds.map { _ in "?" }.joined(separator: ",")
                    try db.execute(
                        sql: "DELETE FROM tab_content WHERE id NOT IN (\(placeholders))",
                        arguments: StatementArguments(liveIds)
                    )
                }
            }
        } catch {
            print("[TabPersistenceService] saveAll error: \(error)")
        }
    }

    func deleteTab(id: UUID) {
        guard let db else { return }
        do {
            _ = try db.write { db in
                try db.execute(sql: "DELETE FROM tab WHERE id = ?", arguments: [id.uuidString])
                try db.execute(sql: "DELETE FROM tab_content WHERE id = ?", arguments: [id.uuidString])
            }
        } catch {
            print("[TabPersistenceService] deleteTab error: \(error)")
        }
    }

    func deleteAllTabs() {
        guard let db else { return }
        do {
            _ = try db.write { db in
                try TabRecord.deleteAll(db)
                try db.execute(sql: "DELETE FROM tab_content")
            }
        } catch {
            print("[TabPersistenceService] deleteAllTabs error: \(error)")
        }
    }

    func flush() {
        // No pending debounce in this service — debouncing is managed in TabManager.
        // flush() is a no-op here; TabManager calls saveAll() directly after cancelling its debounce.
    }

    func databaseSize() -> Int64? {
        guard let url = try? databaseURL() else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.size] as? Int64
    }

    func saveAllWithContent(tabs: [JSONTab], activeTabId: UUID?, contentId: UUID, fullText: String?) {
        guard let db else { return }
        do {
            _ = try db.write { db in
                // 1. Save all tabs (same logic as saveAll)
                try TabRecord.deleteAll(db)
                for (index, tab) in tabs.enumerated() {
                    let record = TabRecord(
                        from: tab,
                        sortOrder: index,
                        isActive: tab.id == activeTabId
                    )
                    try record.insert(db)
                }
                // Clean up orphaned tab_content rows
                let liveIds = tabs.map { $0.id.uuidString }
                if liveIds.isEmpty {
                    try db.execute(sql: "DELETE FROM tab_content")
                } else {
                    let placeholders = liveIds.map { _ in "?" }.joined(separator: ",")
                    try db.execute(
                        sql: "DELETE FROM tab_content WHERE id NOT IN (\(placeholders))",
                        arguments: StatementArguments(liveIds)
                    )
                }

                // 2. Save tab_content atomically within the same transaction
                if let text = fullText {
                    try db.execute(
                        sql: "INSERT OR REPLACE INTO tab_content (id, fullInputText) VALUES (?, ?)",
                        arguments: [contentId.uuidString, text]
                    )
                } else {
                    try db.execute(
                        sql: "DELETE FROM tab_content WHERE id = ?",
                        arguments: [contentId.uuidString]
                    )
                }
            }
        } catch {
            print("[TabPersistenceService] saveAllWithContent error: \(error)")
        }
    }

    func saveTabContent(id: UUID, fullText: String?) {
        guard let db else { return }
        do {
            _ = try db.write { db in
                if let text = fullText {
                    try db.execute(
                        sql: "INSERT OR REPLACE INTO tab_content (id, fullInputText) VALUES (?, ?)",
                        arguments: [id.uuidString, text]
                    )
                } else {
                    try db.execute(
                        sql: "DELETE FROM tab_content WHERE id = ?",
                        arguments: [id.uuidString]
                    )
                }
            }
        } catch {
            print("[TabPersistenceService] saveTabContent error: \(error)")
        }
    }

    func loadTabContent(id: UUID) -> (inputText: String, fullInputText: String?)? {
        guard let db else { return nil }
        do {
            return try db.read { db in
                guard let record = try TabRecord
                    .filter(Column("id") == id.uuidString)
                    .fetchOne(db) else { return nil }
                let fullText = try String.fetchOne(db,
                    sql: "SELECT fullInputText FROM tab_content WHERE id = ?",
                    arguments: [id.uuidString])
                return (record.inputText, fullText)
            }
        } catch {
            print("[TabPersistenceService] loadTabContent error: \(error)")
            return nil
        }
    }
}
