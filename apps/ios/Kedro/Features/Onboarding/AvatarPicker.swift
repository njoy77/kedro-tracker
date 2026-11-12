import PhotosUI
import SwiftUI

/// Pick a face (design §3.5, mockup frame 3): a photo first (library or camera, then Move and
/// Scale), or, for anyone who'd rather not, an emoji on one of 12 colors. Used by onboarding and
/// by Settings → Profile.
struct AvatarPicker: View {
    enum Source: String, CaseIterable, Identifiable {
        case photo = "Photo"
        case emoji = "Emoji"

        var id: String { rawValue }
    }

    /// The full-screen photo flow: the camera, then the crop editor (one cover, so Retake can go
    /// back to the camera without stacking presentations).
    enum PhotoStep {
        case camera
        case crop(CGImage, fromCamera: Bool)
    }

    @Binding var avatar: Avatar?
    /// Shown under the preview (real casing; displayed uppercase).
    var name: String

    @State private var source: Source = .photo
    @State private var photoItem: PhotosPickerItem?
    @State private var photoStep: PhotoStep?
    @State private var isLoadingPhoto = false
    @State private var photoError: String?
    @State private var emoji = Avatar.starterEmoji[0]
    @State private var colorIndex = 0
    /// A current emoji that isn't one of the choices (picked on an older build or the web).
    @State private var extraEmoji: String?

    /// A fixed set to tap: no typing, so nothing to get stuck on.
    static let emojiChoices = Avatar.starterEmoji + [
        "🐸", "🦁", "🐻", "🦖", "🐎", "🦄", "🐯", "🐼", "🐵", "🦝", "🐢", "🦩",
        "🃏", "🎲", "🍸", "🔥", "👑", "💀", "🎩", "🌙", "⚡️", "💎", "🍀", "🎯",
        "👻", "🤠", "😈", "🤡", "👽", "🤖", "😎", "🥶",
    ]

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                AvatarView(avatar: avatar, name: name, size: .profile)
                    .overlay {
                        if isLoadingPhoto { ProgressView().tint(.cream) }
                    }
                Text(name).kedroFont(.headline).foregroundStyle(.cream)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Your face")

            Picker("Source", selection: $source) {
                ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)

            switch source {
            case .photo: photoPane
            case .emoji: emojiPane
            }
        }
        .onAppear(perform: syncFromAvatar)
        // The owner may load the avatar after this appears (Settings fills it in its own
        // onAppear): follow it, so a current emoji is always in the grid and selected.
        .onChange(of: avatar) { old, new in
            if old == nil { syncFromAvatar() } else { syncEmoji() }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .fullScreenCover(isPresented: isShowingPhotoStep) {
            photoStepView
        }
    }

    // MARK: Photo

    private var photoPane: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                Label("Choose a Photo", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.kedroGlassWide)
            if CameraCapture.isAvailable {
                Button("Take a Photo", systemImage: "camera") { photoStep = .camera }
                    .buttonStyle(.kedroGlassWide)
            }
            if let photoError {
                Text(photoError).font(.footnote).foregroundStyle(.silver)
            } else {
                Text("You'll move and zoom it next. Anyone can report a photo, so keep it to your face.")
                    .font(.footnote)
                    .foregroundStyle(.silverDim)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 26)
    }

    private var isShowingPhotoStep: Binding<Bool> {
        Binding(get: { photoStep != nil }, set: { if !$0 { photoStep = nil } })
    }

    @ViewBuilder
    private var photoStepView: some View {
        switch photoStep {
        case .camera:
            CameraCapture { data in
                guard let data else {
                    photoStep = nil
                    return
                }
                if let image = AvatarPhotoStore.editableImage(from: data) {
                    photoStep = .crop(image, fromCamera: true)
                } else {
                    photoStep = nil
                    photoError = AvatarPhotoStore.PhotoError.unreadableImage.localizedDescription
                }
            }
            .ignoresSafeArea()
        case .crop(let image, let fromCamera):
            AvatarCropView(
                image: image,
                onCancel: { photoStep = nil },
                onRetake: fromCamera ? { photoStep = .camera } : nil,
                onChoose: { crop in
                    savePhoto(image, crop: crop)
                    photoStep = nil
                }
            )
        case nil:
            Color.black.ignoresSafeArea()
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        isLoadingPhoto = true
        defer {
            isLoadingPhoto = false
            photoItem = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = AvatarPhotoStore.editableImage(from: data)
        else {
            photoError = AvatarPhotoStore.PhotoError.unreadableImage.localizedDescription
            return
        }
        photoError = nil
        photoStep = .crop(image, fromCamera: false)
    }

    private func savePhoto(_ image: CGImage, crop: AvatarCrop) {
        do {
            let url = try AvatarPhotoStore.save(image, crop: crop.cropRect)
            AvatarPhotoStore.removeIfLocal(avatar)
            avatar = .photo(url)
            photoError = nil
        } catch {
            photoError = error.localizedDescription
        }
    }

    // MARK: Emoji

    /// The choices, with `extraEmoji` kept up front so it stays selectable.
    private var emojiGrid: [String] {
        extraEmoji.map { [$0] + Self.emojiChoices } ?? Self.emojiChoices
    }

    private var emojiPane: some View {
        VStack(spacing: 14) {
            Text("No photo? Pick an emoji and a color.")
                .font(.footnote)
                .foregroundStyle(.silverDim)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
                ForEach(emojiGrid, id: \.self) { item in
                    Button {
                        emoji = item
                        applyEmoji()
                    } label: {
                        Text(item)
                            .font(.title3)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(isSelected(item) ? Color.surfaceRaised : .clear, in: .rect(cornerRadius: 10))
                    }
                    // Its own hit target: in Settings the picker is one Form row, where default-style
                    // buttons all fire on any tap in the row.
                    .buttonStyle(.plain)
                    .accessibilityLabel(item)
                    .accessibilityAddTraits(isSelected(item) ? .isSelected : [])
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                ForEach(AvatarPalette.colors.indices, id: \.self) { index in
                    Button {
                        colorIndex = index
                        applyEmoji()
                    } label: {
                        Circle()
                            .fill(AvatarPalette.color(index))
                            .frame(width: 36, height: 36)
                            .overlay {
                                if index == colorIndex {
                                    Circle().stroke(.kedroRed, lineWidth: 2).padding(-4)
                                }
                            }
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Color \(index + 1)")
                    .accessibilityAddTraits(index == colorIndex ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, 22)
    }

    private func isSelected(_ item: String) -> Bool {
        if case .emoji(let current, _) = avatar { return current == item }
        return false
    }

    private func applyEmoji() {
        AvatarPhotoStore.removeIfLocal(avatar)
        avatar = .emoji(emoji, colorIndex: colorIndex)
    }

    private func syncFromAvatar() {
        switch avatar {
        case .emoji: source = .emoji
        case .photo, .curated, nil: source = .photo
        }
        syncEmoji()
    }

    private func syncEmoji() {
        guard case let .emoji(value, index) = avatar else { return }
        emoji = value
        colorIndex = index
        if !Self.emojiChoices.contains(value) { extraEmoji = value }
    }
}

#Preview("Photo first") {
    @Previewable @State var avatar: Avatar?
    ScrollView {
        AvatarPicker(avatar: $avatar, name: "Noah")
            .padding(.vertical)
    }
    .background(.night)
    .previewEnvironment()
    .preferredColorScheme(.dark)
}

#Preview("Emoji") {
    @Previewable @State var avatar: Avatar? = .emoji("🦊", colorIndex: 3)
    ScrollView {
        AvatarPicker(avatar: $avatar, name: "Ana")
            .padding(.vertical)
    }
    .background(.night)
    .previewEnvironment()
    .preferredColorScheme(.dark)
}
