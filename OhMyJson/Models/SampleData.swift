//
//  SampleData.swift
//  OhMyJson
//

import Foundation

struct SampleData {
    static var onboardingJson: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return """
        {
          "appName": "OhMyJson",
          "appVersion": "\(version)"
        }
        """
    }

    static let json = """
    {
      "app": {
        "name": "OhMyJson",
        "version": "1.0.0",
        "description": "A beautiful JSON viewer for macOS"
      },
      "features": [
        {
          "id": 1,
          "name": "Tree View",
          "enabled": true,
          "description": "Hierarchical JSON visualization"
        },
        {
          "id": 2,
          "name": "Beautify",
          "enabled": true,
          "description": "Syntax-highlighted formatted view"
        },
        {
          "id": 3,
          "name": "Search",
          "enabled": true,
          "description": "Find keys and values instantly"
        }
      ],
      "shortcuts": {
        "open": "Cmd+J",
        "newTab": "Cmd+N",
        "search": "Cmd+F",
        "close": "Cmd+W"
      },
      "stats": {
        "tabs": 42,
        "parsed": 1337,
        "uptime": "99.9%"
      }
    }
    """
}
