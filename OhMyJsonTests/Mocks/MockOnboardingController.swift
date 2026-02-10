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

    func show() {
        showCallCount += 1
        isShowing = true
    }
}
#endif
