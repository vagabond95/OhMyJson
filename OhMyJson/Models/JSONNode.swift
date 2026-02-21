//
//  JSONNode.swift
//  OhMyJson
//

import Foundation
import Observation

enum JSONValue: Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case object([String: JSONValue])
    case array([JSONValue])

    var typeDescription: String {
        switch self {
        case .string: return "string"
        case .number: return "number"
        case .bool: return "boolean"
        case .null: return "null"
        case .object: return "object"
        case .array: return "array"
        }
    }

    var isContainer: Bool {
        switch self {
        case .object, .array: return true
        default: return false
        }
    }

    var childCount: Int {
        switch self {
        case .object(let dict): return dict.count
        case .array(let arr): return arr.count
        default: return 0
        }
    }

    func toJSONString(prettyPrinted: Bool = true) -> String? {
        let any = toAny()
        guard JSONSerialization.isValidJSONObject(wrapIfNeeded(any)) else {
            if let str = any as? String { return "\"\(str)\"" }
            if let num = any as? NSNumber { return "\(num)" }
            if any is NSNull { return "null" }
            return nil
        }

        do {
            let options: JSONSerialization.WritingOptions = prettyPrinted ? [.prettyPrinted, .sortedKeys] : []
            let data = try JSONSerialization.data(withJSONObject: wrapIfNeeded(any), options: options)
            var result = String(data: data, encoding: .utf8)
            if prettyPrinted, let str = result {
                // Re-indent leading spaces only (preserve string values intact)
                let lines = str.components(separatedBy: "\n")
                var nativeIndent = 0
                for line in lines {
                    let stripped = line.drop(while: { $0 == " " })
                    let leading = line.count - stripped.count
                    if leading > 0 { nativeIndent = leading; break }
                }
                let target = 4
                if nativeIndent > 0 && nativeIndent != target {
                    result = lines.map { line -> String in
                        let stripped = line.drop(while: { $0 == " " })
                        let leading = line.count - stripped.count
                        guard leading > 0 else { return line }
                        let level = leading / nativeIndent
                        return String(repeating: " ", count: level * target) + stripped
                    }.joined(separator: "\n")
                }
            }
            return result
        } catch {
            return nil
        }
    }

    private func wrapIfNeeded(_ value: Any) -> Any {
        if value is [Any] || value is [String: Any] {
            return value
        }
        return [value]
    }

    func toAny() -> Any {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .null: return NSNull()
        case .object(let dict):
            var result: [String: Any] = [:]
            for (key, value) in dict {
                result[key] = value.toAny()
            }
            return result
        case .array(let arr):
            return arr.map { $0.toAny() }
        }
    }

    // MARK: - Search without JSONNode materialization

    /// Count matches in the JSONValue tree without creating any JSONNode objects.
    func countMatches(key: String?, query: String) -> Int {
        var count = 0
        countMatchesRecursive(key: key, query: query, count: &count)
        return count
    }

    private func countMatchesRecursive(key: String?, query: String, count: inout Int) {
        count += Self.leafOccurrenceCount(value: self, key: key, query: query)

        switch self {
        case .object(let dict):
            for (childKey, childValue) in dict {
                childValue.countMatchesRecursive(key: childKey, query: query, count: &count)
            }
        case .array(let arr):
            for (index, childValue) in arr.enumerated() {
                childValue.countMatchesRecursive(key: "[\(index)]", query: query, count: &count)
            }
        default:
            break
        }
    }

    /// Find paths (child indices at each depth) to all matching nodes.
    /// Paths use sorted-key order for objects (matching JSONNode.buildChildren).
    func searchMatchPaths(key: String?, query: String) -> [[Int]] {
        var results: [[Int]] = []
        searchMatchPathsRecursive(key: key, query: query, currentPath: [], results: &results)
        return results
    }

    private func searchMatchPathsRecursive(key: String?, query: String, currentPath: [Int], results: inout [[Int]]) {
        if Self.leafMatches(value: self, key: key, query: query) {
            results.append(currentPath)
        }

        switch self {
        case .object(let dict):
            let sortedKeys = dict.keys.sorted()
            for (index, childKey) in sortedKeys.enumerated() {
                dict[childKey]!.searchMatchPathsRecursive(
                    key: childKey, query: query,
                    currentPath: currentPath + [index], results: &results
                )
            }
        case .array(let arr):
            for (index, childValue) in arr.enumerated() {
                childValue.searchMatchPathsRecursive(
                    key: "[\(index)]", query: query,
                    currentPath: currentPath + [index], results: &results
                )
            }
        default:
            break
        }
    }

    /// Count non-overlapping occurrences of `query` in `text` (case-insensitive).
    private static func substringCount(in text: String, of query: String) -> Int {
        let lower = text.lowercased()
        let lowerQuery = query.lowercased()
        guard !lowerQuery.isEmpty else { return 0 }
        var count = 0
        var searchStart = lower.startIndex
        while searchStart < lower.endIndex,
              let range = lower.range(of: lowerQuery, range: searchStart..<lower.endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count
    }

    /// Return the display texts that TreeNodeView renders for search matching.
    /// Matches the exact escape/formatting logic used in TreeNodeView.highlightedText.
    static func searchDisplayTexts(value: JSONValue, key: String?) -> (keyText: String?, valueText: String?) {
        let keyText = key

        let valueText: String?
        switch value {
        case .string(let s):
            let escaped = s
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\t", with: "\\t")
            valueText = "\"\(escaped)\""
        case .number(let n):
            valueText = n.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", n)
                : String(n)
        case .bool(let b):
            valueText = b ? "true" : "false"
        case .null:
            valueText = "null"
        case .object, .array:
            valueText = nil
        }

        return (keyText: keyText, valueText: valueText)
    }

    /// Count all text-level occurrences of `query` in the display texts of a leaf node.
    static func leafOccurrenceCount(value: JSONValue, key: String?, query: String) -> Int {
        let texts = searchDisplayTexts(value: value, key: key)
        var count = 0
        if let keyText = texts.keyText {
            count += substringCount(in: keyText, of: query)
        }
        if let valueText = texts.valueText {
            count += substringCount(in: valueText, of: query)
        }
        return count
    }

    /// Check if a leaf node matches the search query (same logic as JSONNode.matches).
    private static func leafMatches(value: JSONValue, key: String?, query: String) -> Bool {
        if let key = key, key.lowercased().contains(query) {
            return true
        }

        switch value {
        case .string(let s):
            return s.lowercased().contains(query)
        case .number(let n):
            let numStr = n.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", n)
                : String(n)
            return numStr.contains(query)
        case .bool(let b):
            return (b ? "true" : "false").contains(query)
        case .null:
            return "null".contains(query)
        default:
            return false
        }
    }

    static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.string(let l), .string(let r)): return l == r
        case (.number(let l), .number(let r)): return l == r
        case (.bool(let l), .bool(let r)): return l == r
        case (.null, .null): return true
        case (.object(let l), .object(let r)): return l == r
        case (.array(let l), .array(let r)): return l == r
        default: return false
        }
    }
}

@Observable
class JSONNode: Identifiable {
    let id: UUID
    let key: String?
    let value: JSONValue
    let depth: Int
    let indexInParent: Int?
    let isLastChild: Bool

    var isExpanded: Bool {
        didSet {
            // Expanding a node triggers lazy child materialization
            if isExpanded, _children == nil {
                materializeChildren()
            }
        }
    }

    weak var parent: JSONNode?

    @ObservationIgnored private var _children: [JSONNode]?
    @ObservationIgnored private let storedFoldDepth: Int

    var children: [JSONNode] {
        if _children == nil {
            materializeChildren()
        }
        return _children!
    }

    init(
        key: String? = nil,
        value: JSONValue,
        depth: Int = 0,
        indexInParent: Int? = nil,
        isLastChild: Bool = true,
        defaultFoldDepth: Int = 2,
        isExpanded: Bool? = nil
    ) {
        self.id = UUID()
        self.key = key
        self.value = value
        self.depth = depth
        self.indexInParent = indexInParent
        self.isLastChild = isLastChild
        self.storedFoldDepth = defaultFoldDepth

        // Calculate expansion based on depth if not explicitly set
        if let explicit = isExpanded {
            self.isExpanded = explicit
        } else {
            // Only expand nodes with depth < defaultFoldDepth
            self.isExpanded = depth < defaultFoldDepth
        }

        // Only eagerly build children if this node is expanded
        if self.isExpanded {
            materializeChildren()
        }
    }

    private func materializeChildren() {
        guard _children == nil else { return }
        let built = buildChildren(defaultFoldDepth: storedFoldDepth)
        _children = built
        for child in built {
            child.parent = self
        }
    }

    private func buildChildren(defaultFoldDepth: Int = 2) -> [JSONNode] {
        switch value {
        case .object(let dict):
            let sortedKeys = dict.keys.sorted()
            return sortedKeys.enumerated().map { index, key in
                JSONNode(
                    key: key,
                    value: dict[key]!,
                    depth: depth + 1,
                    indexInParent: index,
                    isLastChild: index == sortedKeys.count - 1,
                    defaultFoldDepth: defaultFoldDepth
                )
            }
        case .array(let arr):
            return arr.enumerated().map { index, item in
                JSONNode(
                    key: "[\(index)]",
                    value: item,
                    depth: depth + 1,
                    indexInParent: index,
                    isLastChild: index == arr.count - 1,
                    defaultFoldDepth: defaultFoldDepth
                )
            }
        default:
            return []
        }
    }

    var displayKey: String {
        if let key = key {
            return key
        }
        return "root"
    }

    var displayValue: String {
        switch value {
        case .string(let s):
            return "\"\(s)\""
        case .number(let n):
            if n.truncatingRemainder(dividingBy: 1) == 0 {
                return String(format: "%.0f", n)
            }
            return String(n)
        case .bool(let b):
            return b ? "true" : "false"
        case .null:
            return "null"
        case .object(let dict):
            return "{ \(dict.count) keys }"
        case .array(let arr):
            return "[ \(arr.count) elements ]"
        }
    }

    var copyValue: String {
        switch value {
        case .string(let s):
            return "\"\(s)\""
        case .number(let n):
            if n.truncatingRemainder(dividingBy: 1) == 0 {
                return String(format: "%.0f", n)
            }
            return String(n)
        case .bool(let b):
            return b ? "true" : "false"
        case .null:
            return "null"
        case .object, .array:
            return value.toJSONString(prettyPrinted: true) ?? ""
        }
    }

    var plainValue: String {
        switch value {
        case .string(let s):
            return s
        case .number(let n):
            if n.truncatingRemainder(dividingBy: 1) == 0 {
                return String(format: "%.0f", n)
            }
            return String(n)
        case .bool(let b):
            return b ? "true" : "false"
        case .null:
            return "null"
        case .object, .array:
            return value.toJSONString(prettyPrinted: true) ?? ""
        }
    }

    func toggleExpanded() {
        isExpanded.toggle()
    }

    func expandAll() {
        isExpanded = true
        children.forEach { $0.expandAll() }
    }

    func collapseAll() {
        isExpanded = false
        children.forEach { $0.collapseAll() }
    }

    /// Returns the count of visible (expanded) descendant nodes, NOT including self.
    func visibleDescendantCount() -> Int {
        guard isExpanded else { return 0 }
        var count = 0
        for child in children {
            count += 1 + child.visibleDescendantCount()
        }
        return count
    }

    func allNodes() -> [JSONNode] {
        var result = [self]
        if isExpanded {
            for child in children {
                result.append(contentsOf: child.allNodes())
            }
        }
        return result
    }

    func allNodesIncludingCollapsed() -> [JSONNode] {
        var result = [self]
        for child in children {
            result.append(contentsOf: child.allNodesIncludingCollapsed())
        }
        return result
    }

    func matches(searchText: String) -> Bool {
        let lowercasedSearch = searchText.lowercased()

        if let key = key, key.lowercased().contains(lowercasedSearch) {
            return true
        }

        switch value {
        case .string(let s):
            return s.lowercased().contains(lowercasedSearch)
        case .number(let n):
            let numStr = n.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", n)
                : String(n)
            return numStr.contains(lowercasedSearch)
        case .bool(let b):
            let boolStr = b ? "true" : "false"
            return boolStr.contains(lowercasedSearch)
        case .null:
            return "null".contains(lowercasedSearch)
        default:
            return false
        }
    }

    /// Navigate to a node by child-index path. Only materializes nodes along the path.
    func nodeAt(childIndices: [Int]) -> JSONNode? {
        var current = self
        for index in childIndices {
            let kids = current.children // materializes only this level if needed
            guard index >= 0 && index < kids.count else { return nil }
            current = kids[index]
        }
        return current
    }

    func expandPathTo(node: JSONNode) {
        // Bottom-up: walk from target to self via parent links — O(depth)
        var ancestors: [JSONNode] = []
        var current = node.parent
        while let ancestor = current {
            ancestors.append(ancestor)
            if ancestor.id == self.id { break }
            current = ancestor.parent
        }
        for ancestor in ancestors {
            ancestor.isExpanded = true
        }
    }
}
