import SwiftUI

/// Main SwiftUI view for the Stop Typing keyboard extension.
struct KeyboardRootView: View {
    let onInsertText: (String) -> Void
    let onDeleteBackward: () -> Void
    let onNextKeyboard: () -> Void
    let onReturnKey: () -> Void
    let onOpenApp: () -> Void
    let onStartDictation: () -> Void
    let onStopDictation: () -> Void
    var showGlobe: Bool = true
    @Binding var isAppAlive: Bool
    @Binding var isRecording: Bool

    @State private var isShifted = false
    @State private var showNumbers = false
    @State private var selectedMode = "Formal"

    private let modes = ["Formal", "Casual", "Friendly", "Short"]

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
            toolbarView
                .padding(.horizontal, 4)
                .padding(.top, 6)
                .padding(.bottom, 4)

            if !isRecording {
                if showNumbers {
                    numbersView
                } else {
                    lettersView
                }

                bottomRow
                    .padding(.bottom, 2)
            }
        }
        .background(Color(UIColor.systemGray5))
    }

    // MARK: - Toolbar (3 states)

    private var toolbarView: some View {
        Group {
            if isRecording {
                // State C: Recording active
                recordingToolbar
            } else if isAppAlive {
                // State B: App alive, ready to record
                activeToolbar
            } else {
                // State A: App not running
                inactiveToolbar
            }
        }
    }

    // State A: App not running — show "Start ST"
    private var inactiveToolbar: some View {
        HStack(spacing: 8) {
            // Insert latest transcript
            Button {
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

            // Start ST button
            Button {
                onOpenApp()
            } label: {
                Text("Start ST")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color(UIColor.darkGray))
                    .clipShape(Capsule())
            }
        }
    }

    // State B: App alive — show mode selector + mic
    private var activeToolbar: some View {
        HStack(spacing: 8) {
            // Insert latest transcript
            Button {
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

            // Mode selector
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

            // Mic button — start recording
            Button {
                onStartDictation()
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

    // State C: Recording — show cancel, listening, done
    private var recordingToolbar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Cancel
                Button {
                    onStopDictation()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(UIColor.label))
                        .frame(width: 36, height: 36)
                        .background(Color(UIColor.systemGray4))
                        .clipShape(Circle())
                }

                Spacer()

                // Mode label
                Text(selectedMode)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(UIColor.secondaryLabel))

                // Done — stop and insert
                Button {
                    onStopDictation()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color(UIColor.darkGray))
                        .clipShape(Circle())
                }
            }

            // Waveform dots
            HStack(spacing: 4) {
                ForEach(0..<9, id: \.self) { _ in
                    Circle()
                        .fill(Color(UIColor.label))
                        .frame(width: 6, height: 6)
                        .opacity(Double.random(in: 0.3...1.0))
                }
            }

            Text("Listening")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(UIColor.label))
            Text("iPhone Microphone")
                .font(.system(size: 13))
                .foregroundStyle(Color(UIColor.secondaryLabel))

            Spacer().frame(height: 40)
        }
        .padding(.top, 8)
    }

    // MARK: - Letters View

    private var lettersView: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(letterRows[0], id: \.self) { key in
                    LetterKey(label: isShifted ? key.uppercased() : key) { tapKey(key) }
                }
            }

            HStack(spacing: 4) {
                ForEach(letterRows[1], id: \.self) { key in
                    LetterKey(label: isShifted ? key.uppercased() : key) { tapKey(key) }
                }
            }

            HStack(spacing: 4) {
                Button { isShifted.toggle() } label: {
                    Image(systemName: isShifted ? "shift.fill" : "shift")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(UIColor.label))
                        .frame(width: 42, height: 42)
                        .background(isShifted ? Color(UIColor.systemGray3) : Color(UIColor.systemGray2))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                ForEach(letterRows[2], id: \.self) { key in
                    LetterKey(label: isShifted ? key.uppercased() : key) { tapKey(key) }
                }

                Button { onDeleteBackward() } label: {
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
                    LetterKey(label: key) { onInsertText(key) }
                }
            }
            HStack(spacing: 4) {
                ForEach(numberRows[1], id: \.self) { key in
                    LetterKey(label: key) { onInsertText(key) }
                }
            }
            HStack(spacing: 4) {
                Spacer()
                ForEach(numberRows[2], id: \.self) { key in
                    LetterKey(label: key) { onInsertText(key) }
                }
                Button { onDeleteBackward() } label: {
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
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Button { showNumbers.toggle() } label: {
                    Text(showNumbers ? "ABC" : "123")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(UIColor.label))
                        .frame(width: 48, height: 42)
                        .background(Color(UIColor.systemGray2))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Button { onInsertText(" ") } label: {
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

                Button { onInsertText(".") } label: {
                    Text(".")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color(UIColor.label))
                        .frame(width: 44, height: 42)
                        .background(Color(UIColor.systemGray2))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Button { onReturnKey() } label: {
                    Image(systemName: "return")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(UIColor.label))
                        .frame(width: 48, height: 42)
                        .background(Color(UIColor.systemGray2))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            if showGlobe {
                HStack {
                    Button { onNextKeyboard() } label: {
                        Image(systemName: "globe")
                            .font(.system(size: 18))
                            .foregroundStyle(Color(UIColor.secondaryLabel))
                            .frame(width: 30, height: 28)
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 3)
    }

    private func tapKey(_ key: String) {
        let char = isShifted ? key.uppercased() : key
        onInsertText(char)
        if isShifted { isShifted = false }
    }
}

// MARK: - Letter Key

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
