//
//  HotKeyManagerProtocol.swift
//  OhMyJson
//

#if os(macOS)
protocol HotKeyManagerProtocol: AnyObject {
    var isEnabled: Bool { get set }
    var isRunning: Bool { get }
    func start(combo: HotKeyCombo, handler: @escaping () -> Void)
    func stop()
    func updateHotKey(_ combo: HotKeyCombo)
}
#endif
