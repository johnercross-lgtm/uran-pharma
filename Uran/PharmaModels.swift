import Foundation

struct DrugSearchResult: Identifiable, Hashable {
    let uaVariantId: String
    let brandName: String
    let innName: String
    let composition: String
    let manufacturer: String
    let source: String
    let formDoseLine: String
    let rxStatus: String
    let isAnnotated: Bool
    let registry: String
    let dosageFormText: String
    let dispensingConditions: String

    var id: String { uaVariantId }

    var title: String {
        let trimmed = innName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? uaVariantId : trimmed
    }

    var subtitle: String {
        let trimmed = brandName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : trimmed
    }

    var completenessScore: Int {
        var score = 0
        if !brandName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 2 }
        if !innName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 4 }
        if !composition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 2 }
        if !formDoseLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 10 }
        if !registry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 1 }
        return score
    }

    var sourcePriority: Int {
        switch source.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "COMPENDIUM": return 0
        case "EN_OFFICIAL": return 1
        case "AI": return 2
        default: return 3
        }
    }
}

struct DrugCard: Hashable {
    let uaVariantId: String
    let finalRecord: [String: String?]?
    let uaRegistryVariant: [String: String?]?
    let enrichedVariant: [String: String?]?
}
