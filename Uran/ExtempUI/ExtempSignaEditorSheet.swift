import SwiftUI

struct ExtempSignaEditorSheet: View {
    let signaText: Binding<String>
    let suggestions: [String]
    let onAppendSuggestion: (String) -> Void
    let onClose: () -> Void
    let onHideKeyboard: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Инструкция для пациента откроется отдельно, чтобы её было удобно набрать и перечитать целиком.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    TextEditor(text: signaText)
                        .frame(minHeight: 220)
                        .padding(10)
                        .background(SolarizedTheme.secondarySurfaceColor)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(SolarizedTheme.borderColor, lineWidth: 1)
                        )

                    Text("Быстрые фразы")
                        .font(.system(size: 14, weight: .semibold))

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(suggestion) {
                                Haptics.tap()
                                onAppendSuggestion(suggestion)
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .background(SolarizedTheme.secondarySurfaceColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(SolarizedTheme.borderColor, lineWidth: 1)
                            )
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(SolarizedTheme.backgroundColor.ignoresSafeArea())
            .navigationTitle("Signa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") {
                        Haptics.tap()
                        onClose()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Скрыть") {
                        onHideKeyboard()
                    }
                }
            }
        }
    }
}
