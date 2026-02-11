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
        // Settings UI is managed by AppDelegate.showSettings() via NSWindow.
        // Empty Settings scene satisfies the App protocol Scene requirement
        // without creating a visible window on launch.
        Settings {
            EmptyView()
        }
        #else
        WindowGroup {
            Text("app.macos_only")
        }
        #endif
    }
}
