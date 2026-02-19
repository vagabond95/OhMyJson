//
//  SearchBar.swift
//  OhMyJson
//

import SwiftUI

#if os(macOS)
struct FloatingSearchBar: View {
    @Binding var searchText: String
    @Binding var currentIndex: Int
    let totalCount: Int
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onClose: () -> Void
    var shouldAutoFocus: Bool = true

    @FocusState private var isFocused: Bool

    @Environment(AppSettings.self) var settings
    private var theme: AppTheme { settings.currentTheme }

    var body: some View {
        HStack(spacing: 8) {
            // Search input
            HStack(spacing: 6) {
                TextField("", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(theme.primaryText)
                    .focused($isFocused)
                    .frame(minWidth: 120)
                    .onSubmit {
                        onNext()
                    }

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(theme.secondaryText)
                            .font(.system(size: 12))
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(theme.panelBackground)
            .cornerRadius(6)

            // Results counter
            Text(resultText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(theme.secondaryText)
                .frame(minWidth: 36)

            // Navigation buttons
            HStack(spacing: 2) {
                Button(action: onPrevious) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(totalCount > 0 ? theme.primaryText : theme.secondaryText)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(totalCount == 0)

                Button(action: onNext) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(totalCount > 0 ? theme.primaryText : theme.secondaryText)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(totalCount == 0)
            }

            // Close button
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(theme.secondaryText)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .background(theme.secondaryBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(theme.shadowOpacity), radius: 8, x: 0, y: 4)
        .onAppear {
            if shouldAutoFocus {
                DispatchQueue.main.async {
                    isFocused = true
                }
            }
        }
    }

    private var resultText: String {
        if searchText.isEmpty {
            return ""
        }
        return "\(totalCount > 0 ? currentIndex + 1 : 0)/\(totalCount)"
    }
}

struct FloatingSearchBar_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            AppSettings.shared.currentTheme.background
                .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    FloatingSearchBar(
                        searchText: .constant("test"),
                        currentIndex: .constant(2),
                        totalCount: 5,
                        onNext: {},
                        onPrevious: {},
                        onClose: {}
                    )
                    .padding()
                }
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
}
#endif
