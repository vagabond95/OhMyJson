//
//  OnboardingWindowController.swift
//  OhMyJson
//

#if os(macOS)
import AppKit
import SwiftUI
import Combine

class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var keyMonitor: Any?
    private var accessibilityCancellable: AnyCancellable?
    var onDismiss: (() -> Void)?

    var isShowing: Bool {
        window != nil
    }

    func show() {
        if AXIsProcessTrusted() {
            showHotkeyPhase()
        } else {
            showAccessibilityPhase()
        }
    }

    // MARK: - Accessibility Phase

    private func showAccessibilityPhase() {
        let accessibilityView = AccessibilityOnboardingView(onSkip: { [weak self] in
            self?.transitionToHotkeyPhase()
        })
        let hostingView = NSHostingView(rootView: accessibilityView)
        createWindow(with: hostingView)

        // Monitor for permission grant → auto-transition
        accessibilityCancellable = AccessibilityManager.shared.$isAccessibilityGranted
            .dropFirst()
            .filter { $0 }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.transitionToHotkeyPhase()
            }
    }

    private func transitionToHotkeyPhase() {
        accessibilityCancellable = nil

        guard let window = window else { return }

        // Fade out
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self = self, let window = self.window else { return }

            // Replace content
            let onboardingView = OnboardingView(
                onGetStarted: {
                    self.dismissWithFade()
                },
                onCopySampleJson: {}
            )
            let hostingView = NSHostingView(rootView: onboardingView)
            window.contentView = hostingView

            // Install key monitor for hotkey phase
            self.installKeyMonitor()

            // Fade in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                window.animator().alphaValue = 1
            })
        })
    }

    // MARK: - Hotkey Phase

    private func showHotkeyPhase() {
        let onboardingView = OnboardingView(
            onGetStarted: {
                self.dismissWithFade()
            },
            onCopySampleJson: {}
        )
        let hostingView = NSHostingView(rootView: onboardingView)
        createWindow(with: hostingView)
        installKeyMonitor()
    }

    // MARK: - Window Management

    private func createWindow(with contentView: NSView) {
        let window = NSWindow(
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
        NSApp.activate(ignoringOtherApps: true)
    }

    private func installKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }

        let defaultCombo = HotKeyCombo.defaultOpen
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(defaultCombo.nsEventModifierFlags) && event.keyCode == UInt16(defaultCombo.keyCode) {
                self?.dismissWithFade()
                return nil
            }
            return event
        }
    }

    private func dismissWithFade() {
        guard let window = window else { return }

        accessibilityCancellable = nil

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
