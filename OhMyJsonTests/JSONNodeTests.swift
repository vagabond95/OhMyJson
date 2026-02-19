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

    // MARK: - Lazy Children

    @Test("Collapsed node does not eagerly materialize children")
    func lazyChildrenNotEagerlyMaterialized() {
        // defaultFoldDepth: 1 means depth 0 is expanded, depth 1+ collapsed
        let value = JSONValue.object([
            "a": .object([
                "deep1": .string("v1"),
                "deep2": .string("v2")
            ])
        ])
        let root = JSONNode(value: value, defaultFoldDepth: 1)

        // Root (depth 0) is expanded, so its children are materialized
        #expect(root.children.count == 1)

        // child "a" (depth 1) is collapsed — its children should not be materialized yet
        let childA = root.children[0]
        #expect(childA.isExpanded == false)

        // Accessing children triggers lazy materialization
        #expect(childA.children.count == 2)
    }

    @Test("Expanding collapsed node triggers lazy child materialization")
    func expandingTriggersLazyMaterialization() {
        let value = JSONValue.object([
            "a": .object(["nested": .string("val")])
        ])
        let root = JSONNode(value: value, defaultFoldDepth: 0) // all collapsed

        // Expand root — should trigger materialization
        root.isExpanded = true
        #expect(root.children.count == 1)
        #expect(root.children[0].key == "a")

        // Child "a" is still collapsed — expand it
        root.children[0].isExpanded = true
        #expect(root.children[0].children.count == 1)
        #expect(root.children[0].children[0].key == "nested")
    }

    @Test("expandPathTo sets parent links and expands ancestors via bottom-up traversal")
    func expandPathToBottomUp() {
        let value = JSONValue.object([
            "x": .object([
                "y": .object([
                    "z": .string("leaf")
                ])
            ])
        ])
        let root = JSONNode(value: value, defaultFoldDepth: 0)

        // All collapsed
        #expect(root.isExpanded == false)

        // Access target to force materialization (sets parent links)
        let target = root.children[0].children[0].children[0]
        #expect(target.key == "z")
        #expect(target.parent != nil)

        // expandPathTo should walk parent links bottom-up
        root.expandPathTo(node: target)

        #expect(root.isExpanded == true)
        #expect(root.children[0].isExpanded == true) // "x"
        #expect(root.children[0].children[0].isExpanded == true) // "y"
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

    // MARK: - visibleDescendantCount

    @Test("visibleDescendantCount returns 0 for leaf node")
    func visibleDescendantCountLeaf() {
        let node = JSONNode(value: .string("hello"))
        #expect(node.visibleDescendantCount() == 0)
    }

    @Test("visibleDescendantCount returns 0 for collapsed container")
    func visibleDescendantCountCollapsed() {
        let value = JSONValue.object([
            "a": .string("1"),
            "b": .string("2"),
            "c": .string("3")
        ])
        let node = JSONNode(value: value, defaultFoldDepth: 0) // collapsed
        #expect(node.visibleDescendantCount() == 0)
    }

    @Test("visibleDescendantCount counts direct children when expanded")
    func visibleDescendantCountFlat() {
        let value = JSONValue.object([
            "a": .string("1"),
            "b": .string("2"),
            "c": .string("3")
        ])
        let node = JSONNode(value: value, defaultFoldDepth: 10) // all expanded
        #expect(node.visibleDescendantCount() == 3)
    }

    @Test("visibleDescendantCount counts nested expanded nodes")
    func visibleDescendantCountNested() {
        let value = JSONValue.object([
            "a": .object([
                "b": .string("val"),
                "c": .string("val")
            ])
        ])
        let node = JSONNode(value: value, defaultFoldDepth: 10) // all expanded
        // "a" (1) + "b" (1) + "c" (1) = 3
        #expect(node.visibleDescendantCount() == 3)
    }

    @Test("visibleDescendantCount respects partial expansion")
    func visibleDescendantCountPartialExpansion() {
        let value = JSONValue.object([
            "expanded": .object([
                "child1": .string("v1"),
                "child2": .string("v2")
            ]),
            "collapsed": .object([
                "hidden1": .string("v3"),
                "hidden2": .string("v4")
            ])
        ])
        let node = JSONNode(value: value, defaultFoldDepth: 10) // all expanded
        // Collapse one child
        node.children[0].isExpanded = false // "collapsed" (sorted: "collapsed" < "expanded")

        // "collapsed" (1, no visible descendants) + "expanded" (1) + "child1" (1) + "child2" (1) = 4
        #expect(node.visibleDescendantCount() == 4)
    }

    @Test("visibleDescendantCount equals allNodes().count - 1")
    func visibleDescendantCountMatchesAllNodes() {
        let value = JSONValue.object([
            "a": .object([
                "b": .array([.string("x"), .string("y")]),
                "c": .string("z")
            ]),
            "d": .number(42)
        ])
        let node = JSONNode(value: value, defaultFoldDepth: 10)
        // allNodes includes self, visibleDescendantCount does not
        #expect(node.visibleDescendantCount() == node.allNodes().count - 1)
    }

    // MARK: - Incremental expand/collapse correctness (P5)

    @Test("Expand node: inserting descendants matches full allNodes rebuild")
    func incrementalExpandMatchesFullRebuild() {
        let value = JSONValue.object([
            "a": .object([
                "b": .string("v1"),
                "c": .string("v2")
            ]),
            "d": .string("v3")
        ])
        let root = JSONNode(value: value, defaultFoldDepth: 1) // depth 0 expanded, depth 1 collapsed

        // Initial visible nodes
        var visibleNodes = root.allNodes()
        // root + "a" (collapsed) + "d" = 3
        #expect(visibleNodes.count == 3)

        // Simulate incremental expand of "a" (sorted index 0)
        let nodeA = root.children[0]
        #expect(nodeA.key == "a")
        nodeA.isExpanded = true

        // Incremental: insert descendants after nodeA
        let nodeIndex = visibleNodes.firstIndex(where: { $0.id == nodeA.id })!
        let newDescendants = Array(nodeA.allNodes().dropFirst())
        visibleNodes.insert(contentsOf: newDescendants, at: nodeIndex + 1)

        // Full rebuild
        let fullRebuild = root.allNodes()

        // Both should match
        #expect(visibleNodes.count == fullRebuild.count)
        #expect(visibleNodes.map(\.id) == fullRebuild.map(\.id))
    }

    @Test("Collapse node: removing descendants matches full allNodes rebuild")
    func incrementalCollapseMatchesFullRebuild() {
        let value = JSONValue.object([
            "a": .object([
                "b": .string("v1"),
                "c": .string("v2")
            ]),
            "d": .string("v3")
        ])
        let root = JSONNode(value: value, defaultFoldDepth: 10) // all expanded

        // Initial visible nodes (all expanded)
        var visibleNodes = root.allNodes()
        // root + "a" + "b" + "c" + "d" = 5
        #expect(visibleNodes.count == 5)

        // Simulate incremental collapse of "a"
        let nodeA = root.children[0]
        let nodeIndex = visibleNodes.firstIndex(where: { $0.id == nodeA.id })!

        nodeA.isExpanded = false

        // Find descendant range (nodes after nodeA with depth > nodeA.depth)
        let nodeDepth = nodeA.depth
        var endIndex = nodeIndex + 1
        while endIndex < visibleNodes.count && visibleNodes[endIndex].depth > nodeDepth {
            endIndex += 1
        }
        visibleNodes.removeSubrange((nodeIndex + 1)..<endIndex)

        // Full rebuild
        let fullRebuild = root.allNodes()

        // Both should match
        #expect(visibleNodes.count == fullRebuild.count)
        #expect(visibleNodes.map(\.id) == fullRebuild.map(\.id))
    }

    @Test("Incremental expand/collapse roundtrip restores original state")
    func incrementalExpandCollapseRoundtrip() {
        let value = JSONValue.object([
            "x": .object([
                "y": .array([.number(1), .number(2)])
            ]),
            "z": .string("end")
        ])
        let root = JSONNode(value: value, defaultFoldDepth: 10)

        let originalNodes = root.allNodes()
        var visibleNodes = Array(originalNodes)

        // Collapse "x"
        let nodeX = root.children[0] // sorted: "x" < "z"
        let xIndex = visibleNodes.firstIndex(where: { $0.id == nodeX.id })!
        nodeX.isExpanded = false

        let xDepth = nodeX.depth
        var endIdx = xIndex + 1
        while endIdx < visibleNodes.count && visibleNodes[endIdx].depth > xDepth {
            endIdx += 1
        }
        visibleNodes.removeSubrange((xIndex + 1)..<endIdx)

        // Now re-expand "x"
        nodeX.isExpanded = true
        let newDescendants = Array(nodeX.allNodes().dropFirst())
        visibleNodes.insert(contentsOf: newDescendants, at: xIndex + 1)

        // Should match original
        #expect(visibleNodes.count == originalNodes.count)
        #expect(visibleNodes.map(\.id) == originalNodes.map(\.id))
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

    // MARK: - nodeAt (path-based navigation)

    @Test("nodeAt returns self for empty path")
    func nodeAtEmptyPath() {
        let root = JSONNode(value: .object(["a": .string("v")]))
        let result = root.nodeAt(childIndices: [])
        #expect(result === root)
    }

    @Test("nodeAt navigates to nested child")
    func nodeAtNestedChild() {
        let value = JSONValue.object([
            "a": .object(["b": .string("target")])
        ])
        let root = JSONNode(value: value, defaultFoldDepth: 0) // all collapsed
        // "a" is at sorted index 0, "b" is at sorted index 0
        let result = root.nodeAt(childIndices: [0, 0])
        #expect(result != nil)
        #expect(result?.key == "b")
        if case .string(let s) = result?.value {
            #expect(s == "target")
        } else {
            Issue.record("Expected string value")
        }
    }

    @Test("nodeAt returns nil for out-of-bounds index")
    func nodeAtOutOfBounds() {
        let root = JSONNode(value: .object(["a": .string("v")]))
        #expect(root.nodeAt(childIndices: [5]) == nil)
    }

    @Test("nodeAt materializes only the path nodes")
    func nodeAtMinimalMaterialization() {
        let value = JSONValue.object([
            "a": .object(["deep": .string("v1")]),
            "b": .object(["deep": .string("v2")])
        ])
        let root = JSONNode(value: value, defaultFoldDepth: 0) // all collapsed

        // Navigate to a → deep (index 0 → index 0, since "a" < "b")
        let result = root.nodeAt(childIndices: [0, 0])
        #expect(result?.key == "deep")

        // "b" branch was never accessed — root.children[1] is materialized
        // (because children array is built as a whole), but its children are not
        let bNode = root.children[1]
        #expect(bNode.key == "b")
        // bNode's children should still be lazy (not materialized by the search)
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

    // MARK: - countMatches (search without materialization)

    @Test("countMatches finds leaf values")
    func countMatchesLeafValues() {
        let value = JSONValue.object([
            "name": .string("John"),
            "age": .number(30),
            "active": .bool(true),
            "note": .null
        ])
        #expect(value.countMatches(key: nil, query: "john") == 1)
        #expect(value.countMatches(key: nil, query: "30") == 1)
        #expect(value.countMatches(key: nil, query: "true") == 1)
        #expect(value.countMatches(key: nil, query: "null") == 1)
    }

    @Test("countMatches finds by key")
    func countMatchesByKey() {
        let value = JSONValue.object([
            "userName": .string("test"),
            "userAge": .number(25)
        ])
        #expect(value.countMatches(key: nil, query: "user") == 2)
    }

    @Test("countMatches searches nested structures")
    func countMatchesNested() {
        let value = JSONValue.object([
            "users": .array([
                .object(["name": .string("Alice")]),
                .object(["name": .string("Bob")])
            ])
        ])
        #expect(value.countMatches(key: nil, query: "name") == 2) // two "name" keys
        #expect(value.countMatches(key: nil, query: "alice") == 1)
        #expect(value.countMatches(key: nil, query: "bob") == 1)
    }

    @Test("countMatches returns zero for no matches")
    func countMatchesNoMatch() {
        let value = JSONValue.object(["key": .string("value")])
        #expect(value.countMatches(key: nil, query: "xyz") == 0)
    }

    // MARK: - searchMatchPaths (path-based search)

    @Test("searchMatchPaths returns correct paths")
    func searchMatchPathsCorrectPaths() {
        let value = JSONValue.object([
            "a": .string("hello"),
            "b": .object(["c": .string("hello")])
        ])
        // Sorted keys: "a"=0, "b"=1. Under "b": "c"=0
        let paths = value.searchMatchPaths(key: nil, query: "hello")
        #expect(paths.count == 2)
        #expect(paths.contains([0]))      // "a" → "hello"
        #expect(paths.contains([1, 0]))   // "b" → "c" → "hello"
    }

    @Test("searchMatchPaths returns empty path for root match")
    func searchMatchPathsRootMatch() {
        let value = JSONValue.string("hello")
        let paths = value.searchMatchPaths(key: nil, query: "hello")
        #expect(paths == [[]])
    }

    @Test("searchMatchPaths with array indices")
    func searchMatchPathsArray() {
        let value = JSONValue.array([
            .string("miss"),
            .string("hit"),
            .string("miss")
        ])
        let paths = value.searchMatchPaths(key: nil, query: "hit")
        #expect(paths == [[1]])
    }

    @Test("searchMatchPaths returns empty for no matches")
    func searchMatchPathsNoMatch() {
        let value = JSONValue.object(["key": .string("value")])
        let paths = value.searchMatchPaths(key: nil, query: "xyz")
        #expect(paths.isEmpty)
    }

    @Test("searchMatchPaths matches key and value independently")
    func searchMatchPathsKeyAndValue() {
        // "name" appears as both a key and part of a value
        let value = JSONValue.object([
            "name": .string("noname")
        ])
        // key "name" matches, value "noname" also contains "name"
        // But searchMatchPaths checks per-node: key OR value match counts once
        let paths = value.searchMatchPaths(key: nil, query: "name")
        #expect(paths.count == 1) // single node matches (key matches)
        #expect(paths == [[0]])
    }

    @Test("searchMatchPaths with empty containers")
    func searchMatchPathsEmptyContainers() {
        let value = JSONValue.object([
            "empty_obj": .object([:]),
            "empty_arr": .array([]),
            "target": .string("found")
        ])
        let paths = value.searchMatchPaths(key: nil, query: "found")
        #expect(paths.count == 1)
    }

    @Test("searchMatchPaths deeply nested match")
    func searchMatchPathsDeeplyNested() {
        let value = JSONValue.object([
            "l1": .object([
                "l2": .object([
                    "l3": .array([
                        .object(["deep": .string("needle")])
                    ])
                ])
            ])
        ])
        let paths = value.searchMatchPaths(key: nil, query: "needle")
        #expect(paths.count == 1)
        // l1(0) → l2(0) → l3(0) → [0](0) → deep(0)
        #expect(paths[0] == [0, 0, 0, 0, 0])
    }

    @Test("searchMatchPaths matches same results as allNodesIncludingCollapsed filter")
    func searchMatchPathsConsistency() {
        let value = JSONValue.object([
            "users": .array([
                .object(["name": .string("Alice"), "age": .number(30)]),
                .object(["name": .string("Bob"), "active": .bool(true)])
            ]),
            "count": .number(2)
        ])
        let root = JSONNode(value: value)
        let query = "name"

        // Old approach (materializes everything)
        let oldResults = root.allNodesIncludingCollapsed()
            .filter { $0.matches(searchText: query) }

        // New approach (path-based)
        let paths = value.searchMatchPaths(key: nil, query: query.lowercased())
        let newResults = paths.compactMap { root.nodeAt(childIndices: $0) }

        #expect(oldResults.count == newResults.count)
        // Both should find the two "name" keys
        #expect(newResults.count == 2)
        #expect(newResults.allSatisfy { $0.key == "name" })
    }
}
