//
//  AccessibilityOnboardingView.swift
//  OhMyJson
//

import SwiftUI

#if os(macOS)
struct AccessibilityOnboardingView: View {
    var accessibilityManager = AccessibilityManager.shared
    let onSkip: () -> Void

    // Dark metal palette (matching OnboardingView)
    private let baseColor = Color(hex: "1A1A1A")
    private let keycapBg = Color(hex: "2A2A2A")
    private let textPrimary = Color(hex: "E4E3E0")
    private let textSecondary = Color(hex: "9E9D9B")

    var body: some View {
        VStack(spacing: 24) {
            

            VStack(spacing: 16) {
                Text("accessibility.title")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(textPrimary)

                Text("accessibility.description")
                    .font(.system(size: 11))
                    .foregroundColor(textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Spacer().frame(height: 0)

            HStack(spacing: 10) {
                Button(action: onSkip) {
                    Text("accessibility.skip")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(keycapBg.opacity(0.6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)

                Button(action: {
                    AccessibilityManager.shared.openSystemSettingsAccessibility()
                }) {
                    Text("accessibility.open_settings")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(keycapBg)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
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
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 24)
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
        .preferredColorScheme(.dark)
    }
}

#Preview {
    AccessibilityOnboardingView(onSkip: {})
}
#endif
