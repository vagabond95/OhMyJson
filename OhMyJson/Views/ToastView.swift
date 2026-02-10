//
//  ToastView.swift
//  OhMyJson
//

import SwiftUI

#if os(macOS)
class ToastManager: ObservableObject {
    static let shared = ToastManager()

    @Published var isShowing = false
    @Published var message = ""

    private var hideTask: DispatchWorkItem?

    private init() {}

    func show(_ message: String, duration: TimeInterval = Duration.toastDefault) {
        hideTask?.cancel()

        self.message = message

        withAnimation(.easeInOut(duration: Animation.standard)) {
            self.isShowing = true
        }

        let task = DispatchWorkItem { [weak self] in
            withAnimation(.easeInOut(duration: Animation.standard)) {
                self?.isShowing = false
            }
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)
    }
}

struct ToastView: View {
    @ObservedObject var manager = ToastManager.shared

    @ObservedObject private var settings = AppSettings.shared
    private var theme: AppTheme { settings.currentTheme }

    var body: some View {
        if manager.isShowing {
            Text(manager.message)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(theme.primaryText)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(theme.panelBackground)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.border, lineWidth: 1)
                )
                .shadow(color: .black.opacity(theme.shadowOpacity), radius: 8, x: 0, y: 4)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }
}

struct ToastModifier: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            content

            VStack {
                Spacer()
                ToastView()
                    .padding(.bottom, 40)
            }
        }
    }
}

extension View {
    func withToast() -> some View {
        modifier(ToastModifier())
    }
}
#endif
