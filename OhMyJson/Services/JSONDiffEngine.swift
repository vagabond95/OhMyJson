//
//  JSONDiffEngine.swift
//  OhMyJson
//
//  Recursive JSON structural comparison engine.
//

import Foundation

final class JSONDiffEngine: JSONDiffEngineProtocol {
    static let shared = JSONDiffEngine()

    private init() {}

    func compare(left: JSONValue, right: JSONValue, options: CompareOptions) -> CompareDiffResult {
        let items = compareValues(left: left, right: right, path: [], depth: 0, options: options)
        return CompareDiffResult(items: [items])
    }

    // MARK: - Recursive Comparison

    private func compareValues(left: JSONValue, right: JSONValue, path: [String], depth: Int, options: CompareOptions) -> DiffItem {
        // Check type compatibility
        if !areSameType(left, right) {
            if !options.strictType, arePrimitiveEquivalent(left, right) {
                return DiffItem(path: path, type: .unchanged, key: path.last, leftValue: left, rightValue: right, children: [], depth: depth)
            }
            // Different types → modified at this level
            return DiffItem(path: path, type: .modified, key: path.last, leftValue: left, rightValue: right, children: [], depth: depth)
        }

        switch (left, right) {
        case (.object(let leftDict), .object(let rightDict)):
            return compareObjects(left: leftDict, right: rightDict, path: path, depth: depth, options: options)

        case (.array(let leftArr), .array(let rightArr)):
            return compareArrays(left: leftArr, right: rightArr, path: path, depth: depth, options: options)

        default:
            // Primitive comparison
            return comparePrimitives(left: left, right: right, path: path, depth: depth, options: options)
        }
    }

    // MARK: - Object Comparison

    private func compareObjects(left: [String: JSONValue], right: [String: JSONValue], path: [String], depth: Int, options: CompareOptions) -> DiffItem {
        let leftKeys = Set(left.keys)
        let rightKeys = Set(right.keys)

        let removedKeys = leftKeys.subtracting(rightKeys)
        let addedKeys = rightKeys.subtracting(leftKeys)
        let commonKeys = leftKeys.intersection(rightKeys)

        var children: [DiffItem] = []

        // Determine key ordering
        let orderedKeys: [String]
        if options.ignoreKeyOrder {
            orderedKeys = (Array(commonKeys) + Array(removedKeys) + Array(addedKeys)).sorted()
        } else {
            // Preserve original left key order, then append added keys
            let leftOrdered = left.keys.filter { commonKeys.contains($0) || removedKeys.contains($0) }
            let addedOrdered = right.keys.filter { addedKeys.contains($0) }
            orderedKeys = Array(leftOrdered) + addedOrdered
        }

        for key in orderedKeys {
            let childPath = path + [key]

            if removedKeys.contains(key) {
                children.append(DiffItem(path: childPath, type: .removed, key: key, leftValue: left[key], rightValue: nil, children: [], depth: depth + 1))
            } else if addedKeys.contains(key) {
                children.append(DiffItem(path: childPath, type: .added, key: key, leftValue: nil, rightValue: right[key], children: [], depth: depth + 1))
            } else {
                // Common key — recurse
                let child = compareValues(left: left[key]!, right: right[key]!, path: childPath, depth: depth + 1, options: options)
                children.append(child)
            }
        }

        let hasAnyDiff = children.contains(where: { $0.hasDiff })
        return DiffItem(path: path, type: hasAnyDiff ? .modified : .unchanged, key: path.last, leftValue: .object(left), rightValue: .object(right), children: children, depth: depth)
    }

    // MARK: - Array Comparison

    private func compareArrays(left: [JSONValue], right: [JSONValue], path: [String], depth: Int, options: CompareOptions) -> DiffItem {
        let children: [DiffItem]

        if options.ignoreArrayOrder {
            children = compareArraysUnordered(left: left, right: right, path: path, depth: depth, options: options)
        } else {
            children = compareArraysOrdered(left: left, right: right, path: path, depth: depth, options: options)
        }

        let hasAnyDiff = children.contains(where: { $0.hasDiff })
        return DiffItem(path: path, type: hasAnyDiff ? .modified : .unchanged, key: path.last, leftValue: .array(left), rightValue: .array(right), children: children, depth: depth)
    }

    private func compareArraysOrdered(left: [JSONValue], right: [JSONValue], path: [String], depth: Int, options: CompareOptions) -> [DiffItem] {
        var children: [DiffItem] = []
        let maxCount = max(left.count, right.count)

        for i in 0..<maxCount {
            let childPath = path + [String(i)]

            if i < left.count && i < right.count {
                let child = compareValues(left: left[i], right: right[i], path: childPath, depth: depth + 1, options: options)
                children.append(child)
            } else if i < left.count {
                children.append(DiffItem(path: childPath, type: .removed, key: String(i), leftValue: left[i], rightValue: nil, children: [], depth: depth + 1))
            } else {
                children.append(DiffItem(path: childPath, type: .added, key: String(i), leftValue: nil, rightValue: right[i], children: [], depth: depth + 1))
            }
        }

        return children
    }

    private func compareArraysUnordered(left: [JSONValue], right: [JSONValue], path: [String], depth: Int, options: CompareOptions) -> [DiffItem] {
        // Check if all elements are primitives
        let allPrimitive = (left + right).allSatisfy { !$0.isContainer }
        if allPrimitive {
            return comparePrimitiveArraysUnordered(left: left, right: right, path: path, depth: depth, options: options)
        }

        // Check if all elements are objects — try matching key inference
        let allObjects = (left + right).allSatisfy {
            if case .object = $0 { return true }
            return false
        }
        if allObjects {
            if let matchingKey = inferMatchingKey(left: left, right: right) {
                return compareObjectArraysByKey(left: left, right: right, matchingKey: matchingKey, path: path, depth: depth, options: options)
            }
            // Fallback: hash-based matching
            return compareArraysByHash(left: left, right: right, path: path, depth: depth, options: options)
        }

        // Mixed array — fallback to ordered comparison
        return compareArraysOrdered(left: left, right: right, path: path, depth: depth, options: options)
    }

    private func comparePrimitiveArraysUnordered(left: [JSONValue], right: [JSONValue], path: [String], depth: Int, options: CompareOptions) -> [DiffItem] {
        var rightRemaining = right.enumerated().map { ($0.offset, $0.element) }
        var children: [DiffItem] = []
        var matchedRightIndices = Set<Int>()

        for (li, lv) in left.enumerated() {
            let childPath = path + [String(li)]
            if let match = rightRemaining.first(where: { !matchedRightIndices.contains($0.0) && valuesEqual(lv, $0.1, options: options) }) {
                matchedRightIndices.insert(match.0)
                children.append(DiffItem(path: childPath, type: .unchanged, key: String(li), leftValue: lv, rightValue: match.1, children: [], depth: depth + 1))
            } else {
                children.append(DiffItem(path: childPath, type: .removed, key: String(li), leftValue: lv, rightValue: nil, children: [], depth: depth + 1))
            }
        }

        for (ri, rv) in right.enumerated() where !matchedRightIndices.contains(ri) {
            let childPath = path + [String(ri)]
            children.append(DiffItem(path: childPath, type: .added, key: String(ri), leftValue: nil, rightValue: rv, children: [], depth: depth + 1))
        }

        return children
    }

    // MARK: - Array Matching Key Inference

    private let preferredKeys = ["id", "_id", "uuid", "key", "name"]

    private func inferMatchingKey(left: [JSONValue], right: [JSONValue]) -> String? {
        guard !left.isEmpty, !right.isEmpty else { return nil }

        // Collect common fields across all objects in both arrays
        var leftCommonKeys: Set<String>?
        for item in left {
            guard case .object(let dict) = item else { return nil }
            let keys = Set(dict.keys)
            if leftCommonKeys == nil {
                leftCommonKeys = keys
            } else {
                leftCommonKeys = leftCommonKeys!.intersection(keys)
            }
        }

        var rightCommonKeys: Set<String>?
        for item in right {
            guard case .object(let dict) = item else { return nil }
            let keys = Set(dict.keys)
            if rightCommonKeys == nil {
                rightCommonKeys = keys
            } else {
                rightCommonKeys = rightCommonKeys!.intersection(keys)
            }
        }

        guard let lck = leftCommonKeys, let rck = rightCommonKeys else { return nil }
        let commonKeys = lck.intersection(rck)

        // Try preferred keys first, then other common keys
        let candidates = preferredKeys.filter { commonKeys.contains($0) } +
            commonKeys.sorted().filter { !preferredKeys.contains($0) }

        for candidate in candidates {
            if isValidMatchingKey(candidate, in: left) && isValidMatchingKey(candidate, in: right) {
                return candidate
            }
        }

        return nil
    }

    private func isValidMatchingKey(_ key: String, in array: [JSONValue]) -> Bool {
        var seen = Set<String>()
        for item in array {
            guard case .object(let dict) = item, let value = dict[key] else { return false }
            // Must be primitive
            guard !value.isContainer else { return false }
            let stringVal = primitiveToString(value)
            if seen.contains(stringVal) { return false }
            seen.insert(stringVal)
        }
        return true
    }

    private func compareObjectArraysByKey(left: [JSONValue], right: [JSONValue], matchingKey: String, path: [String], depth: Int, options: CompareOptions) -> [DiffItem] {
        // Build lookup maps
        var leftMap: [String: (Int, JSONValue)] = [:]
        for (i, item) in left.enumerated() {
            if case .object(let dict) = item, let keyVal = dict[matchingKey] {
                leftMap[primitiveToString(keyVal)] = (i, item)
            }
        }

        var rightMap: [String: (Int, JSONValue)] = [:]
        for (i, item) in right.enumerated() {
            if case .object(let dict) = item, let keyVal = dict[matchingKey] {
                rightMap[primitiveToString(keyVal)] = (i, item)
            }
        }

        var children: [DiffItem] = []
        var processedRightKeys = Set<String>()

        // Process left items
        for (i, item) in left.enumerated() {
            if case .object(let dict) = item, let keyVal = dict[matchingKey] {
                let keyStr = primitiveToString(keyVal)
                let childPath = path + [String(i)]

                if let (_, rightItem) = rightMap[keyStr] {
                    processedRightKeys.insert(keyStr)
                    let child = compareValues(left: item, right: rightItem, path: childPath, depth: depth + 1, options: options)
                    children.append(child)
                } else {
                    children.append(DiffItem(path: childPath, type: .removed, key: String(i), leftValue: item, rightValue: nil, children: [], depth: depth + 1))
                }
            }
        }

        // Process unmatched right items
        for (i, item) in right.enumerated() {
            if case .object(let dict) = item, let keyVal = dict[matchingKey] {
                let keyStr = primitiveToString(keyVal)
                if !processedRightKeys.contains(keyStr) {
                    let childPath = path + [String(i)]
                    children.append(DiffItem(path: childPath, type: .added, key: String(i), leftValue: nil, rightValue: item, children: [], depth: depth + 1))
                }
            }
        }

        return children
    }

    private func compareArraysByHash(left: [JSONValue], right: [JSONValue], path: [String], depth: Int, options: CompareOptions) -> [DiffItem] {
        // Hash-based matching: normalize each object to a canonical string
        let leftHashes = left.map { normalizeHash($0) }
        let rightHashes = right.map { normalizeHash($0) }

        var matchedRightIndices = Set<Int>()
        var children: [DiffItem] = []

        for (li, lHash) in leftHashes.enumerated() {
            let childPath = path + [String(li)]
            if let ri = rightHashes.enumerated().first(where: { !matchedRightIndices.contains($0.offset) && $0.element == lHash })?.offset {
                matchedRightIndices.insert(ri)
                let child = compareValues(left: left[li], right: right[ri], path: childPath, depth: depth + 1, options: options)
                children.append(child)
            } else {
                children.append(DiffItem(path: childPath, type: .removed, key: String(li), leftValue: left[li], rightValue: nil, children: [], depth: depth + 1))
            }
        }

        for (ri, rv) in right.enumerated() where !matchedRightIndices.contains(ri) {
            let childPath = path + [String(ri)]
            children.append(DiffItem(path: childPath, type: .added, key: String(ri), leftValue: nil, rightValue: rv, children: [], depth: depth + 1))
        }

        return children
    }

    // MARK: - Primitive Comparison

    private func comparePrimitives(left: JSONValue, right: JSONValue, path: [String], depth: Int, options: CompareOptions) -> DiffItem {
        let areEqual = valuesEqual(left, right, options: options)
        return DiffItem(path: path, type: areEqual ? .unchanged : .modified, key: path.last, leftValue: left, rightValue: right, children: [], depth: depth)
    }

    private func valuesEqual(_ left: JSONValue, _ right: JSONValue, options: CompareOptions) -> Bool {
        if options.strictType {
            return left == right
        }
        // Non-strict: compare by string representation
        return primitiveToString(left) == primitiveToString(right)
    }

    private func areSameType(_ left: JSONValue, _ right: JSONValue) -> Bool {
        switch (left, right) {
        case (.string, .string), (.number, .number), (.bool, .bool), (.null, .null),
             (.object, .object), (.array, .array):
            return true
        default:
            return false
        }
    }

    /// For non-strict type comparison: check if two different-type primitives have equivalent string values
    private func arePrimitiveEquivalent(_ left: JSONValue, _ right: JSONValue) -> Bool {
        guard !left.isContainer, !right.isContainer else { return false }
        return primitiveToString(left) == primitiveToString(right)
    }

    private func primitiveToString(_ value: JSONValue) -> String {
        switch value {
        case .string(let s): return s
        case .number(let n):
            if n.truncatingRemainder(dividingBy: 1) == 0 {
                return String(format: "%.0f", n)
            }
            return String(n)
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .object, .array:
            // For hashing purposes, use sorted JSON
            return value.toJSONString(prettyPrinted: false) ?? ""
        }
    }

    private func normalizeHash(_ value: JSONValue) -> String {
        return value.toJSONString(prettyPrinted: false) ?? ""
    }
}
