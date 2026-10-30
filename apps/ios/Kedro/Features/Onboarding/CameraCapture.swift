import SwiftUI
import UIKit

// UIKit: SwiftUI has no camera capture view (PhotosPicker only reads the library), so taking a
// new avatar photo wraps UIImagePickerController. Kept to the minimum: capture, hand back JPEG
// data, dismiss.

/// Takes one photo with the camera and returns it as JPEG data (nil if cancelled).
struct CameraCapture: UIViewControllerRepresentable {
    var onFinish: (Data?) -> Void

    /// The camera exists and the app declares why it needs it (`NSCameraUsageDescription`).
    /// Without the usage string iOS would terminate the app on access, so the option is hidden.
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
            && Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .front
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (Data?) -> Void

        init(onFinish: @escaping (Data?) -> Void) {
            self.onFinish = onFinish
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage
            onFinish(image?.jpegData(compressionQuality: 0.9))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
