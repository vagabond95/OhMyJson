//
//  ErrorView.swift
//  OhMyJson
//

import SwiftUI

#if os(macOS)
struct ErrorView: View {
    let error: JSONParseError

    @Environment(AppSettings.self) var settings
    private var theme: AppTheme { settings.currentTheme }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(error.category.localizedHeader)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundColor(theme.accent)
            }

            if !error.message.isEmpty {
                Text(error.message)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundColor(theme.secondaryText)
            }

            if let line = error.line, let column = error.column {
                Text("Line \(line), Column \(column)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(theme.secondaryText)
            }

            Spacer()
        }
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.background)
    }
}

struct ErrorView_Previews: PreviewProvider {
    static var previews: some View {
        ErrorView(error: JSONParseError(
            message: "Unexpected token '}' at position 42",
            line: 3,
            column: 15
        ))
        .frame(width: 500, height: 300)
        .preferredColorScheme(.dark)
    }
}
#endif
