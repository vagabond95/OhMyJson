//
//  ErrorView.swift
//  OhMyJson
//

import SwiftUI

#if os(macOS)
struct ErrorView: View {
    let error: JSONParseError

    @ObservedObject private var settings = AppSettings.shared
    private var theme: AppTheme { settings.currentTheme }

    var body: some View {
        VStack(alignment: .leading) {
            Text("viewer.invalid_json")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(theme.accent)

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
            column: 15,
            originalText: """
            {
                "name": "test",
                "value": }
            }
            """
        ))
        .frame(width: 500, height: 300)
        .preferredColorScheme(.dark)
    }
}
#endif
