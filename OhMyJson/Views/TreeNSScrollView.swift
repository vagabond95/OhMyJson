//
//  TreeNSScrollView.swift
//  OhMyJson
//
//  NSViewRepresentable wrapping FastScrollView for TreeView with horizontal scroll support
//

import SwiftUI
import AppKit

#if os(macOS)

// MARK: - Scroll Command

struct TreeScrollCommand: Equatable {
    let targetNodeId: UUID
    let targetIndex: Int
    let anchor: TreeScrollAnchor
    let version: Int
}

enum TreeScrollAnchor: Equatable {
    case top
    case center
    case visible
}

// MARK: - ArrowCursorHostingView

/// NSHostingView subclass that forces the arrow cursor, preventing I-beam from SwiftUI Text views
class ArrowCursorHostingView<Content: View>: NSHostingView<Content> {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}

// MARK: - FlippedDocumentView

/// Flipped NSView container that hosts an NSHostingView for top-to-bottom layout
class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }

    private var hostingView: ArrowCursorHostingView<AnyView>?

    func setContent(_ content: AnyView) {
        if let existing = hostingView {
            existing.rootView = content
        } else {
            let hv = ArrowCursorHostingView(rootView: content)
            hv.translatesAutoresizingMaskIntoConstraints = false
            addSubview(hv)
            NSLayoutConstraint.activate([
                hv.leadingAnchor.constraint(equalTo: leadingAnchor),
                hv.topAnchor.constraint(equalTo: topAnchor),
                hv.widthAnchor.constraint(equalTo: widthAnchor),
            ])
            hostingView = hv
        }
    }

    func contentFittingSize() -> NSSize {
        hostingView?.fittingSize ?? .zero
    }
}

// MARK: - TreeNSScrollView

struct TreeNSScrollView: NSViewRepresentable {
    let treeContent: AnyView
    let nodeCount: Int
    let viewportWidth: CGFloat
    let estimatedContentWidth: CGFloat
    let scrollCommand: TreeScrollCommand?
    let isActive: Bool
    let isRestoringTabState: Bool

    @Binding var scrollAnchorId: UUID?
    @Binding var horizontalScrollOffset: CGFloat
    @Binding var topVisibleIndex: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> FastScrollView {
        let scrollView = FastScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.usesPredominantAxisScrolling = true
        scrollView.drawsBackground = false

        let documentView = FlippedDocumentView()
        documentView.setContent(treeContent)

        scrollView.documentView = documentView

        context.coordinator.scrollView = scrollView
        context.coordinator.documentView = documentView

        // Calculate initial document size
        let fittingSize = documentView.contentFittingSize()
        let documentWidth = max(viewportWidth, max(fittingSize.width, estimatedContentWidth))
        let documentHeight = CGFloat(nodeCount) * TreeLayout.rowHeight + 8
        documentView.frame = NSRect(x: 0, y: 0, width: documentWidth, height: documentHeight)

        // Restore scroll position immediately (SelectableTextView pattern)
        if horizontalScrollOffset > 0 || scrollCommand != nil {
            let clipView = scrollView.contentView
            clipView.scroll(to: NSPoint(x: horizontalScrollOffset, y: 0))
            scrollView.reflectScrolledClipView(clipView)
        }

        // Pre-seed last scroll command version to avoid re-execution on first update
        if let cmd = scrollCommand {
            context.coordinator.lastScrollCommandVersion = cmd.version
        }

        // Observe scroll events
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        return scrollView
    }

    func updateNSView(_ scrollView: FastScrollView, context: Context) {
        context.coordinator.parent = self

        guard let documentView = context.coordinator.documentView else { return }

        // Update SwiftUI content
        documentView.setContent(treeContent)

        // Update document size when nodeCount or viewportWidth changes
        let nodeCountChanged = context.coordinator.lastNodeCount != nodeCount
        let viewportChanged = context.coordinator.lastViewportWidth != viewportWidth
        let contentWidthChanged = context.coordinator.lastEstimatedContentWidth != estimatedContentWidth

        if nodeCountChanged || viewportChanged || contentWidthChanged {
            context.coordinator.lastNodeCount = nodeCount
            context.coordinator.lastViewportWidth = viewportWidth
            context.coordinator.lastEstimatedContentWidth = estimatedContentWidth

            let fittingSize = documentView.contentFittingSize()
            let documentWidth = max(viewportWidth, max(fittingSize.width, estimatedContentWidth))
            let documentHeight = CGFloat(nodeCount) * TreeLayout.rowHeight + 8
            documentView.frame = NSRect(x: 0, y: 0, width: documentWidth, height: documentHeight)
        }

        // Handle tab restoration
        if isRestoringTabState {
            let clipView = scrollView.contentView
            clipView.scroll(to: NSPoint(x: horizontalScrollOffset, y: clipView.bounds.origin.y))
            scrollView.reflectScrolledClipView(clipView)
            if let cmd = scrollCommand {
                context.coordinator.lastScrollCommandVersion = cmd.version
            }
            return
        }

        // Execute scroll command (version-based dedup)
        if let cmd = scrollCommand, cmd.version != context.coordinator.lastScrollCommandVersion {
            context.coordinator.lastScrollCommandVersion = cmd.version
            context.coordinator.executeScrollCommand(cmd, in: scrollView)
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject {
        var parent: TreeNSScrollView
        weak var scrollView: FastScrollView?
        weak var documentView: FlippedDocumentView?

        var lastNodeCount: Int = 0
        var lastViewportWidth: CGFloat = 0
        var lastEstimatedContentWidth: CGFloat = 0
        var lastScrollCommandVersion: Int = -1

        private var scrollDebounceItem: DispatchWorkItem?
        private var isExecutingScrollCommand = false

        init(_ parent: TreeNSScrollView) {
            self.parent = parent
        }

        @objc func scrollViewDidScroll(_ notification: Notification) {
            guard !parent.isRestoringTabState,
                  !isExecutingScrollCommand,
                  let scrollView = scrollView else { return }

            let clipView = scrollView.contentView
            let currentX = clipView.bounds.origin.x
            let currentY = clipView.bounds.origin.y

            // Update horizontal offset immediately
            if abs(parent.horizontalScrollOffset - currentX) > Timing.scrollPositionThreshold {
                DispatchQueue.main.async {
                    self.parent.horizontalScrollOffset = currentX
                }
            }

            // Debounce vertical topVisibleIndex updates
            scrollDebounceItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let topIndex = max(0, Int(currentY / TreeLayout.rowHeight))
                if self.parent.topVisibleIndex != topIndex {
                    self.parent.topVisibleIndex = topIndex
                }
            }
            scrollDebounceItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: item)
        }

        func executeScrollCommand(_ cmd: TreeScrollCommand, in scrollView: FastScrollView) {
            isExecutingScrollCommand = true

            let clipView = scrollView.contentView
            let currentX = clipView.bounds.origin.x
            let targetY = CGFloat(cmd.targetIndex) * TreeLayout.rowHeight + 4
            let visibleHeight = clipView.bounds.height
            let documentHeight = scrollView.documentView?.frame.height ?? 0
            let maxY = max(0, documentHeight - visibleHeight)

            let scrollY: CGFloat
            switch cmd.anchor {
            case .top:
                scrollY = min(targetY, maxY)
            case .center:
                scrollY = min(max(0, targetY - visibleHeight / 2), maxY)
            case .visible:
                let currentTop = clipView.bounds.origin.y
                let currentBottom = currentTop + visibleHeight
                let nodeBottom = targetY + TreeLayout.rowHeight
                if targetY >= currentTop && nodeBottom <= currentBottom {
                    // Already visible — don't scroll
                    isExecutingScrollCommand = false
                    return
                }
                if targetY < currentTop {
                    scrollY = min(targetY, maxY)
                } else {
                    scrollY = min(max(0, nodeBottom - visibleHeight), maxY)
                }
            }

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Animation.quick
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                clipView.animator().setBoundsOrigin(NSPoint(x: currentX, y: scrollY))
            } completionHandler: { [weak self] in
                self?.isExecutingScrollCommand = false
                scrollView.reflectScrolledClipView(clipView)
            }
        }

        deinit {
            scrollDebounceItem?.cancel()
            NotificationCenter.default.removeObserver(self)
        }
    }
}

#endif
