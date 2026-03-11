import Foundation

struct ExtempRepositoryBootstrap {
    let repository: ExtempRepository
    let units: [ExtempUnit]
    let dosageForms: [ExtempDosageForm]
    let mfRules: [ExtempMfRule]
}

struct ExtempStorageLookupResult {
    let rules: [ExtempStorageRule]
    let propertyTitles: [String]
}

enum ExtempLookupService {
    static func bootstrapRepository() async throws -> ExtempRepositoryBootstrap {
        let repository = try ExtempRepository()

        async let unitsTask = repository.listUnits()
        async let formsTask = repository.listDosageForms()
        async let rulesTask = repository.listMfRules()

        return ExtempRepositoryBootstrap(
            repository: repository,
            units: try await unitsTask,
            dosageForms: try await formsTask,
            mfRules: try await rulesTask
        )
    }

    static func searchSubstances(
        query: String,
        repository: ExtempRepository,
        limit: Int = 30
    ) async throws -> [ExtempSubstance] {
        try await repository.searchSubstances(query: query, limit: limit)
    }

    static func loadStorageLookup(
        substanceIds: [Int],
        repository: ExtempRepository
    ) async throws -> ExtempStorageLookupResult {
        guard !substanceIds.isEmpty else {
            return ExtempStorageLookupResult(rules: [], propertyTitles: [])
        }

        var allRules: [ExtempStorageRule] = []
        for substanceId in substanceIds {
            let rules = try await repository.loadStorageRules(substanceId: substanceId)
            allRules.append(contentsOf: rules)
        }

        let propertyTitles = try await repository.distinctStoragePropertyTitles(substanceIds: substanceIds)
        return ExtempStorageLookupResult(rules: allRules, propertyTitles: propertyTitles)
    }
}
