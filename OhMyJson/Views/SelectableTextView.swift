//
//  SelectableTextView.swift
//  OhMyJson
//
//  Read-only NSTextView wrapper that enables text selection with optional line number gutter
//

import SwiftUI
import AppKit

#if os(macOS)
// MARK: - HighlightPatch

/// A single attribute change for incremental search highlight updates.
/// Passed from BeautifyView to SelectableTextView to update only 2 ranges
/// (previous current match → other; new current match → current) instead of
/// replacing the entire attributed string on every Cmd+G navigation.
struct HighlightPatch {
    let range: NSRange
    let backgroundColor: NSColor
    let foregroundColor: NSColor
    let font: NSFont
}

// MARK: - NSTextView that clears selection on focus loss
class DeselectOnResignTextView: NSTextView {
    var onMouseDown: (() -> Void)?
    /// When true, selection is not cleared on resignFirstResponder.
    /// Set to true while the search bar is visible so a drag selection survives
    /// ⌘F opening the search bar without losing first-responder.
    var preserveSelection: Bool = false

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            if preserveSelection {
                preserveSelection = false  // One-shot: consumed
            } else {
                setSelectedRange(NSRange(location: selectedRange().location, length: 0))
            }
        }
        return result
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

        switch characters {
        case "c":
            copy(nil)
            return true
        case "a":
            selectAll(nil)
            return true
        default:
            // Let menu items handle all other ⌘-shortcuts.
            // This is a read-only view — only copy and selectAll are relevant.
            return false
        }
    }
}

/// A read-only text view that supports text selection, wrapping NSTextView
/// Optionally displays line numbers in a non-selectable gutter
struct SelectableTextView: NSViewRepresentable {
    let attributedString: NSAttributedString
    let lineNumberString: NSAttributedString?
    let backgroundColor: NSColor
    let selectedTextForegroundColor: NSColor?
    let selectedTextBackgroundColor: NSColor?
    @Binding var scrollPosition: CGFloat
    var scrollToRange: NSRange?
    var isRestoringTabState: Bool
    var onMouseDown: (() -> Void)?
    /// O(1) identity token for the content attributed string.
    /// Callers increment this whenever the attributed string content actually changes,
    /// replacing the previous O(n) NSAttributedString equality check in updateNSView.
    var contentId: Int
    /// O(1) identity token for the line-number gutter attributed string.
    var gutterContentId: Int
    /// Incremental attribute patches for the current search match transition.
    /// When non-nil and `highlightVersion` changes without a `contentId` change,
    /// updateNSView applies only these 2 ranges instead of replacing the full string.
    var highlightPatches: [HighlightPatch]?
    /// Monotonically increasing version for highlight patches.
    var highlightVersion: Int
    /// When true, selection is preserved when the text view loses focus.
    /// Pass `isSearchVisible` from BeautifyView so a drag selection survives ⌘F.
    var preserveSelection: Bool

    @Environment(\.colorScheme) private var colorScheme

    init(
        attributedString: NSAttributedString,
        lineNumberString: NSAttributedString? = nil,
        backgroundColor: NSColor = AppSettings.shared.currentTheme.nsBackground,
        selectedTextForegroundColor: NSColor? = nil,
        selectedTextBackgroundColor: NSColor? = nil,
        scrollPosition: Binding<CGFloat>,
        scrollToRange: NSRange? = nil,
        isRestoringTabState: Bool = false,
        onMouseDown: (() -> Void)? = nil,
        contentId: Int = 0,
        gutterContentId: Int = 0,
        highlightPatches: [HighlightPatch]? = nil,
        highlightVersion: Int = 0,
        preserveSelection: Bool = false
    ) {
        self.attributedString = attributedString
        self.lineNumberString = lineNumberString
        self.backgroundColor = backgroundColor
        self.selectedTextForegroundColor = selectedTextForegroundColor
        self.selectedTextBackgroundColor = selectedTextBackgroundColor
        self._scrollPosition = scrollPosition
        self.scrollToRange = scrollToRange
        self.isRestoringTabState = isRestoringTabState
        self.onMouseDown = onMouseDown
        self.contentId = contentId
        self.gutterContentId = gutterContentId
        self.highlightPatches = highlightPatches
        self.highlightVersion = highlightVersion
        self.preserveSelection = preserveSelection
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSView {
        // Create container for gutter + content
        let containerView = NSView()
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = backgroundColor.cgColor

        // Create the main content scroll view with 1.5x scroll speed
        let contentScrollView = FastScrollView()
        let contentTextView = DeselectOnResignTextView(usingTextLayoutManager: true)

        // Configure text view sizing
        contentTextView.minSize = NSSize(width: 0, height: 0)
        contentTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        contentTextView.isVerticallyResizable = true
        contentTextView.isHorizontallyResizable = true
        contentTextView.autoresizingMask = [.width]

        // Configure scroll view
        contentScrollView.documentView = contentTextView
        contentScrollView.drawsBackground = false
        contentScrollView.hasVerticalScroller = true
        contentScrollView.hasHorizontalScroller = true
        contentScrollView.autohidesScrollers = true
        contentScrollView.scrollerStyle = .overlay

        // Configure content text view for read-only selection
        contentTextView.isEditable = false
        contentTextView.isSelectable = true
        contentTextView.backgroundColor = backgroundColor
        contentTextView.drawsBackground = true

        // Apply custom selection colors
        var selectionAttrs: [NSAttributedString.Key: Any] = [:]
        if let fg = selectedTextForegroundColor {
            selectionAttrs[.foregroundColor] = fg
        }
        if let bg = selectedTextBackgroundColor {
            selectionAttrs[.backgroundColor] = bg
        }
        if !selectionAttrs.isEmpty {
            contentTextView.selectedTextAttributes = selectionAttrs
        }

        // Disable unwanted features
        contentTextView.isAutomaticQuoteSubstitutionEnabled = false
        contentTextView.isAutomaticDashSubstitutionEnabled = false
        contentTextView.isAutomaticTextReplacementEnabled = false
        contentTextView.isAutomaticSpellingCorrectionEnabled = false
        contentTextView.isContinuousSpellCheckingEnabled = false

        // Set text container properties for proper layout
        contentTextView.textContainer?.widthTracksTextView = false
        contentTextView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        // Set initial content
        contentTextView.textStorage?.setAttributedString(attributedString)

        // Wire mouseDown callback via coordinator
        let coordinator = context.coordinator
        coordinator.onMouseDown = onMouseDown
        contentTextView.onMouseDown = { [weak coordinator] in
            coordinator?.onMouseDown?()
        }

        // Store references
        context.coordinator.contentScrollView = contentScrollView
        context.coordinator.contentTextView = contentTextView

        // Verify TextKit 2 is active — init(usingTextLayoutManager: true) must not silently downgrade
        assert(contentTextView.textLayoutManager != nil, "SelectableTextView: TextKit 2 not active for contentTextView")

        // Create line number gutter if needed
        if let lineNumbers = lineNumberString {
            // Use EventForwardingScrollView for gutter - forwards scroll events to content
            // This ensures scrolling over gutter area uses content's FastScrollView (1.5x speed)
            let gutterScrollView = EventForwardingScrollView()
            gutterScrollView.targetScrollView = contentScrollView
            let gutterTextView = NSTextView(usingTextLayoutManager: true)

            // Configure gutter text view sizing
            gutterTextView.minSize = NSSize(width: 0, height: 0)
            gutterTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            gutterTextView.isVerticallyResizable = true
            gutterTextView.isHorizontallyResizable = true
            gutterTextView.autoresizingMask = [.width]

            // Configure gutter scroll view - hide scrollers, synced by content
            gutterScrollView.documentView = gutterTextView
            gutterScrollView.backgroundColor = backgroundColor
            gutterScrollView.drawsBackground = true
            gutterScrollView.hasVerticalScroller = false
            gutterScrollView.hasHorizontalScroller = false
            // Disable scroll event posting - gutter is slave to content
            gutterScrollView.contentView.postsBoundsChangedNotifications = false

            // Configure gutter text view - non-selectable
            gutterTextView.isEditable = false
            gutterTextView.isSelectable = false
            gutterTextView.backgroundColor = backgroundColor
            gutterTextView.drawsBackground = true

            // Match text container settings
            gutterTextView.textContainer?.widthTracksTextView = false
            gutterTextView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

            // Set line numbers content
            gutterTextView.textStorage?.setAttributedString(lineNumbers)

            // Calculate gutter width based on content
            let gutterWidth = calculateGutterWidth(for: lineNumbers)

            // Verify gutter TextKit 2 is active
            assert(gutterTextView.textLayoutManager != nil, "SelectableTextView: TextKit 2 not active for gutterTextView")

            // Store gutter references
            context.coordinator.gutterScrollView = gutterScrollView
            context.coordinator.gutterTextView = gutterTextView
            context.coordinator.gutterWidth = gutterWidth

            // Link content's FastScrollView to sync gutter immediately during scroll
            contentScrollView.syncScrollView = gutterScrollView

            // Add views to container
            gutterScrollView.translatesAutoresizingMaskIntoConstraints = false
            contentScrollView.translatesAutoresizingMaskIntoConstraints = false
            containerView.addSubview(gutterScrollView)
            containerView.addSubview(contentScrollView)

            NSLayoutConstraint.activate([
                gutterScrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                gutterScrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
                gutterScrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
                gutterScrollView.widthAnchor.constraint(equalToConstant: gutterWidth),

                contentScrollView.leadingAnchor.constraint(equalTo: gutterScrollView.trailingAnchor),
                contentScrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                contentScrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
                contentScrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])

            // No longer need Notification-based sync for gutter
            // Content's FastScrollView.scrollWheel() handles gutter sync directly
        } else {
            // No gutter - just use content scroll view directly
            contentScrollView.translatesAutoresizingMaskIntoConstraints = false
            containerView.addSubview(contentScrollView)

            NSLayoutConstraint.activate([
                contentScrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                contentScrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                contentScrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
                contentScrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])
        }

        // Restore scroll position IMMEDIATELY (same run loop, before view appears)
        if scrollPosition > 0 {
            let clipView = contentScrollView.contentView
            clipView.scroll(to: NSPoint(x: 0, y: scrollPosition))
            contentScrollView.reflectScrolledClipView(clipView)
            // Sync gutter if present
            if let gutterScrollView = context.coordinator.gutterScrollView {
                let gutterClipView = gutterScrollView.contentView
                gutterClipView.scroll(to: NSPoint(x: 0, y: scrollPosition))
                gutterScrollView.reflectScrolledClipView(gutterClipView)
            }
        }

        // Pre-seed lastScrolledRange so updateNSView won't re-scroll to the search result
        // on tab restore. This ensures saved scroll position takes priority over search position.
        context.coordinator.lastScrolledRange = scrollToRange

        // Observe scroll for position binding (boundsDidChangeNotification only - more efficient than didLiveScrollNotification)
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: contentScrollView.contentView
        )

        return containerView
    }

    private func calculateGutterWidth(for lineNumbers: NSAttributedString) -> CGFloat {
        // The last line number is always the widest (most digits + padding).
        // Measure only that one string instead of laying out the entire document.
        let fullString = lineNumbers.string
        let lastLine = fullString.components(separatedBy: "\n").last ?? fullString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        ]
        let size = (lastLine as NSString).size(withAttributes: attrs)
        return ceil(size.width) + 8
    }

    func updateNSView(_ containerView: NSView, context: Context) {
        // Sync coordinator's parent reference so it sees latest isRestoringTabState
        context.coordinator.parent = self
        context.coordinator.onMouseDown = onMouseDown

        guard let contentTextView = context.coordinator.contentTextView,
              let contentScrollView = context.coordinator.contentScrollView else { return }

        // Rising-edge detection: only set preserveSelection = true on false→true transition.
        // This ensures the one-shot flag is armed only once per search-bar open, not re-armed
        // on every SwiftUI update while the search bar stays visible.
        if let deselectView = contentTextView as? DeselectOnResignTextView {
            if preserveSelection && !context.coordinator.lastPreserveSelectionInput {
                deselectView.preserveSelection = true
            }
            context.coordinator.lastPreserveSelectionInput = preserveSelection
        }

        // Update content if changed (O(1) id check avoids O(n) NSAttributedString comparison)
        let contentChanged = contentId != context.coordinator.lastContentId
        if contentChanged {
            context.coordinator.lastContentId = contentId
            // Sync highlight version so the incremental patch path doesn't re-fire
            context.coordinator.lastHighlightVersion = highlightVersion
            // Preserve selection if possible
            let selectedRange = contentTextView.selectedRange()

            contentTextView.textStorage?.setAttributedString(attributedString)

            // Restore selection if valid
            let maxLocation = attributedString.length
            if selectedRange.location < maxLocation {
                let validLength = min(selectedRange.length, maxLocation - selectedRange.location)
                contentTextView.setSelectedRange(NSRange(location: selectedRange.location, length: validLength))
            }
        }

        // Incremental highlight patch: apply only changed ranges for search index navigation.
        // Skipped when the full content was just replaced (contentChanged), since the
        // full attributed string already contains correct highlights.
        if !contentChanged,
           highlightVersion != context.coordinator.lastHighlightVersion,
           let patches = highlightPatches, !patches.isEmpty,
           let textStorage = contentTextView.textStorage {
            context.coordinator.lastHighlightVersion = highlightVersion
            textStorage.beginEditing()
            for patch in patches {
                let maxLen = textStorage.length
                guard maxLen > 0, patch.range.location < maxLen else { continue }
                let safeLength = min(patch.range.length, maxLen - patch.range.location)
                guard safeLength > 0 else { continue }
                let safeRange = NSRange(location: patch.range.location, length: safeLength)
                textStorage.addAttribute(.backgroundColor, value: patch.backgroundColor, range: safeRange)
                textStorage.addAttribute(.foregroundColor, value: patch.foregroundColor, range: safeRange)
                textStorage.addAttribute(.font, value: patch.font, range: safeRange)
            }
            textStorage.endEditing()
        }

        // Update line numbers if present
        if let lineNumbers = lineNumberString,
           let gutterTextView = context.coordinator.gutterTextView,
           let gutterScrollView = context.coordinator.gutterScrollView {
            if gutterContentId != context.coordinator.lastGutterContentId {
                context.coordinator.lastGutterContentId = gutterContentId
                gutterTextView.textStorage?.setAttributedString(lineNumbers)

                // Recalculate and update gutter width if needed
                let newWidth = calculateGutterWidth(for: lineNumbers)
                if abs(newWidth - context.coordinator.gutterWidth) > 1 {
                    context.coordinator.gutterWidth = newWidth
                    // Update constraint
                    for constraint in gutterScrollView.constraints {
                        if constraint.firstAttribute == .width {
                            constraint.constant = newWidth
                            break
                        }
                    }
                }
            }
        }

        // Update background colors only when color scheme changes
        // (Avoids NSColor comparison issues that can cause layout loops)
        if context.coordinator.lastAppliedColorScheme != colorScheme {
            context.coordinator.lastAppliedColorScheme = colorScheme

            if let gutterTextView = context.coordinator.gutterTextView,
               let gutterScrollView = context.coordinator.gutterScrollView {
                gutterTextView.backgroundColor = backgroundColor
                gutterScrollView.backgroundColor = backgroundColor
            }

            containerView.layer?.backgroundColor = backgroundColor.cgColor
            contentTextView.backgroundColor = backgroundColor

            // Update selection colors
            var selectionAttrs: [NSAttributedString.Key: Any] = [:]
            if let fg = selectedTextForegroundColor {
                selectionAttrs[.foregroundColor] = fg
            }
            if let bg = selectedTextBackgroundColor {
                selectionAttrs[.backgroundColor] = bg
            }
            if !selectionAttrs.isEmpty {
                contentTextView.selectedTextAttributes = selectionAttrs
            }
        }

        // During tab restoration: restore saved scroll position, skip search-to-range
        if isRestoringTabState {
            let clipView = contentScrollView.contentView
            clipView.scroll(to: NSPoint(x: 0, y: scrollPosition))
            contentScrollView.reflectScrolledClipView(clipView)
            // Sync gutter
            if let gutterScrollView = context.coordinator.gutterScrollView {
                let gutterClipView = gutterScrollView.contentView
                gutterClipView.scroll(to: NSPoint(x: 0, y: scrollPosition))
                gutterScrollView.reflectScrolledClipView(gutterClipView)
            }
            // Pre-seed so next non-restoring update won't re-scroll to the same range
            context.coordinator.lastScrolledRange = scrollToRange
            return
        }

        // Scroll to specific range if requested (for search navigation)
        if let range = scrollToRange, range != context.coordinator.lastScrolledRange {
            context.coordinator.lastScrolledRange = range
            context.coordinator.scrollToCharacterRange(range, animated: true)
        }
        // Note: Scroll position is restored synchronously in makeNSView()
        // No async restore here - it was causing event blocking and position jumps
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        // Clear text storage content before NSTextView dealloc.
        // Using setAttributedString(empty) keeps layout manager attached so TextKit
        // internal state stays consistent; an empty storage has minimal dealloc cost.
        coordinator.contentTextView?.textStorage?.setAttributedString(NSAttributedString())
        coordinator.gutterTextView?.textStorage?.setAttributedString(NSAttributedString())
    }

    class Coordinator: NSObject {
        var parent: SelectableTextView
        weak var contentScrollView: NSScrollView?
        weak var contentTextView: NSTextView?
        weak var gutterScrollView: NSScrollView?
        weak var gutterTextView: NSTextView?
        var gutterWidth: CGFloat = 0
        var lastAppliedColorScheme: ColorScheme?
        /// Tracks the last scrolled range to avoid duplicate scrolls
        var lastScrolledRange: NSRange?
        /// Flag to prevent scroll binding updates during programmatic scrolls (search navigation)
        private var isScrollingToRange = false
        /// Callback for mouseDown events (updated by parent on each updateNSView)
        var onMouseDown: (() -> Void)?
        /// Last seen contentId — used for O(1) content-change detection in updateNSView
        var lastContentId: Int = -1
        /// Last seen gutterContentId — used for O(1) gutter-change detection in updateNSView
        var lastGutterContentId: Int = -1
        /// Last seen highlightVersion — used for O(1) incremental patch detection
        var lastHighlightVersion: Int = -1
        /// Tracks last preserveSelection input for rising-edge detection
        var lastPreserveSelectionInput: Bool = false

        init(_ parent: SelectableTextView) {
            self.parent = parent
        }

        @objc func scrollViewDidScroll(_ notification: Notification) {
            // Block updates during tab state restoration or programmatic scroll-to-range animation
            guard !parent.isRestoringTabState,
                  !isScrollingToRange,
                  let scrollView = contentScrollView else { return }
            let clipView = scrollView.contentView

            // Get current scroll Y position
            let currentY = clipView.bounds.origin.y

            // Only update if position actually changed (with small threshold to reduce noise)
            if abs(parent.scrollPosition - currentY) > Timing.scrollPositionThreshold {
                DispatchQueue.main.async {
                    self.parent.scrollPosition = currentY
                }
            }
        }

        // Gutter sync is now handled directly in FastScrollView.scrollWheel()
        // No Notification-based sync needed - eliminates feedback loops and timing issues

        /// Scrolls to a specific character range with center alignment and animation.
        /// Uses TextKit 2 (NSTextLayoutManager) to compute the target rect,
        /// avoiding a forced downgrade to TextKit 1 that would occur if layoutManager were accessed.
        func scrollToCharacterRange(_ range: NSRange, animated: Bool = true) {
            guard let scrollView = contentScrollView,
                  let textView = contentTextView else { return }

            guard range.location < textView.string.count else { return }

            // TextKit 2: compute rect via textLayoutManager — never touches layoutManager
            guard let tlm = textView.textLayoutManager,
                  let tcm = tlm.textContentManager else {
                // Defensive fallback — should not be reached when usingTextLayoutManager: true
                textView.scrollRangeToVisible(range)
                return
            }

            // Convert NSRange → NSTextRange via document-relative offsets
            guard let startLoc = tcm.location(tcm.documentRange.location, offsetBy: range.location),
                  let endLoc = tcm.location(startLoc, offsetBy: max(range.length, 1)),
                  let textRange = NSTextRange(location: startLoc, end: endLoc) else {
                textView.scrollRangeToVisible(range)
                return
            }

            // Ensure TextKit 2 has performed layout for this (possibly off-screen) range
            tlm.ensureLayout(for: textRange)

            // Extract the segment frame in the text view's coordinate space
            var targetRect: CGRect = .zero
            tlm.enumerateTextSegments(in: textRange, type: .standard, options: []) { (_, segmentFrame, _, _) in
                targetRect = segmentFrame
                return false  // first segment is sufficient
            }

            guard targetRect != .zero else {
                textView.scrollRangeToVisible(range)
                return
            }

            // Apply textContainerOrigin offset (mirrors TextKit 1 behaviour)
            let origin = textView.textContainerOrigin
            let adjustedRect = CGRect(
                x: targetRect.origin.x + origin.x,
                y: targetRect.origin.y + origin.y,
                width: targetRect.width,
                height: targetRect.height
            )

            // Center the target in the visible area
            let visibleHeight = scrollView.contentView.bounds.height
            let targetY = adjustedRect.origin.y - (visibleHeight / 2) + (adjustedRect.height / 2)
            let maxY = max(0, textView.frame.height - visibleHeight)
            let clampedY = max(0, min(targetY, maxY))

            isScrollingToRange = true

            if animated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = Animation.quick
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: clampedY))
                    if let gutterScrollView = self.gutterScrollView {
                        gutterScrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: clampedY))
                    }
                } completionHandler: { [weak self] in
                    self?.isScrollingToRange = false
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                    if let g = self?.gutterScrollView {
                        g.reflectScrolledClipView(g.contentView)
                    }
                }
            } else {
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: clampedY))
                scrollView.reflectScrolledClipView(scrollView.contentView)
                if let g = gutterScrollView {
                    g.contentView.scroll(to: NSPoint(x: 0, y: clampedY))
                    g.reflectScrolledClipView(g.contentView)
                }
                isScrollingToRange = false
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
#endif
