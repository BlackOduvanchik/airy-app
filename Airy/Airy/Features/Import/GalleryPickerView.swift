//
//  GalleryPickerView.swift
//  Airy
//
//  Presents PHPickerViewController immediately when view appears. No intermediate screen.
//

import SwiftUI
import PhotosUI

struct GalleryPickerView: UIViewControllerRepresentable {
    var onImagePicked: (UIImage) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked, onCancel: onCancel)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var onImagePicked: (UIImage) -> Void
        var onCancel: () -> Void

        init(onImagePicked: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImagePicked = onImagePicked
            self.onCancel = onCancel
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let result = results.first else {
                onCancel()
                return
            }
            result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] obj, _ in
                guard let image = obj as? UIImage else {
                    DispatchQueue.main.async { self?.onCancel() }
                    return
                }
                DispatchQueue.main.async {
                    self?.onImagePicked(image)
                }
            }
        }
    }
}
