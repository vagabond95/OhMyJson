//
//  CompareView.swift
//  OhMyJson
//
//  Main container for Compare mode: input panels + toolbar + result panels.
//

import SwiftUI

#if os(macOS)
struct CompareView: View {
    @Environment(ViewerViewModel.self) var viewModel
    @Environment(AppSettings.self) var settings

    @State private var inputRatio: CGFloat = CompareLayout.defaultInputRatio
    @State private var isDraggingDivider = false
    @State private var dragStartRatio: CGFloat = 0
    @State private var dragStartY: CGFloat = 0

    private var theme: AppTheme { settings.currentTheme }

    var body: some View {
        GeometryReader { geometry in
            let totalHeight = geometry.size.height
            let dividerHeight: CGFloat = 9
            let toolbarHeight: CGFloat = 36
            let availableHeight = totalHeight - dividerHeight - toolbarHeight
            let inputHeight = max(80, min(availableHeight - 80, availableHeight * inputRatio))
            let resultHeight = availableHeight - inputHeight

            VStack(spacing: 0) {
                // Input Panels (top)
                CompareInputPanel()
                    .frame(height: inputHeight)
                    .allowsHitTesting(!isDraggingDivider)

                // Horizontal divider (draggable)
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: dividerHeight)
                    .overlay(
                        Rectangle()
                            .fill(theme.border)
                            .frame(height: 1)
                            .allowsHitTesting(false)
                    )
                    .background(ResizeVerticalCursorView())
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 2, coordinateSpace: .named("compareArea"))
                            .onChanged { value in
                                if !isDraggingDivider {
                                    isDraggingDivider = true
                                    dragStartRatio = inputRatio
                                    dragStartY = value.startLocation.y
                                    NSCursor.resizeUpDown.push()
                                }
                                let deltaY = value.location.y - dragStartY
                                let newInputHeight = availableHeight * dragStartRatio + deltaY
                                let clampedHeight = max(80, min(availableHeight - 80, newInputHeight))
                                let newRatio = clampedHeight / availableHeight
                                if abs(newRatio - inputRatio) * availableHeight > Timing.dividerDragThreshold {
                                    inputRatio = newRatio
                                }
                            }
                            .onEnded { _ in
                                isDraggingDivider = false
                                NSCursor.pop()
                            }
                    )

                // Toolbar
                CompareToolbar()
                    .frame(height: toolbarHeight)

                Rectangle()
                    .fill(theme.border)
                    .frame(height: 1)

                // Result Panels (bottom)
                CompareResultPanels()
                    .frame(height: resultHeight)
                    .allowsHitTesting(!isDraggingDivider)
            }
            .coordinateSpace(name: "compareArea")
        }
        .background(theme.background)
    }
}

// MARK: - Vertical resize cursor

private struct ResizeVerticalCursorView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = VerticalCursorView()
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        if nsView.window != nil {
            nsView.window?.invalidateCursorRects(for: nsView)
        }
    }
    private class VerticalCursorView: NSView {
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeUpDown)
        }
    }
}
#endif
