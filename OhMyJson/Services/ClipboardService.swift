//
//  ClipboardService.swift
//  OhMyJson
//

#if os(macOS)
import AppKit

class ClipboardService: ClipboardServiceProtocol {
    static let shared = ClipboardService()

    private init() {}

    func readText() -> String? {
        let pasteboard = NSPasteboard.general
        return pasteboard.string(forType: .string)
    }

    func writeText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func hasText() -> Bool {
        let pasteboard = NSPasteboard.general
        return pasteboard.string(forType: .string) != nil
    }
}
#endif
