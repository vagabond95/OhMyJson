//
//  KeyboardShortcutTests.swift
//  OhMyJsonTests
//

import Testing
import AppKit
@testable import OhMyJson

@Suite("KeyboardShortcut Tests")
struct KeyboardShortcutTests {

    // MARK: - ShortcutKey displayString

    @Test("Command-only modifier displays ⌘")
    func commandOnly() {
        let key = ShortcutKey(display: "N", modifiers: [.command], keyEquivalent: "n")
        #expect(key.displayString == "⌘N")
    }

    @Test("Command+Shift modifiers display ⇧⌘")
    func commandShift() {
        let key = ShortcutKey(display: "[", modifiers: [.command, .shift], keyEquivalent: "[")
        #expect(key.displayString == "⇧⌘[")
    }

    @Test("Control+Option+Command modifiers display ⌃⌥⌘")
    func controlOptionCommand() {
        let key = ShortcutKey(display: "J", modifiers: [.control, .option, .command], keyEquivalent: "j")
        #expect(key.displayString == "⌃⌥⌘J")
    }

    @Test("All four modifiers display ⌃⌥⇧⌘")
    func allModifiers() {
        let key = ShortcutKey(display: "X", modifiers: [.control, .option, .shift, .command], keyEquivalent: "x")
        #expect(key.displayString == "⌃⌥⇧⌘X")
    }

    @Test("No modifiers displays key only")
    func noModifiers() {
        let key = ShortcutKey(display: "A", modifiers: [], keyEquivalent: "a")
        #expect(key.displayString == "A")
    }

    // MARK: - AppShortcut Definitions

    @Test("AppShortcut.settings displays ⌘,")
    func settingsShortcut() {
        #expect(AppShortcut.settings.displayString == "⌘,")
        #expect(AppShortcut.settings.keyEquivalent == ",")
    }

    @Test("AppShortcut.quit displays ⌘Q")
    func quitShortcut() {
        #expect(AppShortcut.quit.displayString == "⌘Q")
        #expect(AppShortcut.quit.keyEquivalent == "q")
    }

    @Test("AppShortcut.newTab displays ⌘N")
    func newTabShortcut() {
        #expect(AppShortcut.newTab.displayString == "⌘N")
        #expect(AppShortcut.newTab.keyEquivalent == "n")
    }

    @Test("AppShortcut.closeTab displays ⌘W")
    func closeTabShortcut() {
        #expect(AppShortcut.closeTab.displayString == "⌘W")
        #expect(AppShortcut.closeTab.keyEquivalent == "w")
    }

    @Test("AppShortcut.previousTab displays ⇧⌘[")
    func previousTabShortcut() {
        #expect(AppShortcut.previousTab.displayString == "⇧⌘[")
        #expect(AppShortcut.previousTab.keyEquivalent == "[")
        #expect(AppShortcut.previousTab.modifiers == [.command, .shift])
    }

    @Test("AppShortcut.nextTab displays ⇧⌘]")
    func nextTabShortcut() {
        #expect(AppShortcut.nextTab.displayString == "⇧⌘]")
        #expect(AppShortcut.nextTab.keyEquivalent == "]")
        #expect(AppShortcut.nextTab.modifiers == [.command, .shift])
    }

    @Test("AppShortcut.find displays ⌘F")
    func findShortcut() {
        #expect(AppShortcut.find.displayString == "⌘F")
    }

    @Test("AppShortcut.findNext displays ⌘G")
    func findNextShortcut() {
        #expect(AppShortcut.findNext.displayString == "⌘G")
        #expect(AppShortcut.findNext.modifiers == [.command])
    }

    @Test("AppShortcut.findPrevious displays ⇧⌘G")
    func findPreviousShortcut() {
        #expect(AppShortcut.findPrevious.displayString == "⇧⌘G")
        #expect(AppShortcut.findPrevious.modifiers == [.command, .shift])
    }

    @Test("AppShortcut.beautifyMode displays ⌘1")
    func beautifyModeShortcut() {
        #expect(AppShortcut.beautifyMode.displayString == "⌘1")
    }

    @Test("AppShortcut.treeMode displays ⌘2")
    func treeModeShortcut() {
        #expect(AppShortcut.treeMode.displayString == "⌘2")
    }

    @Test("AppShortcut.undo displays ⌘Z")
    func undoShortcut() {
        #expect(AppShortcut.undo.displayString == "⌘Z")
    }

    @Test("AppShortcut.redo displays ⇧⌘Z")
    func redoShortcut() {
        #expect(AppShortcut.redo.displayString == "⇧⌘Z")
        #expect(AppShortcut.redo.keyEquivalent == "Z")
    }

    @Test("Edit shortcuts have correct key equivalents")
    func editShortcuts() {
        #expect(AppShortcut.cut.displayString == "⌘X")
        #expect(AppShortcut.copy.displayString == "⌘C")
        #expect(AppShortcut.paste.displayString == "⌘V")
        #expect(AppShortcut.selectAll.displayString == "⌘A")
    }
}
