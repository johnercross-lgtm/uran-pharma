import SwiftUI

struct DrugDetailView: View {
    @StateObject private var viewModel: DrugDetailViewModel
    private let repository: PharmaRepository
    private let onApplyAnnotation: ((AnnotationTarget, String) -> Void)?

    init(
        repository: PharmaRepository,
        uaVariantId: String,
        onApplyAnnotation: ((AnnotationTarget, String) -> Void)? = nil
    ) {
        self.repository = repository
        self.onApplyAnnotation = onApplyAnnotation
        _viewModel = StateObject(wrappedValue: DrugDetailViewModel(repository: repository, uaVariantId: uaVariantId))
    }

    private func mergedData(card: DrugCard) -> [String: String] {
        var out: [String: String] = [:]

        let sources: [[String: String?]?] = [card.finalRecord, card.uaRegistryVariant, card.enrichedVariant]
        for dict in sources {
            guard let dict else { continue }
            for (k, v) in dict {
                if out[k] != nil { continue }
                guard let v, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                out[k] = v
            }
        }
        return out
    }

    private func isHiddenKey(_ key: String) -> Bool {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if k.contains("source") { return true }
        if k.contains("provider") { return true }
        if k.contains("method") { return true }
        if k.contains("embedding") { return true }
        if k.contains("rank") { return true }
        if k.hasSuffix("_json") { return true }
        if k.hasSuffix("_tokens_json") { return true }
        if k.contains("tokens_json") { return true }
        if k.contains("see_also") { return true }
        if k.contains("at_codes") { return true }
        if k.contains("atc_codes") { return true }
        if k == "id" { return true }
        return false
    }

    private func normalizeSelection(_ selection: String, target: AnnotationTarget) -> String {
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }

        switch target {
        case .dose:
            let extracted = RecipeParsing.extractDose(from: trimmed)
            return extracted.isEmpty ? trimmed : extracted
        case .concentration:
            let extracted = RecipeParsing.extractConcentration(from: trimmed)
            return extracted.isEmpty ? trimmed : extracted
        case .quantity:
            let n = RecipeParsing.extractQuantityN(from: trimmed)
            if !n.isEmpty { return n }
            let digits = trimmed.filter { $0.isNumber }
            return digits.isEmpty ? trimmed : digits
        case .form:
            return trimmed
        case .signa:
            return trimmed
        }
    }

    private func handleAnnotate(card: DrugCard, target: AnnotationTarget, selection: String) {
        let normalized = normalizeSelection(selection, target: target)
        guard !normalized.isEmpty else { return }

        Task {
            do {
                switch target {
                case .dose:
                    try await repository.saveUserRecipeAnnotation(uaVariantId: card.uaVariantId, doseText: normalized)
                case .concentration:
                    try await repository.saveUserRecipeAnnotation(uaVariantId: card.uaVariantId, doseText: normalized)
                case .quantity:
                    try await repository.saveUserRecipeAnnotation(uaVariantId: card.uaVariantId, quantityN: normalized)
                case .form:
                    try await repository.saveUserRecipeAnnotation(uaVariantId: card.uaVariantId, formRaw: normalized)
                case .signa:
                    try await repository.saveUserRecipeAnnotation(uaVariantId: card.uaVariantId, signaText: normalized)
                }
            } catch {
            }
        }

        onApplyAnnotation?(target, normalized)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }

                if let card = viewModel.card {
                    DrugHeaderView(card: card)
                    let merged = mergedData(card: card)
                    KeyValueSection(
                        title: "Информация",
                        data: merged,
                        isHiddenKey: isHiddenKey,
                        onAnnotate: { target, selection in
                            handleAnnotate(card: card, target: target, selection: selection)
                        }
                    )
                }
            }
            .padding(16)
        }
        .navigationTitle("Карточка")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let card = viewModel.card {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Рецепт") {
                        RecipeBuilderView(card: card, repository: repository)
                    }
                }
            }
        }
        .task { await viewModel.load() }
    }
}

private struct DrugHeaderView: View {
    let card: DrugCard

    private var brandName: String {
        let enriched = (card.enrichedVariant?["brand_name"] ?? nil) ?? ""
        if !enriched.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return enriched }
        let finalUa = (card.finalRecord?["brand_name_ua"] ?? nil) ?? ""
        if !finalUa.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return finalUa }
        let final = (card.finalRecord?["brand_name"] ?? nil) ?? ""
        if !final.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return final }
        let registry = (card.uaRegistryVariant?["brand_name"] ?? nil) ?? ""
        if !registry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return registry }
        return card.uaVariantId
    }

    private var innName: String {
        let final3 = (card.finalRecord?["inn"] ?? nil) ?? ""
        if !final3.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return final3 }
        let final = (card.finalRecord?["inn_name"] ?? nil) ?? ""
        if !final.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return final }
        let registry = (card.uaRegistryVariant?["inn_name"] ?? nil) ?? ""
        return registry
    }

    private var manufacturer: String {
        let m1 = (card.finalRecord?["manufacturer1_ua"] ?? nil) ?? ""
        if !m1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return m1 }
        let app = (card.finalRecord?["applicant_ua"] ?? nil) ?? ""
        if !app.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return app }
        return (card.uaRegistryVariant?["manufacturer"] ?? nil) ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(brandName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)
                .textSelection(.enabled)

            if !innName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(innName)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if !manufacturer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(manufacturer)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .opacity(0.7)
                    .textSelection(.enabled)
            }

            Text(card.uaVariantId)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .opacity(0.7)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct KeyValueSection: View {
    let title: String
    let data: [String: String]?
    let isHiddenKey: (String) -> Bool
    let onAnnotate: (AnnotationTarget, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            if let data {
                let keys = data.keys
                    .filter { !isHiddenKey($0) }
                    .sorted()

                ForEach(keys, id: \.self) { key in
                    if let value = data[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        KeyValueRow(key: key, value: value, onAnnotate: onAnnotate)
                    }
                }
            } else {
                Text("Нет данных")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct KeyValueRow: View {
    let key: String
    let value: String
    let onAnnotate: (AnnotationTarget, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(key)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            AnnotatableTextView(text: value, font: .systemFont(ofSize: 15), foregroundColor: .label) { target, selection in
                onAnnotate(target, selection)
            }
        }
    }
}
