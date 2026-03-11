import SwiftUI
import Combine
import UIKit

struct QuickInputToken: Identifiable, Hashable {
    let label: String
    let insertion: String

    var id: String { "\(label)|\(insertion)" }
}

final class KeyboardObserver: ObservableObject {
    @Published private(set) var height: CGFloat = 0

    private var cancellables: Set<AnyCancellable> = []

    init() {
        let center = NotificationCenter.default

        center.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .merge(with: center.publisher(for: UIResponder.keyboardWillHideNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handle(notification)
            }
            .store(in: &cancellables)
    }

    private func handle(_ notification: Notification) {
        let endFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
        let screenHeight = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.bounds.height }
            .max() ?? 0
        let overlap = max(0, screenHeight - endFrame.minY)

        withAnimation(.easeInOut(duration: 0.22)) {
            height = overlap
        }
    }
}

struct QuickInputAccessoryBar: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let keyboardType: UIKeyboardType
    let tokens: [QuickInputToken]
    let onDone: () -> Void

    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Быстрый ввод")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                }

                Spacer()

                Button("Очистить") {
                    Haptics.tap()
                    text = ""
                    focusInput()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

                Button("Готово") {
                    Haptics.tap()
                    onDone()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SolarizedTheme.accentColor)
            }

            HStack(spacing: 8) {
                TextField(placeholder, text: $text)
                    .focused($isInputFocused)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(SolarizedTheme.surfaceColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(SolarizedTheme.borderColor, lineWidth: 1)
                    )

                Button {
                    guard !text.isEmpty else { return }
                    Haptics.tap()
                    text.removeLast()
                    focusInput()
                } label: {
                    Image(systemName: "delete.left")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 42, height: 42)
                        .background(SolarizedTheme.surfaceColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(SolarizedTheme.borderColor, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            if !tokens.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tokens) { token in
                            Button(token.label) {
                                Haptics.tap()
                                appendToken(token.insertion)
                                focusInput()
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(SolarizedTheme.surfaceColor)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(SolarizedTheme.borderColor, lineWidth: 1)
                            )
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
        .padding(12)
        .uranCard(
            background: SolarizedTheme.secondarySurfaceColor,
            border: SolarizedTheme.borderColor,
            cornerRadius: 18,
            shadowColor: Color.black.opacity(0.16),
            shadowRadius: 14,
            shadowY: 8,
            padding: nil
        )
        .onAppear {
            focusInput()
        }
        .onChange(of: title) { _, _ in
            focusInput()
        }
    }

    private func appendToken(_ insertion: String) {
        guard !insertion.isEmpty else { return }

        if text.isEmpty {
            text = insertion.trimmingCharacters(in: .whitespaces)
            return
        }

        if shouldAppendWithoutSpace(insertion) {
            text += insertion
            return
        }

        if text.hasSuffix(" ") {
            text += insertion
            return
        }

        text += " \(insertion)"
    }

    private func shouldAppendWithoutSpace(_ insertion: String) -> Bool {
        insertion.hasPrefix(" ")
            || insertion.hasPrefix(",")
            || insertion.hasPrefix(".")
            || insertion.hasPrefix("/")
            || insertion == "%"
            || text.hasSuffix("/")
            || text.hasSuffix("-")
            || text.hasSuffix("(")
    }

    private func focusInput() {
        DispatchQueue.main.async {
            isInputFocused = true
        }
    }
}
