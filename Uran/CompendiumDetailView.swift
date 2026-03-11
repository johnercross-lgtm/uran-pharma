import SwiftUI
import Combine

@MainActor
final class CompendiumDetailViewModel: ObservableObject {
    @Published private(set) var item: CompendiumItemDetails?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading: Bool = false

    private let id: String

    init(id: String) {
        self.id = id
    }

    func load() async {
        if isLoading { return }
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            errorMessage = "Пустой id для карточки"
            item = nil
            return
        }
        isLoading = true
        do {
            let targetId = trimmed
            let loaded = try await Task.detached(priority: .userInitiated) {
                try await CompendiumSQLiteService.shared.fetchItem(id: targetId)
            }.value
            await MainActor.run {
                item = loaded
                errorMessage = loaded == nil ? "Ничего не найдено по id=\(targetId)" : nil
            }
        } catch {
            print("Compendium fetch error:", error)
            await MainActor.run {
                item = nil
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }
}

struct CompendiumDetailView: View {
    @StateObject private var viewModel: CompendiumDetailViewModel

    init(id: String) {
        _viewModel = StateObject(wrappedValue: CompendiumDetailViewModel(id: id))
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

                if let item = viewModel.item {
                    header(item)
                    section("Состав", item.composition)
                    section("Фармакологические свойства", item.pharmacologicalProperties)
                    section("Показания", item.indications)
                    section("Способ применения", item.dosageAdministration)
                    section("Противопоказания", item.contraindications)
                    section("Побочные эффекты", item.sideEffects)
                    section("Взаимодействия", item.interactions)
                    section("Передозировка", item.overdose)
                    section("Условия хранения", item.storageConditions)
                }
            }
            .padding(16)
        }
        .navigationTitle("Карточка")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private func header(_ item: CompendiumItemDetails) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text((item.brandName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? item.id : (item.brandName ?? ""))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)
                .textSelection(.enabled)

            let inn = (item.inn ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !inn.isEmpty {
                Text(inn)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            let atc = (item.atcCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !atc.isEmpty {
                Text(atc)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .opacity(0.7)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ value: String?) -> some View {
        let text = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}
