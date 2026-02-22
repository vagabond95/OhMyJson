//
//  InstantTooltip.swift
//  OhMyJson
//

import SwiftUI

#if os(macOS)

// MARK: - Tooltip Window Controller

/// Renders tooltip content in a floating NSPanel at .popUpMenu level,
/// so it is never clipped by any parent view or window boundary.
private final class TooltipWindowController {
    static let shared = TooltipWindowController()
    private var panel: NSPanel?

    private init() {}

    func show(anyView: AnyView, near screenPoint: NSPoint) {
        hide()

        let hostingView = NSHostingView(rootView: anyView)
        hostingView.layout()
        var size = hostingView.fittingSize
        size.width  = max(size.width,  10)
        size.height = max(size.height, 10)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu          // always above all app content
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.contentView = hostingView
        panel.setFrameOrigin(NSPoint(
            x: screenPoint.x - size.width / 2,
            y: screenPoint.y + 16          // appear above cursor
        ))
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

// MARK: - Tooltip Content

private struct TooltipLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(Color(hex: "FAF9F6"))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "2A2A2A"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(hex: "3A3A3A"), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
            .fixedSize()
    }
}

// MARK: - Simple Text Tooltip

enum TooltipPosition {
    case top
    case bottom
}

struct InstantTooltip: ViewModifier {
    let text: String
    let position: TooltipPosition   // kept for API compatibility; NSPanel always floats near cursor

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering {
                    TooltipWindowController.shared.show(
                        anyView: AnyView(TooltipLabel(text: text)),
                        near: NSEvent.mouseLocation
                    )
                } else {
                    TooltipWindowController.shared.hide()
                }
            }
    }
}

extension View {
    func instantTooltip(_ text: String, position: TooltipPosition = .top) -> some View {
        modifier(InstantTooltip(text: text, position: position))
    }
}

// MARK: - Rich Tooltip (View-based content)

enum TooltipAlignment {
    case center
    case leading
}

struct InstantRichTooltip<TooltipContent: View>: ViewModifier {
    let position: TooltipPosition   // kept for API compatibility
    let alignment: TooltipAlignment // kept for API compatibility
    let maxWidth: CGFloat
    @ViewBuilder let tooltipContent: () -> TooltipContent

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering {
                    let view = AnyView(
                        tooltipContent()
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "FAF9F6"))
                            .frame(width: maxWidth, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(hex: "1A1A1A"))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color(hex: "3A3A3A"), lineWidth: 0.5)
                            )
                            .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                    )
                    TooltipWindowController.shared.show(anyView: view, near: NSEvent.mouseLocation)
                } else {
                    TooltipWindowController.shared.hide()
                }
            }
    }
}

extension View {
    func instantRichTooltip<Content: View>(
        position: TooltipPosition = .bottom,
        alignment: TooltipAlignment = .center,
        maxWidth: CGFloat = 260,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(InstantRichTooltip(
            position: position,
            alignment: alignment,
            maxWidth: maxWidth,
            tooltipContent: content
        ))
    }
}
#endif
