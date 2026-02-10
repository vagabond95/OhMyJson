//
//  JSONNodeTests.swift
//  OhMyJsonTests
//

import Testing
@testable import OhMyJson

@Suite("JSONNode Tests")
struct JSONNodeTests {

    // MARK: - Initialization

    @Test("Root node defaults")
    func rootNodeDefaults() {
        let node = JSONNode(value: .object(["key": .string("value")]))
        #expect(node.key == nil)
        #expect(node.depth == 0)
        #expect(node.indexInParent == nil)
        #expect(node.isLastChild == true)
        #expect(node.displayKey == "root")
    }

    @Test("Child node properties")
    func childNodeProperties() {
        let node = JSONNode(
            key: "name",
            value: .string("hello"),
            depth: 1,
            indexInParent: 0,
            isLastChild: false
        )
        #expect(node.key == "name")
        #expect(node.depth == 1)
        #expect(node.indexInParent == 0)
        #expect(node.isLastChild == false)
        #expect(node.displayKey == "name")
    }

    // MARK: - Children Building

    @Test("Object node builds sorted children")
    func objectChildrenSorted() {
        let value = JSONValue.object([
            "charlie": .number(3),
            "alpha": .number(1),
            "bravo": .number(2)
        ])
        let node = JSONNode(value: value)
        #expect(node.children.count == 3)
        #expect(node.children[0].key == "alpha")
        #expect(node.children[1].key == "bravo")
        #expect(node.children[2].key == "charlie")
    }

    @Test("Array node builds indexed children")
    func arrayChildren() {
        let value = JSONValue.array([.string("a"), .string("b"), .string("c")])
        let node = JSONNode(value: value)
        #expect(node.children.count == 3)
        #expect(node.children[0].key == "[0]")
        #expect(node.children[1].key == "[1]")
        #expect(node.children[2].key == "[2]")
    }

    @Test("Leaf nodes have no children")
    func leafNoChildren() {
        let stringNode = JSONNode(value: .string("hello"))
        let numberNode = JSONNode(value: .number(42))
        let boolNode = JSONNode(value: .bool(true))
        let nullNode = JSONNode(value: .null)

        #expect(stringNode.children.isEmpty)
        #expect(numberNode.children.isEmpty)
        #expect(boolNode.children.isEmpty)
        #expect(nullNode.children.isEmpty)
    }

    @Test("isLastChild correctly set for children")
    func isLastChildProperty() {
        let value = JSONValue.array([.number(1), .number(2), .number(3)])
        let node = JSONNode(value: value)
        #expect(node.children[0].isLastChild == false)
        #expect(node.children[1].isLastChild == false)
        #expect(node.children[2].isLastChild == true)
    }

    @Test("Nested depth tracking")
    func depthTracking() {
        let value = JSONValue.object([
            "level1": .object([
                "level2": .object([
                    "level3": .string("deep")
                ])
            ])
        ])
        let node = JSONNode(value: value)
        #expect(node.depth == 0)
        #expect(node.children[0].depth == 1)
        #expect(node.children[0].children[0].depth == 2)
        #expect(node.children[0].children[0].children[0].depth == 3)
    }

    // MARK: - Expansion / Collapse

    @Test("Default fold depth controls expansion")
    func defaultFoldDepth() {
        let value = JSONValue.object([
            "a": .object([
                "b": .object([
                    "c": .string("deep")
                ])
            ])
        ])

        // defaultFoldDepth = 2: depth 0 and 1 expanded, depth 2+ collapsed
        let node = JSONNode(value: value, defaultFoldDepth: 2)
        #expect(node.isExpanded == true)          // depth 0
        #expect(node.children[0].isExpanded == true) // depth 1
        #expect(node.children[0].children[0].isExpanded == false) // depth 2
    }

    @Test("Explicit isExpanded overrides default")
    func explicitExpansion() {
        let node = JSONNode(
            value: .object(["key": .string("val")]),
            depth: 5,
            defaultFoldDepth: 2,
            isExpanded: true
        )
        #expect(node.isExpanded == true)
    }

    @Test("toggleExpanded flips state")
    func toggleExpanded() {
        let node = JSONNode(value: .object(["key": .string("val")]))
        let initial = node.isExpanded
        node.toggleExpanded()
        #expect(node.isExpanded == !initial)
        node.toggleExpanded()
        #expect(node.isExpanded == initial)
    }

    @Test("expandAll expands entire tree")
    func expandAll() {
        let value = JSONValue.object([
            "a": .object([
                "b": .object([
                    "c": .string("deep")
                ])
            ])
        ])
        let node = JSONNode(value: value, defaultFoldDepth: 0) // all collapsed
        #expect(node.isExpanded == false)

        node.expandAll()

        #expect(node.isExpanded == true)
        #expect(node.children[0].isExpanded == true)
        #expect(node.children[0].children[0].isExpanded == true)
    }

    @Test("collapseAll collapses entire tree")
    func collapseAll() {
        let value = JSONValue.object([
            "a": .object([
                "b": .string("val")
            ])
        ])
        let node = JSONNode(value: value, defaultFoldDepth: 10) // all expanded
        #expect(node.isExpanded == true)

        node.collapseAll()

        #expect(node.isExpanded == false)
        #expect(node.children[0].isExpanded == false)
    }

    // MARK: - allNodes Traversal

    @Test("allNodes returns only visible (expanded) nodes")
    func allNodesExpanded() {
        let value = JSONValue.object([
            "a": .string("1"),
            "b": .string("2")
        ])
        let node = JSONNode(value: value, defaultFoldDepth: 10)
        let all = node.allNodes()
        #expect(all.count == 3) // root + 2 children
    }

    @Test("allNodes excludes collapsed children")
    func allNodesCollapsed() {
        let value = JSONValue.object([
            "a": .object(["nested": .string("val")])
        ])
        let node = JSONNode(value: value, defaultFoldDepth: 10)
        node.children[0].isExpanded = false

        let all = node.allNodes()
        // root (expanded) + "a" node (collapsed, still visible) = 2
        // "nested" is NOT visible because "a" is collapsed
        #expect(all.count == 2)
    }

    @Test("allNodesIncludingCollapsed returns all nodes regardless of expansion")
    func allNodesIncludingCollapsed() {
        let value = JSONValue.object([
            "a": .object(["nested": .string("val")])
        ])
        let node = JSONNode(value: value, defaultFoldDepth: 0) // all collapsed
        let all = node.allNodesIncludingCollapsed()
        #expect(all.count == 3) // root + "a" + "nested"
    }

    // MARK: - Search Matching

    @Test("matches by key")
    func matchesByKey() {
        let node = JSONNode(key: "userName", value: .string("test"))
        #expect(node.matches(searchText: "user") == true)
        #expect(node.matches(searchText: "USER") == true) // case-insensitive
        #expect(node.matches(searchText: "xyz") == false)
    }

    @Test("matches by string value")
    func matchesByStringValue() {
        let node = JSONNode(key: "key", value: .string("Hello World"))
        #expect(node.matches(searchText: "hello") == true)
        #expect(node.matches(searchText: "world") == true)
        #expect(node.matches(searchText: "missing") == false)
    }

    @Test("matches by number value")
    func matchesByNumber() {
        let intNode = JSONNode(key: "count", value: .number(42))
        #expect(intNode.matches(searchText: "42") == true)
        #expect(intNode.matches(searchText: "43") == false)

        let floatNode = JSONNode(key: "price", value: .number(3.14))
        #expect(floatNode.matches(searchText: "3.14") == true)
    }

    @Test("matches by boolean value")
    func matchesByBool() {
        let trueNode = JSONNode(key: "flag", value: .bool(true))
        #expect(trueNode.matches(searchText: "true") == true)
        #expect(trueNode.matches(searchText: "tru") == true)
        #expect(trueNode.matches(searchText: "false") == false)
    }

    @Test("matches by null value")
    func matchesByNull() {
        let nullNode = JSONNode(key: "empty", value: .null)
        #expect(nullNode.matches(searchText: "null") == true)
        #expect(nullNode.matches(searchText: "nul") == true)
        #expect(nullNode.matches(searchText: "nil") == false)
    }

    @Test("Container nodes don't match by value")
    func containerNoMatch() {
        let objNode = JSONNode(value: .object(["key": .string("val")]))
        #expect(objNode.matches(searchText: "key") == false) // no key on root
        #expect(objNode.matches(searchText: "val") == false)  // doesn't search children
    }

    // MARK: - expandPathTo

    @Test("expandPathTo expands ancestors to target node")
    func expandPathTo() {
        let value = JSONValue.object([
            "a": .object([
                "b": .object([
                    "c": .string("target")
                ])
            ])
        ])
        let root = JSONNode(value: value, defaultFoldDepth: 0) // all collapsed

        let target = root.children[0].children[0].children[0] // "c" node
        root.expandPathTo(node: target)

        #expect(root.isExpanded == true)
        #expect(root.children[0].isExpanded == true)
        #expect(root.children[0].children[0].isExpanded == true)
    }

    // MARK: - Parent Reference

    @Test("Root node parent is nil")
    func rootParentNil() {
        let node = JSONNode(value: .object(["key": .string("value")]))
        #expect(node.parent == nil)
    }

    @Test("Object children have parent set")
    func objectChildrenParent() {
        let node = JSONNode(value: .object([
            "a": .string("1"),
            "b": .string("2")
        ]))
        for child in node.children {
            #expect(child.parent === node)
        }
    }

    @Test("Array children have parent set")
    func arrayChildrenParent() {
        let node = JSONNode(value: .array([.string("a"), .string("b")]))
        for child in node.children {
            #expect(child.parent === node)
        }
    }

    @Test("Nested children have correct parent chain")
    func nestedParentChain() {
        let value = JSONValue.object([
            "level1": .object([
                "level2": .string("deep")
            ])
        ])
        let root = JSONNode(value: value)
        let level1 = root.children[0]
        let level2 = level1.children[0]

        #expect(root.parent == nil)
        #expect(level1.parent === root)
        #expect(level2.parent === level1)
    }

    // MARK: - Display Values

    @Test("displayValue for all types")
    func displayValues() {
        #expect(JSONNode(value: .string("hello")).displayValue == "\"hello\"")
        #expect(JSONNode(value: .number(42)).displayValue == "42")
        #expect(JSONNode(value: .number(3.14)).displayValue == "3.14")
        #expect(JSONNode(value: .bool(true)).displayValue == "true")
        #expect(JSONNode(value: .bool(false)).displayValue == "false")
        #expect(JSONNode(value: .null).displayValue == "null")
        #expect(JSONNode(value: .object(["a": .null, "b": .null])).displayValue == "{ 2 keys }")
        #expect(JSONNode(value: .array([.null, .null, .null])).displayValue == "[ 3 elements ]")
    }

    @Test("copyValue for leaf types")
    func copyValues() {
        #expect(JSONNode(value: .string("hello")).copyValue == "\"hello\"")
        #expect(JSONNode(value: .number(42)).copyValue == "42")
        #expect(JSONNode(value: .bool(true)).copyValue == "true")
        #expect(JSONNode(value: .null).copyValue == "null")
    }
}

// MARK: - JSONValue Tests

@Suite("JSONValue Tests")
struct JSONValueTests {

    @Test("typeDescription")
    func typeDescription() {
        #expect(JSONValue.string("").typeDescription == "string")
        #expect(JSONValue.number(0).typeDescription == "number")
        #expect(JSONValue.bool(true).typeDescription == "boolean")
        #expect(JSONValue.null.typeDescription == "null")
        #expect(JSONValue.object([:]).typeDescription == "object")
        #expect(JSONValue.array([]).typeDescription == "array")
    }

    @Test("isContainer")
    func isContainer() {
        #expect(JSONValue.object([:]).isContainer == true)
        #expect(JSONValue.array([]).isContainer == true)
        #expect(JSONValue.string("").isContainer == false)
        #expect(JSONValue.number(0).isContainer == false)
        #expect(JSONValue.bool(true).isContainer == false)
        #expect(JSONValue.null.isContainer == false)
    }

    @Test("childCount")
    func childCount() {
        #expect(JSONValue.object(["a": .null, "b": .null]).childCount == 2)
        #expect(JSONValue.array([.null, .null, .null]).childCount == 3)
        #expect(JSONValue.string("hello").childCount == 0)
        #expect(JSONValue.object([:]).childCount == 0)
        #expect(JSONValue.array([]).childCount == 0)
    }

    @Test("Equatable conformance")
    func equatable() {
        #expect(JSONValue.string("a") == JSONValue.string("a"))
        #expect(JSONValue.string("a") != JSONValue.string("b"))
        #expect(JSONValue.number(1) == JSONValue.number(1))
        #expect(JSONValue.bool(true) == JSONValue.bool(true))
        #expect(JSONValue.bool(true) != JSONValue.bool(false))
        #expect(JSONValue.null == JSONValue.null)
        #expect(JSONValue.string("a") != JSONValue.number(1))
    }

    @Test("toJSONString for object")
    func toJSONStringObject() {
        let value = JSONValue.object(["key": .string("value")])
        let jsonString = value.toJSONString(prettyPrinted: false)
        #expect(jsonString != nil)
        #expect(jsonString!.contains("key"))
        #expect(jsonString!.contains("value"))
    }

    @Test("toJSONString for array")
    func toJSONStringArray() {
        let value = JSONValue.array([.number(1), .number(2)])
        let jsonString = value.toJSONString(prettyPrinted: false)
        #expect(jsonString != nil)
        #expect(jsonString!.contains("1"))
        #expect(jsonString!.contains("2"))
    }
}
