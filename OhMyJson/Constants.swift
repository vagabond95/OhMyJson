//
//  Constants.swift
//  OhMyJson
//

import Foundation
import CoreGraphics

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
    static let onboardingWidth: CGFloat  = 400
    static let onboardingHeight: CGFloat = 500
}

// MARK: - File Size Thresholds

enum FileSize {
    static let largeThreshold = 5 * 1024 * 1024 // 5MB
    static let megabyte       = 1024 * 1024      // 1MB
}
