//
//  MockWindowManager.swift
//  OhMyJsonTests
//

#if os(macOS)
@testable import OhMyJson

final class MockWindowManager: WindowManagerProtocol {
    var isViewerOpen: Bool = false

    var createNewTabCallCount = 0
    var lastCreatedJSON: String?
    var closeViewerCallCount = 0
    var bringToFrontCallCount = 0

    func createNewTab(with jsonString: String?) {
        createNewTabCallCount += 1
        lastCreatedJSON = jsonString
        isViewerOpen = true
    }

    func closeViewer() {
        closeViewerCallCount += 1
        isViewerOpen = false
    }

    func bringToFront() {
        bringToFrontCallCount += 1
    }
}
#endif
