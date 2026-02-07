//
//  OnboardingWindowController.swift
//  OhMyJson
//

#if os(macOS)
import AppKit
import SwiftUI

class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var keyMonitor: Any?
    var onDismiss: (() -> Void)?

    var isShowing: Bool {
        window != nil
    }

    func show() {
        let onboardingView = OnboardingView(
            onGetStarted: {
                self.dismissWithFade()
            },
            onCopySampleJson: {
                // Toast is handled internally by OnboardingView @State
            }
        )

        let hostingView = NSHostingView(rootView: onboardingView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        self.window = window

        // Listen for ⌘J to dismiss onboarding
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command) && event.keyCode == 0x26 /* kVK_ANSI_J */ {
                self?.dismissWithFade()
                return nil
            }
            return event
        }

        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func dismissWithFade() {
        guard let window = window else { return }

        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
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
