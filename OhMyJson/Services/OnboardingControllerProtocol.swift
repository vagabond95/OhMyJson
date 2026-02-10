//
//  OnboardingControllerProtocol.swift
//  OhMyJson
//

#if os(macOS)
protocol OnboardingControllerProtocol: AnyObject {
    var isShowing: Bool { get }
    var onDismiss: (() -> Void)? { get set }
    func show()
}
#endif
