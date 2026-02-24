//
//  InstantTooltip.swift
//  OhMyJson
//

import SwiftUI

#if os(macOS)

// MARK: - Frame Capture

/// Captures the screen-coordinate frame of a SwiftUI view via an embedded NSView.
/// Used to position the tooltip panel relative to the anchor view, not the cursor.
private class FrameCaptureNSView: NSView {
    var onFrameUpdate: (NSRect) -> Void
    private var windowObserver: NSObjectProtocol?

    init(onFrameUpdate: @escaping (NSRect) -> Void) {
        self.onFrameUpdate = onFrameUpdate
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        reportFrame()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let windowObserver {
            NotificationCenter.default.removeObserver(windowObserver)
            self.windowObserver = nil
        }
        if let window {
            windowObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.reportFrame()
            }
        }
        reportFrame()
    }

    override func removeFromSuperview() {
        if let windowObserver {
            NotificationCenter.default.removeObserver(windowObserver)
            self.windowObserver = nil
        }
        super.removeFromSuperview()
    }

    private func reportFrame() {
        guard let window else { return }
        let frameInWindow = convert(bounds, to: nil)
        let frameInScreen = window.convertToScreen(frameInWindow)
        onFrameUpdate(frameInScreen)
    }
}

private struct FrameCapture: NSViewRepresentable {
    let onFrameUpdate: (NSRect) -> Void

    func makeNSView(context: Context) -> FrameCaptureNSView {
        FrameCaptureNSView(onFrameUpdate: onFrameUpdate)
    }

    func updateNSView(_ nsView: FrameCaptureNSView, context: Context) {
        nsView.onFrameUpdate = onFrameUpdate
    }
}

// MARK: - Tooltip Window Controller

/// Renders tooltip content in a floating NSPanel at .popUpMenu level,
/// so it is never clipped by any parent view or window boundary.
private final class TooltipWindowController {
    static let shared = TooltipWindowController()
    private var panel: NSPanel?

    private init() {}

    func show(
        anyView: AnyView,
        anchorFrame: NSRect,
        position: TooltipPosition,
        alignment: TooltipAlignment = .center,
        gap: CGFloat = 4
    ) {
        hide()

        let hostingView = NSHostingView(rootView: anyView)
        hostingView.layout()
        var size = hostingView.fittingSize
        size.width  = max(size.width,  10)
        size.height = max(size.height, 10)

        let origin = tooltipOrigin(
            tooltipSize: size,
            anchorFrame: anchorFrame,
            position: position,
            alignment: alignment,
            gap: gap
        )

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
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// Computes the bottom-left origin of the tooltip panel in screen coordinates.
    /// macOS screen coords: (0,0) = bottom-left of primary screen, y increases upward.
    private func tooltipOrigin(
        tooltipSize: NSSize,
        anchorFrame: NSRect,
        position: TooltipPosition,
        alignment: TooltipAlignment,
        gap: CGFloat
    ) -> NSPoint {
        let x: CGFloat
        switch alignment {
        case .center:
            x = anchorFrame.midX - tooltipSize.width / 2
        case .leading:
            x = anchorFrame.minX
        }

        let y: CGFloat
        switch position {
        case .top:
            // Tooltip sits above the anchor: panel bottom = anchor top + gap
            y = anchorFrame.maxY + gap
        case .bottom:
            // Tooltip sits below the anchor: panel bottom = anchor bottom - gap - height
            y = anchorFrame.minY - gap - tooltipSize.height
        }

        return NSPoint(x: x, y: y)
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
    let position: TooltipPosition
    @State private var anchorFrame: NSRect = .zero

    func body(content: Content) -> some View {
        content
            .background(FrameCapture { anchorFrame = $0 })
            .onHover { hovering in
                if hovering, !text.isEmpty {
                    TooltipWindowController.shared.show(
                        anyView: AnyView(TooltipLabel(text: text)),
                        anchorFrame: anchorFrame,
                        position: position
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
    let position: TooltipPosition
    let alignment: TooltipAlignment
    let maxWidth: CGFloat
    @ViewBuilder let tooltipContent: () -> TooltipContent
    @State private var anchorFrame: NSRect = .zero

    func body(content: Content) -> some View {
        content
            .background(FrameCapture { anchorFrame = $0 })
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
                    TooltipWindowController.shared.show(
                        anyView: view,
                        anchorFrame: anchorFrame,
                        position: position,
                        alignment: alignment
                    )
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
