import SwiftUI
import UIKit

enum AnnotationTarget {
    case dose
    case concentration
    case quantity
    case form
    case signa
}

struct AnnotatableTextView: UIViewRepresentable {
    let text: String
    let font: UIFont
    let foregroundColor: UIColor
    let onAnnotate: (AnnotationTarget, String) -> Void

    init(
        text: String,
        font: UIFont = .systemFont(ofSize: 15),
        foregroundColor: UIColor = .label,
        onAnnotate: @escaping (AnnotationTarget, String) -> Void
    ) {
        self.text = text
        self.font = font
        self.foregroundColor = foregroundColor
        self.onAnnotate = onAnnotate
    }

    func makeUIView(context: Context) -> AnnotatableUITextView {
        let view = AnnotatableUITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.widthTracksTextView = true
        view.textContainer.lineBreakMode = .byCharWrapping
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.onAnnotate = onAnnotate
        return view
    }

    func updateUIView(_ uiView: AnnotatableUITextView, context: Context) {
        uiView.text = text
        uiView.font = font
        uiView.textColor = foregroundColor
        uiView.textContainer.widthTracksTextView = true
        uiView.textContainer.lineBreakMode = .byCharWrapping
        uiView.onAnnotate = onAnnotate
    }
}

struct AnnotatableTextEditor: UIViewRepresentable {
    @Binding var text: String

    let font: UIFont
    let foregroundColor: UIColor
    let onAnnotate: (AnnotationTarget, String) -> Void

    init(
        text: Binding<String>,
        font: UIFont = .systemFont(ofSize: 15),
        foregroundColor: UIColor = .label,
        onAnnotate: @escaping (AnnotationTarget, String) -> Void
    ) {
        self._text = text
        self.font = font
        self.foregroundColor = foregroundColor
        self.onAnnotate = onAnnotate
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: AnnotatableTextEditor

        init(parent: AnnotatableTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> AnnotatableUITextView {
        let view = AnnotatableUITextView()
        view.isEditable = true
        view.isSelectable = true
        view.isScrollEnabled = true
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.widthTracksTextView = true
        view.textContainer.lineBreakMode = .byCharWrapping
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.onAnnotate = onAnnotate
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: AnnotatableUITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.font = font
        uiView.textColor = foregroundColor
        uiView.onAnnotate = onAnnotate
    }
}

final class AnnotatableUITextView: UITextView {
    var onAnnotate: ((AnnotationTarget, String) -> Void)?

    private func tapHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(annotateDose)
            || action == #selector(annotateConcentration)
            || action == #selector(annotateQuantity)
            || action == #selector(annotateForm)
            || action == #selector(annotateSigna) {
            return selectedRange.length > 0
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard selectedRange.length > 0 else { return }

        let dose = UIAction(title: "Доза") { [weak self] _ in
            guard let self else { return }
            self.annotateDose()
        }

        let conc = UIAction(title: "Конц.") { [weak self] _ in
            guard let self else { return }
            self.annotateConcentration()
        }

        let qty = UIAction(title: "Кол-во") { [weak self] _ in
            guard let self else { return }
            self.annotateQuantity()
        }
        let form = UIAction(title: "Форма") { [weak self] _ in
            guard let self else { return }
            self.annotateForm()
        }
        let signa = UIAction(title: "Сигна") { [weak self] _ in
            guard let self else { return }
            self.annotateSigna()
        }

        builder.replaceChildren(ofMenu: .edit) { children in
            [dose, conc, qty, form, signa] + children
        }
    }

    @available(iOS 16.0, *)
    override func editMenu(for textRange: UITextRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard selectedRange.length > 0 else {
            return super.editMenu(for: textRange, suggestedActions: suggestedActions)
        }

        let dose = UIAction(title: "Доза") { [weak self] _ in
            self?.annotateDose()
        }
        let conc = UIAction(title: "Конц.") { [weak self] _ in
            self?.annotateConcentration()
        }
        let qty = UIAction(title: "Кол-во") { [weak self] _ in
            self?.annotateQuantity()
        }
        let form = UIAction(title: "Форма") { [weak self] _ in
            self?.annotateForm()
        }
        let signa = UIAction(title: "Сигна") { [weak self] _ in
            self?.annotateSigna()
        }

        let customInline = UIMenu(options: .displayInline, children: [dose, conc, qty, form, signa])
        return UIMenu(children: [customInline] + suggestedActions)
    }

    private func selectedText() -> String {
        guard selectedRange.length > 0 else { return "" }
        let ns = self.text as NSString
        let raw = ns.substring(with: selectedRange)
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @objc private func annotateDose() {
        let value = selectedText()
        guard !value.isEmpty else { return }
        tapHaptic()
        onAnnotate?(.dose, value)
    }

    @objc private func annotateConcentration() {
        let value = selectedText()
        guard !value.isEmpty else { return }
        tapHaptic()
        onAnnotate?(.concentration, value)
    }

    @objc private func annotateQuantity() {
        let value = selectedText()
        guard !value.isEmpty else { return }
        tapHaptic()
        onAnnotate?(.quantity, value)
    }

    @objc private func annotateForm() {
        let value = selectedText()
        guard !value.isEmpty else { return }
        tapHaptic()
        onAnnotate?(.form, value)
    }

    @objc private func annotateSigna() {
        let value = selectedText()
        guard !value.isEmpty else { return }
        tapHaptic()
        onAnnotate?(.signa, value)
    }
}
