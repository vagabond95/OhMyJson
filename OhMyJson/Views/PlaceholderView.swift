//
//  PlaceholderView.swift
//  OhMyJson
//

import SwiftUI

struct PlaceholderView: View {
    @Environment(AppSettings.self) var settings
    private var theme: AppTheme { settings.currentTheme }

    @State private var shimmerOffset: CGFloat = -1.0

    var body: some View {
        VStack(alignment: .leading) {
            Text("viewer.placeholder")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(theme.secondaryText)
                .padding(.top, 6)
                .modifier(ShimmerEffect(offset: shimmerOffset, color: theme.searchHighlight))

            Spacer()
        }
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.background)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                shimmerOffset = 1.0
            }
        }
        .onDisappear {
            shimmerOffset = -1.0
        }
    }
}

struct ShimmerEffect: ViewModifier {
    let offset: CGFloat
    let color: Color

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            .clear,
                            color.opacity(0.7),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.5)
                    .offset(x: geo.size.width * offset)
                    .blendMode(.sourceAtop)
                }
            )
            .mask(content)
    }
}

#Preview {
    PlaceholderView()
        .frame(width: 300, height: 200)
}
