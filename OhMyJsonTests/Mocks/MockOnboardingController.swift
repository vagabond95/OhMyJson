//
//  MockOnboardingController.swift
//  OhMyJsonTests
//

#if os(macOS)
@testable import OhMyJson

final class MockOnboardingController: OnboardingControllerProtocol {
    var isShowing: Bool = false
    var onDismiss: (() -> Void)?

    var showCallCount = 0
    var dismissCallCount = 0

    func show() {
        showCallCount += 1
        isShowing = true
    }

    func dismiss() {
        dismissCallCount += 1
        isShowing = false
        onDismiss?()
    }
}
#endif
