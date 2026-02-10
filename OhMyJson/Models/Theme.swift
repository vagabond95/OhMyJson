//
//  Theme.swift
//  OhMyJson
//

import SwiftUI
import AppKit

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Theme Protocol

protocol AppTheme {
    // Backgrounds
    var background: Color { get }
    var secondaryBackground: Color { get }
    var panelBackground: Color { get }

    // Text
    var primaryText: Color { get }
    var secondaryText: Color { get }

    // Syntax
    var key: Color { get }
    var string: Color { get }
    var number: Color { get }
    var boolean: Color { get }
    var null: Color { get }
    var structure: Color { get }

    // Highlights
    var searchHighlight: Color { get }
    var selectionBg: Color { get }
    var hoverBg: Color { get }
    var searchCurrentMatchBg: Color { get }
    var searchOtherMatchBg: Color { get }
    var searchCurrentMatchFg: Color { get }
    var searchOtherMatchFg: Color { get }

    // UI
    var border: Color { get }
    var accent: Color { get }

    // Tab bar
    var tabBarBackground: Color { get }
    var activeTabBackground: Color { get }
    var activeTabBorder: Color { get }
    var inactiveTabBackground: Color { get }
    var inactiveTabBorder: Color { get }
    var hoveredTabBackground: Color { get }

    // NSTextView specific
    var nsBackground: NSColor { get }
    var nsPrimaryText: NSColor { get }
    var nsInsertionPoint: NSColor { get }
    var nsSelectedTextBackground: NSColor { get }

    // Shadow
    var shadowOpacity: Double { get }

    // Color scheme
    var colorScheme: ColorScheme { get }
}

// MARK: - Dark Theme (migrated from TerminalTheme)

struct DarkTheme: AppTheme {
    let background = Color(hex: "131313")
    let secondaryBackground = Color(hex: "131313")
    let panelBackground = Color(hex: "2D2D2D")

    let primaryText = Color(hex: "E4E3E0")
    let secondaryText = Color(hex: "9E9D9B")

    let key = Color(hex: "C792EA")
    let string = Color(hex: "A8CC8C")
    let number = Color(hex: "E8B4B4")
    let boolean = Color(hex: "66C2CD")
    let null = Color(hex: "808080")
    let structure = Color(hex: "D4D4D4")

    let searchHighlight = Color(hex: "FFB86C")
    let selectionBg = Color(hex: "264F78")
    let hoverBg = Color(hex: "2A2D2E")
    let searchCurrentMatchBg = Color(hex: "FF8C00")
    let searchOtherMatchBg = Color(hex: "7A5E1E")
    let searchCurrentMatchFg = Color(hex: "000000")
    let searchOtherMatchFg = Color(hex: "FFE0A0")

    let border = Color(hex: "282827")
    let accent = Color(hex: "FF6B6B")

    let tabBarBackground = Color(hex: "131313")
    let activeTabBackground = Color(hex: "222222")
    let activeTabBorder = Color(hex: "505050")
    let inactiveTabBackground = Color(hex: "1A1A1A")
    let inactiveTabBorder = Color(hex: "404040")
    let hoveredTabBackground = Color(hex: "1C1C1C")

    let nsBackground = NSColor(Color(hex: "131313"))
    let nsPrimaryText = NSColor(Color(hex: "FAF9F6"))
    let nsInsertionPoint = NSColor(Color(hex: "FAF9F6"))
    let nsSelectedTextBackground = NSColor(Color(hex: "264F78"))

    let shadowOpacity: Double = 0.3

    let colorScheme: ColorScheme = .dark
}

// MARK: - Light Theme (VS Code Light+ inspired)

struct LightTheme: AppTheme {
    let background = Color(hex: "FFFFFF")
    let secondaryBackground = Color(hex: "F3F3F3")
    let panelBackground = Color(hex: "E8E8E8")

    let primaryText = Color(hex: "1E1E1E")
    let secondaryText = Color(hex: "6B6B6B")

    let key = Color(hex: "0451A5")
    let string = Color(hex: "A31515")
    let number = Color(hex: "098658")
    let boolean = Color(hex: "0000FF")
    let null = Color(hex: "808080")
    let structure = Color(hex: "383838")

    let searchHighlight = Color(hex: "F9A825")
    let selectionBg = Color(hex: "ADD6FF")
    let hoverBg = Color(hex: "E8E8E8")
    let searchCurrentMatchBg = Color(hex: "FF8C00")
    let searchOtherMatchBg = Color(hex: "FFE135")
    let searchCurrentMatchFg = Color(hex: "000000")
    let searchOtherMatchFg = Color(hex: "1A1A00")

    let border = Color(hex: "D4D4D4")
    let accent = Color(hex: "D32F2F")

    let tabBarBackground = Color(hex: "F3F3F3")
    let activeTabBackground = Color(hex: "FFFFFF")
    let activeTabBorder = Color(hex: "B8B8B8")
    let inactiveTabBackground = Color(hex: "ECECEC")
    let inactiveTabBorder = Color(hex: "D4D4D4")
    let hoveredTabBackground = Color(hex: "E8E8E8")

    let nsBackground = NSColor(Color(hex: "FFFFFF"))
    let nsPrimaryText = NSColor(Color(hex: "1E1E1E"))
    let nsInsertionPoint = NSColor(Color(hex: "1E1E1E"))
    let nsSelectedTextBackground = NSColor(Color(hex: "ADD6FF"))

    let shadowOpacity: Double = 0.1

    let colorScheme: ColorScheme = .light
}
