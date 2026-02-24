//
//  OnboardingWindowController.swift
//  OhMyJson
//

#if os(macOS)
import AppKit
import SwiftUI

private class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

class OnboardingWindowController: NSObject, NSWindowDelegate, OnboardingControllerProtocol {
    private var window: NSWindow?
    var onDismiss: (() -> Void)?

    var isShowing: Bool {
        window != nil
    }

    deinit {
        window?.delegate = nil
    }

    func show() {
        showHotkeyPhase()
    }

    func dismiss() {
        dismissWithFade()
    }

    // MARK: - Hotkey Phase

    private func showHotkeyPhase() {
        let jsonText = SampleData.onboardingJson

        let onboardingView = OnboardingView(
            jsonPreview: jsonText,
            onCopyJson: {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(jsonText, forType: .string)
            },
            onGetStarted: { [weak self] in
                self?.dismissWithFade()
            }
        )
        let hostingView = NSHostingView(rootView: onboardingView)
        createWindow(with: hostingView)
    }

    // MARK: - Window Management

    private func createWindow(with contentView: NSView) {
        let window = KeyableWindow(
            contentRect: NSRect(x: 0, y: 0, width: WindowSize.onboardingWidth, height: WindowSize.onboardingHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.contentView = contentView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        self.window = window

        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func dismissWithFade() {
        guard let window = window else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            window.delegate = nil
            window.orderOut(nil)
            self?.window = nil
            self?.onDismiss?()
        })
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return false
    }
}
#endif
