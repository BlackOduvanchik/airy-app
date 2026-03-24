//
//  SheetSafeTextField.swift
//  Airy
//
//  UIKit-backed TextField that avoids "System gesture gate timed out" in sheets.
//  SwiftUI's TextField + @FocusState inside a sheet causes a ~2s freeze because
//  UIKit's sheet gesture recognizers compete with becomeFirstResponder().
//  This wrapper bypasses SwiftUI's gesture resolution entirely.
//

import SwiftUI
import UIKit

struct SheetSafeTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var textColor: UIColor = .label
    var placeholderColor: UIColor = .tertiaryLabel
    var font: UIFont = .systemFont(ofSize: 15)
    var keyboardType: UIKeyboardType = .default
    var autocapitalizationType: UITextAutocapitalizationType = .sentences
    var autocorrectionType: UITextAutocorrectionType = .default
    var returnKeyType: UIReturnKeyType = .done
    var onFocusChange: ((Bool) -> Void)?

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.font = font
        tf.textColor = textColor
        tf.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: placeholderColor, .font: font]
        )
        tf.keyboardType = keyboardType
        tf.autocapitalizationType = autocapitalizationType
        tf.autocorrectionType = autocorrectionType
        tf.returnKeyType = returnKeyType
        tf.delegate = context.coordinator
        tf.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tf
    }

    func updateUIView(_ tf: UITextField, context: Context) {
        if tf.text != text {
            tf.text = text
        }
        tf.textColor = textColor
        tf.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: placeholderColor, .font: font]
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SheetSafeTextField

        init(_ parent: SheetSafeTextField) {
            self.parent = parent
        }

        @objc func textChanged(_ sender: UITextField) {
            parent.text = sender.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.onFocusChange?(true)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.onFocusChange?(false)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}
