import Foundation
import Combine

@MainActor
final class DrugSearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published private(set) var results: [CompendiumHit] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading: Bool = false

    private var cancellables = Set<AnyCancellable>()

    init() {
        $query
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] q in
                guard let self else { return }
                Task { await self.search(q) }
            }
            .store(in: &cancellables)
    }

    func search(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            results = []
            errorMessage = nil
            isLoading = false
            return
        }

        isLoading = true
        do {
            let found = try await Task.detached(priority: .userInitiated) {
                try await CompendiumSQLiteService.shared.searchFTS(trimmed, limit: 50)
            }.value
            await MainActor.run {
                results = found
                errorMessage = nil
            }
        } catch {
            print("Compendium search error:", error)
            await MainActor.run {
                results = []
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }
}
