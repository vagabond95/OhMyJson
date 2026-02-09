//
//  InputView.swift
//  OhMyJson
//

import SwiftUI
import AppKit
import Carbon.HIToolbox

// MARK: - Custom NSTextView that handles key equivalents directly
class EditableTextView: NSTextView {
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
        if keyCode == 49 || keyCode == 36 || keyCode == 76 {
            let isEmpty = self.string.isEmpty
            let isAtEnd = self.selectedRange().location >= self.string.count
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
            return super.performKeyEquivalent(with: event)
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

    @ObservedObject private var settings = AppSettings.shared
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
        scrollView.backgroundColor = currentTheme.nsBackground
        scrollView.drawsBackground = true

        // Show scroll bars only when content overflows
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        // Configure text view
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

        // Set initial text
        textView.string = text
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)

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

        let textView = scrollView.documentView as! NSTextView
        let currentTheme = theme

        // Update theme colors
        let expectedBg = currentTheme.nsBackground
        if textView.backgroundColor != expectedBg {
            scrollView.backgroundColor = expectedBg
            textView.backgroundColor = expectedBg
            textView.textColor = currentTheme.nsPrimaryText
            textView.insertionPointColor = currentTheme.nsInsertionPoint
            textView.selectedTextAttributes = [
                .backgroundColor: currentTheme.nsSelectedTextBackground
            ]
        }

        // Only update if text is different to avoid breaking undo
        if textView.string != text {
            context.coordinator.isProgrammaticUpdate = true

            // Register undo for programmatic text changes (like Clear button)
            let oldText = textView.string
            let newText = text

            if let undoManager = textView.undoManager {
                // Register undo action
                undoManager.registerUndo(withTarget: context.coordinator) { coordinator in
                    coordinator.restoreText(oldText)
                }

                if oldText.isEmpty && !newText.isEmpty {
                    undoManager.setActionName("Set Text")
                } else if !oldText.isEmpty && newText.isEmpty {
                    undoManager.setActionName("Clear")
                } else {
                    undoManager.setActionName("Change Text")
                }
            }

            // Update text view
            let selectedRange = textView.selectedRange()
            textView.string = text
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)

            if isRestoringTabState {
                // During tab restoration (hotkey, tab switch), cursor goes to beginning
                textView.setSelectedRange(NSRange(location: 0, length: 0))
            } else if selectedRange.location <= text.count {
                // Restore selection if valid
                textView.setSelectedRange(selectedRange)
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

        init(_ parent: UndoableTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticUpdate else { return }
            guard let textView = notification.object as? NSTextView else { return }

            // Update binding (this doesn't trigger updateNSView due to the equality check)
            DispatchQueue.main.async {
                self.parent.text = textView.string
                self.parent.onTextChange(textView.string)
            }
        }

        @objc func restoreText(_ text: String) {
            // Update the binding which will trigger updateNSView
            DispatchQueue.main.async {
                self.parent.text = text
                self.parent.onTextChange(text)
            }
        }

        @objc func scrollViewDidScroll(_ notification: Notification) {
            guard !parent.isRestoringTabState,
                  let scrollView = scrollView else { return }
            let currentY = scrollView.contentView.bounds.origin.y
            if abs(parent.scrollPosition - currentY) > 0.5 {
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

    @ObservedObject private var settings = AppSettings.shared
    private var theme: AppTheme { settings.currentTheme }

    var body: some View {
        VStack(spacing: 0) {
            // Text Editor with placeholder
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Paste or type JSON here...")
                        .foregroundColor(theme.secondaryText)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }

                UndoableTextView(
                    text: $text,
                    font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                    onTextChange: onTextChange,
                    scrollPosition: $scrollPosition,
                    isRestoringTabState: isRestoringTabState
                )
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

    @ObservedObject private var settings = AppSettings.shared
    private var theme: AppTheme { settings.currentTheme }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Json Input")
                    .font(.headline)
                    .foregroundColor(theme.secondaryText)

                Spacer()

                Button(action: onClear) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(theme.secondaryText)
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .instantTooltip("Clear", position: .bottom)
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
                isRestoringTabState: isRestoringTabState
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
