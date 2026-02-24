//
//  OnboardingView.swift
//  OhMyJson
//

import SwiftUI

struct OnboardingView: View {
    let jsonPreview: String
    let onCopyJson: () -> Void
    let onGetStarted: () -> Void

    @State private var showKeycap = false
    @State private var isHoveringCopy = false
    @State private var isHoveringKeycap = false

    // Dark metal palette
    private let baseColor = Color(hex: "1A1A1A")
    private let keycapBg = Color(hex: "2A2A2A")
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
        PhaseAnimator([false, true]) { phase in
            let pulsing = phase && !isHoveringKeycap

            VStack(spacing: 14) {
                // "Now press:"
                Text("onboarding.now_press")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(textSecondary)

                // Keycap row — clickable as fallback
                Button(action: onGetStarted) {
                    keycapRow()
                        .background(styledBackground(accent: true))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .scaleEffect(isHoveringKeycap ? 1.08 : (pulsing ? 1.07 : 1.0))
                .brightness(isHoveringKeycap ? 0.1 : 0)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.clear)
                        .shadow(color: pulseColor.opacity(pulsing ? 0.55 : 0.08), radius: pulsing ? 16 : 3)
                )
                .animation(.easeOut(duration: 0.15), value: isHoveringKeycap)
                .onHover { hovering in
                    isHoveringKeycap = hovering
                }

                // "to view formatted JSON"
                Text("onboarding.to_view")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(textSecondary)
            }
        } animation: { _ in
            .easeInOut(duration: 1.2)
        }
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

    // MARK: - Keycap Row

    private func keycapRow() -> some View {
        HStack(spacing: 8) {
            ForEach(HotKeyCombo.defaultOpen.displayLabels, id: \.self) { label in
                keycap(label: label, size: 30)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func keycap(label: String, size: CGFloat) -> some View {
        Text(label)
            .font(.system(size: 20, weight: .medium, design: .rounded))
            .foregroundColor(textPrimary)
            .frame(width: size, height: size)
    }
}

#Preview {
    OnboardingView(
        jsonPreview: SampleData.onboardingJson,
        onCopyJson: { print("Copy JSON") },
        onGetStarted: { print("Get Started") }
    )
}
