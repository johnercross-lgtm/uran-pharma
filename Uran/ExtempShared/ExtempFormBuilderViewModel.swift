import Foundation
import Combine

@MainActor
final class ExtempFormBuilderViewModel: ObservableObject {
    @Published var query: String = ""
    @Published private(set) var results: [ExtempSubstance] = []
    @Published private(set) var units: [ExtempUnit] = []
    @Published private(set) var dosageForms: [ExtempDosageForm] = []
    @Published private(set) var mfRules: [ExtempMfRule] = []
    @Published private(set) var ingredientSubstanceById: [UUID: ExtempSubstance] = [:]
    @Published private(set) var storageRules: [ExtempStorageRule] = []
    @Published private(set) var storageRuleError: String?
    @Published private(set) var storagePropertyTitles: [String] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var incompatibilityMessage: String?
    @Published private(set) var incompatibilityIsBlocking: Bool = false
    @Published private(set) var searchDebugCaptionByKey: [String: String] = [:]

    private var repository: ExtempRepository?
    private var searchTask: Task<Void, Never>?
    private var storageLoadGeneration: Int = 0
    private var cancellables = Set<AnyCancellable>()
    private var parsedIndexLoadAttempted: Bool = false
    private var parsedSubstanceTokenIndex: Set<String> = []

    init() {
        $query
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .removeDuplicates()
            .handleEvents(receiveOutput: { [weak self] trimmed in
                guard let self else { return }
                if trimmed.isEmpty {
                    self.searchTask?.cancel()
                    self.results = []
                    self.searchDebugCaptionByKey = [:]
                    self.errorMessage = nil
                    self.isLoading = false
                }
            })
            .filter { !$0.isEmpty }
            .debounce(for: .milliseconds(350), scheduler: DispatchQueue.main)
            .sink { [weak self] trimmed in
                guard let self else { return }
                self.searchTask?.cancel()
                self.searchTask = Task { await self.performSearch(trimmed) }
            }
            .store(in: &cancellables)
    }

    var outputLookupContext: ExtempOutputLookupContext {
        ExtempOutputLookupContext(
            dosageForms: dosageForms,
            mfRules: mfRules,
            ingredientSubstanceById: ingredientSubstanceById
        )
    }

    func setDraftValue<Value>(
        in store: RxBuilderStore,
        _ keyPath: WritableKeyPath<ExtempRecipeDraft, Value>,
        to value: Value
    ) {
        store.update { $0[keyPath: keyPath] = value }
    }

    func replaceIngredient(in store: RxBuilderStore, id: UUID, with ingredient: IngredientDraft) {
        store.update { draft in
            if let index = draft.ingredients.firstIndex(where: { $0.id == id }) {
                draft.ingredients[index] = ingredient
            }
        }
    }

    func updateIngredient(
        in store: RxBuilderStore,
        id: UUID,
        mutate: (inout IngredientDraft) -> Void
    ) {
        store.update { draft in
            guard let index = draft.ingredients.firstIndex(where: { $0.id == id }) else { return }
            mutate(&draft.ingredients[index])
        }
    }

    func appendIngredient(in store: RxBuilderStore, _ ingredient: IngredientDraft) {
        store.update { $0.ingredients.append(ingredient) }
    }

    func moveIngredients(in store: RxBuilderStore, from: IndexSet, to: Int) {
        store.update { draft in
            let moving = from.map { draft.ingredients[$0] }
            for index in from.sorted(by: >) {
                draft.ingredients.remove(at: index)
            }
            let destination = min(to, draft.ingredients.count)
            draft.ingredients.insert(contentsOf: moving, at: destination)
        }
    }

    func removeIngredient(in store: RxBuilderStore, id: UUID) {
        store.update { draft in
            draft.ingredients.removeAll { $0.id == id }
        }
    }

    func clearIngredients(in store: RxBuilderStore) {
        store.update { $0.ingredients = [] }
    }

    func setFormMode(
        in store: RxBuilderStore,
        to newValue: FormMode,
        resolvedMode: FormMode
    ) {
        store.update { draft in
            draft.formMode = newValue
            applyFormModeSideEffects(draft: &draft, resolvedMode: resolvedMode)
        }
    }

    func syncAutoResolvedFormMode(in store: RxBuilderStore, resolvedMode: FormMode) {
        store.update { draft in
            applyFormModeSideEffects(draft: &draft, resolvedMode: resolvedMode)
        }
    }

    func setAdFlag(
        in store: RxBuilderStore,
        ingredientId id: UUID,
        isEnabled: Bool
    ) {
        store.update { draft in
            guard let idx = draft.ingredients.firstIndex(where: { $0.id == id }) else { return }

            if isEnabled {
                for i in draft.ingredients.indices where i != idx {
                    draft.ingredients[i].isAd = false
                }

                draft.ingredients[idx].isAd = true
                draft.ingredients[idx].isQS = false

                let unit = draft.ingredients[idx].unit
                if draft.targetUnit == nil || draft.targetUnit?.rawValue.isEmpty == true {
                    draft.targetUnit = unit
                }

                if draft.targetValue == nil, draft.ingredients[idx].amountValue > 0 {
                    draft.targetValue = draft.ingredients[idx].amountValue
                }

                if draft.ingredients[idx].amountValue > 0 {
                    draft.ingredients[idx].amountValue = 0
                }
            } else {
                draft.ingredients[idx].isAd = false
            }
        }
    }

    func updateSolutionPercent(
        in store: RxBuilderStore,
        ingredientId id: UUID,
        text: String,
        parsedValue: Double?
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        store.update { draft in
            guard let idx = draft.ingredients.firstIndex(where: { $0.id == id }) else { return }
            let hasInput = !trimmed.isEmpty

            if hasInput {
                for i in draft.ingredients.indices where i != idx {
                    if draft.ingredients[i].presentationKind == .solution {
                        draft.ingredients[i].presentationKind = .substance
                        if draft.ingredients[i].rpPrefix == .sol {
                            draft.ingredients[i].rpPrefix = .none
                        }
                    }
                }
                draft.ingredients[idx].presentationKind = .solution
                if draft.ingredients[idx].rpPrefix == .none {
                    draft.ingredients[idx].rpPrefix = .sol
                }
                let normalizedUnit = draft.ingredients[idx].unit.rawValue
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                if normalizedUnit.isEmpty || normalizedUnit == "g" || normalizedUnit == "г" {
                    draft.ingredients[idx].unit = UnitCode(rawValue: "ml")
                }
                draft.solPercentInputText = trimmed
                draft.solPercent = parsedValue

                if (draft.solVolumeMl ?? 0) <= 0 {
                    let unit = draft.ingredients[idx].unit.rawValue
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                    if unit == "ml", draft.ingredients[idx].amountValue > 0 {
                        draft.solVolumeMl = draft.ingredients[idx].amountValue
                    }
                }
                return
            }

            if draft.ingredients[idx].presentationKind == .solution {
                draft.solPercentInputText = ""
                draft.solPercent = nil
                let hasVolume = (draft.solVolumeMl ?? 0) > 0
                let unit = draft.ingredients[idx].unit.rawValue
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                let hasAmountVolume = unit == "ml" && draft.ingredients[idx].amountValue > 0
                if !hasVolume && !hasAmountVolume {
                    draft.ingredients[idx].presentationKind = .substance
                    if draft.ingredients[idx].rpPrefix == .sol {
                        draft.ingredients[idx].rpPrefix = .none
                    }
                }
            }
        }
    }

    func updateSolutionVolume(
        in store: RxBuilderStore,
        ingredientId id: UUID,
        text: String,
        parsedValue: Double?
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        store.update { draft in
            guard let idx = draft.ingredients.firstIndex(where: { $0.id == id }) else { return }
            let hasInput = !trimmed.isEmpty

            if hasInput {
                for i in draft.ingredients.indices where i != idx {
                    if draft.ingredients[i].presentationKind == .solution {
                        draft.ingredients[i].presentationKind = .substance
                        if draft.ingredients[i].rpPrefix == .sol {
                            draft.ingredients[i].rpPrefix = .none
                        }
                    }
                }
                draft.ingredients[idx].presentationKind = .solution
                if draft.ingredients[idx].rpPrefix == .none {
                    draft.ingredients[idx].rpPrefix = .sol
                }
                let normalizedUnit = draft.ingredients[idx].unit.rawValue
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                if normalizedUnit.isEmpty || normalizedUnit == "g" || normalizedUnit == "г" {
                    draft.ingredients[idx].unit = UnitCode(rawValue: "ml")
                }
                draft.solVolumeMl = parsedValue
                if let parsedValue, parsedValue > 0 {
                    draft.ingredients[idx].amountValue = parsedValue
                }
                return
            }

            if draft.ingredients[idx].presentationKind == .solution {
                draft.solVolumeMl = nil
                let hasPercent = (draft.solPercent ?? 0) > 0
                    || !draft.solPercentInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let unit = draft.ingredients[idx].unit.rawValue
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                let hasAmountVolume = unit == "ml" && draft.ingredients[idx].amountValue > 0
                if !hasPercent && !hasAmountVolume {
                    draft.ingredients[idx].presentationKind = .substance
                    if draft.ingredients[idx].rpPrefix == .sol {
                        draft.ingredients[idx].rpPrefix = .none
                    }
                }
            }
        }
    }

    func appendSignaSuggestion(in store: RxBuilderStore, suggestion: String) {
        let current = store.draft.signa.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty {
            store.update { $0.signa = suggestion }
            return
        }
        store.update { $0.signa = current + " " + suggestion }
    }

    func loadInitialData() async {
        do {
            try PharmaDB.shared.open()
        } catch {
            errorMessage = error.localizedDescription
        }

        await loadRepositoryIfNeeded()
    }

    func syncDraftStateOnAppear(normalizedIngredients: [ExtempIngredientDraft]) {
        reloadStorage(for: normalizedIngredients)
    }

    func reloadStorage(for normalizedIngredients: [ExtempIngredientDraft]) {
        storageLoadGeneration += 1
        let generation = storageLoadGeneration
        Task { await loadStorageRules(for: normalizedIngredients, expectedGeneration: generation) }
    }

    func prepareIngredientDraft(
        for substance: ExtempSubstance,
        currentDrafts: [IngredientDraft],
        normalizedDraft: ExtempRecipeDraft,
        existingDraft: ExtempRecipeDraft
    ) async -> IngredientDraft? {
        incompatibilityMessage = nil
        incompatibilityIsBlocking = false

        clearSearch()

        let currentIngredientsSnapshot = ExtempIngredientService.makeCurrentIngredientsSnapshot(
            drafts: currentDrafts,
            substancesById: ingredientSubstanceById,
            units: units,
            solutionPercent: normalizedDraft.solPercent,
            solutionVolumeMl: normalizedDraft.solVolumeMl
        )

        let compatibility = await ExtempIngredientService.checkCompatibility(
            new: substance,
            existing: currentIngredientsSnapshot,
            repository: repository
        )
        incompatibilityMessage = compatibility.message
        incompatibilityIsBlocking = compatibility.isBlocking

        if compatibility.isBlocking {
            return nil
        }

        let draftId = UUID()
        ingredientSubstanceById[draftId] = substance
        return ExtempIngredientService.makeIngredientDraft(
            id: draftId,
            substance: substance,
            units: units,
            existingDraft: existingDraft
        )
    }

    func removeIngredientReference(_ id: UUID) {
        ingredientSubstanceById.removeValue(forKey: id)
    }

    func clearDraftScopedState() {
        ingredientSubstanceById = [:]
        incompatibilityMessage = nil
        incompatibilityIsBlocking = false
        clearSearch()
        resetStorageRulesState()
    }

    func clearSearch() {
        searchTask?.cancel()
        searchTask = nil
        if !query.isEmpty {
            query = ""
        }
        results = []
        searchDebugCaptionByKey = [:]
        isLoading = false
        errorMessage = nil
    }

    private func performSearch(_ text: String) async {
        if repository == nil {
            await loadRepositoryIfNeeded()
        }
        guard let repository else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let found = try await ExtempLookupService.searchSubstances(
                query: text,
                repository: repository,
                limit: 30
            )
            guard !Task.isCancelled else { return }
            searchDebugCaptionByKey = buildSearchDebugCaptions(for: found)
            results = found
            logSearchResultSources(query: text, results: found)
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            searchDebugCaptionByKey = [:]
            errorMessage = error.localizedDescription
        }
    }

    private func loadRepositoryIfNeeded() async {
        if repository != nil { return }

        do {
            let bootstrap = try await ExtempLookupService.bootstrapRepository()
            repository = bootstrap.repository
            units = bootstrap.units
            dosageForms = bootstrap.dosageForms
            mfRules = bootstrap.mfRules

            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedQuery.isEmpty {
                searchTask?.cancel()
                searchTask = Task { await performSearch(trimmedQuery) }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadStorageRules(
        for normalizedIngredients: [ExtempIngredientDraft],
        expectedGeneration: Int
    ) async {
        guard let repository else {
            resetStorageIfGenerationMatches(expectedGeneration)
            return
        }

        let substanceIds = normalizedIngredients.map { $0.substance.id }
        guard !substanceIds.isEmpty else {
            resetStorageIfGenerationMatches(expectedGeneration)
            return
        }

        do {
            let lookup = try await ExtempLookupService.loadStorageLookup(
                substanceIds: substanceIds,
                repository: repository
            )
            guard expectedGeneration == storageLoadGeneration else { return }
            storageRules = lookup.rules
            storagePropertyTitles = lookup.propertyTitles
            storageRuleError = nil
        } catch {
            guard expectedGeneration == storageLoadGeneration else { return }
            storageRules = []
            storagePropertyTitles = []
            storageRuleError = error.localizedDescription
        }
    }

    private func resetStorageIfGenerationMatches(_ expectedGeneration: Int) {
        guard expectedGeneration == storageLoadGeneration else { return }
        resetStorageRulesState()
    }

    private func resetStorageRulesState() {
        storageRules = []
        storageRuleError = nil
        storagePropertyTitles = []
    }

    private func applyFormModeSideEffects(
        draft: inout ExtempRecipeDraft,
        resolvedMode: FormMode
    ) {
        if resolvedMode != .drops {
            draft.isOphthalmicDrops = false
        }
        if resolvedMode != .solutions {
            draft.liquidTechnologyMode = .waterSolution
        }
        if resolvedMode != .solutions && resolvedMode != .drops {
            draft.useVmsColloidsBlock = false
            draft.useStandardSolutionsBlock = false
            draft.useBuretteSystem = false
        }
    }

    func debugSearchCaption(for item: ExtempSubstance) -> String? {
        searchDebugCaptionByKey[searchIdentityKey(for: item)]
    }

    private func buildSearchDebugCaptions(for results: [ExtempSubstance]) -> [String: String] {
        guard !results.isEmpty else { return [:] }
        let parsedIndex = parsedSubstanceIndex()
        var out: [String: String] = [:]
        out.reserveCapacity(results.count)

        for item in results {
            let source = searchSourceLabel(for: item)
            let jsonLabel = isPresentInParsedJSON(item: item, parsedIndex: parsedIndex) ? "yes" : "no"
            out[searchIdentityKey(for: item)] = "\(source) | JSON \(jsonLabel)"
        }

        return out
    }

    private func searchIdentityKey(for item: ExtempSubstance) -> String {
        let id = String(item.id)
        let inn = SolutionReferenceStore.normalizeToken(item.innKey)
        let nom = SolutionReferenceStore.normalizeToken(item.nameLatNom)
        return "\(id)|\(inn)|\(nom)"
    }

    private func logSearchResultSources(query: String, results: [ExtempSubstance]) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        if results.isEmpty {
            print("[ExtempSearchSource] query=\"\(trimmedQuery)\" results=0")
            return
        }

        let parsedIndex = parsedSubstanceIndex()
        for item in results {
            let source = searchSourceLabel(for: item)
            let parsedPresence = isPresentInParsedJSON(item: item, parsedIndex: parsedIndex) ? "yes" : "no"
            let label = item.nameLatNom.trimmingCharacters(in: .whitespacesAndNewlines)
            let inn = item.innKey.trimmingCharacters(in: .whitespacesAndNewlines)
            print("[ExtempSearchSource] query=\"\(trimmedQuery)\" source=\(source) json_parsed=\(parsedPresence) name=\"\(label)\" inn=\"\(inn)\"")
        }
    }

    private func searchSourceLabel(for item: ExtempSubstance) -> String {
        let refType = item.refType.trimmingCharacters(in: .whitespacesAndNewlines)
        if !refType.isEmpty {
            return "DB+CSV"
        }
        return "DB"
    }

    private func isPresentInParsedJSON(item: ExtempSubstance, parsedIndex: Set<String>?) -> Bool {
        guard let parsedIndex else { return false }
        let inn = SolutionReferenceStore.normalizeToken(item.innKey)
        let nom = SolutionReferenceStore.normalizeToken(item.nameLatNom)
        let gen = SolutionReferenceStore.normalizeToken(item.nameLatGen)

        if (!inn.isEmpty && parsedIndex.contains(inn))
            || (!nom.isEmpty && parsedIndex.contains(nom))
            || (!gen.isEmpty && parsedIndex.contains(gen)) {
            return true
        }
        return false
    }

    private func parsedSubstanceIndex() -> Set<String>? {
        if !parsedIndexLoadAttempted {
            parsedIndexLoadAttempted = true
            parsedSubstanceTokenIndex = loadParsedSubstanceIndex()
        }
        return parsedSubstanceTokenIndex.isEmpty ? nil : parsedSubstanceTokenIndex
    }

    private func loadParsedSubstanceIndex() -> Set<String> {
        struct Root: Decodable {
            struct Item: Decodable {
                struct ItemName: Decodable {
                    let latNom: String?
                    let latGen: String?
                }

                let substanceKey: String?
                let name: ItemName?
            }

            let items: [Item]
        }

        guard let url = Bundle.main.url(forResource: "substances_master", withExtension: "json") else {
            print("[ExtempSearchSource] JSON parsed index unavailable: substances_master.json not found in bundle")
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            let root = try JSONDecoder().decode(Root.self, from: data)
            var tokens: Set<String> = []
            tokens.reserveCapacity(root.items.count * 3)

            for item in root.items {
                if let substanceKey = item.substanceKey {
                    let normalized = SolutionReferenceStore.normalizeToken(substanceKey)
                    if !normalized.isEmpty {
                        tokens.insert(normalized)
                    }
                }
                if let latNom = item.name?.latNom {
                    let normalized = SolutionReferenceStore.normalizeToken(latNom)
                    if !normalized.isEmpty {
                        tokens.insert(normalized)
                    }
                }
                if let latGen = item.name?.latGen {
                    let normalized = SolutionReferenceStore.normalizeToken(latGen)
                    if !normalized.isEmpty {
                        tokens.insert(normalized)
                    }
                }
            }

            print("[ExtempSearchSource] JSON parsed index loaded: \(tokens.count) tokens")
            return tokens
        } catch {
            print("[ExtempSearchSource] JSON parsed index load failed: \(error.localizedDescription)")
            return []
        }
    }
}
