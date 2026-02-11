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

    // Tabs (dynamic — read from AppSettings)
    static var newTab: ShortcutKey { ShortcutKey(from: AppSettings.shared.newTabHotKey) }
    static var closeTab: ShortcutKey { ShortcutKey(from: AppSettings.shared.closeTabHotKey) }
    static var previousTab: ShortcutKey { ShortcutKey(from: AppSettings.shared.previousTabHotKey) }
    static var nextTab: ShortcutKey { ShortcutKey(from: AppSettings.shared.nextTabHotKey) }

    // View (dynamic)
    static let find         = ShortcutKey(display: "F", modifiers: [.command], keyEquivalent: "f")
    static var beautifyMode: ShortcutKey { ShortcutKey(from: AppSettings.shared.beautifyModeHotKey) }
    static var treeMode: ShortcutKey { ShortcutKey(from: AppSettings.shared.treeModeHotKey) }

    // Search (dynamic)
    static var findNext: ShortcutKey { ShortcutKey(from: AppSettings.shared.findNextHotKey) }
    static var findPrevious: ShortcutKey { ShortcutKey(from: AppSettings.shared.findPreviousHotKey) }

    // Edit (fixed)
    static let undo         = ShortcutKey(display: "Z", modifiers: [.command], keyEquivalent: "z")
    static let redo         = ShortcutKey(display: "Z", modifiers: [.command, .shift], keyEquivalent: "Z")
    static let cut          = ShortcutKey(display: "X", modifiers: [.command], keyEquivalent: "x")
    static let copy         = ShortcutKey(display: "C", modifiers: [.command], keyEquivalent: "c")
    static let paste        = ShortcutKey(display: "V", modifiers: [.command], keyEquivalent: "v")
    static let selectAll    = ShortcutKey(display: "A", modifiers: [.command], keyEquivalent: "a")
}

#endif
