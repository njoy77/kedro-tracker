import SwiftUI

/// "Move and Scale" for a new avatar photo: drag to reposition, pinch to zoom, under a round
/// mask. What's inside the circle is exactly what gets saved and uploaded (`AvatarCrop.cropRect`).
/// Shown after picking from the library and after taking a photo (with Retake).
struct AvatarCropView: View {
    let image: CGImage
    var onCancel: () -> Void
    /// Camera only: back to the camera for another shot.
    var onRetake: (() -> Void)?
    var onChoose: (AvatarCrop) -> Void

    @State private var crop: AvatarCrop
    @State private var lastTranslation: CGSize = .zero
    @State private var lastMagnification: CGFloat = 1

    init(image: CGImage, onCancel: @escaping () -> Void, onRetake: (() -> Void)? = nil, onChoose: @escaping (AvatarCrop) -> Void) {
        self.image = image
        self.onCancel = onCancel
        self.onRetake = onRetake
        self.onChoose = onChoose
        _crop = State(initialValue: AvatarCrop(imageSize: CGSize(width: image.width, height: image.height)))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                canvas(size: proxy.size)
            }
            .background(.black)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Text("Drag to move. Pinch to zoom.")
                        .font(.footnote)
                        .foregroundStyle(.silver)
                    if let onRetake {
                        Button("Retake", systemImage: "camera", action: onRetake)
                            .buttonStyle(.kedroGlass)
                    }
                }
                .padding(.bottom, 12)
            }
            .navigationTitle("Move and Scale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Choose") { onChoose(crop) }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// The photo under the mask, with the gestures.
    private func canvas(size: CGSize) -> some View {
        let diameter = max(1, min(size.width, size.height) - 40)
        let shown = crop.displayedSize
        return ZStack {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: shown.width * diameter, height: shown.height * diameter)
                .offset(x: crop.offset.width * diameter, y: crop.offset.height * diameter)
            mask(diameter: diameter)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .contentShape(.rect)
        .gesture(drag(diameter: diameter).simultaneously(with: pinch))
        .onTapGesture(count: 2, perform: toggleZoom)
        .modifier(CropAccessibility(crop: $crop))
    }

    private func toggleZoom() {
        withAnimation(.snappy) { crop = crop.zoomed(by: crop.zoom > 1 ? 1 / crop.zoom : 2) }
    }

    /// Dims everything outside the circle and outlines it.
    private func mask(diameter: CGFloat) -> some View {
        ZStack {
            Color.black.opacity(0.6)
                .mask {
                    Rectangle()
                        .overlay {
                            Circle()
                                .frame(width: diameter, height: diameter)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                }
            Circle()
                .stroke(.white.opacity(0.7), lineWidth: 1)
                .frame(width: diameter, height: diameter)
        }
        .allowsHitTesting(false)
    }

    /// Moves by the change since the last update, so the clamp at the edges never stores
    /// overshoot: drag back and the photo follows at once.
    private func drag(diameter: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let delta = CGSize(
                    width: (value.translation.width - lastTranslation.width) / diameter,
                    height: (value.translation.height - lastTranslation.height) / diameter
                )
                lastTranslation = value.translation
                crop = crop.moved(by: delta)
            }
            .onEnded { _ in lastTranslation = .zero }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                crop = crop.zoomed(by: value.magnification / lastMagnification)
                lastMagnification = value.magnification
            }
            .onEnded { _ in lastMagnification = 1 }
    }
}

/// VoiceOver can't drag or pinch: swipe up and down to zoom, and actions to move the photo.
private struct CropAccessibility: ViewModifier {
    @Binding var crop: AvatarCrop

    private var zoomText: String {
        "Zoom \(Double(crop.zoom).formatted(.number.precision(.fractionLength(1))))×"
    }

    func body(content: Content) -> some View {
        content
            .accessibilityElement()
            .accessibilityLabel("Photo crop")
            .accessibilityValue(zoomText)
            .accessibilityHint("Drag to move the photo, pinch to zoom. What's inside the circle is your face.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: crop = crop.zoomed(by: 1.25)
                case .decrement: crop = crop.zoomed(by: 0.8)
                @unknown default: break
                }
            }
            .accessibilityAction(named: "Move Photo Up") { move(0, -0.1) }
            .accessibilityAction(named: "Move Photo Down") { move(0, 0.1) }
            .accessibilityAction(named: "Move Photo Left") { move(-0.1, 0) }
            .accessibilityAction(named: "Move Photo Right") { move(0.1, 0) }
    }

    private func move(_ x: CGFloat, _ y: CGFloat) {
        crop = crop.moved(by: CGSize(width: x, height: y))
    }
}

#Preview {
    let renderer = ImageRenderer(
        content: LinearGradient(colors: [.kedroRed, .gold, .night], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay { Text("🦊").font(.system(size: 160)) }
            .frame(width: 300, height: 450)
    )
    if let image = renderer.cgImage {
        AvatarCropView(image: image, onCancel: {}, onRetake: {}, onChoose: { _ in })
    }
}
