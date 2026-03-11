import Foundation

private struct BreakerCase {
    let id: String
    let input: [String: Any]
}

private struct SnapshotRoot: Decodable {
    let version: String
    let description: String
    let cases: [SnapshotCase]
}

private struct SnapshotCase: Decodable {
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
        throw NSError(domain: "SnapshotRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid breaker JSON schema"])
    }

    return rawCases.compactMap { row in
        guard let id = row["id"] as? String,
              let input = row["input"] as? [String: Any] else {
            return nil
        }
        return BreakerCase(id: id, input: input)
    }
}

private func loadSnapshots(path: String) throws -> [String: SnapshotCase] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let root = try JSONDecoder().decode(SnapshotRoot.self, from: data)
    var byId: [String: SnapshotCase] = [:]
    for entry in root.cases {
        byId[entry.id] = entry
    }
    return byId
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

private func approxEqual(_ lhs: Double?, _ rhs: Double?, eps: Double = 0.001) -> Bool {
    guard let lhs, let rhs else { return lhs == nil && rhs == nil }
    return abs(lhs - rhs) <= eps
}

private func compareDictionaries(_ lhs: [String: Double], _ rhs: [String: Double], key: String) -> [String] {
    var issues: [String] = []
    let keys = Set(lhs.keys).union(rhs.keys)
    for itemKey in keys.sorted() {
        if !approxEqual(lhs[itemKey], rhs[itemKey]) {
            issues.append("\(key)[\(itemKey)] expected=\(rhs[itemKey] ?? -999) actual=\(lhs[itemKey] ?? -999)")
        }
    }
    return issues
}

private func compare(snapshot: SnapshotCase, result: SolutionEngineResult) -> [String] {
    var issues: [String] = []

    if snapshot.branch != result.solutionBranch {
        issues.append("branch expected=\(snapshot.branch ?? "nil") actual=\(result.solutionBranch ?? "nil")")
    }
    if snapshot.route != result.route {
        issues.append("route expected=\(snapshot.route ?? "nil") actual=\(result.route ?? "nil")")
    }
    if snapshot.confidence != result.confidence.rawValue {
        issues.append("confidence expected=\(snapshot.confidence) actual=\(result.confidence.rawValue)")
    }
    if snapshot.state != result.state.rawValue {
        issues.append("state expected=\(snapshot.state) actual=\(result.state.rawValue)")
    }

    let warnings = result.warnings
        .map { "\($0.code)|\(($0.state?.rawValue) ?? "NONE")|\($0.severity.rawValue)" }
        .sorted()
    if warnings != snapshot.warnings {
        issues.append("warnings expected=\(snapshot.warnings) actual=\(warnings)")
    }

    if result.technologyFlags != snapshot.technologyFlags {
        issues.append("technologyFlags expected=\(snapshot.technologyFlags) actual=\(result.technologyFlags)")
    }
    if result.technologySteps != snapshot.technologySteps {
        issues.append("technologySteps expected=\(snapshot.technologySteps) actual=\(result.technologySteps)")
    }

    if result.packaging.packaging != snapshot.packaging {
        issues.append("packaging expected=\(snapshot.packaging) actual=\(result.packaging.packaging)")
    }
    if result.packaging.labels != snapshot.labels {
        issues.append("labels expected=\(snapshot.labels) actual=\(result.packaging.labels)")
    }
    if result.packaging.storage != snapshot.storage {
        issues.append("storage expected=\(snapshot.storage) actual=\(result.packaging.storage)")
    }

    if !approxEqual(result.calculationTrace.waterToAddMl, snapshot.waterToAddMl) {
        issues.append("waterToAddMl expected=\(snapshot.waterToAddMl ?? -999) actual=\(result.calculationTrace.waterToAddMl ?? -999)")
    }
    if !approxEqual(result.calculationTrace.sumSolidsG, snapshot.sumSolidsG) {
        issues.append("sumSolidsG expected=\(snapshot.sumSolidsG) actual=\(result.calculationTrace.sumSolidsG)")
    }
    if result.calculationTrace.kvoApplied != snapshot.kvoApplied {
        issues.append("kvoApplied expected=\(snapshot.kvoApplied) actual=\(result.calculationTrace.kvoApplied)")
    }

    issues.append(contentsOf: compareDictionaries(result.calculationTrace.requiredMassesG, snapshot.requiredMassesG, key: "requiredMassesG"))
    issues.append(contentsOf: compareDictionaries(result.calculationTrace.concentrateVolumesMl, snapshot.concentrateVolumesMl, key: "concentrateVolumesMl"))

    let sectionKeys = result.ppkDocument.sections.keys.sorted()
    if sectionKeys != snapshot.ppkSectionKeys {
        issues.append("ppkSectionKeys expected=\(snapshot.ppkSectionKeys) actual=\(sectionKeys)")
    }

    let sectionLineCounts = result.ppkDocument.sections.mapValues { $0.count }
    if sectionLineCounts != snapshot.ppkSectionLineCounts {
        issues.append("ppkSectionLineCounts expected=\(snapshot.ppkSectionLineCounts) actual=\(sectionLineCounts)")
    }

    let forbiddenPhrases = [
        "Після виготовлення концентрат підлягає",
        "титруванням або рефрактометрією"
    ]
    let forbiddenHits = forbiddenPhrases.filter { result.ppkDocument.renderedText.contains($0) }
    if forbiddenHits != snapshot.ppkForbiddenHits {
        issues.append("ppkForbiddenHits expected=\(snapshot.ppkForbiddenHits) actual=\(forbiddenHits)")
    }

    return issues
}

@main
struct SnapshotRunnerMain {
    static func main() throws {
        let defaultBase = "/Users/eugentamara/URAN/Uran/URAN_Pharma_Engine"
        let basePath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : defaultBase
        let breakerPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "\(basePath)/tests/RECIPE_BREAKER_TEST_SET.json"
        let snapshotPath = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "\(basePath)/tests/RECIPE_BREAKER_STRICT_SNAPSHOTS.json"

        let snapshots = try loadSnapshots(path: snapshotPath)
        let cases = try loadBreakerCases(path: breakerPath)
        let caseMap = Dictionary(uniqueKeysWithValues: cases.map { ($0.id, $0) })

        let references = try SolutionReferenceStore(baseURL: URL(fileURLWithPath: basePath))
        let engine = try SolutionEngine(references: references)

        var failed: [(String, [String], String, [String])] = []
        var passed: [String] = []

        for id in snapshots.keys.sorted() {
            guard let entry = caseMap[id] else {
                failed.append((id, ["missing_case_in_breaker_set"], "nil", []))
                continue
            }
            guard let snapshot = snapshots[id] else { continue }

            let result = engine.process(request: makeRequest(from: entry.input))
            let issues = compare(snapshot: snapshot, result: result)
            let ruleCodes = result.warnings.map(\.code)
            if issues.isEmpty {
                passed.append(id)
            } else {
                failed.append((id, issues, result.solutionBranch ?? "nil", ruleCodes))
            }
        }

        print("strict_total=\(snapshots.count)")
        print("strict_passed=\(passed.count)")
        print("strict_failed=\(failed.count)")
        print("strict_passed_ids=\(passed.joined(separator: ","))")

        if !failed.isEmpty {
            print("--- strict_failed_details ---")
            for item in failed {
                print("\(item.0) branch=\(item.2)")
                print("  rules=\(item.3)")
                for issue in item.1 {
                    print("  - \(issue)")
                }
            }
            throw NSError(
                domain: "SnapshotRunner",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Strict snapshot checks failed: \(failed.count) case(s)"]
            )
        }
    }
}
