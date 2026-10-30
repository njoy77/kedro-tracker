import PhotosUI
import SwiftUI

/// Pick a face (design §3.5, mockup frame 3): a photo (library or camera), any emoji on one of 12
/// colors, or one of the 24 curated avatars. Used by onboarding and by Settings → Profile.
struct AvatarPicker: View {
    enum Source: String, CaseIterable, Identifiable {
        case photo = "Photo"
        case emoji = "Emoji"
        case curated = "Kedro"

        var id: String { rawValue }
    }

    @Binding var avatar: Avatar?
    /// Shown under the preview (real casing; displayed uppercase).
    var name: String
    /// Secret avatars this player has unlocked with badges.
    var unlocked: Set<CuratedAvatarID> = []

    @State private var source: Source = .curated
    @State private var photoItem: PhotosPickerItem?
    @State private var isCapturing = false
    @State private var photoError: String?
    @State private var emojiText = ""
    @State private var emoji = Avatar.starterEmoji[0]
    @State private var colorIndex = 0

    static let quickEmoji = Avatar.starterEmoji + ["🃏", "🎲", "🍸", "🔥", "👑", "💀", "🐎", "🦄", "🐸", "🦁", "🐻", "🦖"]

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                AvatarView(avatar: avatar, name: name, size: .profile)
                Text(name).kedroFont(.headline).foregroundStyle(.cream)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Your face")

            Picker("Source", selection: $source) {
                ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)

            switch source {
            case .photo: photoPane
            case .emoji: emojiPane
            case .curated: curatedPane
            }
        }
        .onAppear(perform: syncFromAvatar)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .fullScreenCover(isPresented: $isCapturing) {
            CameraCapture { data in
                isCapturing = false
                if let data { savePhoto(data) }
            }
            .ignoresSafeArea()
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
                Button("Take a Photo", systemImage: "camera") { isCapturing = true }
                    .buttonStyle(.kedroGlassWide)
            }
            if let photoError {
                Text(photoError).font(.footnote).foregroundStyle(.silver)
            } else {
                Text("Cropped to a circle. Anyone can report a photo, so keep it to your face.")
                    .font(.footnote)
                    .foregroundStyle(.silverDim)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 26)
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                photoError = AvatarPhotoStore.PhotoError.unreadableImage.localizedDescription
                return
            }
            savePhoto(data)
        } catch {
            photoError = AvatarPhotoStore.PhotoError.unreadableImage.localizedDescription
        }
        photoItem = nil
    }

    private func savePhoto(_ data: Data) {
        do {
            let url = try AvatarPhotoStore.save(data)
            AvatarPhotoStore.removeIfLocal(avatar)
            avatar = .photo(url)
            photoError = nil
        } catch {
            photoError = error.localizedDescription
        }
    }

    // MARK: Emoji

    private var emojiPane: some View {
        VStack(spacing: 14) {
            TextField("Type any emoji", text: $emojiText)
                .multilineTextAlignment(.center)
                .font(.title2)
                .padding(.vertical, 10)
                .background(.surface, in: .rect(cornerRadius: 12))
                .onChange(of: emojiText) { _, text in
                    if let picked = EmojiInput.lastEmoji(in: text) {
                        emoji = picked
                        applyEmoji()
                    }
                    if !text.isEmpty { emojiText = "" }
                }
                .accessibilityHint("Opens the keyboard. Switch to the emoji keyboard and pick one.")

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                ForEach(Self.quickEmoji, id: \.self) { item in
                    Button {
                        emoji = item
                        applyEmoji()
                    } label: {
                        Text(item)
                            .font(.title3)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(item == emoji ? Color.surfaceRaised : .clear, in: .rect(cornerRadius: 10))
                    }
                    .accessibilityLabel(item)
                    .accessibilityAddTraits(item == emoji ? .isSelected : [])
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
                    .accessibilityLabel("Color \(index + 1)")
                    .accessibilityAddTraits(index == colorIndex ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, 22)
    }

    private func applyEmoji() {
        AvatarPhotoStore.removeIfLocal(avatar)
        avatar = .emoji(emoji, colorIndex: colorIndex)
    }

    // MARK: Curated

    private var curatedPane: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                ForEach(CuratedAvatarID.allCases) { id in
                    let locked = id.isSecret && !unlocked.contains(id)
                    Button {
                        AvatarPhotoStore.removeIfLocal(avatar)
                        avatar = .curated(id)
                    } label: {
                        AvatarView(avatar: .curated(id), name: id.displayName, size: .medium, ring: avatar == .curated(id) ? .focus : .none)
                            .opacity(locked ? 0.35 : 1)
                            .frame(minWidth: 56, minHeight: 56)
                    }
                    .disabled(locked)
                    .accessibilityLabel(id.displayName)
                    .accessibilityValue(locked ? "Locked. Unlocks with \(id.unlockingBadge ?? "a secret badge")." : "")
                    .accessibilityAddTraits(avatar == .curated(id) ? .isSelected : [])
                }
            }
            Text("Faded ones unlock with secret badges.")
                .font(.footnote)
                .foregroundStyle(.silverDim)
        }
        .padding(.horizontal, 26)
    }

    private func syncFromAvatar() {
        switch avatar {
        case .photo: source = .photo
        case let .emoji(value, index):
            source = .emoji
            emoji = value
            colorIndex = index
        case .curated, nil: source = .curated
        }
    }
}

#Preview {
    @Previewable @State var avatar: Avatar? = .curated(.crow)
    ScrollView {
        AvatarPicker(avatar: $avatar, name: "Noah")
            .padding(.vertical)
    }
    .background(.night)
    .previewEnvironment()
    .preferredColorScheme(.dark)
}
