import SwiftUI

struct WikiRecipeDetailView: View {
    let repository: PharmaRepository
    let item: WikiRecipeItem

    @EnvironmentObject private var session: UserSessionStore

    @State private var isApplying: Bool = false
    @State private var applyError: String?
    @State private var appliedOK: Bool = false

    var body: some View {
        Form {
            Section("Препарат") {
                Text(item.title.isEmpty ? item.uaVariantId : item.title)
                    .font(.system(size: 16, weight: .semibold))
                Text(item.uaVariantId)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section("Рецепт") {
                if !item.formRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    LabeledContent("Форма", value: item.formRaw)
                }
                if !item.doseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    LabeledContent("Доза", value: item.doseText)
                }
                if !item.quantityN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    LabeledContent("Количество", value: item.quantityN)
                }
                if !item.signaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Signa")
                            .font(.system(size: 13, weight: .semibold))
                        Text(item.signaText)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            if let applyError, !applyError.isEmpty {
                Section {
                    Text(applyError)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button(appliedOK ? "Применено" : (isApplying ? "Применение…" : "Применить в конструкторе")) {
                    if isApplying || appliedOK { return }
                    Haptics.tap()
                    isApplying = true
                    applyError = nil
                    appliedOK = false

                    Task {
                        do {
                            try await repository.saveUserRecipeAnnotation(
                                uaVariantId: item.uaVariantId,
                                doseText: item.doseText,
                                quantityN: item.quantityN,
                                formRaw: item.formRaw,
                                signaText: item.signaText
                            )
                            await MainActor.run {
                                appliedOK = true
                                isApplying = false
                            }
                        } catch {
                            await MainActor.run {
                                applyError = error.localizedDescription
                                isApplying = false
                            }
                        }
                    }
                }
                .disabled(isApplying)
            }
        }
        .navigationTitle("Рецепт")
        .navigationBarTitleDisplayMode(.inline)
    }
}
