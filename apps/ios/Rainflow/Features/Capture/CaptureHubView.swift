import PhotosUI
import SwiftUI
@preconcurrency import UIKit

struct CaptureHubView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isCameraUnavailablePresented = false
    let onTakePhoto: () -> Void
    let onManualEntry: () -> Void
    let onReceiptEntry: (Data) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Add Transaction")
                    .font(.title2.weight(.semibold))
                    .padding(.bottom, 8)

                actionButton(
                    title: "Take Photo",
                    subtitle: "Capture a receipt",
                    symbol: "camera.fill"
                ) {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        onTakePhoto()
                    } else {
                        isCameraUnavailablePresented = true
                    }
                }

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    CaptureActionLabel(
                        title: "Choose from Library",
                        subtitle: "Select a receipt image",
                        symbol: "photo.fill"
                    )
                }
                .buttonStyle(.plain)

                actionButton(
                    title: "Add Manually",
                    subtitle: "Enter without a receipt",
                    symbol: "pencil"
                ) {
                    onManualEntry()
                }

                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .tint(RainflowColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .padding(16)
            .background(RainflowColor.background)
            .onChange(of: selectedPhoto) { _, newValue in
                guard let newValue else { return }
                Task {
                    if let data = try? await newValue.loadTransferable(type: Data.self) {
                        let receiptData = UIImage(data: data)?.normalizedReceiptJPEGData() ?? data
                        await MainActor.run {
                            onReceiptEntry(receiptData)
                        }
                    }
                    await MainActor.run {
                        selectedPhoto = nil
                    }
                }
            }
            .alert("Camera unavailable", isPresented: $isCameraUnavailablePresented) {
                Button("Add Manually") {
                    onManualEntry()
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("The simulator does not have a camera. Use Choose from Library in the simulator, or test Take Photo on a real iPhone.")
            }
        }
    }

    private func actionButton(
        title: String,
        subtitle: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            CaptureActionLabel(title: title, subtitle: subtitle, symbol: symbol)
        }
        .buttonStyle(.plain)
    }

}

private struct CaptureActionLabel: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(RainflowColor.brandAccent)
                .frame(width: 42, height: 42)
                .background(RainflowColor.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(RainflowColor.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(RainflowColor.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(RainflowColor.textSecondary)
        }
        .padding(14)
        .background(RainflowColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(RainflowColor.border, lineWidth: 1)
        }
    }
}

@MainActor
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: @MainActor (UIImage) -> Void
    let onCancel: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image"]
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: @MainActor (UIImage) -> Void
        let onCancel: @MainActor () -> Void

        init(
            onImage: @escaping @MainActor (UIImage) -> Void,
            onCancel: @escaping @MainActor () -> Void
        ) {
            self.onImage = onImage
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
