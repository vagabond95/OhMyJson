//
//  MockClipboardService.swift
//  OhMyJsonTests
//

@testable import OhMyJson

final class MockClipboardService: ClipboardServiceProtocol {
    var storedText: String?

    func readText() -> String? {
        storedText
    }

    func writeText(_ text: String) {
        storedText = text
    }

    func hasText() -> Bool {
        storedText != nil
    }
}
