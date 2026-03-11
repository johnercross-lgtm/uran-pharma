import Foundation
import Combine

@MainActor
final class DrugDetailViewModel: ObservableObject {
    @Published private(set) var card: DrugCard?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading: Bool = false

    private let repository: PharmaRepository
    private let uaVariantId: String

    init(repository: PharmaRepository, uaVariantId: String) {
        self.repository = repository
        self.uaVariantId = uaVariantId
    }

    func load() async {
        if isLoading { return }
        isLoading = true
        do {
            card = try await repository.loadCard(uaVariantId: uaVariantId)
            errorMessage = nil
        } catch {
            card = nil
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
