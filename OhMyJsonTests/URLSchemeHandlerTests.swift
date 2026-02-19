//
//  URLSchemeHandlerTests.swift
//  OhMyJsonTests
//

import Testing
import Foundation
@testable import OhMyJson

#if os(macOS)
@Suite("URLSchemeHandler Tests")
struct URLSchemeHandlerTests {

    // MARK: - parseAction

    @Test("ohmyjson://open returns openFromClipboard")
    func openAction() {
        let url = URL(string: "ohmyjson://open")!
        #expect(URLSchemeHandler.parseAction(from: url) == .openFromClipboard)
    }

    @Test("ohmyjson://open with trailing slash returns openFromClipboard")
    func openActionTrailingSlash() {
        let url = URL(string: "ohmyjson://open/")!
        #expect(URLSchemeHandler.parseAction(from: url) == .openFromClipboard)
    }

    @Test("ohmyjson://open with query parameters returns openFromClipboard")
    func openActionWithQuery() {
        let url = URL(string: "ohmyjson://open?source=chrome")!
        #expect(URLSchemeHandler.parseAction(from: url) == .openFromClipboard)
    }

    @Test("Unknown host returns unknown")
    func unknownHost() {
        let url = URL(string: "ohmyjson://unknown")!
        #expect(URLSchemeHandler.parseAction(from: url) == .unknown)
    }

    @Test("Empty host returns unknown")
    func emptyHost() {
        let url = URL(string: "ohmyjson:///")!
        #expect(URLSchemeHandler.parseAction(from: url) == .unknown)
    }

    @Test("Wrong scheme returns unknown")
    func wrongScheme() {
        let url = URL(string: "https://open")!
        #expect(URLSchemeHandler.parseAction(from: url) == .unknown)
    }

    @Test("Different scheme returns unknown")
    func differentScheme() {
        let url = URL(string: "myapp://open")!
        #expect(URLSchemeHandler.parseAction(from: url) == .unknown)
    }
}
#endif
