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
#endif
