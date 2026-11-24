import SwiftUI

/// One line saying how much of the library is searchable yet.
struct IndexProgressLine: View {
    @Environment(IndexStatus.self) private var status

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if status.isRunning {
                ProgressView(value: Double(status.indexed), total: Double(max(status.total, 1))) {
                    Text("Indexing \(status.indexed) of \(status.total) photos")
                }
                if let pause = status.pause {
                    Text(pause.message)
                }
            } else if status.total > 0 {
                Text("\(status.indexed) of \(status.total) photos indexed on this device")
            }
            if !status.semanticSearchAvailable {
                Text("Search by description is off because the MobileCLIP models are not installed. Text and label search still works.")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}
