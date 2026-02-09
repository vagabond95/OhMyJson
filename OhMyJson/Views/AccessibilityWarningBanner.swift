//
//  AccessibilityWarningBanner.swift
//  OhMyJson
//

import SwiftUI

#if os(macOS)
struct AccessibilityWarningBanner: View {
    @ObservedObject var accessibilityManager = AccessibilityManager.shared
    @Environment(\.colorScheme) private var colorScheme

    private var bannerBackground: Color {
        colorScheme == .dark ? Color(hex: "3D1111") : Color(hex: "FDE8E8")
    }
    private var bannerBorder: Color {
        colorScheme == .dark ? Color(hex: "8B2020") : Color(hex: "E8A0A0")
    }
    private var bannerText: Color {
        colorScheme == .dark ? Color(hex: "FFA0A0") : Color(hex: "9B1C1C")
    }
    private var bannerIcon: Color {
        colorScheme == .dark ? Color(hex: "FF6B6B") : Color(hex: "DC2626")
    }
    private var buttonBackground: Color {
        colorScheme == .dark ? Color(hex: "8B2020") : Color(hex: "DC2626")
    }

    var body: some View {
        if !accessibilityManager.isAccessibilityGranted {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(bannerIcon)

                Text("Accessibility permission required for hotkeys")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(bannerText)

                Button(action: {
                    AccessibilityManager.shared.openSystemSettingsAccessibility()
                }) {
                    Text("Fix")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(buttonBackground)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(bannerBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(bannerBorder, lineWidth: 1)
                    )
            )
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}

struct AccessibilityWarningModifier: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            content

            VStack {
                Spacer()
                AccessibilityWarningBanner()
                    .padding(.bottom, 12)
            }
            .animation(.easeInOut(duration: 0.3), value: AccessibilityManager.shared.isAccessibilityGranted)
        }
    }
}

extension View {
    func withAccessibilityWarning() -> some View {
        modifier(AccessibilityWarningModifier())
    }
}
#endif
