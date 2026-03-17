//
//  OhMyJsonApp.swift
//  OhMyJson
//

import SwiftUI

@main
struct OhMyJsonApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        #if os(macOS)
        Settings {
            SettingsWindowView()
                .environment(AppSettings.shared)
        }
        #else
        WindowGroup {
            Text("OhMyJson is available on macOS only.")
        }
        #endif
    }
}
