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

    var isExpanded: Bool

    weak var parent: JSONNode?

    private(set) var children: [JSONNode] = []

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

        // Calculate expansion based on depth if not explicitly set
        if let explicit = isExpanded {
            self.isExpanded = explicit
        } else {
            // Only expand nodes with depth < defaultFoldDepth
            self.isExpanded = depth < defaultFoldDepth
        }

        self.children = buildChildren(defaultFoldDepth: defaultFoldDepth)
        for child in children {
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

    func expandPathTo(node: JSONNode) {
        if children.contains(where: { $0.id == node.id }) {
            isExpanded = true
            return
        }

        for child in children {
            if child.containsNode(node) {
                isExpanded = true
                child.expandPathTo(node: node)
                return
            }
        }
    }

    private func containsNode(_ node: JSONNode) -> Bool {
        if id == node.id { return true }
        return children.contains { $0.containsNode(node) }
    }
}
