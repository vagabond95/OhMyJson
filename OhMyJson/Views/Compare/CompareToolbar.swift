//
//  CompareToolbar.swift
//  OhMyJson
//
//  Toolbar for Compare mode: diff summary badges, navigation, options, copy.
//

import SwiftUI

#if os(macOS)
struct CompareToolbar: View {
    @Environment(ViewerViewModel.self) var viewModel
    @Environment(AppSettings.self) var settings

    private var theme: AppTheme { settings.currentTheme }

    var body: some View {
        @Bindable var viewModel = viewModel

        HStack(spacing: 8) {
            // View Mode segmented control
            viewModeSegmentedControl

            Spacer().frame(width: 8)

            if viewModel.isCompareDiffing {
                ProgressView()
                    .controlSize(.small)
                    .padding(.horizontal, 4)
            } else if let result = viewModel.compareDiffResult {
                // Diff summary badges
                if result.isIdentical {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 12))
                        Text("No differences")
                            .font(.system(size: 11))
                            .foregroundColor(theme.secondaryText)
                    }
                } else {
                    diffBadge(count: result.addedCount, label: "added", color: theme.diffAddedGutter)
                    diffBadge(count: result.removedCount, label: "removed", color: theme.diffRemovedGutter)
                    diffBadge(count: result.modifiedCount, label: "modified", color: theme.diffModifiedGutter)

                    // Navigation buttons
                    HStack(spacing: 2) {
                        Button(action: viewModel.navigateToPreviousDiff) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 10, weight: .medium))
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                                .toolbarIconHover()
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.totalDiffCount == 0)

                        Button(action: viewModel.navigateToNextDiff) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .medium))
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                                .toolbarIconHover()
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.totalDiffCount == 0)
                    }
                }
            }

            Spacer()

            // Option toggle chips
            HStack(spacing: 4) {
                optionChip(
                    label: "Key Order",
                    isActive: viewModel.compareIgnoreKeyOrder,
                    action: { viewModel.updateCompareOption(ignoreKeyOrder: !viewModel.compareIgnoreKeyOrder) }
                )
                optionChip(
                    label: "Array Order",
                    isActive: viewModel.compareIgnoreArrayOrder,
                    action: { viewModel.updateCompareOption(ignoreArrayOrder: !viewModel.compareIgnoreArrayOrder) }
                )
                optionChip(
                    label: "Strict Type",
                    isActive: viewModel.compareStrictType,
                    action: { viewModel.updateCompareOption(strictType: !viewModel.compareStrictType) }
                )
            }

            // Copy Diff button
            if let result = viewModel.compareDiffResult, !result.isIdentical {
                Button(action: viewModel.copyDiff) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                        .toolbarIconHover()
                }
                .buttonStyle(.plain)
                .instantTooltip("Copy Diff", position: .bottom)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(theme.secondaryBackground)
    }

    // MARK: - View Mode Segmented Control

    private var viewModeSegmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                let isDisabled = mode == .beautify && viewModel.isLargeJSON
                Button(action: {
                    viewModel.switchViewMode(to: mode)
                }) {
                    Text(mode.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .toolbarIconHover(isActive: viewModel.viewMode == mode && !isDisabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            viewModel.viewMode == mode && !isDisabled
                                ? theme.panelBackground
                                : Color.clear
                        )
                        .cornerRadius(4)
                        .contentShape(Rectangle())
                        .opacity(isDisabled ? 0.35 : 1.0)
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
            }
        }
        .padding(2)
        .background(theme.background)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    // MARK: - Components

    @ViewBuilder
    private func diffBadge(count: Int, label: String, color: Color) -> some View {
        if count > 0 {
            HStack(spacing: 3) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text("\(count) \(label)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(theme.primaryText)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .cornerRadius(4)
        }
    }

    @ViewBuilder
    private func optionChip(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isActive ? theme.primaryText : theme.secondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    isActive
                        ? theme.panelBackground
                        : Color.clear
                )
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isActive ? theme.border : theme.border.opacity(0.5), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
