//
//  OrderedJSONObject.swift
//  OhMyJson
//

import Foundation

/// A dictionary wrapper that preserves insertion order of keys.
/// Used by `JSONValue.object` to maintain original JSON key ordering.
struct OrderedJSONObject {
    private(set) var orderedKeys: [String]
    private var storage: [String: JSONValue]

    init() {
        self.orderedKeys = []
        self.storage = [:]
    }

    /// Initialize with ordered key-value pairs. Duplicate keys: last value wins, first position kept.
    init(_ pairs: [(String, JSONValue)]) {
        self.orderedKeys = []
        self.storage = [:]
        for (key, value) in pairs {
            if storage[key] != nil {
                storage[key] = value
            } else {
                orderedKeys.append(key)
                storage[key] = value
            }
        }
    }

    var keys: [String] { orderedKeys }
    var count: Int { storage.count }
    var isEmpty: Bool { storage.isEmpty }

    subscript(key: String) -> JSONValue? {
        get { storage[key] }
        set {
            if let value = newValue {
                if storage[key] == nil {
                    orderedKeys.append(key)
                }
                storage[key] = value
            } else {
                storage.removeValue(forKey: key)
                orderedKeys.removeAll { $0 == key }
            }
        }
    }
}

// MARK: - Equatable (order-independent, JSON semantic equality)

extension OrderedJSONObject: Equatable {
    static func == (lhs: OrderedJSONObject, rhs: OrderedJSONObject) -> Bool {
        lhs.storage == rhs.storage
    }
}

// MARK: - Sequence (iterates in insertion order)

extension OrderedJSONObject: Sequence {
    func makeIterator() -> IndexingIterator<[(String, JSONValue)]> {
        orderedKeys.compactMap { key in
            storage[key].map { (key, $0) }
        }.makeIterator()
    }
}

// MARK: - ExpressibleByDictionaryLiteral

extension OrderedJSONObject: ExpressibleByDictionaryLiteral {
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        self.init(elements)
    }
}

// MARK: - Hashable (order-independent)

extension OrderedJSONObject: Hashable {
    func hash(into hasher: inout Hasher) {
        // Order-independent hash: XOR all key-value pair hashes
        var combined = 0
        for (key, value) in storage {
            var h = Hasher()
            h.combine(key)
            h.combine(value)
            combined ^= h.finalize()
        }
        hasher.combine(combined)
    }
}

// MARK: - JSONValue Hashable conformance

extension JSONValue: Hashable {
    func hash(into hasher: inout Hasher) {
        switch self {
        case .string(let s):
            hasher.combine(0)
            hasher.combine(s)
        case .number(let n):
            hasher.combine(1)
            hasher.combine(n)
        case .bool(let b):
            hasher.combine(2)
            hasher.combine(b)
        case .null:
            hasher.combine(3)
        case .object(let obj):
            hasher.combine(4)
            hasher.combine(obj)
        case .array(let arr):
            hasher.combine(5)
            hasher.combine(arr)
        }
    }
}
