import SwiftUI

/// Simple in-memory transcript history store.
/// Can be upgraded to SwiftData or Core Data later.
@MainActor
final class TranscriptHistoryStore: ObservableObject {
    static let shared = TranscriptHistoryStore()

    @Published var items: [TranscriptItem] = []

    private let storageKey = "transcriptHistory"

    private var hasLoaded = false

    private init() {}

    func ensureLoaded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        load()
    }

    func add(_ item: TranscriptItem) {
        ensureLoaded()
        items.insert(item, at: 0)
        save()
    }

    func remove(at offsets: IndexSet) {
        ensureLoaded()
        items.remove(atOffsets: offsets)
        save()
    }

    func clearAll() {
        items.removeAll()
        hasLoaded = true
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([TranscriptItem].self, from: data) else {
            return
        }
        items = decoded
    }
}

struct HistoryView: View {
    @StateObject private var store = TranscriptHistoryStore.shared
    @State private var showCopiedToast = false

    var body: some View {
        NavigationStack {
            Group {
                if store.items.isEmpty {
                    EmptyStateView(
                        icon: "clock",
                        title: "No History",
                        message: "Your transcripts will appear here after you record them."
                    )
                } else {
                    List {
                        ForEach(store.items) { item in
                            TranscriptCard(item: item) {
                                UIPasteboard.general.string = item.text
                                withAnimation { showCopiedToast = true }
                                Task {
                                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                                    withAnimation { showCopiedToast = false }
                                }
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(
                                top: 4, leading: 16, bottom: 4, trailing: 16
                            ))
                        }
                        .onDelete { offsets in
                            store.remove(at: offsets)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(AppTheme.background)
            .navigationTitle("History")
            .onAppear { store.ensureLoaded() }
            .toolbar {
                if !store.items.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear All", role: .destructive) {
                            store.clearAll()
                        }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if showCopiedToast {
                    Text("Copied to clipboard")
                        .font(AppTheme.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(.black.opacity(0.8)))
                        .padding(.bottom, 32)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }
}

#Preview {
    HistoryView()
}
