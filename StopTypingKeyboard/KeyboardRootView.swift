import SwiftUI

/// Main SwiftUI view for the Stop Typing keyboard extension.
/// Modeled after Wispr Flow's clean keyboard design.
struct KeyboardRootView: View {
    let onInsertText: (String) -> Void
    let onDeleteBackward: () -> Void
    let onNextKeyboard: () -> Void
    let onReturnKey: () -> Void
    var showGlobe: Bool = true

    @State private var isShifted = false
    @State private var showNumbers = false
    @State private var selectedMode = "Formal"

    private let modes = ["Formal", "Casual", "Friendly", "Short"]

    // MARK: - Key Layout

    private let letterRows: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"],
    ]

    private let numberRows: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
        [".", ",", "?", "!", "'"],
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar
            toolbarView
                .padding(.horizontal, 4)
                .padding(.top, 6)
                .padding(.bottom, 4)

            // Key rows
            if showNumbers {
                numbersView
            } else {
                lettersView
            }

            // Bottom row
            bottomRow
                .padding(.bottom, 2)

        }
        .background(Color(UIColor.systemGray5))
    }

    // MARK: - Toolbar

    private var toolbarView: some View {
        HStack(spacing: 8) {
            // Settings / filter icon
            Button {
                // TODO: Show insert latest transcript
                let state = SharedKeyboardState.load()
                if let transcript = state.transcript, !transcript.isEmpty {
                    onInsertText(transcript)
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(UIColor.label))
                    .frame(width: 36, height: 36)
            }

            Spacer()

            // Mode selector dropdown
            Menu {
                ForEach(modes, id: \.self) { mode in
                    Button {
                        selectedMode = mode
                    } label: {
                        HStack {
                            Text(mode)
                            if mode == selectedMode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedMode)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(UIColor.label))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(UIColor.secondaryLabel))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(UIColor.systemGray4))
                .clipShape(Capsule())
            }

            // Mic button
            Button {
                // Mic tapped — insert latest transcript as a quick action
                let state = SharedKeyboardState.load()
                if let transcript = state.transcript, !transcript.isEmpty {
                    onInsertText(transcript)
                }
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color(UIColor.darkGray))
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - Letters View

    private var lettersView: some View {
        VStack(spacing: 6) {
            // Row 1
            HStack(spacing: 4) {
                ForEach(letterRows[0], id: \.self) { key in
                    LetterKey(
                        label: isShifted ? key.uppercased() : key,
                        onTap: { tapKey(key) }
                    )
                }
            }

            // Row 2 (slightly indented)
            HStack(spacing: 4) {
                ForEach(letterRows[1], id: \.self) { key in
                    LetterKey(
                        label: isShifted ? key.uppercased() : key,
                        onTap: { tapKey(key) }
                    )
                }
            }

            // Row 3 with shift and backspace
            HStack(spacing: 4) {
                // Shift
                Button {
                    isShifted.toggle()
                } label: {
                    Image(systemName: isShifted ? "shift.fill" : "shift")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(UIColor.label))
                        .frame(width: 42, height: 42)
                        .background(isShifted ? Color(UIColor.systemGray3) : Color(UIColor.systemGray2))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                ForEach(letterRows[2], id: \.self) { key in
                    LetterKey(
                        label: isShifted ? key.uppercased() : key,
                        onTap: { tapKey(key) }
                    )
                }

                // Backspace
                Button {
                    onDeleteBackward()
                } label: {
                    Image(systemName: "delete.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(UIColor.label))
                        .frame(width: 42, height: 42)
                        .background(Color(UIColor.systemGray2))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(.horizontal, 3)
    }

    // MARK: - Numbers View

    private var numbersView: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(numberRows[0], id: \.self) { key in
                    LetterKey(label: key, onTap: { onInsertText(key) })
                }
            }

            HStack(spacing: 4) {
                ForEach(numberRows[1], id: \.self) { key in
                    LetterKey(label: key, onTap: { onInsertText(key) })
                }
            }

            HStack(spacing: 4) {
                Spacer()
                ForEach(numberRows[2], id: \.self) { key in
                    LetterKey(label: key, onTap: { onInsertText(key) })
                }

                Button {
                    onDeleteBackward()
                } label: {
                    Image(systemName: "delete.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(UIColor.label))
                        .frame(width: 42, height: 42)
                        .background(Color(UIColor.systemGray2))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Spacer()
            }
        }
        .padding(.horizontal, 3)
    }

    // MARK: - Bottom Row

    private var bottomRow: some View {
        HStack(spacing: 4) {
            // 123 / ABC toggle
            Button {
                showNumbers.toggle()
            } label: {
                Text(showNumbers ? "ABC" : "123")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(UIColor.label))
                    .frame(width: 42, height: 42)
                    .background(Color(UIColor.systemGray2))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Globe — integrated into bottom row like Wispr Flow
            if showGlobe {
                Button {
                    onNextKeyboard()
                } label: {
                    Image(systemName: "globe")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(UIColor.label))
                        .frame(width: 38, height: 42)
                        .background(Color(UIColor.systemGray2))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            // Spacebar with branding
            Button {
                onInsertText(" ")
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(UIColor.tertiaryLabel))
                    Text("Stop Typing")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color(UIColor.tertiaryLabel))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(Color(UIColor.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Period
            Button {
                onInsertText(".")
            } label: {
                Text(".")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color(UIColor.label))
                    .frame(width: 38, height: 42)
                    .background(Color(UIColor.systemGray2))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Return
            Button {
                onReturnKey()
            } label: {
                Image(systemName: "return")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(UIColor.label))
                    .frame(width: 42, height: 42)
                    .background(Color(UIColor.systemGray2))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 3)
    }

    // MARK: - Helpers

    private func tapKey(_ key: String) {
        let char = isShifted ? key.uppercased() : key
        onInsertText(char)
        if isShifted { isShifted = false }
    }
}

// MARK: - Letter Key Component

struct LetterKey: View {
    let label: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color(UIColor.label))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(Color(UIColor.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.15), radius: 0.5, x: 0, y: 0.5)
        }
    }
}
