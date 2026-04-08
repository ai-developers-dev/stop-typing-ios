import SwiftUI

struct KeyboardRootView: View {
    let onInsertText: (String) -> Void
    let onDeleteBackward: () -> Void
    let onNextKeyboard: () -> Void
    let onReturnKey: () -> Void
    let onOpenApp: () -> Void
    let onStartDictation: () -> Void
    let onStopDictation: () -> Void
    let onCancelDictation: () -> Void
    var showGlobe: Bool = true
    @Binding var isAppAlive: Bool
    @Binding var isRecording: Bool

    @State private var isShifted = false
    @State private var showNumbers = false
    @State private var selectedMode = "Formal"
    @State private var waveformBars: [CGFloat] = Array(repeating: 4, count: 11)
    @State private var waveformTimer: Timer?
    @State private var deleteTimer: Timer?

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

    // Design constants
    private let keyH: CGFloat = 43
    private let keySpaceH: CGFloat = 6
    private let keySpaceV: CGFloat = 11
    private let keyRadius: CGFloat = 5
    private let letterFont: CGFloat = 23
    private let utilWidth: CGFloat = 44
    private let padH: CGFloat = 3
    private let darkBg = Color(red: 0.2, green: 0.2, blue: 0.2) // #333

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbarView
                .padding(.horizontal, 6)
                .padding(.top, 8)
                .padding(.bottom, 6)

            if !isRecording {
                if showNumbers {
                    numbersView
                } else {
                    lettersView
                }
                bottomRow
                    .padding(.top, keySpaceV)
                    .padding(.bottom, 4)
            }
        }
        .background(Color(UIColor.systemGray6))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Toolbar
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var toolbarView: some View {
        Group {
            if isRecording {
                recordingToolbar
            } else if isAppAlive {
                activeToolbar
            } else {
                inactiveToolbar
            }
        }
    }

    // State A: App not running
    private var inactiveToolbar: some View {
        HStack(spacing: 8) {
            Button {
                let state = SharedKeyboardState.load()
                if let t = state.transcript, !t.isEmpty { onInsertText(t) }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(UIColor.label))
                    .frame(width: 36, height: 36)
            }

            Spacer()

            Button { onOpenApp() } label: {
                Text("Start ST")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(darkBg)
                    .clipShape(Capsule())
            }
        }
    }

    // State B: App alive
    private var activeToolbar: some View {
        HStack(spacing: 8) {
            Button {
                let state = SharedKeyboardState.load()
                if let t = state.transcript, !t.isEmpty { onInsertText(t) }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(UIColor.label))
                    .frame(width: 36, height: 36)
            }

            Spacer()

            Menu {
                ForEach(modes, id: \.self) { mode in
                    Button {
                        selectedMode = mode
                    } label: {
                        HStack {
                            Text(mode)
                            if mode == selectedMode { Image(systemName: "checkmark") }
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
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(UIColor.systemGray4))
                .clipShape(Capsule())
            }

            Button { onStartDictation() } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(darkBg)
                    .clipShape(Circle())
            }
        }
    }

    // State C: Recording
    private var recordingToolbar: some View {
        VStack(spacing: 16) {
            HStack {
                Button { onCancelDictation() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(UIColor.label))
                        .frame(width: 34, height: 34)
                        .background(Color(UIColor.systemGray4))
                        .clipShape(Circle())
                }

                Spacer()

                Text(selectedMode)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(UIColor.secondaryLabel))

                Button { onStopDictation() } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(darkBg)
                        .clipShape(Circle())
                }
            }

            // Audio-reactive waveform bars
            HStack(spacing: 3) {
                ForEach(0..<11, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(UIColor.label))
                        .frame(width: 3, height: waveformBars[i])
                        .animation(.easeOut(duration: 0.15), value: waveformBars[i])
                }
            }
            .onAppear { startWaveformPolling() }
            .onDisappear { stopWaveformPolling() }

            VStack(spacing: 2) {
                Text("Listening")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(UIColor.label))
                Text("iPhone Microphone")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(UIColor.secondaryLabel))
            }

            Spacer().frame(height: 30)
        }
        .padding(.top, 8)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Letters
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var lettersView: some View {
        VStack(spacing: keySpaceV) {
            // Row 1
            HStack(spacing: keySpaceH) {
                ForEach(letterRows[0], id: \.self) { key in
                    letterKey(isShifted ? key.uppercased() : key) { tapKey(key) }
                }
            }
            .padding(.horizontal, padH)

            // Row 2 — indented
            HStack(spacing: keySpaceH) {
                ForEach(letterRows[1], id: \.self) { key in
                    letterKey(isShifted ? key.uppercased() : key) { tapKey(key) }
                }
            }
            .padding(.horizontal, padH + 16)

            // Row 3 — shift + keys + delete
            HStack(spacing: keySpaceH) {
                Button { isShifted.toggle() } label: {
                    Image(systemName: isShifted ? "shift.fill" : "shift")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(UIColor.label))
                        .frame(width: utilWidth, height: keyH)
                        .background(Color(UIColor.systemGray3))
                        .clipShape(RoundedRectangle(cornerRadius: keyRadius))
                }

                ForEach(letterRows[2], id: \.self) { key in
                    letterKey(isShifted ? key.uppercased() : key) { tapKey(key) }
                }

                deleteKey
            }
            .padding(.horizontal, padH)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Numbers
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var numbersView: some View {
        VStack(spacing: keySpaceV) {
            HStack(spacing: keySpaceH) {
                ForEach(numberRows[0], id: \.self) { key in
                    letterKey(key) { onInsertText(key) }
                }
            }
            .padding(.horizontal, padH)

            HStack(spacing: keySpaceH) {
                ForEach(numberRows[1], id: \.self) { key in
                    letterKey(key) { onInsertText(key) }
                }
            }
            .padding(.horizontal, padH)

            HStack(spacing: keySpaceH) {
                Spacer()
                ForEach(numberRows[2], id: \.self) { key in
                    letterKey(key) { onInsertText(key) }
                }
                deleteKey
                Spacer()
            }
            .padding(.horizontal, padH)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Bottom Row
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var bottomRow: some View {
        HStack(spacing: keySpaceH) {
            // 123
            Button { showNumbers.toggle() } label: {
                Text(showNumbers ? "ABC" : "123")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(UIColor.label))
                    .frame(width: 50, height: keyH)
                    .background(Color(UIColor.systemGray3))
                    .clipShape(RoundedRectangle(cornerRadius: keyRadius))
            }

            // Spacebar
            Button { onInsertText(" ") } label: {
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(UIColor.tertiaryLabel))
                    Text("ST")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color(UIColor.tertiaryLabel))
                }
                .frame(maxWidth: .infinity)
                .frame(height: keyH)
                .background(Color(UIColor.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: keyRadius))
                .shadow(color: .black.opacity(0.2), radius: 0.5, x: 0, y: 1)
            }

            // Period
            Button { onInsertText(".") } label: {
                Text(".")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color(UIColor.label))
                    .frame(width: 44, height: keyH)
                    .background(Color(UIColor.systemGray3))
                    .clipShape(RoundedRectangle(cornerRadius: keyRadius))
            }

            // Return
            Button { onReturnKey() } label: {
                Image(systemName: "return")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(UIColor.label))
                    .frame(width: 50, height: keyH)
                    .background(Color(UIColor.systemGray3))
                    .clipShape(RoundedRectangle(cornerRadius: keyRadius))
            }
        }
        .padding(.horizontal, padH)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Key Builder
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func letterKey(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: letterFont, weight: .regular))
                .foregroundStyle(Color(UIColor.label))
                .frame(maxWidth: .infinity)
                .frame(height: keyH)
                .background(Color(UIColor.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: keyRadius))
                .shadow(color: .black.opacity(0.2), radius: 0.5, x: 0, y: 1)
        }
    }

    private func tapKey(_ key: String) {
        let char = isShifted ? key.uppercased() : key
        onInsertText(char)
        if isShifted { isShifted = false }
    }

    // MARK: - Waveform

    private func startWaveformPolling() {
        waveformTimer?.invalidate()
        waveformTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
            let level = CGFloat(SharedDefaults.shared.audioLevel)
            // Generate bars based on real audio level with some randomness for natural feel
            var newBars: [CGFloat] = []
            // Pattern: outer bars shorter, inner bars taller
            let pattern: [CGFloat] = [0.5, 0.3, 0.6, 0.2, 1.0, 0.2, 0.3, 1.0, 0.2, 0.6, 0.3]
            for i in 0..<11 {
                let base: CGFloat = 4 // minimum height when silent
                let maxHeight: CGFloat = 36
                let randomJitter = CGFloat.random(in: -0.1...0.1)
                let barLevel = max(0, min(1, level * pattern[i] + randomJitter))
                newBars.append(base + barLevel * (maxHeight - base))
            }
            waveformBars = newBars
        }
    }

    private func stopWaveformPolling() {
        waveformTimer?.invalidate()
        waveformTimer = nil
        waveformBars = Array(repeating: 4, count: 11)
    }

    // MARK: - Delete Key (hold to repeat)

    private var deleteKey: some View {
        Image(systemName: "delete.left")
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Color(UIColor.label))
            .frame(width: utilWidth, height: keyH)
            .background(Color(UIColor.systemGray3))
            .clipShape(RoundedRectangle(cornerRadius: keyRadius))
            .onTapGesture {
                onDeleteBackward()
            }
            .onLongPressGesture(minimumDuration: 0.3, pressing: { pressing in
                if pressing {
                    // Start repeating delete
                    deleteTimer?.invalidate()
                    deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                        onDeleteBackward()
                    }
                } else {
                    // Stop repeating
                    deleteTimer?.invalidate()
                    deleteTimer = nil
                }
            }, perform: {})
    }
}
