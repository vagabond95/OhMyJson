//
//  OnboardingView.swift
//  OhMyJson
//

import SwiftUI

struct OnboardingView: View {
    let onGetStarted: () -> Void
    let onCopySampleJson: () -> Void

    @State private var showToast = false
    @State private var showKeycap = false
    @State private var isHoveringCopy = false
    @State private var isHoveringKeycap = false
    @State private var isPulsing = false

    // Dark metal palette
    private let baseColor = Color(hex: "1A1A1A")
    private let keycapBg = Color(hex: "2A2A2A")
    private let textPrimary = Color(hex: "E4E3E0")
    private let textSecondary = Color(hex: "9E9D9B")
    private let accentColor = Color(hex: "4A4A4A")

    var body: some View {
        ZStack {
            VStack(spacing: 20) {
                // Copy json
                Button(action: {
                    onCopySampleJson()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showToast = true
                    }
                    withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
                        showKeycap = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showToast = false
                        }
                    }
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 30, weight: .light))
                            .foregroundColor(showKeycap ? textPrimary : .white)
                        Text("onboarding.copy_json")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(showKeycap ? textPrimary : .white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
                    .background(styledBackground(accent: !showKeycap))
                }
                .buttonStyle(.plain)
                .disabled(showKeycap)
                .scaleEffect(!showKeycap && isHoveringCopy ? 1.05 : 1.0)
                .brightness(!showKeycap && isHoveringCopy ? 0.08 : 0)
                .opacity(showKeycap ? 0.4 : 1.0)
                .shadow(color: Color.white.opacity(isPulsing && !showKeycap ? 0.3 : 0), radius: isPulsing && !showKeycap ? 8 : 0)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.15)) {
                        isHoveringCopy = hovering
                    }
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                }

                if showKeycap {
                    arrowDown()
                        .transition(.opacity.combined(with: .move(edge: .top)))

                    // Hotkey
                    Button(action: onGetStarted) {
                        keycapRow().background(styledBackground(accent: true))
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(isHoveringKeycap ? 1.05 : 1.0)
                    .brightness(isHoveringKeycap ? 0.08 : 0)
                    .shadow(color: Color.white.opacity(isPulsing ? 0.3 : 0.1), radius: isPulsing ? 8 : 4)
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.15)) {
                            isHoveringKeycap = hovering
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(width: 250, height: 250)
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

            // Toast overlay
            if showToast {
                VStack {
                    Spacer()
                    Text("toast.json_copied")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(keycapBg)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
                .padding(.bottom, -24)
                .allowsHitTesting(false)
            }
        }
        .frame(width: 250, height: 250)
        .preferredColorScheme(.dark)
    }

    private func styledBackground(accent: Bool) -> some View {
        let fillColor = accent ? accentColor : keycapBg
        let gradientOpacity = accent ? 0.20 : 0.10
        let strokeOpacity = accent ? 0.20 : 0.15
        let shadowColor = accent ? Color.white.opacity(0.15) : Color.black.opacity(0.4)

        return RoundedRectangle(cornerRadius: 10)
            .fill(fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(gradientOpacity),
                                Color.clear,
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        Color.white.opacity(strokeOpacity),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: shadowColor,
                radius: accent ? 4 : 3,
                y: 2
            )
    }

    // MARK: - Arrow Down

    private func arrowDown() -> some View {
        Image(systemName: "arrow.down")
            .font(.system(size: 20, weight: .medium))
            .foregroundColor(textSecondary.opacity(0.6))
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
    OnboardingView(onGetStarted: {
        print("Get Started tapped")
    }, onCopySampleJson: {
        print("Copy Sample JSON tapped")
    })
}
