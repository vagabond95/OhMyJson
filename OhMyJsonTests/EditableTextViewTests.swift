//
//  EditableTextViewTests.swift
//  OhMyJsonTests
//

import Testing
import AppKit
import Carbon.HIToolbox
@testable import OhMyJson

#if os(macOS)
@Suite("EditableTextView Key Equivalent Tests")
@MainActor
struct EditableTextViewTests {

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

    // MARK: - Bypass cases (must return false so menu items can handle them)

    @Test("⌘F returns false — bypasses NSTextView, lets menu handle it")
    func commandF_returnsFalse() {
        let textView = EditableTextView()
        let event = makeEvent(keyCode: kVK_ANSI_F, characters: "f")

        let result = textView.performKeyEquivalent(with: event)

        #expect(result == false)
    }

    @Test("⌘1 returns false — bypasses NSTextView, lets menu handle it")
    func command1_returnsFalse() {
        let textView = EditableTextView()
        let event = makeEvent(keyCode: kVK_ANSI_1, characters: "1")

        let result = textView.performKeyEquivalent(with: event)

        #expect(result == false)
    }

    @Test("⌘2 returns false — bypasses NSTextView, lets menu handle it")
    func command2_returnsFalse() {
        let textView = EditableTextView()
        let event = makeEvent(keyCode: kVK_ANSI_2, characters: "2")

        let result = textView.performKeyEquivalent(with: event)

        #expect(result == false)
    }

    // MARK: - Handled cases (must return true — text view handles them directly)

    @Test("⌘V returns true — handled by text view")
    func commandV_returnsTrue() {
        let textView = EditableTextView()
        let event = makeEvent(keyCode: kVK_ANSI_V, characters: "v")

        let result = textView.performKeyEquivalent(with: event)

        #expect(result == true)
    }

    @Test("⌘C returns true — handled by text view")
    func commandC_returnsTrue() {
        let textView = EditableTextView()
        let event = makeEvent(keyCode: kVK_ANSI_C, characters: "c")

        let result = textView.performKeyEquivalent(with: event)

        #expect(result == true)
    }

    @Test("⌘X returns true — handled by text view")
    func commandX_returnsTrue() {
        let textView = EditableTextView()
        let event = makeEvent(keyCode: kVK_ANSI_X, characters: "x")

        let result = textView.performKeyEquivalent(with: event)

        #expect(result == true)
    }

    @Test("⌘A returns true — handled by text view")
    func commandA_returnsTrue() {
        let textView = EditableTextView()
        let event = makeEvent(keyCode: kVK_ANSI_A, characters: "a")

        let result = textView.performKeyEquivalent(with: event)

        #expect(result == true)
    }

    @Test("⌘Z returns true — handled by text view")
    func commandZ_returnsTrue() {
        let textView = EditableTextView()
        textView.allowsUndo = true
        let event = makeEvent(keyCode: kVK_ANSI_Z, characters: "z")

        let result = textView.performKeyEquivalent(with: event)

        #expect(result == true)
    }

    @Test("⇧⌘Z returns true — redo handled by text view")
    func shiftCommandZ_returnsTrue() {
        let textView = EditableTextView()
        textView.allowsUndo = true
        let event = makeEvent(
            keyCode: kVK_ANSI_Z,
            characters: "z",
            modifierFlags: [.command, .shift]
        )

        let result = textView.performKeyEquivalent(with: event)

        #expect(result == true)
    }

    // MARK: - Non-command key (should delegate to super)

    @Test("Key without command modifier delegates to super")
    func nonCommandKey_delegatesToSuper() {
        let textView = EditableTextView()
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
