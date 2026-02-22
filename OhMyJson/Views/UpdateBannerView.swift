//
//  UpdateBannerView.swift
//  OhMyJson
//

import SwiftUI

#if os(macOS)
struct UpdateBannerView: View {
    @Environment(ViewerViewModel.self) var viewModel
    @Environment(AppSettings.self) var settings

    private var theme: AppTheme { settings.currentTheme }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.circle")
                .font(.system(size: 12))
                .foregroundColor(theme.secondaryText)

            if let version = viewModel.availableVersion {
                Text("v\(version) available")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(theme.primaryText)
            }

            Spacer()

            Button {
                viewModel.triggerUpdate()
            } label: {
                Text("Update")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(theme.primaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(theme.panelBackground)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(theme.border, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                viewModel.dismissUpdateBanner()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(theme.secondaryText)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(theme.panelBackground)
    }
}
#endif
