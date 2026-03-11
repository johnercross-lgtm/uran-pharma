import Foundation

private struct BreakerCase {
    let id: String
    let input: [String: Any]
}

private struct ExistingSnapshotRoot: Decodable {
    let version: String
    let description: String
    let cases: [ExistingSnapshotCase]
}

private struct ExistingSnapshotCase: Decodable {
    let id: String
}

private struct SnapshotRoot: Encodable {
    let version: String
    let description: String
    let cases: [SnapshotCase]
}

private struct SnapshotCase: Encodable {
    let id: String
    let branch: String?
    let route: String?
    let confidence: String
    let state: String
    let warnings: [String]
    let technologyFlags: [String]
    let technologySteps: [String]
    let packaging: [String]
    let labels: [String]
    let storage: [String]
    let waterToAddMl: Double?
    let sumSolidsG: Double
    let kvoApplied: Bool
    let requiredMassesG: [String: Double]
    let concentrateVolumesMl: [String: Double]
    let ppkSectionKeys: [String]
    let ppkSectionLineCounts: [String: Int]
    let ppkForbiddenHits: [String]
}

private func loadBreakerCases(path: String) throws -> [BreakerCase] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let rawCases = root["cases"] as? [[String: Any]] else {
        throw NSError(domain: "SnapshotUpdater", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid breaker JSON schema"])
    }

    return rawCases.compactMap { row in
        guard let id = row["id"] as? String,
              let input = row["input"] as? [String: Any] else {
            return nil
        }
        return BreakerCase(id: id, input: input)
    }
}

private func loadExistingSnapshotRoot(path: String) throws -> ExistingSnapshotRoot {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return try JSONDecoder().decode(ExistingSnapshotRoot.self, from: data)
}

private func makeRequest(from input: [String: Any]) -> SolutionEngineRequest {
    var request = SolutionEngineRequest()
    request.recipeText = input["recipeText"] as? String
    request.route = input["route"] as? String
    request.forceReferenceConcentrate = input["forceReferenceConcentrate"] as? [String: String]

    if let structuredRaw = input["structuredInput"] as? [String: Any] {
        var structuredIngredients: [StructuredIngredientInput] = []
        if let ingredients = structuredRaw["ingredients"] as? [[String: Any]] {
            structuredIngredients = ingredients.map { row in
                StructuredIngredientInput(
                    name: (row["name"] as? String) ?? "",
                    presentationKind: row["presentationKind"] as? String,
                    massG: row["massG"] as? Double,
                    volumeMl: row["volumeMl"] as? Double,
                    concentrationPercent: row["concentrationPercent"] as? Double,
                    ratio: row["ratio"] as? String,
                    isAd: row["isAd"] as? Bool,
                    adTargetMl: row["adTargetMl"] as? Double
                )
            }
        }

        request.structuredInput = StructuredSolutionInput(
            dosageForm: structuredRaw["dosageForm"] as? String,
            route: structuredRaw["route"] as? String,
            targetVolumeMl: structuredRaw["targetVolumeMl"] as? Double,
            signa: structuredRaw["signa"] as? String,
            ingredients: structuredIngredients
        )
    }

    return request
}

@main
struct SnapshotUpdaterMain {
    static func main() throws {
        let defaultBase = "/Users/eugentamara/URAN/Uran/URAN_Pharma_Engine"
        let basePath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : defaultBase
        let breakerPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "\(basePath)/tests/RECIPE_BREAKER_TEST_SET.json"
        let snapshotPath = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "\(basePath)/tests/RECIPE_BREAKER_STRICT_SNAPSHOTS.json"

        let existingRoot = try loadExistingSnapshotRoot(path: snapshotPath)
        let snapshotIds = existingRoot.cases.map(\.id)
        let breakerCases = try loadBreakerCases(path: breakerPath)
        let caseMap = Dictionary(uniqueKeysWithValues: breakerCases.map { ($0.id, $0) })

        let references = try SolutionReferenceStore(baseURL: URL(fileURLWithPath: basePath))
        let engine = try SolutionEngine(references: references)

        let forbiddenPhrases = [
            "Після виготовлення концентрат підлягає",
            "титруванням або рефрактометрією"
        ]

        var outputCases: [SnapshotCase] = []
        for id in snapshotIds {
            guard let entry = caseMap[id] else {
                throw NSError(
                    domain: "SnapshotUpdater",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Snapshot case \(id) is missing in breaker set"]
                )
            }

            let result = engine.process(request: makeRequest(from: entry.input))
            let warnings = result.warnings
                .map { "\($0.code)|\(($0.state?.rawValue) ?? "NONE")|\($0.severity.rawValue)" }
                .sorted()

            let sectionKeys = result.ppkDocument.sections.keys.sorted()
            let sectionLineCounts = result.ppkDocument.sections.mapValues { $0.count }
            let forbiddenHits = forbiddenPhrases.filter { result.ppkDocument.renderedText.contains($0) }

            outputCases.append(
                SnapshotCase(
                    id: id,
                    branch: result.solutionBranch,
                    route: result.route,
                    confidence: result.confidence.rawValue,
                    state: result.state.rawValue,
                    warnings: warnings,
                    technologyFlags: result.technologyFlags,
                    technologySteps: result.technologySteps,
                    packaging: result.packaging.packaging,
                    labels: result.packaging.labels,
                    storage: result.packaging.storage,
                    waterToAddMl: result.calculationTrace.waterToAddMl,
                    sumSolidsG: result.calculationTrace.sumSolidsG,
                    kvoApplied: result.calculationTrace.kvoApplied,
                    requiredMassesG: result.calculationTrace.requiredMassesG,
                    concentrateVolumesMl: result.calculationTrace.concentrateVolumesMl,
                    ppkSectionKeys: sectionKeys,
                    ppkSectionLineCounts: sectionLineCounts,
                    ppkForbiddenHits: forbiddenHits
                )
            )
        }

        let root = SnapshotRoot(
            version: existingRoot.version,
            description: existingRoot.description,
            cases: outputCases
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(root)
        try data.write(to: URL(fileURLWithPath: snapshotPath), options: .atomic)

        print("strict_snapshot_updated_cases=\(outputCases.count)")
        print("strict_snapshot_path=\(snapshotPath)")
    }
}
