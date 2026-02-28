//
//  CompareToolbar.swift
//  OhMyJson
//
//  Toolbar for Compare mode: view mode segmented control (top bar)
//  and result header with diff badges, options, copy.
//

import SwiftUI

#if os(macOS)

// MARK: - CompareToolbar (viewMode only)

struct CompareToolbar: View {
    @Environment(ViewerViewModel.self) var viewModel
    @Environment(AppSettings.self) var settings

    private var theme: AppTheme { settings.currentTheme }

    var body: some View {
        HStack(spacing: 8) {
            viewModeSegmentedControl
            Spacer()
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
}

// MARK: - CompareResultHeader

struct CompareResultHeader: View {
    @Environment(ViewerViewModel.self) var viewModel
    @Environment(AppSettings.self) var settings

    private var theme: AppTheme { settings.currentTheme }

    var body: some View {
        HStack(spacing: 8) {
            // Left: diff badges
            if viewModel.isCompareDiffing {
                ProgressView()
                    .controlSize(.small)
                    .padding(.horizontal, 4)
            } else if let result = viewModel.compareDiffResult, !result.isIdentical {
                diffBadge(count: result.addedCount, label: "added", color: theme.diffAddedGutter)
                diffBadge(count: result.removedCount, label: "removed", color: theme.diffRemovedGutter)
                diffBadge(count: result.modifiedCount, label: "modified", color: theme.diffModifiedGutter)
            }

            Spacer()

            // Right: option checkboxes + copy button
            HStack(spacing: 6) {
                optionCheckbox(
                    label: "Key Order",
                    isActive: viewModel.compareIgnoreKeyOrder,
                    action: { viewModel.updateCompareOption(ignoreKeyOrder: !viewModel.compareIgnoreKeyOrder) },
                    tooltipTitle: "Ignore Key Order",
                    tooltipDescription: "Treat objects with same keys in different order as identical"
                )
                optionCheckbox(
                    label: "Array Order",
                    isActive: viewModel.compareIgnoreArrayOrder,
                    action: { viewModel.updateCompareOption(ignoreArrayOrder: !viewModel.compareIgnoreArrayOrder) },
                    tooltipTitle: "Ignore Array Order",
                    tooltipDescription: "Treat arrays with same elements in different order as identical"
                )
                optionCheckbox(
                    label: "Strict Type",
                    isActive: viewModel.compareStrictType,
                    action: { viewModel.updateCompareOption(strictType: !viewModel.compareStrictType) },
                    tooltipTitle: "Strict Type Check",
                    tooltipDescription: "Treat different types (e.g. \"1\" vs 1) as modifications"
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
        .padding(.vertical, 3)
        .background(theme.secondaryBackground)
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
    private func optionCheckbox(
        label: String,
        isActive: Bool,
        action: @escaping () -> Void,
        tooltipTitle: String,
        tooltipDescription: String
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: isActive ? "checkmark.square.fill" : "square")
                    .font(.system(size: 11))
                    .foregroundColor(isActive ? theme.primaryText : theme.secondaryText)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isActive ? theme.primaryText : theme.secondaryText)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .instantRichTooltip(position: .bottom, maxWidth: 220) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tooltipTitle)
                    .font(.system(size: 11, weight: .semibold))
                Text(tooltipDescription)
                    .font(.system(size: 10))
                    .opacity(0.8)
            }
        }
    }
}
#endif
