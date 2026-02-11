//
//  WindowManagerProtocol.swift
//  OhMyJson
//

#if os(macOS)
import AppKit

protocol WindowManagerProtocol: AnyObject {
    var isViewerOpen: Bool { get }
    func createNewTab(with jsonString: String?)
    func closeViewer()
    func bringToFront()
    func isViewerWindow(_ window: NSWindow) -> Bool
}
#endif
