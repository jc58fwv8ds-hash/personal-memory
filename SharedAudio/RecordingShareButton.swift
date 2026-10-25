#if os(iOS)
import SwiftUI
import UIKit

struct RecordingShareButton: View {
    let item: RecordingItem
    @StateObject private var session = RecordingExportSession()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { session.prepare(item.url) } label: {
                Label(session.isPreparing ? "共有の準備中…" : "Macなどへ共有", systemImage: "square.and.arrow.up")
            }
            .disabled(session.isPreparing || session.shared != nil)
            .accessibilityIdentifier("share-recording-\(item.id.uuidString)")
            if let message = session.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .sheet(item: $session.shared, onDismiss: session.dismiss) { recording in
            RecordingActivitySheet(url: recording.url)
        }
        .onDisappear { session.cancelPreparation() }
    }
}

private struct RecordingActivitySheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
