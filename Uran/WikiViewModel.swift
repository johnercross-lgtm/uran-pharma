import Foundation
import Combine

@MainActor
final class WikiViewModel: ObservableObject {
    @Published var items: [WikiRecipeItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let repository: PharmaRepository

    init(repository: PharmaRepository) {
        self.repository = repository
    }

    func load(searchQuery: String? = nil) async {
        let trimmed = (searchQuery ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await repository.listSharedRecipesFromCloud(searchQuery: trimmed.isEmpty ? nil : trimmed)
            items = loaded
        } catch {
            errorMessage = error.localizedDescription
            items = []
        }
        isLoading = false
    }
}
