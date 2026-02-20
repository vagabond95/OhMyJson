//
//  FastScrollView.swift
//  OhMyJson
//
//  NSScrollView subclass with 1.5x vertical scroll speed via CGEvent delta modification
//

import AppKit

/// NSScroller that doesn't draw the knob slot (track background)
class ClearTrackScroller: NSScroller {
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // No-op: skip drawing the track background
    }
}

/// NSScrollView with 1.5x vertical scroll speed that preserves NSScrollView's internal state machine.
///
/// Instead of bypassing super.scrollWheel and manually setting clipView position,
/// this modifies the CGEvent's delta values before passing to super, keeping
/// NSScrollView's momentum/inertia system fully intact.
class FastScrollView: NSScrollView {
    /// Scroll speed multiplier (1.5x faster than default)
    static let scrollMultiplier: CGFloat = 1.5

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installClearTrackScrollers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installClearTrackScrollers()
    }

    private func installClearTrackScrollers() {
        horizontalScroller = ClearTrackScroller()
        verticalScroller = ClearTrackScroller()
    }

    /// ScrollView to synchronize with (for gutter sync)
    weak var syncScrollView: NSScrollView?

    override func scrollWheel(with event: NSEvent) {
        if event.momentumPhase != [] {
            // Momentum (inertia) events — pass through unmodified.
            // NSScrollView generated these based on the amplified user deltas,
            // so they are already correctly scaled.
            super.scrollWheel(with: event)
        } else if event.phase != [] {
            // User gesture events (.began, .changed, .ended, .cancelled)
            // Amplify the delta so NSScrollView's internal tracker accumulates
            // the multiplied velocity, producing correct momentum on release.
            if let amplified = Self.amplifiedEvent(from: event, multiplier: Self.scrollMultiplier) {
                super.scrollWheel(with: amplified)
            } else {
                super.scrollWheel(with: event)
            }
        } else {
            // Discrete mouse wheel (no phase, no momentumPhase)
            if let amplified = Self.amplifiedEvent(from: event, multiplier: Self.scrollMultiplier) {
                super.scrollWheel(with: amplified)
            } else {
                super.scrollWheel(with: event)
            }
        }

        syncGutterPosition()
    }

    // MARK: - CGEvent Delta Amplification

    /// Creates a new NSEvent with scrolling deltas multiplied by the given factor.
    ///
    /// Works by copying the underlying CGEvent and modifying its delta fields,
    /// then wrapping it back into an NSEvent. This preserves all other event
    /// properties (phase, momentumPhase, timestamp, etc.) exactly.
    private static func amplifiedEvent(from event: NSEvent, multiplier: CGFloat) -> NSEvent? {
        guard let cgEvent = event.cgEvent?.copy() else { return nil }

        // Amplify only vertical (Axis1) deltas. Horizontal (Axis2) is left unmodified
        // to avoid interfering with NSScrollView's axis-locking (usesPredominantAxisScrolling)
        // which causes initial horizontal swipes to be swallowed and then over-accelerated.

        // Amplify vertical pixel-based deltas (used by trackpad precise scrolling)
        let pixelDeltaY = cgEvent.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        cgEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: pixelDeltaY * Double(multiplier))

        // Amplify vertical line-based deltas (used by discrete mouse wheel)
        let lineDeltaY = cgEvent.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        cgEvent.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(Double(lineDeltaY) * Double(multiplier)))

        // Amplify vertical fixedPt deltas which some scroll paths use
        let fixedPtY = cgEvent.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        cgEvent.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fixedPtY * Double(multiplier))

        return NSEvent(cgEvent: cgEvent)
    }

    // MARK: - Gutter Sync

    /// Synchronizes the linked gutter ScrollView to match current Y position
    private func syncGutterPosition() {
        guard let syncScrollView = syncScrollView else { return }
        let currentY = contentView.bounds.origin.y
        let syncClipView = syncScrollView.contentView
        syncClipView.scroll(to: NSPoint(x: 0, y: currentY))
        syncScrollView.reflectScrolledClipView(syncClipView)
    }
}
