//
//  SelectableTextViewTests.swift
//  OhMyJsonTests
//

import Testing
import AppKit
import Carbon.HIToolbox
@testable import OhMyJson

#if os(macOS)
@Suite("DeselectOnResignTextView Key Equivalent Tests")
@MainActor
struct SelectableTextViewTests {

    private func makeEvent(
        keyCode: Int,
        characters: String,
        modifierFlags: NSEvent.ModifierFlags = [.command]
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: UInt16(keyCode)
        )!
    }

    /// Places the text view in a window and makes it the first responder.
    @discardableResult
    private func makeFirstResponder(_ textView: NSTextView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = textView
        window.makeFirstResponder(textView)
        return window
    }

    // MARK: - Handled cases (must return true — read-only view handles copy/selectAll)

    @Test("⌘C returns true — copy handled by read-only text view")
    func commandC_returnsTrue() {
        let textView = DeselectOnResignTextView()
        makeFirstResponder(textView)
        let event = makeEvent(keyCode: kVK_ANSI_C, characters: "c")

        let result = textView.performKeyEquivalent(with: event)

        #expect(result == true)
    }

    @Test("⌘A returns true — selectAll handled by read-only text view")
    func commandA_returnsTrue() {
        let textView = DeselectOnResignTextView()
        makeFirstResponder(textView)
        let event = makeEvent(keyCode: kVK_ANSI_A, characters: "a")

        let result = textView.performKeyEquivalent(with: event)

        #expect(result == true)
    }

    // MARK: - First responder guard (non-focused text view must not consume events)

    @Test("⌘C returns false when not first responder — allows other text views to handle it")
    func commandC_notFirstResponder_returnsFalse() {
        let textView = DeselectOnResignTextView()
        // No window/first responder setup — simulates unfocused state
        let event = makeEvent(keyCode: kVK_ANSI_C, characters: "c")

        let result = textView.performKeyEquivalent(with: event)

        #expect(result == false)
    }

    // MARK: - Bypass cases (must return false so menu items can handle them)

    @Test("⌘N returns false — bypasses to menu for New Tab")
    func commandN_returnsFalse() {
        let textView = DeselectOnResignTextView()
        let event = makeEvent(keyCode: kVK_ANSI_N, characters: "n")

        let result = textView.performKeyEquivalent(with: event)

        #expect(result == false)
    }

    @Test("⌘W returns false — bypasses to menu for Close Tab")
    func commandW_returnsFalse() {
        let textView = DeselectOnResignTextView()
        let event = makeEvent(keyCode: kVK_ANSI_W, characters: "w")

        let result = textView.performKeyEquivalent(with: event)

        #expect(result == false)
    }

    @Test("⌘F returns false — bypasses to menu for Find")
    func commandF_returnsFalse() {
        let textView = DeselectOnResignTextView()
        let event = makeEvent(keyCode: kVK_ANSI_F, characters: "f")

        let result = textView.performKeyEquivalent(with: event)

        #expect(result == false)
    }

    @Test("⌘1 returns false — bypasses to menu for Beautify mode")
    func command1_returnsFalse() {
        let textView = DeselectOnResignTextView()
        let event = makeEvent(keyCode: kVK_ANSI_1, characters: "1")

        let result = textView.performKeyEquivalent(with: event)

        #expect(result == false)
    }

    @Test("⌘2 returns false — bypasses to menu for Tree mode")
    func command2_returnsFalse() {
        let textView = DeselectOnResignTextView()
        let event = makeEvent(keyCode: kVK_ANSI_2, characters: "2")

        let result = textView.performKeyEquivalent(with: event)

        #expect(result == false)
    }

    @Test("⌘, returns false — bypasses to menu for Settings")
    func commandComma_returnsFalse() {
        let textView = DeselectOnResignTextView()
        let event = makeEvent(keyCode: kVK_ANSI_Comma, characters: ",")

        let result = textView.performKeyEquivalent(with: event)

        #expect(result == false)
    }

    @Test("⌘Q returns false — bypasses to menu for Quit")
    func commandQ_returnsFalse() {
        let textView = DeselectOnResignTextView()
        let event = makeEvent(keyCode: kVK_ANSI_Q, characters: "q")

        let result = textView.performKeyEquivalent(with: event)

        #expect(result == false)
    }

    @Test("⌘V returns false — paste not applicable to read-only view")
    func commandV_returnsFalse() {
        let textView = DeselectOnResignTextView()
        let event = makeEvent(keyCode: kVK_ANSI_V, characters: "v")

        let result = textView.performKeyEquivalent(with: event)

        #expect(result == false)
    }

    @Test("⌘X returns false — cut not applicable to read-only view")
    func commandX_returnsFalse() {
        let textView = DeselectOnResignTextView()
        let event = makeEvent(keyCode: kVK_ANSI_X, characters: "x")

        let result = textView.performKeyEquivalent(with: event)

        #expect(result == false)
    }

    @Test("⇧⌘[ returns false — bypasses to menu for Previous Tab")
    func shiftCommandLeftBracket_returnsFalse() {
        let textView = DeselectOnResignTextView()
        let event = makeEvent(
            keyCode: kVK_ANSI_LeftBracket,
            characters: "[",
            modifierFlags: [.command, .shift]
        )

        let result = textView.performKeyEquivalent(with: event)

        #expect(result == false)
    }

    @Test("⇧⌘] returns false — bypasses to menu for Next Tab")
    func shiftCommandRightBracket_returnsFalse() {
        let textView = DeselectOnResignTextView()
        let event = makeEvent(
            keyCode: kVK_ANSI_RightBracket,
            characters: "]",
            modifierFlags: [.command, .shift]
        )

        let result = textView.performKeyEquivalent(with: event)

        #expect(result == false)
    }

    // MARK: - Non-command key (should delegate to super)

    @Test("Key without command modifier delegates to super")
    func nonCommandKey_delegatesToSuper() {
        let textView = DeselectOnResignTextView()
        let event = makeEvent(
            keyCode: kVK_ANSI_F,
            characters: "f",
            modifierFlags: []
        )

        let result = textView.performKeyEquivalent(with: event)

        #expect(result == false)
    }
}
#endif
