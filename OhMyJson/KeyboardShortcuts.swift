//
//  KeyboardShortcuts.swift
//  OhMyJson
//

#if os(macOS)
import AppKit

// MARK: - ShortcutKey

struct ShortcutKey {
    let display: String
    let modifiers: NSEvent.ModifierFlags
    let keyEquivalent: String

    var displayString: String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option)  { symbols += "⌥" }
        if modifiers.contains(.shift)   { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        return symbols + display
    }

    init(display: String, modifiers: NSEvent.ModifierFlags, keyEquivalent: String) {
        self.display = display
        self.modifiers = modifiers
        self.keyEquivalent = keyEquivalent
    }

    init(from combo: HotKeyCombo) {
        self.display = combo.displayLabels.last ?? ""
        self.modifiers = combo.nsEventModifierFlags
        self.keyEquivalent = combo.keyEquivalent
    }
}

// MARK: - AppShortcut

enum AppShortcut {
    // General (fixed)
    static let settings     = ShortcutKey(display: ",", modifiers: [.command], keyEquivalent: ",")
    static let quit         = ShortcutKey(display: "Q", modifiers: [.command], keyEquivalent: "q")

    // Tabs
    static let newTab       = ShortcutKey(display: "N", modifiers: [.command], keyEquivalent: "n")
    static let closeTab     = ShortcutKey(display: "W", modifiers: [.command], keyEquivalent: "w")
    static let previousTab  = ShortcutKey(display: "[", modifiers: [.command, .shift], keyEquivalent: "[")
    static let nextTab      = ShortcutKey(display: "]", modifiers: [.command, .shift], keyEquivalent: "]")

    // View
    static let find         = ShortcutKey(display: "F", modifiers: [.command], keyEquivalent: "f")
    static let beautifyMode = ShortcutKey(display: "1", modifiers: [.command], keyEquivalent: "1")
    static let treeMode     = ShortcutKey(display: "2", modifiers: [.command], keyEquivalent: "2")
    static let compareMode  = ShortcutKey(display: "3", modifiers: [.command], keyEquivalent: "3")

    // Tree
    static let expandAll    = ShortcutKey(display: "+", modifiers: [.command, .shift], keyEquivalent: "+")
    static let collapseAll  = ShortcutKey(display: "-", modifiers: [.command, .shift], keyEquivalent: "-")

    // Search
    static let findNext     = ShortcutKey(display: "G", modifiers: [.command], keyEquivalent: "g")
    static let findPrevious = ShortcutKey(display: "G", modifiers: [.command, .shift], keyEquivalent: "G")

    // Edit (fixed)
    static let undo         = ShortcutKey(display: "Z", modifiers: [.command], keyEquivalent: "z")
    static let redo         = ShortcutKey(display: "Z", modifiers: [.command, .shift], keyEquivalent: "Z")
    static let cut          = ShortcutKey(display: "X", modifiers: [.command], keyEquivalent: "x")
    static let copy         = ShortcutKey(display: "C", modifiers: [.command], keyEquivalent: "c")
    static let paste        = ShortcutKey(display: "V", modifiers: [.command], keyEquivalent: "v")
    static let selectAll    = ShortcutKey(display: "A", modifiers: [.command], keyEquivalent: "a")
}

#endif
