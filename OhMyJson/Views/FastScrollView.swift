//
//  FastScrollView.swift
//  OhMyJson
//
//  NSScrollView subclass with 1.5x scroll speed via CGEvent delta modification
//

import AppKit

/// NSScrollView with 1.5x scroll speed that preserves NSScrollView's internal state machine.
///
/// Instead of bypassing super.scrollWheel and manually setting clipView position,
/// this modifies the CGEvent's delta values before passing to super, keeping
/// NSScrollView's momentum/inertia system fully intact.
class FastScrollView: NSScrollView {
    /// Scroll speed multiplier (1.5x faster than default)
    static let scrollMultiplier: CGFloat = 1.5

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

        // .scrollWheelEventDeltaAxis1 = vertical (Int field, line-based delta)
        // .scrollWheelEventPointDeltaAxis1 = vertical (pixel-based delta for precise scrolling)
        // Axis2 = horizontal

        // Amplify pixel-based deltas (used by trackpad precise scrolling)
        let pixelDeltaY = cgEvent.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let pixelDeltaX = cgEvent.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        cgEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: pixelDeltaY * Double(multiplier))
        cgEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: pixelDeltaX * Double(multiplier))

        // Amplify line-based deltas (used by discrete mouse wheel)
        let lineDeltaY = cgEvent.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let lineDeltaX = cgEvent.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        cgEvent.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(Double(lineDeltaY) * Double(multiplier)))
        cgEvent.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(Double(lineDeltaX) * Double(multiplier)))

        // Also amplify the fixedPt deltas which some scroll paths use
        let fixedPtY = cgEvent.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let fixedPtX = cgEvent.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        cgEvent.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fixedPtY * Double(multiplier))
        cgEvent.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixedPtX * Double(multiplier))

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
