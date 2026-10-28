import SwiftUI

// STUB: owned by talk. Replace this file's contents; keep the type name and initializer.

/// Send a Receipt after a finished game (design §8.5).
struct ReceiptComposer: View {
    let gameID: GameID

    var body: some View {
        ContentUnavailableView(
            "Send a Receipt",
            systemImage: "doc.text",
            description: Text("Coming soon.")
        )
        .navigationTitle("Send a Receipt")
    }
}

#Preview {
    ReceiptComposer(gameID: PreviewData.sampleGameID).previewEnvironment()
}
