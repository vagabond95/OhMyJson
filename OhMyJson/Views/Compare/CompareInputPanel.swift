//
//  CompareInputPanel.swift
//  OhMyJson
//
//  Side-by-side input panels for Compare mode (left + right JSON).
//

import SwiftUI

#if os(macOS)
struct CompareInputPanel: View {
    @Environment(ViewerViewModel.self) var viewModel
    @Environment(AppSettings.self) var settings

    @State private var leftScrollPosition: CGFloat = 0
    @State private var rightScrollPosition: CGFloat = 0

    private var theme: AppTheme { settings.currentTheme }

    var body: some View {
        @Bindable var viewModel = viewModel

        HStack(spacing: 0) {
            // Left panel
            panelView(
                label: "Left JSON",
                text: $viewModel.compareLeftText,
                scrollPosition: $leftScrollPosition,
                onTextChange: viewModel.handleCompareLeftTextChange,
                onClear: viewModel.clearCompareLeft,
                parseResult: viewModel.compareLeftParseResult,
                isLargeJSON: viewModel.compareLeftText.utf8.count > InputSize.displayThreshold
            )

            // Vertical divider
            Rectangle()
                .fill(theme.border)
                .frame(width: 1)

            // Right panel
            panelView(
                label: "Right JSON",
                text: $viewModel.compareRightText,
                scrollPosition: $rightScrollPosition,
                onTextChange: viewModel.handleCompareRightTextChange,
                onClear: viewModel.clearCompareRight,
                parseResult: viewModel.compareRightParseResult,
                isLargeJSON: viewModel.compareRightText.utf8.count > InputSize.displayThreshold
            )
        }
    }

    @ViewBuilder
    private func panelView(
        label: String,
        text: Binding<String>,
        scrollPosition: Binding<CGFloat>,
        onTextChange: @escaping (String) -> Void,
        onClear: @escaping () -> Void,
        parseResult: JSONParseResult?,
        isLargeJSON: Bool
    ) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(theme.secondaryText)

                Spacer()

                if !text.wrappedValue.isEmpty {
                    Button(action: onClear) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                            .toolbarIconHover()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(height: 28)
            .background(theme.secondaryBackground)

            Rectangle()
                .fill(theme.border)
                .frame(height: 1)

            // Text editor
            ZStack {
                UndoableTextView(
                    text: text,
                    font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                    onTextChange: onTextChange,
                    scrollPosition: scrollPosition,
                    isEditable: !isLargeJSON
                )

                // Placeholder
                if text.wrappedValue.isEmpty {
                    Text("Paste JSON here...")
                        .font(.system(size: 13))
                        .foregroundColor(theme.secondaryText.opacity(0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
            }

            // Inline error
            if case .failure(let error) = parseResult {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text(error.localizedDescription)
                        .font(.system(size: 10))
                        .foregroundColor(theme.secondaryText)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(theme.secondaryBackground)
            }
        }
        .background(theme.inputBackground)
    }
}
#endif
