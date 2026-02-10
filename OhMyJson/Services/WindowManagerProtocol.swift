//
//  WindowManagerProtocol.swift
//  OhMyJson
//

#if os(macOS)
protocol WindowManagerProtocol: AnyObject {
    var isViewerOpen: Bool { get }
    func createNewTab(with jsonString: String?)
    func closeViewer()
    func bringToFront()
}
#endif
