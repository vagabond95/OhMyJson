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

// MARK: - Toolbar Icon Hover Modifier

/// Animates toolbar icon color from `secondaryText` (default) to `primaryText` on hover.
/// When `isActive` is `true`, `primaryText` is always applied regardless of hover state.
struct ToolbarIconHoverModifier: ViewModifier {
    let isActive: Bool

    @Environment(AppSettings.self) var settings
    @State private var isHovered = false

    private var theme: AppTheme { settings.currentTheme }

    func body(content: Content) -> some View {
        content
            .foregroundColor(isActive || isHovered ? theme.primaryText : theme.secondaryText)
            .onHover { isHovered = $0 }
    }
}

extension View {
    /// Toolbar 아이콘에 hover 시 `primaryText` 색상을 적용. 기본: `secondaryText`.
    /// `isActive: true`이면 hover 여부와 무관하게 `primaryText` 고정.
    func toolbarIconHover(isActive: Bool = false) -> some View {
        self.modifier(ToolbarIconHoverModifier(isActive: isActive))
    }
}

#endif
