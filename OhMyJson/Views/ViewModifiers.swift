//
//  ViewModifiers.swift
//  OhMyJson
//

import SwiftUI

#if os(macOS)

// MARK: - Arrow Cursor Modifier

/// Forces the arrow cursor on a view, preventing I-beam from SwiftUI Text views
/// inside nested NSHostingView (NSViewRepresentable).
///
/// - macOS 15+: Uses `.pointerStyle(.default)` (Apple's official API)
/// - macOS 14:  Falls back to `onContinuousHover` + `NSCursor.arrow.set()`
///              (best-effort; cursor rect system may still override on static hover)
extension View {
    @ViewBuilder
    func arrowCursor() -> some View {
        if #available(macOS 15.0, *) {
            self.pointerStyle(.default)
        } else {
            self.modifier(ArrowCursorFallbackModifier())
        }
    }
}

/// Fallback modifier for macOS 14 that resets cursor to arrow on every mouse move.
private struct ArrowCursorFallbackModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    NSCursor.arrow.set()
                case .ended:
                    break
                }
            }
    }
}

#endif
