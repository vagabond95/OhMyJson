//
//  OnboardingView.swift
//  OhMyJson
//

import SwiftUI

struct OnboardingView: View {
    let onGetStarted: () -> Void
    let onCopySampleJson: () -> Void

    @State private var showToast = false

    // Dark metal palette
    private let baseColor = Color(hex: "1A1A1A")
    private let keycapBg = Color(hex: "2A2A2A")
    private let textPrimary = Color(hex: "E4E3E0")
    private let textSecondary = Color(hex: "9E9D9B")

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                VStack(spacing: 20) {

                    // Copy json
                    Button(action: {
                        onCopySampleJson()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showToast = true
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
                                .foregroundColor(textPrimary)
                            Text("onboarding.copy_json")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(textPrimary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 12)
                        .background(buttonBackground())
                    }
                    .buttonStyle(.plain)

                    arrowDown()

                    // Hotkey
                    Button(action: onGetStarted) {
                        keycapRow().background(buttonBackground())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 40)
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
                .padding(.bottom, 16)
                .allowsHitTesting(false)
            }
        }
        .frame(width: 250, height: 250)
        .preferredColorScheme(.dark)
    }

    private func buttonBackground() -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(keycapBg)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.10),
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
                        Color.white.opacity(0.15),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: Color.black.opacity(0.4),
                radius: 3,
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
