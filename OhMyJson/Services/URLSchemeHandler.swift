//
//  URLSchemeHandler.swift
//  OhMyJson
//

import Foundation

enum URLSchemeAction: Equatable {
    case openFromClipboard
    case unknown
}

enum URLSchemeHandler {
    static func parseAction(from url: URL) -> URLSchemeAction {
        guard url.scheme == "ohmyjson" else { return .unknown }

        switch url.host {
        case "open":
            return .openFromClipboard
        default:
            return .unknown
        }
    }
}
