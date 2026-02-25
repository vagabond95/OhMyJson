//
//  CompareResultPanel.swift
//  OhMyJson
//
//  Side-by-side result panels for Compare mode with sync scroll.
//

import SwiftUI
import AppKit

#if os(macOS)
struct CompareResultPanels: View {
    @Environment(ViewerViewModel.self) var viewModel
    @Environment(AppSettings.self) var settings

    @State private var leftScrollPosition: CGFloat = 0
    @State private var rightScrollPosition: CGFloat = 0
    @State private var isSyncingScroll = false

    private var theme: AppTheme { settings.currentTheme }

    var body: some View {
        if let diffResult = viewModel.compareDiffResult, diffResult.isIdentical {
            noDiffView()
        } else {
            HStack(spacing: 0) {
                // Left result
                resultPanel(side: .left)

                // Vertical divider
                Rectangle()
                    .fill(theme.border)
                    .frame(width: 1)

                // Right result
                resultPanel(side: .right)
            }
        }
    }

    @ViewBuilder
    private func noDiffView() -> some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 28))
            Text("No Differences")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(theme.primaryText)
            Text("Both JSON structures are identical")
                .font(.system(size: 12))
                .foregroundColor(theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background)
    }

    @ViewBuilder
    private func resultPanel(side: CompareSide) -> some View {
        ZStack {
            if viewModel.isCompareDiffing {
                // Loading state
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Comparing...")
                        .font(.system(size: 12))
                        .foregroundColor(theme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let renderResult = viewModel.compareRenderResult {
                // Diff result
                let content = side == .left ? renderResult.leftContent : renderResult.rightContent

                CompareResultTextView(
                    attributedString: content,
                    scrollPosition: side == .left ? $leftScrollPosition : $rightScrollPosition,
                    contentId: viewModel.compareRenderVersion,
                    onScroll: { offset in
                        handleScroll(offset: offset, from: side)
                    }
                )
            } else if bothPanelsEmpty {
                // Placeholder
                VStack(spacing: 8) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 24))
                        .foregroundColor(theme.secondaryText.opacity(0.5))
                    Text("Paste JSON in both panels to compare")
                        .font(.system(size: 12))
                        .foregroundColor(theme.secondaryText.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if hasParseError {
                // Error state
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundColor(.orange)
                    Text("Fix JSON errors to compare")
                        .font(.system(size: 12))
                        .foregroundColor(theme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Waiting for input
                VStack(spacing: 8) {
                    Text("Waiting for JSON input...")
                        .font(.system(size: 12))
                        .foregroundColor(theme.secondaryText.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.background)
    }

    private var bothPanelsEmpty: Bool {
        viewModel.compareLeftText.isEmpty && viewModel.compareRightText.isEmpty
    }

    private var hasParseError: Bool {
        if case .failure = viewModel.compareLeftParseResult { return true }
        if case .failure = viewModel.compareRightParseResult { return true }
        return false
    }

    // MARK: - Sync Scroll

    private func handleScroll(offset: CGFloat, from side: CompareSide) {
        guard !isSyncingScroll else { return }
        isSyncingScroll = true

        if side == .left {
            rightScrollPosition = offset
        } else {
            leftScrollPosition = offset
        }

        DispatchQueue.main.async {
            isSyncingScroll = false
        }
    }
}

// MARK: - CompareResultTextView (NSViewRepresentable)

struct CompareResultTextView: NSViewRepresentable {
    let attributedString: NSAttributedString
    @Binding var scrollPosition: CGFloat
    var contentId: Int
    var onScroll: ((CGFloat) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .none

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        // Observe scroll
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        scrollView.contentView.postsBoundsChangedNotifications = true

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        // Update content only when contentId changes
        if context.coordinator.lastContentId != contentId {
            context.coordinator.lastContentId = contentId
            textView.textStorage?.setAttributedString(attributedString)
        }

        // Restore scroll position
        if context.coordinator.lastSetScrollPosition != scrollPosition {
            context.coordinator.lastSetScrollPosition = scrollPosition
            context.coordinator.isProgrammaticScroll = true
            let contentView = nsView.contentView
            let maxY = max(0, (nsView.documentView?.frame.height ?? 0) - contentView.bounds.height)
            let y = min(scrollPosition, maxY)
            contentView.scroll(to: NSPoint(x: 0, y: y))
            nsView.reflectScrolledClipView(contentView)
            DispatchQueue.main.async {
                context.coordinator.isProgrammaticScroll = false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject {
        var parent: CompareResultTextView
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        var lastContentId: Int = -1
        var lastSetScrollPosition: CGFloat = -1
        var isProgrammaticScroll = false

        init(parent: CompareResultTextView) {
            self.parent = parent
        }

        @objc func scrollViewDidScroll(_ notification: Notification) {
            guard !isProgrammaticScroll,
                  let scrollView = scrollView else { return }
            let offset = scrollView.contentView.bounds.origin.y
            parent.scrollPosition = offset
            parent.onScroll?(offset)
        }
    }
}
#endif
