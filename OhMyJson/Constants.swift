//
//  Constants.swift
//  OhMyJson
//

import Foundation
import CoreGraphics
#if os(macOS)
import AppKit
#endif

// MARK: - Key Codes

enum KeyCode {
    static let escape: UInt16      = 53
    static let space: UInt16       = 49
    static let returnKey: UInt16   = 36
    static let numpadEnter: UInt16 = 76
    static let leftArrow: UInt16   = 123
    static let rightArrow: UInt16  = 124
    static let downArrow: UInt16   = 125
    static let upArrow: UInt16     = 126
    static let gKey: UInt16        = 5
}

// MARK: - Animation Durations

enum Animation {
    static let quick: TimeInterval    = 0.15
    static let standard: TimeInterval = 0.2
    static let slow: TimeInterval     = 0.3
}

// MARK: - Display Durations

enum Duration {
    static let toastDefault: TimeInterval = 1.5
    static let toastLong: TimeInterval    = 2.0
}

// MARK: - Timing / Debounce

enum Timing {
    static let parseDebounce: TimeInterval       = 0.3
    static let tabRestoreDebounce: TimeInterval   = 0.2
    static let hotKeyThrottle: TimeInterval       = 0.5
    static let treeRestoreDelay: TimeInterval     = 0.05
    static let confettiDelay: TimeInterval        = 0.5
    static let scrollPositionThreshold: CGFloat   = 0.5
    static let dividerDragThreshold: CGFloat      = 0.5
    static let hoverDismissGrace: TimeInterval    = 0.15
}

// MARK: - Window Sizes

enum WindowSize {
    static let defaultWidth: CGFloat  = 1400
    static let defaultHeight: CGFloat = 900
    static let minWidth: CGFloat      = 800
    static let minHeight: CGFloat     = 400
    static let onboardingWidth: CGFloat  = 330
    static let onboardingHeight: CGFloat = 310
}

// MARK: - File Size Thresholds

enum FileSize {
    static let megabyte = 1024 * 1024  // 1MB
}

// MARK: - Input Size Thresholds

enum InputSize {
    /// Maximum byte size for direct NSTextView display.
    /// Text larger than this threshold is replaced with a notice in InputView to prevent
    /// TextKit's synchronous glyph generation causing SBBOD on the main thread.
    static let displayThreshold = 512 * 1024  // 512KB

    /// Prefix of the notice text that replaces large JSON in InputView.
    /// Used to detect lost `tab_content` during hydration.
    static let largeInputNoticePrefix = "// JSON too large"
}

// MARK: - Beautify Display Limits

enum BeautifyLimit {
    /// Maximum lines rendered in BeautifyView's NSAttributedString.
    /// TextKit 2 lazy layout prevents SBBOD; this limit guards against
    /// excessive memory usage (~50MB NSAttributedString at 50K lines).
    static let maxDisplayLines = 50_000
}

// MARK: - Tree Layout

enum TreeLayout {
    static let rowHeight: CGFloat = 26
    static let virtualizationBuffer: Int = 10  // top/bottom row buffer for windowed rendering
    #if os(macOS)
    static let charWidth: CGFloat = {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        return ceil(("W" as NSString).size(withAttributes: [.font: font]).width)
    }()
    #endif
}

// MARK: - Notification Names

extension Notification.Name {
    static let checkForUpdates = Notification.Name("checkForUpdates")
}

// MARK: - Compare Mode

enum CompareTiming {
    static let diffDebounce: TimeInterval = 0.5
}

enum CompareLayout {
    static let defaultInputRatio: CGFloat = 0.3
    static let minInputRatio: CGFloat = 0.15
    static let maxInputRatio: CGFloat = 0.7
    static let gutterWidth: CGFloat = 3
    static let collapseContext: Int = 3
}

enum CompareLimit {
    static let maxDisplayLines = 5_000
}

// MARK: - Persistence

enum Persistence {
    static let databaseFileName = "tabs.sqlite"
    static let directoryName = "OhMyJson"
    static let saveDebounceInterval: TimeInterval = 0.5
    /// Number of most-recently-accessed tabs to keep fully hydrated in memory.
    static let hydratedTabCount = 3
}
