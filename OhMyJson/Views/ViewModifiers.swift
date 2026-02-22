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

// MARK: - Hover Highlight Modifier

/// Adds a rounded rectangle background that appears on hover.
struct HoverHighlightModifier: ViewModifier {
    let hoverColor: Color
    let cornerRadius: CGFloat

    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isHovered ? hoverColor : Color.clear)
            )
            .onHover { isHovered = $0 }
    }
}

extension View {
    func hoverHighlight(color: Color, cornerRadius: CGFloat = 4) -> some View {
        self.modifier(HoverHighlightModifier(hoverColor: color, cornerRadius: cornerRadius))
    }
}

#endif
