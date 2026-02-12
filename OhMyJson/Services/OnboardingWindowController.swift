//
//  OnboardingWindowController.swift
//  OhMyJson
//

#if os(macOS)
import AppKit
import SwiftUI

class OnboardingWindowController: NSObject, NSWindowDelegate, OnboardingControllerProtocol {
    private var window: NSWindow?
    private var keyMonitor: Any?
    var onDismiss: (() -> Void)?

    var isShowing: Bool {
        window != nil
    }

    deinit {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        window?.delegate = nil
    }

    func show() {
        showHotkeyPhase()
    }

    // MARK: - Hotkey Phase

    private func showHotkeyPhase() {
        let onboardingView = OnboardingView(
            onGetStarted: { [weak self] in
                self?.dismissWithFade()
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
        NSApp.activate()
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

        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }

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
