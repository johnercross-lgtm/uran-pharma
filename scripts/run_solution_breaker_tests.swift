import Foundation

private struct BreakerCase {
    let id: String
    let title: String
    let input: [String: Any]
    let expected: [String: Any]
}

private func loadBreakerCases(path: String) throws -> [BreakerCase] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let rawCases = root["cases"] as? [[String: Any]] else {
        throw NSError(domain: "BreakerRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid breaker JSON schema"])
    }

    return rawCases.compactMap { row in
        guard let id = row["id"] as? String,
              let title = row["title"] as? String,
              let input = row["input"] as? [String: Any],
              let expected = row["expected"] as? [String: Any] else {
            return nil
        }
        return BreakerCase(id: id, title: title, input: input, expected: expected)
    }
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

private func stringListContains(_ haystack: [String], needle: String) -> Bool {
    let token = needle.lowercased()
    return haystack.contains { $0.lowercased().contains(token) }
}

private func evaluate(case entry: BreakerCase, result: SolutionEngineResult) -> [String] {
    var failures: [String] = []
    let expected = entry.expected

    if let branch = expected["branch"] as? String,
       result.solutionBranch != branch {
        failures.append("branch expected=\(branch) actual=\(result.solutionBranch ?? "nil")")
    }

    if let route = expected["route"] as? String,
       result.route != route {
        failures.append("route expected=\(route) actual=\(result.route ?? "nil")")
    }

    if let confidence = expected["confidence"] as? String,
       result.confidence.rawValue != confidence {
        failures.append("confidence expected=\(confidence) actual=\(result.confidence.rawValue)")
    }

    if let confidenceNot = expected["confidenceMustNotBe"] as? String,
       result.confidence.rawValue == confidenceNot {
        failures.append("confidence must not be \(confidenceNot)")
    }

    if let water = expected["waterToAddMl"] as? Double,
       !approxEqual(result.calculationTrace.waterToAddMl, water) {
        failures.append("waterToAddMl expected=\(water) actual=\(result.calculationTrace.waterToAddMl ?? -999)")
    }

    if let solids = expected["sumSolidsG"] as? Double,
       !approxEqual(result.calculationTrace.sumSolidsG, solids) {
        failures.append("sumSolidsG expected=\(solids) actual=\(result.calculationTrace.sumSolidsG)")
    }

    if let kvo = expected["kvoApplied"] as? Bool,
       result.calculationTrace.kvoApplied != kvo {
        failures.append("kvoApplied expected=\(kvo) actual=\(result.calculationTrace.kvoApplied)")
    }

    if let requiredMasses = expected["requiredMassesG"] as? [String: Double] {
        for (key, value) in requiredMasses {
            let actual = result.calculationTrace.requiredMassesG[key]
            if !approxEqual(actual, value) {
                failures.append("requiredMassesG[\(key)] expected=\(value) actual=\(actual ?? -999)")
            }
        }
    }

    if let concentrates = expected["concentrateVolumesMl"] as? [String: Double] {
        for (key, value) in concentrates {
            let actual = result.calculationTrace.concentrateVolumesMl[key]
            if !approxEqual(actual, value) {
                failures.append("concentrateVolumesMl[\(key)] expected=\(value) actual=\(actual ?? -999)")
            }
        }
    }

    let warningCodes = Set(result.warnings.map(\.code))
    if let mustContain = expected["warningsMustContain"] as? [String] {
        for code in mustContain where !warningCodes.contains(code) {
            failures.append("missing warning \(code)")
        }
    }

    if let mustNotContain = expected["warningsMustNotContain"] as? [String] {
        for code in mustNotContain where warningCodes.contains(code) {
            failures.append("unexpected warning \(code)")
        }
    }

    if let mustContainTech = expected["technologyMustContain"] as? [String] {
        let allTech = result.technologySteps + result.technologyFlags
        for token in mustContainTech where !stringListContains(allTech, needle: token) {
            failures.append("technology missing token \(token)")
        }
    }

    if let mustNotContainTech = expected["technologyMustNotContain"] as? [String] {
        let allTech = result.technologySteps + result.technologyFlags
        for token in mustNotContainTech where stringListContains(allTech, needle: token) {
            failures.append("technology unexpectedly contains \(token)")
        }
    }

    if let packMustContain = expected["packagingMustContain"] as? [String] {
        for token in packMustContain where !stringListContains(result.packaging.packaging, needle: token) {
            failures.append("packaging missing \(token)")
        }
    }

    if let labelsMustNotContain = expected["labelsMustNotContain"] as? [String] {
        for token in labelsMustNotContain where stringListContains(result.packaging.labels, needle: token) {
            failures.append("labels unexpectedly contain \(token)")
        }
    }

    if let storageMustContain = expected["storageMustContain"] as? [String] {
        for token in storageMustContain where !stringListContains(result.packaging.storage, needle: token) {
            failures.append("storage missing \(token)")
        }
    }

    if let doseControl = expected["doseControl"] as? [String: Any] {
        if let single = doseControl["singleDoseMl"] as? Double,
           !approxEqual(result.doseControl.singleDoseMl, single) {
            failures.append("dose.singleDoseMl expected=\(single) actual=\(result.doseControl.singleDoseMl ?? -999)")
        }

        if let freq = doseControl["frequencyPerDay"] as? Int,
           result.doseControl.frequencyPerDay != freq {
            failures.append("dose.frequencyPerDay expected=\(freq) actual=\(result.doseControl.frequencyPerDay ?? -1)")
        }
    }

    if let mustNotContainPpc = expected["ppcMustNotContain"] as? [String] {
        for token in mustNotContainPpc where result.ppkDocument.renderedText.contains(token) {
            failures.append("ppc unexpectedly contains forbidden phrase \(token)")
        }
    }

    if let sectionCounts = expected["ppcSectionCounts"] as? [String: Int] {
        for (section, expectedCount) in sectionCounts {
            let count = result.ppkDocument.sections[section] == nil ? 0 : 1
            if count != expectedCount {
                failures.append("ppc section \(section) count expected=\(expectedCount) actual=\(count)")
            }
        }
    }

    if let resolved = expected["resolvedSubstanceKeys"] as? [String] {
        let resolvedKeys = Set(result.normalizedIngredients.compactMap(\.substanceKey).map { $0.lowercased() })
        for key in resolved where !resolvedKeys.contains(key.lowercased()) {
            failures.append("resolvedSubstanceKeys missing \(key)")
        }
    }

    if let noCrash = expected["engineMustNotCrash"] as? Bool, noCrash {
        // If we got here, engine did not crash.
    }

    return failures
}

@main
struct BreakerRunnerMain {
    static func main() throws {
        let defaultBase = "/Users/eugentamara/URAN/Uran/URAN_Pharma_Engine"
        let basePath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : defaultBase
        let breakerPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "\(basePath)/tests/RECIPE_BREAKER_TEST_SET.json"

        let references = try SolutionReferenceStore(baseURL: URL(fileURLWithPath: basePath))
        let engine = try SolutionEngine(references: references)
        let cases = try loadBreakerCases(path: breakerPath)

        var passed: [String] = []
        var failed: [(id: String, confidence: String, issues: [String])] = []
        var blocked: [String] = []

        for entry in cases {
            let request = makeRequest(from: entry.input)
            let result = engine.process(request: request)
            let issues = evaluate(case: entry, result: result)

            if result.confidence == .blocked {
                blocked.append(entry.id)
            }

            if issues.isEmpty {
                passed.append(entry.id)
            } else {
                failed.append((entry.id, result.confidence.rawValue, issues))
            }
        }

        print("total=\(cases.count)")
        print("passed=\(passed.count)")
        print("failed=\(failed.count)")
        print("blocked=\(blocked.count)")
        print("passed_ids=\(passed.joined(separator: ","))")

        if !failed.isEmpty {
            print("--- failed_details ---")
            for item in failed {
                print("\(item.id) confidence=\(item.confidence)")
                for issue in item.issues {
                    print("  - \(issue)")
                }
            }
            throw NSError(
                domain: "BreakerRunner",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Recipe breaker checks failed: \(failed.count) case(s)"]
            )
        }
    }
}
