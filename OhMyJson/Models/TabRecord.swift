//
//  TabRecord.swift
//  OhMyJson
//
//  GRDB-backed persistent record for a tab session.
//

import Foundation
import GRDB

struct TabRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "tab"

    var id: String
    var sortOrder: Int
    var inputText: String
    var fullInputText: String?
    var title: String
    var customTitle: String?
    var viewMode: String
    var searchText: String
    var beautifySearchIndex: Int
    var treeSearchIndex: Int
    var isSearchVisible: Bool
    var inputScrollPosition: Double
    var beautifyScrollPosition: Double
    var treeHorizontalScrollOffset: Double
    var beautifySearchDismissed: Bool
    var treeSearchDismissed: Bool
    var createdAt: Double
    var lastAccessedAt: Double
    var isActive: Bool
    var isParseSuccess: Bool
}
