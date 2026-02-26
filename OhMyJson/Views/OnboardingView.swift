//
//  OnboardingView.swift
//  OhMyJson
//

import SwiftUI
import AppKit

// MARK: - KeyPressTracker

@Observable
final class KeyPressTracker {
    let combo: HotKeyCombo

    private(set) var pressedKeys: Set<Int> = []
    private(set) var allKeysPressed = false

    var onComplete: (() -> Void)?

    @ObservationIgnored private var flagsMonitor: Any?
    @ObservationIgnored private var keyDownMonitor: Any?
    @ObservationIgnored private var keyUpMonitor: Any?
    @ObservationIgnored private var completionWorkItem: DispatchWorkItem?
    @ObservationIgnored private lazy var elements = combo.keyElements

    init(combo: HotKeyCombo) {
        self.combo = combo
    }

    deinit {
        stopMonitoring()
        onComplete = nil
    }

    // MARK: - Computed

    /// Index of the first unpressed key — the one to highlight as "guided"
    var guidedKeyIndex: Int? {
        guard !allKeysPressed else { return nil }
        return elements.first(where: { !pressedKeys.contains($0.id) })?.id
    }

    // MARK: - Monitoring

    func startMonitoring() {
        stopMonitoring()

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
            return event
        }

        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.handleKeyUp(event)
            return event
        }
    }

    func stopMonitoring() {
        if let m = flagsMonitor { NSEvent.removeMonitor(m); flagsMonitor = nil }
        if let m = keyDownMonitor { NSEvent.removeMonitor(m); keyDownMonitor = nil }
        if let m = keyUpMonitor { NSEvent.removeMonitor(m); keyUpMonitor = nil }
        completionWorkItem?.cancel()
        completionWorkItem = nil
    }

    // MARK: - Event Handlers

    private func handleFlagsChanged(_ event: NSEvent) {
        guard !allKeysPressed else { return }
        let currentFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        for element in elements where element.isModifier {
            guard let flag = element.modifierFlag else { continue }
            if currentFlags.contains(flag) {
                pressedKeys.insert(element.id)
            } else {
                pressedKeys.remove(element.id)
            }
        }
        checkCompletion()
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard !allKeysPressed else { return }
        for element in elements where !element.isModifier {
            if let kc = element.keyCode, event.keyCode == kc {
                pressedKeys.insert(element.id)
            }
        }
        checkCompletion()
    }

    private func handleKeyUp(_ event: NSEvent) {
        guard !allKeysPressed else { return }
        for element in elements where !element.isModifier {
            if let kc = element.keyCode, event.keyCode == kc {
                pressedKeys.remove(element.id)
            }
        }
    }

    private func checkCompletion() {
        let allIds = Set(elements.map(\.id))
        if pressedKeys == allIds {
            allKeysPressed = true
            let work = DispatchWorkItem { [weak self] in
                self?.onComplete?()
            }
            completionWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }
}

// MARK: - OnboardingView

struct OnboardingView: View {
    let jsonPreview: String
    let onCopyJson: () -> Void
    let onGetStarted: () -> Void

    @State private var showKeycap = false
    @State private var isHoveringCopy = false
    @State private var tracker = KeyPressTracker(combo: .defaultOpen)

    // Dark metal palette
    private let baseColor = Color(hex: "1A1A1A")
    private let keycapBg = Color(hex: "2A2A2A")
    private let keycapPressedBg = Color(hex: "3A3A3A")
    private let codeBg = Color(hex: "111111")
    private let textPrimary = Color(hex: "E4E3E0")
    private let textSecondary = Color(hex: "9E9D9B")
    private let buttonBg = Color(hex: "1E1E1E")
    private let pulseColor = Color(hex: "8AB4F8") // soft blue glow

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            if showKeycap {
                // MARK: - Step 2: Hotkey Guide
                step2HotkeyGuide()
                    .transition(.opacity)
            } else {
                // MARK: - Step 1: JSON Preview + Copy
                step1JsonPreview()
                    .transition(.opacity)
            }

            Spacer()
        }
        .frame(width: 280, height: 260)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(baseColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.03), Color.clear,
                                ],
                                center: .top,
                                startRadius: 0,
                                endRadius: 350
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.12),
                                    Color.white.opacity(0.04),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }

    // MARK: - Step 1: JSON Preview + Copy Button

    private func step1JsonPreview() -> some View {
        PhaseAnimator([false, true], trigger: showKeycap) { phase in
            let pulsing = phase && !isHoveringCopy

            VStack(spacing: 30) {
                // JSON code block
                Text(jsonPreview)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(textPrimary)
                    .lineSpacing(2)
                    .padding(36)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(codeBg)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 20)

                // Copy JSON button
                Button {
                    onCopyJson()
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showKeycap = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                        Text("onboarding.copy_json")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(styledBackground(accent: true))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .scaleEffect(isHoveringCopy ? 1.08 : (pulsing ? 1.07 : 1.0))
                .brightness(isHoveringCopy ? 0.1 : 0)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.clear)
                        .shadow(color: pulseColor.opacity(pulsing ? 0.55 : 0.08), radius: pulsing ? 16 : 3)
                )
                .animation(.easeOut(duration: 0.15), value: isHoveringCopy)
                .onHover { hovering in
                    isHoveringCopy = hovering
                }
            }
        } animation: { _ in
            .easeInOut(duration: 1.2)
        }
    }

    // MARK: - Step 2: Hotkey Guide

    private func step2HotkeyGuide() -> some View {
        let elements = tracker.combo.keyElements
        let compact = elements.count > 3

        return PhaseAnimator([false, true]) { phase in
            VStack(spacing: 14) {
                Text("onboarding.now_press")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(textSecondary)

                HStack(spacing: compact ? 4 : 6) {
                    ForEach(Array(elements.enumerated()), id: \.element.id) { index, element in
                        if index > 0 {
                            Text("+")
                                .font(.system(size: compact ? 12 : 14, weight: .medium, design: .rounded))
                                .foregroundColor(textSecondary.opacity(0.6))
                        }

                        keycapView(
                            element: element,
                            isPressed: tracker.pressedKeys.contains(element.id),
                            isGuided: tracker.guidedKeyIndex == element.id,
                            allDone: tracker.allKeysPressed,
                            pulsing: phase,
                            compact: compact
                        )
                    }
                }

                Text("onboarding.to_view")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(textSecondary)
            }
        } animation: { _ in
            .easeInOut(duration: 1.2)
        }
        .onAppear {
            tracker.onComplete = onGetStarted
            tracker.startMonitoring()
        }
        .onDisappear {
            tracker.stopMonitoring()
        }
    }

    // MARK: - Individual Keycap View

    private func keycapView(
        element: KeyElement,
        isPressed: Bool,
        isGuided: Bool,
        allDone: Bool,
        pulsing: Bool,
        compact: Bool
    ) -> some View {
        let fontSize: CGFloat = compact ? 13 : 15
        let minW: CGFloat = compact ? 36 : 44
        let minH: CGFloat = compact ? 30 : 36
        let hPad: CGFloat = compact ? 7 : 10

        let bgColor = (isPressed || allDone) ? keycapPressedBg : keycapBg

        let borderColor: Color
        let borderWidth: CGFloat
        if isPressed || allDone {
            borderColor = pulseColor.opacity(0.6)
            borderWidth = 1.5
        } else if isGuided {
            borderColor = pulseColor.opacity(0.4)
            borderWidth = 1.5
        } else {
            borderColor = Color.white.opacity(0.12)
            borderWidth = 1
        }

        let scale: CGFloat = isPressed && !allDone ? 0.93 : 1.0

        let shadowColor: Color
        let shadowRadius: CGFloat
        if allDone {
            shadowColor = pulseColor.opacity(0.4)
            shadowRadius = 6
        } else if isPressed {
            shadowColor = pulseColor.opacity(0.3)
            shadowRadius = 4
        } else if isGuided {
            shadowColor = pulseColor.opacity(pulsing ? 0.5 : 0.15)
            shadowRadius = pulsing ? 12 : 4
        } else {
            shadowColor = Color.black.opacity(0.3)
            shadowRadius = 2
        }

        return Text(element.label)
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .foregroundColor(textPrimary)
            .padding(.horizontal, hPad)
            .frame(minWidth: minW, minHeight: minH)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(bgColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.06), Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .shadow(color: shadowColor, radius: shadowRadius)
            .scaleEffect(scale)
            .animation(.easeOut(duration: 0.1), value: isPressed)
            .animation(.easeOut(duration: 0.1), value: allDone)
    }

    // MARK: - Styled Background

    private func styledBackground(accent: Bool) -> some View {
        let fillColor = accent ? buttonBg : keycapBg
        let strokeColor = accent ? pulseColor.opacity(0.25) : Color.white.opacity(0.15)

        return RoundedRectangle(cornerRadius: 10)
            .fill(fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.08),
                                Color.clear,
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(strokeColor, lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(0.4),
                radius: 3,
                y: 2
            )
    }
}

#Preview {
    OnboardingView(
        jsonPreview: SampleData.onboardingJson,
        onCopyJson: { print("Copy JSON") },
        onGetStarted: { print("Get Started") }
    )
}
