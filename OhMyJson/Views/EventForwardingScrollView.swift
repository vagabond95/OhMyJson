//
//  EventForwardingScrollView.swift
//  OhMyJson
//
//  NSScrollView that forwards scroll events to a target ScrollView
//  Used for gutter to delegate all scrolling to content's FastScrollView
//

import AppKit

/// NSScrollView that forwards scroll wheel events to a target ScrollView
/// instead of handling them itself. This ensures all scrolling goes through
/// a single ScrollView (e.g., FastScrollView) for consistent behavior.
class EventForwardingScrollView: NSScrollView {
    /// The ScrollView that should handle all scroll events
    /// Typically the content's FastScrollView
    weak var targetScrollView: NSScrollView?

    override func scrollWheel(with event: NSEvent) {
        // Forward scroll event to target instead of handling ourselves
        // This ensures:
        // 1. All scrolling goes through one ScrollView (FastScrollView)
        // 2. Consistent 1.5x scroll speed regardless of mouse position
        // 3. No position desync between gutter and content
        if let target = targetScrollView {
            target.scrollWheel(with: event)
        }
        // Don't call super - we don't want to scroll ourselves independently
    }
}
