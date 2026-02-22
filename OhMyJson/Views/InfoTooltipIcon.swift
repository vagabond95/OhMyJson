//
//  InfoTooltipIcon.swift
//  OhMyJson
//

import SwiftUI

#if os(macOS)
struct InfoTooltipIcon<TooltipContent: View>: View {
    let iconSize: CGFloat
    let circleSize: CGFloat
    let tooltipPosition: TooltipPosition
    let tooltipMaxWidth: CGFloat
    @ViewBuilder let tooltipContent: () -> TooltipContent

    @Environment(AppSettings.self) private var settings
    private var theme: any AppTheme { settings.currentTheme }

    init(
        iconSize: CGFloat = 9,
        circleSize: CGFloat = 16,
        tooltipPosition: TooltipPosition = .bottom,
        tooltipMaxWidth: CGFloat = 260,
        @ViewBuilder tooltipContent: @escaping () -> TooltipContent
    ) {
        self.iconSize = iconSize
        self.circleSize = circleSize
        self.tooltipPosition = tooltipPosition
        self.tooltipMaxWidth = tooltipMaxWidth
        self.tooltipContent = tooltipContent
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(theme.secondaryBackground)
                .frame(width: circleSize, height: circleSize)
            Image(systemName: "questionmark")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundColor(theme.secondaryText)
        }
        .contentShape(Circle())
        .instantRichTooltip(
            position: tooltipPosition,
            alignment: .leading,
            maxWidth: tooltipMaxWidth
        ) {
            tooltipContent()
        }
        .zIndex(100)
    }
}
#endif
