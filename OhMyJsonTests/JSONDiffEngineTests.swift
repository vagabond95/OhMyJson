//
//  JSONDiffEngineTests.swift
//  OhMyJsonTests
//

import Testing
@testable import OhMyJson

@Suite("JSONDiffEngine Tests")
struct JSONDiffEngineTests {
    let engine = JSONDiffEngine.shared

    // MARK: - Primitive Comparison

    @Test("Identical strings are unchanged")
    func identicalStrings() {
        let result = engine.compare(left: .string("hello"), right: .string("hello"), options: CompareOptions())
        #expect(result.isIdentical)
    }

    @Test("Different strings are modified")
    func differentStrings() {
        let result = engine.compare(left: .string("hello"), right: .string("world"), options: CompareOptions())
        #expect(result.modifiedCount == 1)
    }

    @Test("Identical numbers are unchanged")
    func identicalNumbers() {
        let result = engine.compare(left: .number(42), right: .number(42), options: CompareOptions())
        #expect(result.isIdentical)
    }

    @Test("Different numbers are modified")
    func differentNumbers() {
        let result = engine.compare(left: .number(1), right: .number(2), options: CompareOptions())
        #expect(result.modifiedCount == 1)
    }

    @Test("Identical booleans are unchanged")
    func identicalBooleans() {
        let result = engine.compare(left: .bool(true), right: .bool(true), options: CompareOptions())
        #expect(result.isIdentical)
    }

    @Test("Null vs null is unchanged")
    func nullVsNull() {
        let result = engine.compare(left: .null, right: .null, options: CompareOptions())
        #expect(result.isIdentical)
    }

    @Test("Different types are modified")
    func differentTypes() {
        let result = engine.compare(left: .string("1"), right: .number(1), options: CompareOptions())
        #expect(result.modifiedCount == 1)
    }

    // MARK: - Strict Type Option

    @Test("Strict type: string '1' vs number 1 are modified")
    func strictTypeStringVsNumber() {
        let result = engine.compare(left: .string("1"), right: .number(1), options: CompareOptions(strictType: true))
        #expect(result.modifiedCount == 1)
    }

    @Test("Non-strict type: string '1' vs number 1 are unchanged")
    func nonStrictTypeStringVsNumber() {
        let result = engine.compare(left: .string("1"), right: .number(1), options: CompareOptions(strictType: false))
        #expect(result.isIdentical)
    }

    @Test("Non-strict type: string 'true' vs bool true are unchanged")
    func nonStrictTypeBoolVsString() {
        let result = engine.compare(left: .string("true"), right: .bool(true), options: CompareOptions(strictType: false))
        #expect(result.isIdentical)
    }

    // MARK: - Object Comparison

    @Test("Identical objects are unchanged")
    func identicalObjects() {
        let left = JSONValue.object(["a": .number(1), "b": .string("hello")])
        let right = JSONValue.object(["a": .number(1), "b": .string("hello")])
        let result = engine.compare(left: left, right: right, options: CompareOptions())
        #expect(result.isIdentical)
    }

    @Test("Object with added key")
    func objectAddedKey() {
        let left = JSONValue.object(["a": .number(1)])
        let right = JSONValue.object(["a": .number(1), "b": .number(2)])
        let result = engine.compare(left: left, right: right, options: CompareOptions())
        #expect(result.addedCount == 1)
        #expect(result.removedCount == 0)
    }

    @Test("Object with removed key")
    func objectRemovedKey() {
        let left = JSONValue.object(["a": .number(1), "b": .number(2)])
        let right = JSONValue.object(["a": .number(1)])
        let result = engine.compare(left: left, right: right, options: CompareOptions())
        #expect(result.removedCount == 1)
        #expect(result.addedCount == 0)
    }

    @Test("Object with modified value")
    func objectModifiedValue() {
        let left = JSONValue.object(["a": .number(1)])
        let right = JSONValue.object(["a": .number(2)])
        let result = engine.compare(left: left, right: right, options: CompareOptions())
        #expect(result.modifiedCount == 1)
    }

    @Test("Object with mixed changes: add, remove, modify")
    func objectMixedChanges() {
        let left = JSONValue.object(["a": .number(1), "b": .number(2), "c": .number(3)])
        let right = JSONValue.object(["a": .number(1), "b": .number(99), "d": .number(4)])
        let result = engine.compare(left: left, right: right, options: CompareOptions())
        #expect(result.modifiedCount == 1)  // b: 2→99
        #expect(result.removedCount == 1)   // c removed
        #expect(result.addedCount == 1)     // d added
    }

    // MARK: - Nested Object Comparison

    @Test("Nested object change is detected")
    func nestedObjectChange() {
        let left = JSONValue.object(["user": .object(["name": .string("Alice"), "age": .number(30)])])
        let right = JSONValue.object(["user": .object(["name": .string("Bob"), "age": .number(30)])])
        let result = engine.compare(left: left, right: right, options: CompareOptions())
        #expect(result.modifiedCount == 1)  // user.name changed
    }

    @Test("Deeply nested change")
    func deeplyNestedChange() {
        let left = JSONValue.object(["a": .object(["b": .object(["c": .number(1)])])])
        let right = JSONValue.object(["a": .object(["b": .object(["c": .number(2)])])])
        let result = engine.compare(left: left, right: right, options: CompareOptions())
        #expect(result.modifiedCount == 1)
        let flattened = result.flattenedDiffItems
        #expect(flattened.count == 1)
        #expect(flattened.first?.path == ["a", "b", "c"])
    }

    // MARK: - Array Comparison (Ordered)

    @Test("Identical arrays are unchanged")
    func identicalArrays() {
        let left = JSONValue.array([.number(1), .number(2), .number(3)])
        let right = JSONValue.array([.number(1), .number(2), .number(3)])
        let result = engine.compare(left: left, right: right, options: CompareOptions())
        #expect(result.isIdentical)
    }

    @Test("Array with extra element")
    func arrayExtraElement() {
        let left = JSONValue.array([.number(1), .number(2)])
        let right = JSONValue.array([.number(1), .number(2), .number(3)])
        let result = engine.compare(left: left, right: right, options: CompareOptions())
        #expect(result.addedCount == 1)
    }

    @Test("Array with removed element")
    func arrayRemovedElement() {
        let left = JSONValue.array([.number(1), .number(2), .number(3)])
        let right = JSONValue.array([.number(1), .number(2)])
        let result = engine.compare(left: left, right: right, options: CompareOptions())
        #expect(result.removedCount == 1)
    }

    @Test("Array with modified element")
    func arrayModifiedElement() {
        let left = JSONValue.array([.number(1), .number(2)])
        let right = JSONValue.array([.number(1), .number(99)])
        let result = engine.compare(left: left, right: right, options: CompareOptions())
        #expect(result.modifiedCount == 1)
    }

    // MARK: - Array Comparison (Unordered)

    @Test("Primitive array order ignored when option ON")
    func primitiveArrayUnordered() {
        let left = JSONValue.array([.number(1), .number(2), .number(3)])
        let right = JSONValue.array([.number(3), .number(1), .number(2)])
        let result = engine.compare(left: left, right: right, options: CompareOptions(ignoreArrayOrder: true))
        #expect(result.isIdentical)
    }

    @Test("Object array matching by id key")
    func objectArrayMatchById() {
        let left = JSONValue.array([
            .object(["id": .number(1), "name": .string("Alice")]),
            .object(["id": .number(2), "name": .string("Bob")]),
        ])
        let right = JSONValue.array([
            .object(["id": .number(2), "name": .string("Bob")]),
            .object(["id": .number(1), "name": .string("Alice Updated")]),
        ])
        let result = engine.compare(left: left, right: right, options: CompareOptions(ignoreArrayOrder: true))
        #expect(result.modifiedCount == 1)  // Alice→Alice Updated
        #expect(result.addedCount == 0)
        #expect(result.removedCount == 0)
    }

    @Test("Object array matching by name key when id not present")
    func objectArrayMatchByName() {
        let left = JSONValue.array([
            .object(["name": .string("A"), "val": .number(1)]),
            .object(["name": .string("B"), "val": .number(2)]),
        ])
        let right = JSONValue.array([
            .object(["name": .string("B"), "val": .number(2)]),
            .object(["name": .string("A"), "val": .number(99)]),
        ])
        let result = engine.compare(left: left, right: right, options: CompareOptions(ignoreArrayOrder: true))
        #expect(result.modifiedCount == 1)  // A's val changed
    }

    // MARK: - Empty / Identical JSON

    @Test("Empty objects are identical")
    func emptyObjects() {
        let result = engine.compare(left: .object([:]), right: .object([:]), options: CompareOptions())
        #expect(result.isIdentical)
    }

    @Test("Empty arrays are identical")
    func emptyArrays() {
        let result = engine.compare(left: .array([]), right: .array([]), options: CompareOptions())
        #expect(result.isIdentical)
    }

    @Test("Identical complex JSON is unchanged")
    func identicalComplexJSON() {
        let json = JSONValue.object([
            "users": .array([
                .object(["id": .number(1), "name": .string("Alice"), "active": .bool(true)]),
                .object(["id": .number(2), "name": .string("Bob"), "active": .bool(false)]),
            ]),
            "count": .number(2),
            "metadata": .null,
        ])
        let result = engine.compare(left: json, right: json, options: CompareOptions())
        #expect(result.isIdentical)
    }

    // MARK: - Serialization

    @Test("serializeDiff produces correct format")
    func serializeDiff() {
        let left = JSONValue.object(["a": .number(1), "b": .number(2)])
        let right = JSONValue.object(["a": .number(1), "c": .number(3)])
        let result = engine.compare(left: left, right: right, options: CompareOptions())
        let serialized = result.serializeDiff()

        #expect(serialized.count == 2) // b removed, c added

        let removedItem = serialized.first(where: { ($0["type"] as? String) == "removed" })
        #expect(removedItem?["path"] as? String == "/b")

        let addedItem = serialized.first(where: { ($0["type"] as? String) == "added" })
        #expect(addedItem?["path"] as? String == "/c")
    }

    @Test("JSON Pointer path format")
    func jsonPointerPath() {
        let item = DiffItem(path: ["users", "0", "name"], type: .modified, key: "name", leftValue: .string("A"), rightValue: .string("B"), children: [], depth: 3)
        #expect(item.jsonPointerPath == "/users/0/name")
    }

    // MARK: - Ignore Key Order

    @Test("Objects with different key order are identical when ignoreKeyOrder=true")
    func ignoreKeyOrder() {
        let left = JSONValue.object(["z": .number(1), "a": .number(2)])
        let right = JSONValue.object(["a": .number(2), "z": .number(1)])
        let result = engine.compare(left: left, right: right, options: CompareOptions(ignoreKeyOrder: true))
        #expect(result.isIdentical)
    }

    // MARK: - Hash Matching Fallback

    @Test("Object arrays without matching key use hash fallback")
    func hashMatchingFallback() {
        // Objects without any unique identifier field
        let left = JSONValue.array([
            .object(["x": .number(1), "y": .number(2)]),
            .object(["x": .number(3), "y": .number(4)]),
        ])
        let right = JSONValue.array([
            .object(["x": .number(3), "y": .number(4)]),
            .object(["x": .number(1), "y": .number(2)]),
        ])
        let result = engine.compare(left: left, right: right, options: CompareOptions(ignoreArrayOrder: true))
        #expect(result.isIdentical)
    }

    // MARK: - DiffItem Properties

    @Test("hasDiff returns false for unchanged item")
    func hasDiffUnchanged() {
        let item = DiffItem(path: [], type: .unchanged, key: nil, leftValue: .null, rightValue: .null, children: [], depth: 0)
        #expect(!item.hasDiff)
    }

    @Test("hasDiff returns true for modified item")
    func hasDiffModified() {
        let item = DiffItem(path: [], type: .modified, key: nil, leftValue: .number(1), rightValue: .number(2), children: [], depth: 0)
        #expect(item.hasDiff)
    }

    @Test("hasDiff returns true when child has diff")
    func hasDiffChildDiff() {
        let child = DiffItem(path: ["a"], type: .added, key: "a", leftValue: nil, rightValue: .number(1), children: [], depth: 1)
        let parent = DiffItem(path: [], type: .unchanged, key: nil, leftValue: nil, rightValue: nil, children: [child], depth: 0)
        #expect(parent.hasDiff)
    }

    // MARK: - CompareDiffResult Counts

    @Test("Counting mixed diff types")
    func countMixedDiffTypes() {
        let left = JSONValue.object([
            "keep": .number(1),
            "change": .string("old"),
            "remove": .bool(true),
        ])
        let right = JSONValue.object([
            "keep": .number(1),
            "change": .string("new"),
            "add": .number(42),
        ])
        let result = engine.compare(left: left, right: right, options: CompareOptions())
        #expect(result.modifiedCount == 1)   // change
        #expect(result.removedCount == 1)    // remove
        #expect(result.addedCount == 1)      // add
        #expect(result.totalDiffCount == 3)
    }
}
