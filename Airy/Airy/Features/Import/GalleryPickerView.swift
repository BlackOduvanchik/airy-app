//
//  GalleryPickerView.swift
//  Airy
//
//  Presents PHPickerViewController immediately when view appears. No intermediate screen.
//

import SwiftUI
import PhotosUI

struct GalleryPickerView: UIViewControllerRepresentable {
    var onImagesPicked: ([UIImage]) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 3
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagesPicked: onImagesPicked, onCancel: onCancel)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var onImagesPicked: ([UIImage]) -> Void
        var onCancel: () -> Void

        init(onImagesPicked: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onImagesPicked = onImagesPicked
            self.onCancel = onCancel
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else {
                onCancel()
                return
            }
            let group = DispatchGroup()
            var images: [UIImage] = []
            let lock = NSLock()
            for result in results {
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                    defer { group.leave() }
                    if let image = obj as? UIImage {
                        lock.lock()
                        images.append(image)
                        lock.unlock()
                    }
                }
            }
            group.notify(queue: .main) { [weak self] in
                guard let self = self else { return }
                if images.isEmpty {
                    self.onCancel()
                } else {
                    self.onImagesPicked(images)
                }
            }
        }
    }
}
