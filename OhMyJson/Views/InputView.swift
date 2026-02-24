//
//  InputView.swift
//  OhMyJson
//

import SwiftUI
import AppKit
import Carbon.HIToolbox

// MARK: - Custom NSTextView that handles key equivalents directly
class EditableTextView: NSTextView {
    /// Called instead of NSTextView insertion when pasted text exceeds InputSize.displayThreshold.
    var onLargeTextPaste: ((String) -> Void)?

    override func paste(_ sender: Any?) {
        guard isEditable else { return }
        guard let text = NSPasteboard.general.string(forType: .string),
              text.utf8.count > InputSize.displayThreshold else {
            super.paste(sender)
            return
        }
        // Bypass NSTextView insertion for large text to prevent SBBOD on main thread.
        onLargeTextPaste?(text)
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            setSelectedRange(NSRange(location: selectedRange().location, length: 0))
        }
        return result
    }

    override func keyDown(with event: NSEvent) {
        // Ignore hotkey combo so it doesn't insert characters into the text view
        let combo = AppSettings.shared.openHotKeyCombo
        if event.keyCode == combo.keyCode {
            var carbonMods: UInt32 = 0
            let flags = event.modifierFlags
            if flags.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if flags.contains(.shift) { carbonMods |= UInt32(shiftKey) }
            if flags.contains(.option) { carbonMods |= UInt32(optionKey) }
            if flags.contains(.control) { carbonMods |= UInt32(controlKey) }
            if carbonMods == combo.modifiers {
                return
            }
        }

        let keyCode = event.keyCode
        // Space: 49, Return: 36, Enter(numpad): 76
        if keyCode == KeyCode.space || keyCode == KeyCode.returnKey || keyCode == KeyCode.numpadEnter {
            let isEmpty = self.string.isEmpty
            let isAtEnd = self.selectedRange().location >= (self.string as NSString).length
            if isEmpty || isAtEnd {
                return
            }
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }

        // Only handle editing shortcuts when this view is the first responder.
        // Multiple NSTextViews coexist (InputView, BeautifyView); without this guard,
        // the wrong text view may consume the event via performKeyEquivalent DFS traversal.
        guard self.window?.firstResponder === self else { return false }

        let characters = event.charactersIgnoringModifiers ?? ""
        let isShift = event.modifierFlags.contains(.shift)

        switch characters {
        case "v":
            paste(nil)
            return true
        case "c":
            copy(nil)
            return true
        case "x":
            cut(nil)
            return true
        case "a":
            selectAll(nil)
            return true
        case "z":
            if isShift {
                undoManager?.redo()
            } else {
                undoManager?.undo()
            }
            return true
        default:
            // Let menu items handle all other ⌘-shortcuts (⌘N, ⌘W, ⌘F, ⌘1, ⌘2, etc.)
            // All editing shortcuts (C/V/X/A/Z) are explicitly handled above.
            return false
        }
    }
}

// MARK: - NSTextView Wrapper with Undo Support
struct UndoableTextView: NSViewRepresentable {
    @Binding var text: String
    let font: NSFont
    let onTextChange: (String) -> Void
    @Binding var scrollPosition: CGFloat
    var isRestoringTabState: Bool = false
    var onLargeTextPaste: ((String) -> Void)?
    var isEditable: Bool = true
    var tabGeneration: Int = 0

    @Environment(AppSettings.self) var settings
    private var theme: AppTheme { settings.currentTheme }

    func makeNSView(context: Context) -> NSScrollView {
        // Use FastScrollView for 1.5x scroll speed
        let scrollView = FastScrollView()
        let textView = EditableTextView()

        let currentTheme = theme

        // Configure text view for proper sizing
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false

        // Configure scroll view
        scrollView.documentView = textView
        scrollView.drawsBackground = false

        // Show scroll bars only when content overflows
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        // Configure text view
        textView.isEditable = isEditable
        textView.isSelectable = isEditable
        textView.font = font
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.delegate = context.coordinator
        textView.allowsUndo = true
        textView.textColor = currentTheme.nsPrimaryText
        textView.backgroundColor = currentTheme.nsBackground
        textView.insertionPointColor = currentTheme.nsInsertionPoint
        textView.selectedTextAttributes = [
            .backgroundColor: currentTheme.nsSelectedTextBackground,
            .foregroundColor: currentTheme.nsSelectedTextColor
        ]

        // Set initial text
        textView.string = text

        // Wire large-paste callback
        textView.onLargeTextPaste = onLargeTextPaste

        // Store references in coordinator
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        // Restore scroll position immediately (before view appears)
        if scrollPosition > 0 {
            let clipView = scrollView.contentView
            clipView.scroll(to: NSPoint(x: 0, y: scrollPosition))
            scrollView.reflectScrolledClipView(clipView)
        }

        // Observe scroll position changes
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        // Sync coordinator's parent reference so it sees latest isRestoringTabState
        context.coordinator.parent = self
        context.coordinator.lastKnownGeneration = tabGeneration

        let textView = scrollView.documentView as! NSTextView
        let currentTheme = theme

        // Update theme colors only when color scheme actually changes
        // (Avoids NSColor comparison issues that can cause layout loops)
        let currentScheme = currentTheme.colorScheme
        if context.coordinator.lastAppliedColorScheme != currentScheme {
            context.coordinator.lastAppliedColorScheme = currentScheme
            textView.backgroundColor = currentTheme.nsBackground
            textView.textColor = currentTheme.nsPrimaryText
            textView.insertionPointColor = currentTheme.nsInsertionPoint
            textView.selectedTextAttributes = [
                .backgroundColor: currentTheme.nsSelectedTextBackground,
                .foregroundColor: currentTheme.nsSelectedTextColor
            ]
        }

        // Update editable state only when it changes (prevents layout loops)
        if context.coordinator.lastAppliedIsEditable != isEditable {
            context.coordinator.lastAppliedIsEditable = isEditable
            textView.isEditable = isEditable
            textView.isSelectable = isEditable
            // Visually dim the background to indicate disabled state
            textView.backgroundColor = isEditable
                ? currentTheme.nsBackground
                : currentTheme.nsBackground.withAlphaComponent(0.6)
        }

        // Only update text when tab generation changes (tab switch/creation).
        // This replaces the O(N) string comparison with an O(1) integer check.
        // User-typed edits are handled by textDidChange delegate, not here.
        let needsTextUpdate = context.coordinator.lastSetTabGeneration != tabGeneration
        if needsTextUpdate {
            context.coordinator.lastSetTabGeneration = tabGeneration
            context.coordinator.isProgrammaticUpdate = true

            // Finalize active IME composition (e.g. Korean Hangul) before replacing
            // text storage. Resigning first responder synchronously ends the IME
            // session through AppKit's internal path, unlike discardMarkedText()
            // which sends async IPC to the input method server and may not complete
            // before the text storage is replaced — causing EXC_BAD_ACCESS.
            var needsRestoreFirstResponder = false
            if textView.hasMarkedText() {
                if let window = textView.window, window.firstResponder === textView {
                    needsRestoreFirstResponder = true
                    window.makeFirstResponder(nil)
                } else {
                    textView.unmarkText()
                }
            }

            if text.isEmpty {
                // Fast path: clearing — skip undo registration.
                // clearAll() resets all state, so undoing only the text is meaningless.
                textView.undoManager?.removeAllActions()
                textView.string = ""
            } else {
                // Normal path: register undo and update text
                let oldText = textView.string
                let newText = text

                if let undoManager = textView.undoManager {
                    undoManager.registerUndo(withTarget: context.coordinator) { coordinator in
                        coordinator.restoreText(oldText)
                    }

                    if oldText.isEmpty && !newText.isEmpty {
                        undoManager.setActionName(String(localized: "undo.set_text"))
                    } else {
                        undoManager.setActionName(String(localized: "undo.change_text"))
                    }
                }

                // Update text view
                let selectedRange = textView.selectedRange()
                textView.string = text

                if isRestoringTabState {
                    // During tab restoration (hotkey, tab switch), cursor goes to beginning
                    textView.setSelectedRange(NSRange(location: 0, length: 0))
                } else if selectedRange.location <= text.count {
                    // Restore selection if valid
                    textView.setSelectedRange(selectedRange)
                }
            }

            if needsRestoreFirstResponder {
                textView.window?.makeFirstResponder(textView)
            }

            context.coordinator.isProgrammaticUpdate = false
        }

        // Restore scroll position during tab state restoration
        if isRestoringTabState {
            let clipView = scrollView.contentView
            clipView.scroll(to: NSPoint(x: 0, y: scrollPosition))
            scrollView.reflectScrolledClipView(clipView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: UndoableTextView
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        var isProgrammaticUpdate = false
        var lastAppliedColorScheme: ColorScheme?
        var lastAppliedIsEditable: Bool?
        var lastKnownGeneration: Int = 0
        var lastSetTabGeneration: Int = -1

        init(_ parent: UndoableTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticUpdate else { return }
            guard let textView = notification.object as? NSTextView else { return }

            let capturedGeneration = lastKnownGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.parent.tabGeneration == capturedGeneration else { return }
                self.parent.text = textView.string
                self.parent.onTextChange(textView.string)
            }
        }

        @objc func restoreText(_ text: String) {
            let capturedGeneration = lastKnownGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.parent.tabGeneration == capturedGeneration else { return }
                self.parent.text = text
                self.parent.onTextChange(text)
            }
        }

        @objc func scrollViewDidScroll(_ notification: Notification) {
            guard !parent.isRestoringTabState,
                  let scrollView = scrollView else { return }
            let currentY = scrollView.contentView.bounds.origin.y
            if abs(parent.scrollPosition - currentY) > Timing.scrollPositionThreshold {
                DispatchQueue.main.async {
                    self.parent.scrollPosition = currentY
                }
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

struct InputView: View {
    @Binding var text: String
    let onTextChange: (String) -> Void
    @Binding var scrollPosition: CGFloat
    var isRestoringTabState: Bool = false
    var onLargeTextPaste: ((String) -> Void)?
    var isLargeJSON: Bool = false
    var isLargeJSONContentLost: Bool = false
    var tabGeneration: Int = 0

    @Environment(AppSettings.self) var settings
    private var theme: AppTheme { settings.currentTheme }

    var body: some View {
        VStack(spacing: 0) {
            // Text Editor with placeholder
            ZStack(alignment: .topLeading) {
                UndoableTextView(
                    text: $text,
                    font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                    onTextChange: onTextChange,
                    scrollPosition: $scrollPosition,
                    isRestoringTabState: isRestoringTabState,
                    onLargeTextPaste: onLargeTextPaste,
                    isEditable: !isLargeJSON && !isLargeJSONContentLost,
                    tabGeneration: tabGeneration
                )

                if text.isEmpty && isLargeJSONContentLost {
                    // Large JSON content could not be restored from DB
                    VStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 16))
                            .foregroundColor(theme.secondaryText)
                        Text("input.largeJSON.contentLost")
                            .foregroundColor(theme.secondaryText)
                            .font(.system(.body, design: .monospaced))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                } else if text.isEmpty {
                    Text("input.placeholder")
                        .foregroundColor(theme.secondaryText)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 5)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.background)
    }
}

// MARK: - Input Panel with Toolbar
struct InputPanel: View {
    @Binding var text: String
    let onTextChange: (String) -> Void
    let onClear: () -> Void
    @Binding var scrollPosition: CGFloat
    var isRestoringTabState: Bool = false
    var onLargeTextPaste: ((String) -> Void)?
    var isLargeJSON: Bool = false
    var isLargeJSONContentLost: Bool = false
    var tabGeneration: Int = 0

    @Environment(AppSettings.self) var settings
    private var theme: AppTheme { settings.currentTheme }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("input.title")
                    .font(.headline)
                    .foregroundColor(theme.secondaryText)

                Spacer()

                Button(action: onClear) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                        .toolbarIconHover()
                }
                .buttonStyle(.plain)
                .instantTooltip(String(localized: "tooltip.clear"), position: .bottom)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(height: 36)
            .background(theme.secondaryBackground)
            .zIndex(1)

            Rectangle()
                .fill(theme.border)
                .frame(height: 1)

            // Input View
            InputView(
                text: $text,
                onTextChange: onTextChange,
                scrollPosition: $scrollPosition,
                isRestoringTabState: isRestoringTabState,
                onLargeTextPaste: onLargeTextPaste,
                isLargeJSON: isLargeJSON,
                isLargeJSONContentLost: isLargeJSONContentLost,
                tabGeneration: tabGeneration
            )
            .padding(8)
        }
        .background(theme.background)
    }
}

#Preview {
    InputPanel(
        text: .constant(""),
        onTextChange: { _ in },
        onClear: {},
        scrollPosition: .constant(0)
    )
    .frame(width: 400, height: 300)
}
