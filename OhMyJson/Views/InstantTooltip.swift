//
//  InstantTooltip.swift
//  OhMyJson
//

import SwiftUI

#if os(macOS)
enum TooltipPosition {
    case top
    case bottom
}

struct InstantTooltip: ViewModifier {
    let text: String
    let position: TooltipPosition
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovered = $0 }
            .overlay {
                GeometryReader { geometry in
                    if isHovered {
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
                            .position(
                                x: geometry.size.width / 2 - 10,
                                y: position == .top ? -14 : geometry.size.height + 14
                            )
                            .allowsHitTesting(false)
                    }
                }
                .allowsHitTesting(false)
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
    @State private var isHovered = false
    @State private var tooltipSize: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .onHover { isHovered = $0 }
            .overlay {
                GeometryReader { parentGeo in
                    if isHovered {
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
                            .background(
                                GeometryReader { tooltipGeo in
                                    Color.clear.onAppear { tooltipSize = tooltipGeo.size }
                                }
                            )
                            .opacity(tooltipSize.height > 0 ? 1 : 0)
                            .position(
                                x: tooltipX(parentWidth: parentGeo.size.width),
                                y: tooltipY(parentHeight: parentGeo.size.height)
                            )
                            .allowsHitTesting(false)
                    }
                }
                .allowsHitTesting(false)
            }
    }

    private let gap: CGFloat = 4

    private func tooltipX(parentWidth: CGFloat) -> CGFloat {
        let totalWidth = maxWidth + 16
        switch alignment {
        case .leading:
            return totalWidth / 2
        case .center:
            return parentWidth / 2
        }
    }

    private func tooltipY(parentHeight: CGFloat) -> CGFloat {
        let h = tooltipSize.height
        switch position {
        case .top:
            return -(h / 2 + gap)
        case .bottom:
            return parentHeight + h / 2 + gap
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
