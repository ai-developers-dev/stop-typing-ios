import SwiftUI

struct DebugLogView: View {
    @State private var log = SharedDefaults.shared.debugLog
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            Text(log.isEmpty ? "No log entries yet.\n\nTap Start Flow on the keyboard, then come back here to see what happened." : log)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(log.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("Debug Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") {
                    SharedDefaults.shared.clearDebugLog()
                    log = ""
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh") {
                    log = SharedDefaults.shared.debugLog
                }
            }
        }
        .onReceive(timer) { _ in
            log = SharedDefaults.shared.debugLog
        }
    }
}
