import SwiftUI

struct ContentView: View {
    @State private var events: [MemoryEvent] = []
    @State private var inputText = ""
    @State private var errorMessage: String? = nil
    @State private var loadSucceeded = false
    
    private let store: MemoryEventStore?
    
    init() {
        do {
            self.store = try MemoryEventStore(fileURL: MemoryEventStore.defaultFileURL())
        } catch {
            self.store = nil
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if events.isEmpty && errorMessage == nil {
                    ContentUnavailableView(
                        "今日の記憶",
                        systemImage: "text.bubble",
                        description: Text("下の欄に出来事を書いて「記録する」を押してください。")
                    )
                } else {
                    List {
                        ForEach(events, id: \.id) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.occurredAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(event.transcript)
                                    .font(.body)
                            }
                        }
                    }
                }
            }
            .navigationTitle("今日の記憶")
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if let error = errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    HStack {
                        TextField("出来事を入力", text: $inputText, axis: .vertical)
                            .lineLimit(1...3)
                            .accessibilityIdentifier("memory-input")
                        Button(action: saveMemory) {
                            Text("記録する")
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store == nil || !loadSucceeded)
                        .accessibilityIdentifier("memory-save")
                    }
                    Text("Watchの音声は「録音」で聴き直せます。AI要約は準備中です。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.bar)
            }
        }
        .onAppear {
            loadEvents()
        }
    }
    
    private func loadEvents() {
        loadSucceeded = false
        guard let store else {
            errorMessage = "保存先を用意できませんでした。記録は変更していません。"
            return
        }
        do {
            events = try store.load()
            loadSucceeded = true
            errorMessage = nil
        } catch {
            errorMessage = "読み込みに失敗しました: \(error.localizedDescription)"
        }
    }
    
    private func saveMemory() {
        guard loadSucceeded, let store else { return }
        let trimmedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }
        
        do {
            var newEvents = events
            let newEvent = MemoryEvent(
                id: UUID(),
                occurredAt: Date(),
                transcript: trimmedInput,
                importance: 50,
                tags: [],
                sourceCaptureIDs: []
            )
            newEvents.append(newEvent)
            try store.save(newEvents)
            events = newEvents
            inputText = ""
            errorMessage = nil
        } catch {
            errorMessage = "保存に失敗しました: \(error.localizedDescription)"
        }
    }
}
