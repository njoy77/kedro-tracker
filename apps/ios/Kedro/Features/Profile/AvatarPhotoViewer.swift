import ImageIO
import SwiftUI

/// A profile photo, full screen (tap the round photo on a profile). Loads the photo's own URL,
/// which is the largest version there is (the stored square, up to 1024 px). Close with the X
/// or a swipe down; a failed load offers Try Again.
struct AvatarPhotoViewer: View {
    let url: URL
    let name: String

    private enum Phase {
        case loading
        case loaded(CGImage)
        case failed
    }

    @Environment(\.dismiss) private var dismiss
    @State private var phase = Phase.loading
    @State private var attempt = 0
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
                .opacity(1 - min(0.6, abs(dragOffset) / 400))
            content
                .offset(y: dragOffset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(.rect)
        .gesture(
            DragGesture()
                .onChanged { dragOffset = max(0, $0.translation.height) }
                .onEnded { value in
                    if value.translation.height > 120 || value.predictedEndTranslation.height > 300 {
                        dismiss()
                    } else {
                        withAnimation(.snappy) { dragOffset = 0 }
                    }
                }
        )
        .overlay(alignment: .topTrailing) {
            Button("Close", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
                .padding(16)
        }
        .preferredColorScheme(.dark)
        .accessibilityAction(.escape) { dismiss() }
        .task(id: attempt) {
            phase = .loading
            if let image = await Self.load(url) {
                withAnimation(.easeOut(duration: 0.2)) { phase = .loaded(image) }
            } else if !Task.isCancelled {
                phase = .failed
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loaded(let image):
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("\(name)'s photo")
        case .failed:
            ContentUnavailableView {
                Label("Couldn't Load the Photo", systemImage: "photo.badge.exclamationmark")
            } description: {
                Text("Check your connection and try again.")
            } actions: {
                Button("Try Again") { attempt += 1 }
                    .buttonStyle(.kedroGlass)
            }
            .foregroundStyle(.cream)
        case .loading:
            ProgressView()
                .tint(.cream)
                .controlSize(.large)
                .accessibilityLabel("Loading \(name)'s photo")
        }
    }

    /// Fetches and decodes the photo (the URL cache usually has it from the profile already). A
    /// short timeout so a dead connection turns into Try Again instead of a minute of spinner.
    @concurrent private static func load(_ url: URL) async -> CGImage? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4096,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// A photo to show in `AvatarPhotoViewer` (for `.fullScreenCover(item:)`).
struct AvatarPhotoTarget: Identifiable, Hashable {
    let url: URL
    let name: String

    var id: URL { url }
}

#Preview("Failure") {
    AvatarPhotoViewer(url: URL(filePath: "/nonexistent/photo.jpg"), name: "Ana")
}

#Preview("Loading") {
    AvatarPhotoViewer(url: URL(string: "https://example.invalid/photo.jpg") ?? URL(filePath: "/"), name: "Ana")
}
