//
//  ClipboardServiceProtocol.swift
//  OhMyJson
//

#if os(macOS)
protocol ClipboardServiceProtocol {
    func readText() -> String?
    func writeText(_ text: String)
    func hasText() -> Bool
}
#endif
