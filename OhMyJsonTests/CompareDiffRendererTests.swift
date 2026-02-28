//
//  CompareDiffRendererTests.swift
//  OhMyJsonTests
//
//  Tests for CompareDiffRenderer line-path mapping and diff assignment.
//

import Foundation
import Testing
@testable import OhMyJson

@Suite("CompareDiffRenderer Tests")
struct CompareDiffRendererTests {

    // MARK: - extractKey Tests

    @Test("Extracts key from simple key-value line")
    func extractKeySimple() {
        #expect(CompareDiffRenderer.extractKey(from: "\"name\" : \"Alice\"") == "name")
    }

    @Test("Extracts key from key-object line")
    func extractKeyObject() {
        #expect(CompareDiffRenderer.extractKey(from: "\"app\" : {") == "app")
    }

    @Test("Extracts key from key-array line")
    func extractKeyArray() {
        #expect(CompareDiffRenderer.extractKey(from: "\"items\" : [") == "items")
    }

    @Test("Returns nil for standalone brace")
    func extractKeyBrace() {
        #expect(CompareDiffRenderer.extractKey(from: "{") == nil)
    }

    @Test("Returns nil for closing brace")
    func extractKeyClosingBrace() {
        #expect(CompareDiffRenderer.extractKey(from: "},") == nil)
    }

    @Test("Returns nil for bare value")
    func extractKeyBareValue() {
        #expect(CompareDiffRenderer.extractKey(from: "42,") == nil)
    }

    @Test("Returns nil for bare string value in array")
    func extractKeyBareString() {
        #expect(CompareDiffRenderer.extractKey(from: "\"hello\",") == nil)
    }

    @Test("Handles escaped quotes in key")
    func extractKeyEscapedQuotes() {
        #expect(CompareDiffRenderer.extractKey(from: "\"key\\\"name\" : 1") == "key\\\"name")
    }

    // MARK: - buildLinePathMap Tests

    @Test("Simple flat object")
    func linePathSimpleObject() {
        let lines = [
            "{",
            "    \"age\" : 30,",
            "    \"name\" : \"Alice\"",
            "}"
        ]
        let paths = CompareDiffRenderer.buildLinePathMap(lines: lines)
        #expect(paths[0] == [])           // {
        #expect(paths[1] == ["age"])      // "age" : 30  (sortedKeys: age before name)
        #expect(paths[2] == ["name"])     // "name" : "Alice"
        #expect(paths[3] == [])           // }
    }

    @Test("Nested object")
    func linePathNestedObject() {
        let lines = [
            "{",
            "    \"app\" : {",
            "        \"id\" : 1,",
            "        \"version\" : \"1.0.0\"",
            "    }",
            "}"
        ]
        let paths = CompareDiffRenderer.buildLinePathMap(lines: lines)
        #expect(paths[0] == [])                      // {
        #expect(paths[1] == ["app"])                  // "app" : {
        #expect(paths[2] == ["app", "id"])            // "id" : 1
        #expect(paths[3] == ["app", "version"])       // "version" : "1.0.0"
        #expect(paths[4] == ["app"])                  // }
        #expect(paths[5] == [])                       // }
    }

    @Test("Array with primitives")
    func linePathArrayPrimitives() {
        let lines = [
            "[",
            "    1,",
            "    2,",
            "    3",
            "]"
        ]
        let paths = CompareDiffRenderer.buildLinePathMap(lines: lines)
        #expect(paths[0] == [])       // [
        #expect(paths[1] == ["0"])    // 1
        #expect(paths[2] == ["1"])    // 2
        #expect(paths[3] == ["2"])    // 3
        #expect(paths[4] == [])       // ]
    }

    @Test("Array with objects")
    func linePathArrayObjects() {
        let lines = [
            "{",
            "    \"items\" : [",
            "        {",
            "            \"name\" : \"A\"",
            "        },",
            "        {",
            "            \"name\" : \"B\"",
            "        }",
            "    ]",
            "}"
        ]
        let paths = CompareDiffRenderer.buildLinePathMap(lines: lines)
        #expect(paths[0] == [])                          // {
        #expect(paths[1] == ["items"])                    // "items" : [
        #expect(paths[2] == ["items", "0"])               // {
        #expect(paths[3] == ["items", "0", "name"])       // "name" : "A"
        #expect(paths[4] == ["items", "0"])               // }
        #expect(paths[5] == ["items", "1"])               // {
        #expect(paths[6] == ["items", "1", "name"])       // "name" : "B"
        #expect(paths[7] == ["items", "1"])               // }
        #expect(paths[8] == ["items"])                    // ]
        #expect(paths[9] == [])                           // }
    }

    @Test("Root array")
    func linePathRootArray() {
        let lines = [
            "[",
            "    {",
            "        \"id\" : 1",
            "    }",
            "]"
        ]
        let paths = CompareDiffRenderer.buildLinePathMap(lines: lines)
        #expect(paths[0] == [])           // [
        #expect(paths[1] == ["0"])        // {
        #expect(paths[2] == ["0", "id"])  // "id" : 1
        #expect(paths[3] == ["0"])        // }
        #expect(paths[4] == [])           // ]
    }

    @Test("Deep nesting")
    func linePathDeepNesting() {
        let lines = [
            "{",
            "    \"a\" : {",
            "        \"b\" : {",
            "            \"c\" : 1",
            "        }",
            "    }",
            "}"
        ]
        let paths = CompareDiffRenderer.buildLinePathMap(lines: lines)
        #expect(paths[3] == ["a", "b", "c"])  // deep nested value
        #expect(paths[4] == ["a", "b"])        // closing }
        #expect(paths[5] == ["a"])             // closing }
    }

    @Test("Empty object")
    func linePathEmptyObject() {
        let lines = [
            "{",
            "}"
        ]
        let paths = CompareDiffRenderer.buildLinePathMap(lines: lines)
        #expect(paths[0] == [])
        #expect(paths[1] == [])
    }

    // MARK: - Core Bug Reproduction Tests

    @Test("Key rename: id changed should not highlight version line")
    func keyRenameDoesNotHighlightWrongLine() {
        // This is the exact bug scenario: changing "id" key should only highlight
        // the "id" line, not the "version" line.
        let leftJSON = """
        {"app": {"id": 1, "version": "1.0.0"}}
        """
        let rightJSON = """
        {"app": {"name": 1, "version": "1.0.0"}}
        """
        let engine = JSONDiffEngine.shared
        let leftValue = parseJSONValue(leftJSON)!
        let rightValue = parseJSONValue(rightJSON)!
        let diffResult = engine.compare(left: leftValue, right: rightValue, options: CompareOptions())

        let result = CompareDiffRenderer.buildRenderResult(
            leftJSON: leftJSON,
            rightJSON: rightJSON,
            diffResult: diffResult
        )

        // Find the "version" line — it must be unchanged on both sides
        for line in result.leftLines {
            if line.text.contains("version") {
                #expect(line.type == .content(.unchanged),
                        "Left 'version' line should be unchanged, got \(line.type)")
            }
        }
        for line in result.rightLines {
            if line.text.contains("version") {
                #expect(line.type == .content(.unchanged),
                        "Right 'version' line should be unchanged, got \(line.type)")
            }
        }

        // The "id" line should be marked as removed on left
        let leftIdLine = result.leftLines.first { $0.text.contains("\"id\"") }
        #expect(leftIdLine != nil, "Should have an 'id' line on left")
        #expect(leftIdLine?.type == .content(.removed))

        // The "name" line should be marked as added on right
        let rightNameLine = result.rightLines.first { $0.text.contains("\"name\"") }
        #expect(rightNameLine != nil, "Should have a 'name' line on right")
        #expect(rightNameLine?.type == .content(.added))
    }

    @Test("Numeric value collision: different paths with overlapping values")
    func numericValueCollision() {
        // "id": 1 and "version": "1.0.0" both contain "1" in text.
        // Only "id" is changed — "version" must stay unchanged.
        let leftJSON = """
        {"id": 1, "version": "1.0.0"}
        """
        let rightJSON = """
        {"id": 2, "version": "1.0.0"}
        """
        let engine = JSONDiffEngine.shared
        let leftValue = parseJSONValue(leftJSON)!
        let rightValue = parseJSONValue(rightJSON)!
        let diffResult = engine.compare(left: leftValue, right: rightValue, options: CompareOptions())

        let result = CompareDiffRenderer.buildRenderResult(
            leftJSON: leftJSON,
            rightJSON: rightJSON,
            diffResult: diffResult
        )

        for line in result.leftLines {
            if line.text.contains("version") {
                #expect(line.type == .content(.unchanged))
            }
        }
        for line in result.rightLines {
            if line.text.contains("version") {
                #expect(line.type == .content(.unchanged))
            }
        }
    }

    @Test("Same value different paths: only changed path is highlighted")
    func sameValueDifferentPaths() {
        // Both "a" and "b" have value 1, but only "b" changes.
        let leftJSON = """
        {"a": 1, "b": 1}
        """
        let rightJSON = """
        {"a": 1, "b": 2}
        """
        let engine = JSONDiffEngine.shared
        let leftValue = parseJSONValue(leftJSON)!
        let rightValue = parseJSONValue(rightJSON)!
        let diffResult = engine.compare(left: leftValue, right: rightValue, options: CompareOptions())

        let result = CompareDiffRenderer.buildRenderResult(
            leftJSON: leftJSON,
            rightJSON: rightJSON,
            diffResult: diffResult
        )

        // "a" line should be unchanged on both sides
        for line in result.leftLines {
            if line.text.contains("\"a\"") {
                #expect(line.type == .content(.unchanged),
                        "Left 'a' line should be unchanged")
            }
        }

        // "b" line should be modified on both sides
        let leftBLine = result.leftLines.first { $0.text.contains("\"b\"") }
        #expect(leftBLine?.type == .content(.modified))
        let rightBLine = result.rightLines.first { $0.text.contains("\"b\"") }
        #expect(rightBLine?.type == .content(.modified))
    }

    // MARK: - Container Diff Tests

    @Test("Object added: all child lines highlighted")
    func objectAdded() {
        let leftJSON = """
        {"name": "test"}
        """
        let rightJSON = """
        {"info": {"id": 1, "type": "A"}, "name": "test"}
        """
        let engine = JSONDiffEngine.shared
        let leftValue = parseJSONValue(leftJSON)!
        let rightValue = parseJSONValue(rightJSON)!
        let diffResult = engine.compare(left: leftValue, right: rightValue, options: CompareOptions())

        let result = CompareDiffRenderer.buildRenderResult(
            leftJSON: leftJSON,
            rightJSON: rightJSON,
            diffResult: diffResult
        )

        // All "info" related lines on right should be added
        for line in result.rightLines {
            if case .content(let dt) = line.type {
                if line.text.contains("\"info\"") || line.text.contains("\"id\"") || line.text.contains("\"type\"") {
                    #expect(dt == .added, "Line '\(line.text.trimmingCharacters(in: .whitespaces))' should be added")
                }
            }
        }

        // "name" should be unchanged
        for line in result.rightLines {
            if line.text.contains("\"name\"") {
                #expect(line.type == .content(.unchanged))
            }
        }
    }

    @Test("Object removed: all child lines highlighted")
    func objectRemoved() {
        let leftJSON = """
        {"info": {"id": 1, "type": "A"}, "name": "test"}
        """
        let rightJSON = """
        {"name": "test"}
        """
        let engine = JSONDiffEngine.shared
        let leftValue = parseJSONValue(leftJSON)!
        let rightValue = parseJSONValue(rightJSON)!
        let diffResult = engine.compare(left: leftValue, right: rightValue, options: CompareOptions())

        let result = CompareDiffRenderer.buildRenderResult(
            leftJSON: leftJSON,
            rightJSON: rightJSON,
            diffResult: diffResult
        )

        // All "info" related lines on left should be removed
        for line in result.leftLines {
            if case .content(let dt) = line.type {
                if line.text.contains("\"info\"") || line.text.contains("\"id\"") || line.text.contains("\"type\"") {
                    #expect(dt == .removed, "Line '\(line.text.trimmingCharacters(in: .whitespaces))' should be removed")
                }
            }
        }
    }

    @Test("Array element added")
    func arrayElementAdded() {
        let leftJSON = """
        {"items": [1, 2]}
        """
        let rightJSON = """
        {"items": [1, 2, 3]}
        """
        let engine = JSONDiffEngine.shared
        let leftValue = parseJSONValue(leftJSON)!
        let rightValue = parseJSONValue(rightJSON)!
        let diffResult = engine.compare(left: leftValue, right: rightValue, options: CompareOptions())

        let result = CompareDiffRenderer.buildRenderResult(
            leftJSON: leftJSON,
            rightJSON: rightJSON,
            diffResult: diffResult
        )

        // The "3" line on right should be added
        let addedLine = result.rightLines.first {
            if case .content(.added) = $0.type { return true }
            return false
        }
        #expect(addedLine != nil, "Should have an added line for element '3'")
        #expect(addedLine?.text.trimmingCharacters(in: .whitespaces).hasPrefix("3") == true)
    }

    // MARK: - Edge Cases

    @Test("Identical JSON produces no diffs")
    func identicalJSON() {
        let json = """
        {"a": 1, "b": [1, 2], "c": {"d": true}}
        """
        let engine = JSONDiffEngine.shared
        let value = parseJSONValue(json)!
        let diffResult = engine.compare(left: value, right: value, options: CompareOptions())

        let result = CompareDiffRenderer.buildRenderResult(
            leftJSON: json,
            rightJSON: json,
            diffResult: diffResult
        )

        // No line should have a diff type
        for line in result.leftLines {
            if case .content(let dt) = line.type {
                #expect(dt == .unchanged, "All left lines should be unchanged")
            }
        }
        for line in result.rightLines {
            if case .content(let dt) = line.type {
                #expect(dt == .unchanged, "All right lines should be unchanged")
            }
        }
    }

    @Test("Modified value marked on both sides")
    func modifiedValueBothSides() {
        let leftJSON = """
        {"key": "old"}
        """
        let rightJSON = """
        {"key": "new"}
        """
        let engine = JSONDiffEngine.shared
        let leftValue = parseJSONValue(leftJSON)!
        let rightValue = parseJSONValue(rightJSON)!
        let diffResult = engine.compare(left: leftValue, right: rightValue, options: CompareOptions())

        let result = CompareDiffRenderer.buildRenderResult(
            leftJSON: leftJSON,
            rightJSON: rightJSON,
            diffResult: diffResult
        )

        let leftKeyLine = result.leftLines.first { $0.text.contains("\"key\"") }
        #expect(leftKeyLine?.type == .content(.modified))

        let rightKeyLine = result.rightLines.first { $0.text.contains("\"key\"") }
        #expect(rightKeyLine?.type == .content(.modified))
    }

    // MARK: - Container Key Rename Tests

    @Test("Array key rename: only key line highlighted, child elements unchanged")
    func arrayKeyRenameOnlyKeyLine() {
        let leftJSON = """
        {"features": [1, 2, 3], "name": "test"}
        """
        let rightJSON = """
        {"feat~~res": [1, 2, 3], "name": "test"}
        """
        let engine = JSONDiffEngine.shared
        let leftValue = parseJSONValue(leftJSON)!
        let rightValue = parseJSONValue(rightJSON)!
        let diffResult = engine.compare(left: leftValue, right: rightValue, options: CompareOptions())

        let result = CompareDiffRenderer.buildRenderResult(
            leftJSON: leftJSON,
            rightJSON: rightJSON,
            diffResult: diffResult
        )

        // Left "features" key line should be removed
        let leftKeyLine = result.leftLines.first { $0.text.contains("\"features\"") }
        #expect(leftKeyLine != nil)
        #expect(leftKeyLine?.type == .content(.removed))

        // Right "feat~~res" key line should be added
        let rightKeyLine = result.rightLines.first { $0.text.contains("\"feat~~res\"") }
        #expect(rightKeyLine != nil)
        #expect(rightKeyLine?.type == .content(.added))

        // Array element lines (1, 2, 3) should be unchanged on both sides
        for line in result.leftLines {
            if case .content(let dt) = line.type {
                let trimmed = line.text.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("1") || trimmed.hasPrefix("2") || trimmed.hasPrefix("3") {
                    #expect(dt == .unchanged, "Left array element '\(trimmed)' should be unchanged")
                }
            }
        }
        for line in result.rightLines {
            if case .content(let dt) = line.type {
                let trimmed = line.text.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("1") || trimmed.hasPrefix("2") || trimmed.hasPrefix("3") {
                    #expect(dt == .unchanged, "Right array element '\(trimmed)' should be unchanged")
                }
            }
        }
    }

    @Test("Object key rename: only key line highlighted, child properties unchanged")
    func objectKeyRenameOnlyKeyLine() {
        let leftJSON = """
        {"config": {"debug": true, "port": 8080}, "name": "app"}
        """
        let rightJSON = """
        {"name": "app", "settings": {"debug": true, "port": 8080}}
        """
        let engine = JSONDiffEngine.shared
        let leftValue = parseJSONValue(leftJSON)!
        let rightValue = parseJSONValue(rightJSON)!
        let diffResult = engine.compare(left: leftValue, right: rightValue, options: CompareOptions())

        let result = CompareDiffRenderer.buildRenderResult(
            leftJSON: leftJSON,
            rightJSON: rightJSON,
            diffResult: diffResult
        )

        // Left "config" key line should be removed
        let leftKeyLine = result.leftLines.first { $0.text.contains("\"config\"") }
        #expect(leftKeyLine != nil)
        #expect(leftKeyLine?.type == .content(.removed))

        // Right "settings" key line should be added
        let rightKeyLine = result.rightLines.first { $0.text.contains("\"settings\"") }
        #expect(rightKeyLine != nil)
        #expect(rightKeyLine?.type == .content(.added))

        // Child properties "debug" and "port" should be unchanged on both sides
        for line in result.leftLines {
            if case .content(let dt) = line.type {
                if line.text.contains("\"debug\"") || line.text.contains("\"port\"") {
                    #expect(dt == .unchanged, "Left child '\(line.text.trimmingCharacters(in: .whitespaces))' should be unchanged")
                }
            }
        }
        for line in result.rightLines {
            if case .content(let dt) = line.type {
                if line.text.contains("\"debug\"") || line.text.contains("\"port\"") {
                    #expect(dt == .unchanged, "Right child '\(line.text.trimmingCharacters(in: .whitespaces))' should be unchanged")
                }
            }
        }
    }

    @Test("Key rename with value change: subtree fully highlighted (no rename detection)")
    func keyRenameWithValueChange() {
        let leftJSON = """
        {"features": [1, 2, 3], "name": "test"}
        """
        let rightJSON = """
        {"feat~~res": [1, 2, 99], "name": "test"}
        """
        let engine = JSONDiffEngine.shared
        let leftValue = parseJSONValue(leftJSON)!
        let rightValue = parseJSONValue(rightJSON)!
        let diffResult = engine.compare(left: leftValue, right: rightValue, options: CompareOptions())

        let result = CompareDiffRenderer.buildRenderResult(
            leftJSON: leftJSON,
            rightJSON: rightJSON,
            diffResult: diffResult
        )

        // When values differ, rename detection should NOT trigger.
        // All lines under "features"/"feat~~res" should be highlighted.
        var leftHighlightedCount = 0
        for line in result.leftLines {
            if case .content(let dt) = line.type, dt == .removed {
                if line.text.contains("\"features\"") || line.text.contains("1") ||
                    line.text.contains("2") || line.text.contains("3") {
                    leftHighlightedCount += 1
                }
            }
        }
        // At minimum the key line + array elements should be highlighted
        #expect(leftHighlightedCount >= 2, "Multiple left lines should be removed when values differ")

        var rightHighlightedCount = 0
        for line in result.rightLines {
            if case .content(let dt) = line.type, dt == .added {
                if line.text.contains("\"feat~~res\"") || line.text.contains("1") ||
                    line.text.contains("2") || line.text.contains("99") {
                    rightHighlightedCount += 1
                }
            }
        }
        #expect(rightHighlightedCount >= 2, "Multiple right lines should be added when values differ")
    }

    @Test("Multiple key renames: each detected independently")
    func multipleKeyRenames() {
        let leftJSON = """
        {"alpha": [1], "beta": {"x": true}}
        """
        let rightJSON = """
        {"alpha2": [1], "beta2": {"x": true}}
        """
        let engine = JSONDiffEngine.shared
        let leftValue = parseJSONValue(leftJSON)!
        let rightValue = parseJSONValue(rightJSON)!
        let diffResult = engine.compare(left: leftValue, right: rightValue, options: CompareOptions())

        let result = CompareDiffRenderer.buildRenderResult(
            leftJSON: leftJSON,
            rightJSON: rightJSON,
            diffResult: diffResult
        )

        // Key lines should be highlighted
        let leftAlpha = result.leftLines.first { $0.text.contains("\"alpha\"") }
        #expect(leftAlpha?.type == .content(.removed))
        let leftBeta = result.leftLines.first { $0.text.contains("\"beta\"") }
        #expect(leftBeta?.type == .content(.removed))

        let rightAlpha2 = result.rightLines.first { $0.text.contains("\"alpha2\"") }
        #expect(rightAlpha2?.type == .content(.added))
        let rightBeta2 = result.rightLines.first { $0.text.contains("\"beta2\"") }
        #expect(rightBeta2?.type == .content(.added))

        // Child content should be unchanged
        for line in result.leftLines {
            if case .content(let dt) = line.type {
                let trimmed = line.text.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("1") || line.text.contains("\"x\"") {
                    #expect(dt == .unchanged, "Left child '\(trimmed)' should be unchanged")
                }
            }
        }
        for line in result.rightLines {
            if case .content(let dt) = line.type {
                let trimmed = line.text.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("1") || line.text.contains("\"x\"") {
                    #expect(dt == .unchanged, "Right child '\(trimmed)' should be unchanged")
                }
            }
        }
    }

    // MARK: - Helpers

    private func parseJSONValue(_ text: String) -> JSONValue? {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return jsonValueFromAny(obj)
    }

    private func jsonValueFromAny(_ value: Any) -> JSONValue {
        switch value {
        case let s as String:
            return .string(s)
        case let n as NSNumber:
            if CFBooleanGetTypeID() == CFGetTypeID(n) {
                return .bool(n.boolValue)
            }
            return .number(n.doubleValue)
        case let arr as [Any]:
            return .array(arr.map { jsonValueFromAny($0) })
        case let dict as [String: Any]:
            return .object(dict.mapValues { jsonValueFromAny($0) })
        case is NSNull:
            return .null
        default:
            return .null
        }
    }
}
