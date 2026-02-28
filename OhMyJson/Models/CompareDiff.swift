//
//  CompareDiff.swift
//  OhMyJson
//
//  Models for JSON structural comparison results.
//

import Foundation
import AppKit

// MARK: - Compare Side

enum CompareSide {
    case left, right
}

// MARK: - Diff Type

enum DiffType: String, Equatable {
    case added       // Right에만 존재
    case removed     // Left에만 존재
    case modified    // 양쪽 모두 존재하지만 값이 다름
    case unchanged   // 양쪽 동일
}

// MARK: - Diff Item

struct DiffItem: Equatable {
    let path: [String]          // JSON Pointer 경로 세그먼트
    let type: DiffType
    let key: String?            // object key (있는 경우)
    let leftValue: JSONValue?
    let rightValue: JSONValue?
    let children: [DiffItem]    // 중첩 비교 결과
    let depth: Int

    /// Convenience: whether this item or any descendant has an actual diff
    var hasDiff: Bool {
        if type != .unchanged { return true }
        return children.contains(where: { $0.hasDiff })
    }
}

// MARK: - Compare Diff Result

struct CompareDiffResult: Equatable {
    let items: [DiffItem]

    var addedCount: Int { countType(.added) }
    var removedCount: Int { countType(.removed) }
    var modifiedCount: Int { countType(.modified) }
    var totalDiffCount: Int { addedCount + removedCount + modifiedCount }
    var isIdentical: Bool { totalDiffCount == 0 }

    /// Flattened list of all leaf-level diff items (non-unchanged, no children with diffs)
    var flattenedDiffItems: [DiffItem] {
        var result: [DiffItem] = []
        flattenItems(items, into: &result)
        return result
    }

    private func flattenItems(_ items: [DiffItem], into result: inout [DiffItem]) {
        for item in items {
            if item.type != .unchanged {
                if item.children.isEmpty || !item.children.contains(where: { $0.hasDiff }) {
                    result.append(item)
                } else {
                    flattenItems(item.children, into: &result)
                }
            } else if !item.children.isEmpty {
                flattenItems(item.children, into: &result)
            }
        }
    }

    private func countType(_ type: DiffType) -> Int {
        countTypeRecursive(items, type: type)
    }

    private func countTypeRecursive(_ items: [DiffItem], type: DiffType) -> Int {
        var count = 0
        for item in items {
            if item.type == type {
                // Count leaf diffs — if it has children with diffs, count those instead
                if item.children.isEmpty || !item.children.contains(where: { $0.hasDiff }) {
                    count += 1
                } else {
                    count += countTypeRecursive(item.children, type: type)
                }
            } else {
                count += countTypeRecursive(item.children, type: type)
            }
        }
        return count
    }
}

// MARK: - Compare Options

struct CompareOptions: Equatable {
    var ignoreKeyOrder: Bool = true
    var ignoreArrayOrder: Bool = false
    var strictType: Bool = true
}

// MARK: - Serialization (RFC 6901 JSON Pointer)

extension DiffItem {
    /// JSON Pointer path string (e.g. "/users/0/name")
    var jsonPointerPath: String {
        "/" + path.joined(separator: "/")
    }
}

extension CompareDiffResult {
    /// Serialize diff result to a JSON-compatible array of dictionaries (for Copy Diff)
    func serializeDiff() -> [[String: Any]] {
        let flattened = flattenedDiffItems
        return flattened.map { item in
            var dict: [String: Any] = [
                "path": item.jsonPointerPath,
                "type": item.type.rawValue,
            ]
            if let left = item.leftValue, item.type == .removed || item.type == .modified {
                dict["left"] = left.toAny()
            }
            if let right = item.rightValue, item.type == .added || item.type == .modified {
                dict["right"] = right.toAny()
            }
            return dict
        }
    }
}

// MARK: - Render Line

enum RenderLineType: Equatable {
    case content(DiffType)  // actual JSON content with diff coloring
    case padding            // empty line for alignment
    case collapse(Int)      // collapsed section marker, Int = number of hidden lines
}

struct RenderLine: Equatable {
    let lineIndex: Int      // original line index in the JSON output
    let type: RenderLineType
    let text: String        // display text (empty for padding, "··· N lines ···" for collapse)

    static func == (lhs: RenderLine, rhs: RenderLine) -> Bool {
        lhs.lineIndex == rhs.lineIndex && lhs.type == rhs.type && lhs.text == rhs.text
    }
}

// MARK: - Compare Render Result

struct CompareRenderResult: Equatable {
    let leftContent: NSAttributedString
    let rightContent: NSAttributedString
    let leftLines: [RenderLine]
    let rightLines: [RenderLine]
    let totalLines: Int

    static func == (lhs: CompareRenderResult, rhs: CompareRenderResult) -> Bool {
        lhs.leftContent == rhs.leftContent && lhs.rightContent == rhs.rightContent
    }
}
