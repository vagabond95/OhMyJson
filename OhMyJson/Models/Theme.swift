//
//  Theme.swift
//  OhMyJson
//

import SwiftUI
import AppKit

// MARK: - NSColor Hex Extension (sRGB)

extension NSColor {
    convenience init(sRGBHex hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        switch hex.count {
        case 6:
            r = CGFloat((int >> 16) & 0xFF) / 255
            g = CGFloat((int >> 8) & 0xFF) / 255
            b = CGFloat(int & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0
        }
        var components: [CGFloat] = [r, g, b, 1.0]
        self.init(colorSpace: .sRGB, components: &components, count: 4)
    }
}

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
    var selectedTextColor: Color { get }
    var selectionBg: Color { get }
    var hoverBg: Color { get }
    var searchCurrentMatchBg: Color { get }
    var searchOtherMatchBg: Color { get }
    var searchCurrentMatchFg: Color { get }
    var searchOtherMatchFg: Color { get }

    // Toggle
    var toggleHoverBg: Color { get }

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

    // Input area
    var inputBackground: Color { get }
    var nsInputBackground: NSColor { get }

    // NSTextView specific
    var nsBackground: NSColor { get }
    var nsPrimaryText: NSColor { get }
    var nsInsertionPoint: NSColor { get }
    var nsSelectedTextColor: NSColor { get }
    var nsSelectedTextBackground: NSColor { get }

    // Shadow
    var shadowOpacity: Double { get }

    // Color scheme
    var colorScheme: ColorScheme { get }

    // Diff colors (Compare mode)
    var diffAddedBg: Color { get }
    var diffRemovedBg: Color { get }
    var diffModifiedBg: Color { get }
    var diffPaddingBg: Color { get }
    var nsDiffAddedBg: NSColor { get }
    var nsDiffRemovedBg: NSColor { get }
    var nsDiffModifiedBg: NSColor { get }
    var nsDiffPaddingBg: NSColor { get }
    var diffAddedGutter: Color { get }
    var diffRemovedGutter: Color { get }
    var diffModifiedGutter: Color { get }
    var diffFocusBorder: Color { get }
}

// MARK: - Dark Theme (migrated from TerminalTheme)

struct DarkTheme: AppTheme {
    let background = Color(hex: "131313")
    let secondaryBackground = Color(hex: "131313")
    let panelBackground = Color(hex: "2D2D2D")

    let primaryText = Color(hex: "E4E3E0")
    let secondaryText = Color(hex: "9E9D9B")

    let key = Color(hex: "B0B9F9")
    let string = Color(hex: "48968C")
    let number = Color(hex: "D77757")
    let boolean = Color(hex: "FF4FDA")
    let null = Color(hex: "808080")
    let structure = Color(hex: "99A3B2")

    let searchHighlight = Color(hex: "FFFA5C")
    let selectedTextColor = Color(hex: "FFC663")
    let selectionBg = Color(hex: "4D4D4D")
    let hoverBg = Color(hex: "2A2D2E")
    let searchCurrentMatchBg = Color(hex: "FF8C00")
    let searchOtherMatchBg = Color(hex: "7A5E1E")
    let searchCurrentMatchFg = Color(hex: "000000")
    let searchOtherMatchFg = Color(hex: "FFE0A0")

    let toggleHoverBg = Color.white.opacity(0.12)

    let border = Color(hex: "282827")
    let accent = Color(hex: "FF6B6B")

    let tabBarBackground = Color(hex: "131313")
    let activeTabBackground = Color(hex: "222222")
    let activeTabBorder = Color(hex: "505050")
    let inactiveTabBackground = Color(hex: "1A1A1A")
    let inactiveTabBorder = Color(hex: "404040")
    let hoveredTabBackground = Color(hex: "1C1C1C")

    let inputBackground = Color(hex: "1C1C1C")
    let nsInputBackground = NSColor(sRGBHex: "1C1C1C")

    let nsBackground = NSColor(sRGBHex: "131313")
    let nsPrimaryText = NSColor(sRGBHex: "FAF9F6")
    let nsInsertionPoint = NSColor(sRGBHex: "FAF9F6")
    let nsSelectedTextColor = NSColor(sRGBHex: "FFC663")
    let nsSelectedTextBackground = NSColor(sRGBHex: "4D4D4D")

    let shadowOpacity: Double = 0.3

    let colorScheme: ColorScheme = .dark

    // Diff colors
    let diffAddedBg = Color(.sRGB, red: 34/255, green: 197/255, blue: 94/255, opacity: 0.15)
    let diffRemovedBg = Color(.sRGB, red: 239/255, green: 68/255, blue: 68/255, opacity: 0.15)
    let diffModifiedBg = Color(.sRGB, red: 234/255, green: 179/255, blue: 8/255, opacity: 0.15)
    let diffPaddingBg = Color(.sRGB, red: 128/255, green: 128/255, blue: 128/255, opacity: 0.05)
    let nsDiffAddedBg: NSColor = {
        var c: [CGFloat] = [34/255, 197/255, 94/255, 0.15]
        return NSColor(colorSpace: .sRGB, components: &c, count: 4)
    }()
    let nsDiffRemovedBg: NSColor = {
        var c: [CGFloat] = [239/255, 68/255, 68/255, 0.15]
        return NSColor(colorSpace: .sRGB, components: &c, count: 4)
    }()
    let nsDiffModifiedBg: NSColor = {
        var c: [CGFloat] = [234/255, 179/255, 8/255, 0.15]
        return NSColor(colorSpace: .sRGB, components: &c, count: 4)
    }()
    let nsDiffPaddingBg: NSColor = {
        var c: [CGFloat] = [128/255, 128/255, 128/255, 0.05]
        return NSColor(colorSpace: .sRGB, components: &c, count: 4)
    }()
    let diffAddedGutter = Color(hex: "22C55E")
    let diffRemovedGutter = Color(hex: "EF4444")
    let diffModifiedGutter = Color(hex: "EAB308")
    let diffFocusBorder = Color(hex: "FFFFFF").opacity(0.5)
}

// MARK: - Light Theme (VS Code Light+ inspired)

struct LightTheme: AppTheme {
    let background = Color(hex: "FFFFFF")
    let secondaryBackground = Color(hex: "F3F3F3")
    let panelBackground = Color(hex: "E8E8E8")

    let primaryText = Color(hex: "1E1E1E")
    let secondaryText = Color(hex: "6B6B6B")

    let key = Color(hex: "AC3EA4")
    let string = Color(hex: "D12F1A")
    let number = Color(hex: "494ADE")
    let boolean = Color(hex: "3E8087")
    let null = Color(hex: "808080")
    let structure = Color(hex: "272627")

    let searchHighlight = Color(hex: "F9A825")
    let selectedTextColor = Color(hex: "000000")
    let selectionBg = Color(hex: "B2D7FF")
    let hoverBg = Color(hex: "E8E8E8")
    let searchCurrentMatchBg = Color(hex: "FF8C00")
    let searchOtherMatchBg = Color(hex: "FFE135")
    let searchCurrentMatchFg = Color(hex: "000000")
    let searchOtherMatchFg = Color(hex: "1A1A00")

    let toggleHoverBg = Color.black.opacity(0.08)

    let border = Color(hex: "D4D4D4")
    let accent = Color(hex: "D32F2F")

    let tabBarBackground = Color(hex: "F3F3F3")
    let activeTabBackground = Color(hex: "FFFFFF")
    let activeTabBorder = Color(hex: "B8B8B8")
    let inactiveTabBackground = Color(hex: "ECECEC")
    let inactiveTabBorder = Color(hex: "D4D4D4")
    let hoveredTabBackground = Color(hex: "E8E8E8")

    let inputBackground = Color(hex: "F7F7F7")
    let nsInputBackground = NSColor(sRGBHex: "F7F7F7")

    let nsBackground = NSColor(sRGBHex: "FFFFFF")
    let nsPrimaryText = NSColor(sRGBHex: "1E1E1E")
    let nsInsertionPoint = NSColor(sRGBHex: "1E1E1E")
    let nsSelectedTextColor = NSColor(sRGBHex: "000000")
    let nsSelectedTextBackground = NSColor(sRGBHex: "B2D7FF")

    let shadowOpacity: Double = 0.1

    let colorScheme: ColorScheme = .light

    // Diff colors
    let diffAddedBg = Color(.sRGB, red: 34/255, green: 197/255, blue: 94/255, opacity: 0.12)
    let diffRemovedBg = Color(.sRGB, red: 239/255, green: 68/255, blue: 68/255, opacity: 0.12)
    let diffModifiedBg = Color(.sRGB, red: 234/255, green: 179/255, blue: 8/255, opacity: 0.12)
    let diffPaddingBg = Color(.sRGB, red: 128/255, green: 128/255, blue: 128/255, opacity: 0.03)
    let nsDiffAddedBg: NSColor = {
        var c: [CGFloat] = [34/255, 197/255, 94/255, 0.12]
        return NSColor(colorSpace: .sRGB, components: &c, count: 4)
    }()
    let nsDiffRemovedBg: NSColor = {
        var c: [CGFloat] = [239/255, 68/255, 68/255, 0.12]
        return NSColor(colorSpace: .sRGB, components: &c, count: 4)
    }()
    let nsDiffModifiedBg: NSColor = {
        var c: [CGFloat] = [234/255, 179/255, 8/255, 0.12]
        return NSColor(colorSpace: .sRGB, components: &c, count: 4)
    }()
    let nsDiffPaddingBg: NSColor = {
        var c: [CGFloat] = [128/255, 128/255, 128/255, 0.03]
        return NSColor(colorSpace: .sRGB, components: &c, count: 4)
    }()
    let diffAddedGutter = Color(hex: "16A34A")
    let diffRemovedGutter = Color(hex: "DC2626")
    let diffModifiedGutter = Color(hex: "CA8A04")
    let diffFocusBorder = Color(hex: "000000").opacity(0.3)
}
