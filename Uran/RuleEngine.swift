import Foundation

struct RuleResult {
    var normalizedDraft: ExtempRecipeDraft
    var derived: DerivedState
    var issues: [RxIssue]
    var techPlan: TechPlan
}

protocol RuleEngineProtocol {
    func evaluate(draft: ExtempRecipeDraft) -> RuleResult
}

final class DefaultRuleEngine: RuleEngineProtocol {
    private let modularEngine = ModularRxEngine()
    private let normalizer = RxDraftNormalizer()

    func evaluate(draft: ExtempRecipeDraft) -> RuleResult {
        let normalization = normalizer.normalize(draft: draft)
        var issues = normalization.issues
        var normalized = normalization.normalizedDraft

        normalized.formMode = SignaUsageAnalyzer.effectiveFormMode(for: normalized)

        let hasQSorAd = normalized.ingredients.contains(where: { $0.isQS || $0.isAd })
        let hasIngredientTarget = normalized.ingredients.contains {
            ($0.isQS || $0.isAd) && $0.amountValue > 0
        }
        if hasQSorAd, normalized.targetValue == nil, !hasIngredientTarget {
            issues.append(
                RxIssue(
                    code: "target.missing",
                    severity: .blocking,
                    message: "Target volume/mass is not defined"
                )
            )
        }

        if normalized.ingredients.contains(where: { $0.scope == .perDose }), normalized.numero == nil {
            issues.append(
                RxIssue(
                    code: "numero.missingForPerDose",
                    severity: .warning,
                    message: "Numero потрібно для per-dose розрахунків"
                )
            )
        }

        if normalized.patientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(
                RxIssue(
                    code: "patient.name.required",
                    severity: .warning,
                    message: "Потрібно ФИО пациента"
                )
            )
        }

        if normalized.rxNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(
                RxIssue(
                    code: "patient.rxNumber.required",
                    severity: .warning,
                    message: "Потрібен № рецепта"
                )
            )
        }

        if normalized.signa.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(
                RxIssue(
                    code: "signa.required",
                    severity: .warning,
                    message: "Потрібна Signa (M. D. S.)"
                )
            )
        }

        if normalized.ingredients.isEmpty {
            issues.append(
                RxIssue(
                    code: "composition.empty",
                    severity: .blocking,
                    message: "Додайте хоча б один інгредієнт"
                )
            )
        }

        issues.append(contentsOf: validateRequiredIngredientAmounts(in: normalized))

        let modular = modularEngine.evaluate(draft: normalized, isNormalized: true)
        issues.append(contentsOf: modular.issues)

        let burette = BuretteSystem.evaluateBurette(draft: normalized)
        issues.append(contentsOf: burette.issues)

        var techPlan = modular.techPlan
        if !burette.techSteps.isEmpty {
            let packagingSteps = techPlan.steps.filter { $0.kind == .packaging }
            let labelingSteps = techPlan.steps.filter { $0.kind == .labeling }
            var coreSteps = techPlan.steps.filter { $0.kind != .packaging && $0.kind != .labeling }

            if let firstFiltrationIdx = coreSteps.firstIndex(where: { $0.kind == .filtration }) {
                coreSteps.insert(contentsOf: burette.techSteps, at: firstFiltrationIdx)
            } else {
                coreSteps.append(contentsOf: burette.techSteps)
            }

            techPlan.steps = coreSteps + packagingSteps + labelingSteps
        }

        var derived = modular.derived

        let metrology = MetrologyRuleEngine.evaluate(
            draft: normalized,
            existingCalculations: derived.calculations
        )
        issues.append(contentsOf: metrology.issues)
        derived.calculations.merge(metrology.calculations, uniquingKeysWith: { _, rhs in rhs })
        if !metrology.ppkLines.isEmpty {
            derived.ppkSections.append(PpkSection(title: "Метрологічний валідатор", lines: metrology.ppkLines))
        }
        derived.ppkDocument = PpkRenderer().buildDocument(
            draft: normalized,
            plan: techPlan,
            issues: issues,
            sections: derived.ppkSections,
            routeBranch: derived.routeBranch,
            activatedBlocks: derived.activatedBlocks,
            powderTechnology: derived.powderTechnology
        )

        return RuleResult(
            normalizedDraft: normalized,
            derived: derived,
            issues: issues,
            techPlan: techPlan
        )
    }

    private func validateRequiredIngredientAmounts(in draft: ExtempRecipeDraft) -> [RxIssue] {
        var issues: [RxIssue] = []

        for ingredient in draft.ingredients where !ingredient.isAd && !ingredient.isQS {
            let unit = ingredient.unit.rawValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let displayName = ingredient.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Subst."
                : ingredient.displayName

            let isMassUnit = unit == "g" || unit == "гр" || unit == "mg" || unit == "мг" || unit == "mcg" || unit == "мкг" || unit == "kg" || unit == "кг"
            let isVolumeUnit = unit == "ml" || unit == "мл" || unit == "l" || unit == "л"

            if isMassUnit, ingredient.amountValue <= 0 {
                let inferredMass = draft.solutionActiveMassG(for: ingredient) ?? 0
                if inferredMass <= 0 {
                    issues.append(
                        RxIssue(
                            code: "ingredient.mass.missing.\(ingredient.id.uuidString)",
                            severity: .blocking,
                            message: "В рецепті відсутня маса для \(displayName)"
                        )
                    )
                }
            }

            if isVolumeUnit, ingredient.amountValue <= 0 {
                let inferredVolume = draft.solutionVolumeMl(for: ingredient) ?? 0
                if inferredVolume <= 0 {
                    issues.append(
                        RxIssue(
                            code: "ingredient.volume.missing.\(ingredient.id.uuidString)",
                            severity: .blocking,
                            message: "В рецепті відсутній об'єм для \(displayName)"
                        )
                    )
                }
            }
        }

        return issues
    }
}

private struct ScaleProfile {
    let selection: MetrologicalScaleSelection
    let name: String
    let maxLoadG: Double
    let minLoadG: Double
    let maxErrorMg: Double
}

private struct WeighingSample {
    let ingredientName: String
    let massG: Double
}

private struct MetrologyEvaluation {
    var issues: [RxIssue] = []
    var calculations: [String: String] = [:]
    var ppkLines: [String] = []
}

private enum MetrologyRuleEngine {
    private static let scaleProfiles: [ScaleProfile] = [
        ScaleProfile(selection: .vr1, name: "ВР-1", maxLoadG: 1.0, minLoadG: 0.02, maxErrorMg: 5),
        ScaleProfile(selection: .vr5, name: "ВР-5", maxLoadG: 5.0, minLoadG: 0.10, maxErrorMg: 10),
        ScaleProfile(selection: .vr20, name: "ВР-20", maxLoadG: 20.0, minLoadG: 1.0, maxErrorMg: 20),
        ScaleProfile(selection: .vr100, name: "ВР-100", maxLoadG: 100.0, minLoadG: 5.0, maxErrorMg: 50),
        ScaleProfile(selection: .vkt1000, name: "ВКТ-1000", maxLoadG: 1000.0, minLoadG: 30.0, maxErrorMg: 100)
    ]

    private static let fallbackKuoByName: [(needle: String, kuo: Double)] = [
        ("гексаметилентетрамин", 0.78),
        ("hexamethylenetetramine", 0.78),
        ("натрия салицилат", 0.58),
        ("natrii salicylas", 0.58)
    ]

    static func evaluate(
        draft: ExtempRecipeDraft,
        existingCalculations: [String: String]
    ) -> MetrologyEvaluation {
        var out = MetrologyEvaluation()
        evaluateWeights(draft: draft, into: &out)
        evaluateDrops(draft: draft, into: &out)
        evaluateSolutionCorrection(draft: draft, into: &out)
        evaluateKuoDisplacement(
            draft: draft,
            existingCalculations: existingCalculations,
            into: &out
        )
        return out
    }

    private static func evaluateWeights(draft: ExtempRecipeDraft, into out: inout MetrologyEvaluation) {
        let samples = weighingSamples(from: draft)
        guard !samples.isEmpty else { return }

        let selectedProfile = scaleProfiles.first(where: { $0.selection == draft.metrologyScale })
        var lines: [String] = []
        var meanRelativeError = 0.0
        var measuredCount = 0.0

        for sample in samples {
            let profile = selectedProfile ?? recommendedProfile(for: sample.massG)
            guard let profile else {
                out.issues.append(
                    RxIssue(
                        code: "metrology.scale.unavailable",
                        severity: .warning,
                        message: "Выбран неверный тип весов: масса \(format(sample.massG)) г не покрывается доступными весами"
                    )
                )
                lines.append("Весы: \(sample.ingredientName) \(format(sample.massG)) g — вне диапазона доступных весов")
                continue
            }

            let isInRange = sample.massG >= profile.minLoadG && sample.massG <= profile.maxLoadG
            if !isInRange, selectedProfile != nil {
                out.issues.append(
                    RxIssue(
                        code: "metrology.scale.invalid.\(profile.selection.rawValue).\(sample.ingredientName)",
                        severity: .warning,
                        message: "Выбран неверный тип весов: \(profile.name) для \(sample.ingredientName) (\(format(sample.massG)) г, допустимо \(format(profile.minLoadG))-\(format(profile.maxLoadG)) г)"
                    )
                )
            }

            guard isInRange || selectedProfile == nil else { continue }

            let absoluteErrorG = profile.maxErrorMg / 1000.0
            let relativeErrorPercent = sample.massG > 0 ? (absoluteErrorG / sample.massG) * 100.0 : 0
            meanRelativeError += relativeErrorPercent
            measuredCount += 1
            lines.append(
                "Весы: \(sample.ingredientName) \(format(sample.massG)) g -> \(profile.name), ε_rel ≈ \(format(relativeErrorPercent))%"
            )
        }

        guard !lines.isEmpty else { return }
        out.ppkLines.append(contentsOf: lines)
        out.calculations["metrology.scale.mode"] = selectedProfile?.name ?? "Авто"
        out.calculations["metrology.scale.samples"] = String(Int(measuredCount))
        if measuredCount > 0 {
            out.calculations["metrology.scale.mean_relative_error_percent"] = format(meanRelativeError / measuredCount)
        }
    }

    private static func evaluateDrops(draft: ExtempRecipeDraft, into out: inout MetrologyEvaluation) {
        let signa = draft.signa.trimmingCharacters(in: .whitespacesAndNewlines)
        let formMode = SignaUsageAnalyzer.effectiveFormMode(for: draft)
        let isDropsContext = formMode == .drops || signa.lowercased().contains("кап")
        guard isDropsContext else { return }

        let nst = parseDropsPerDose(from: signa)
        var lines: [String] = []

        switch draft.metrologyDropperMode {
        case .standard:
            lines.append("Каплемер: стандартний, 1 ml води = 20 крапель")
            if let nst, nst > 0 {
                lines.append("n_st = \(format(nst)) кап., K = 1.000, N = \(format(nst)) кап.")
            }
            out.calculations["metrology.dropper.k"] = "1.000"
            out.calculations["metrology.dropper.n_ml"] = "20.000"
        case .nonStandard:
            guard let n = draft.metrologyDropperDropsPerMlWater, n > 0 else {
                out.issues.append(
                    RxIssue(
                        code: "metrology.dropper.calibration.missing",
                        severity: .warning,
                        message: "Для нестандартного каплемера вкажіть n (кількість крапель у 1 мл води)"
                    )
                )
                return
            }

            let k = 20.0 / n
            lines.append("Каплемер: нестандартний, n = \(format(n)) кап./ml, K = 20/n = \(format(k))")
            out.calculations["metrology.dropper.k"] = format(k)
            out.calculations["metrology.dropper.n_ml"] = format(n)

            if let nst, nst > 0 {
                let calibrated = nst * k
                lines.append("Перерахунок рецепта: N = n_st × K = \(format(nst)) × \(format(k)) = \(format(calibrated)) кап.")
                out.calculations["metrology.dropper.n_recipe"] = format(calibrated)
            } else {
                lines.append("n_st у Signa не знайдено; перерахунок N не виконано")
            }
        }

        if !lines.isEmpty {
            out.ppkLines.append(contentsOf: lines)
        }
    }

    private static func evaluateSolutionCorrection(draft: ExtempRecipeDraft, into out: inout MetrologyEvaluation) {
        guard let volume = draft.metrologyCorrectionVolumeMl, volume > 0,
              let cFact = draft.metrologyCorrectionActualPercent, cFact > 0,
              let cNeeded = draft.metrologyCorrectionTargetPercent, cNeeded > 0 else {
            return
        }

        if cFact > cNeeded {
            let waterToAdd = volume * (cFact - cNeeded) / cNeeded
            out.ppkLines.append(
                "Розбавлення: X = V × (Cfact - Cneeded) / Cneeded = \(format(volume)) × (\(format(cFact)) - \(format(cNeeded))) / \(format(cNeeded)) = \(format(waterToAdd)) ml води"
            )
            out.calculations["metrology.solution.dilution_water_ml"] = format(waterToAdd)
            return
        }

        if cFact < cNeeded {
            let dryMassToAdd = volume * (cNeeded - cFact) / 100.0
            out.ppkLines.append(
                "Укріплення (суха речовина): m = V × (Cneeded - Cfact) / 100 = \(format(dryMassToAdd)) g"
            )
            out.calculations["metrology.solution.strengthen_dry_g"] = format(dryMassToAdd)

            if let cStock = draft.metrologyCorrectionStockPercent, cStock > cNeeded, cStock > cFact {
                let stockVolume = volume * (cNeeded - cFact) / (cStock - cNeeded)
                out.ppkLines.append(
                    "Укріплення (правило змішування): Vstock = V × (Cneeded - Cfact) / (Cstock - Cneeded) = \(format(stockVolume)) ml"
                )
                out.calculations["metrology.solution.strengthen_stock_ml"] = format(stockVolume)
            } else if draft.metrologyCorrectionStockPercent != nil {
                out.issues.append(
                    RxIssue(
                        code: "metrology.solution.stock.invalid",
                        severity: .warning,
                        message: "Для укріплення через концентрат потрібно Cstock > Cneeded"
                    )
                )
            }
            return
        }

        out.ppkLines.append("Корекція розчину: Cfact = Cneeded, додаткові дії не потрібні")
    }

    private static func evaluateKuoDisplacement(
        draft: ExtempRecipeDraft,
        existingCalculations: [String: String],
        into out: inout MetrologyEvaluation
    ) {
        let ignoreKuoForBurette = existingCalculations["ignore_kuo_for_burette"] == "true"
        if ignoreKuoForBurette {
            out.calculations["metrology.kuo.suppressed"] = "true"
            return
        }

        guard let totalVolume = resolvedTargetVolumeMl(draft: draft), totalVolume > 0 else { return }

        let solids = drySolidsForKuo(from: draft)
        guard !solids.isEmpty else { return }

        var displacement = 0.0
        var missingKuo = 0

        for item in solids {
            guard let kuo = item.kuo else {
                missingKuo += 1
                continue
            }
            displacement += item.massG * kuo
        }

        guard displacement > 0 else { return }

        let ratioPercent = (displacement / totalVolume) * 100.0
        out.ppkLines.append("КУО: Σ(m × КУО) = \(format(displacement)) ml, що становить \(format(ratioPercent))% від Vtotal")
        out.calculations["metrology.kuo.displacement_ml"] = format(displacement)
        out.calculations["metrology.kuo.displacement_percent"] = format(ratioPercent)

        if ratioPercent >= 3.0 {
            let waterVolume = max(0, totalVolume - displacement)
            out.ppkLines.append("КУО-корекція: Vwater = Vtotal - Σ(m × КУО) = \(format(waterVolume)) ml")
            out.calculations["metrology.kuo.water_ml"] = format(waterVolume)

            let kuoAlreadyApplied = existingCalculations["kuo_volume_ml"] != nil
                || existingCalculations["drops_kuo_displacement_ml"] != nil
                || existingCalculations["ophthalmic_kuo_displacement_ml"] != nil
            if !kuoAlreadyApplied {
                out.issues.append(
                    RxIssue(
                        code: "metrology.kuo.force",
                        severity: .warning,
                        message: "КУО перевищує 3% від об'єму: воду потрібно відмірювати з урахуванням витіснення"
                    )
                )
            }
        }

        if ratioPercent >= 4.0 {
            out.issues.append(
                RxIssue(
                    code: "metrology.kuo.high",
                    severity: .warning,
                    message: "Σ(m×КУО) перевищує 4% від загального об’єму; контроль об’єму обов’язковий"
                )
            )
        }

        if missingKuo > 0 {
            out.issues.append(
                RxIssue(
                    code: "metrology.kuo.missing",
                    severity: .warning,
                    message: "Для \(missingKuo) твердих компонентів відсутній КУО; розрахунок КУО може бути неповним"
                )
            )
        }
    }

    private static func weighingSamples(from draft: ExtempRecipeDraft) -> [WeighingSample] {
        let numero = max(1, draft.numero ?? 1)
        return draft.ingredients.compactMap { ingredient in
            guard !ingredient.isAd, !ingredient.isQS else { return nil }
            guard isMassUnit(ingredient.unit) else { return nil }
            let multiplier = ingredient.scope == .perDose ? Double(numero) : 1.0
            let mass = max(0, ingredient.amountValue * multiplier)
            guard mass > 0 else { return nil }
            return WeighingSample(ingredientName: ingredient.displayName, massG: mass)
        }
    }

    private static func recommendedProfile(for massG: Double) -> ScaleProfile? {
        scaleProfiles.first(where: { massG >= $0.minLoadG && massG <= $0.maxLoadG })
    }

    private static func parseDropsPerDose(from signa: String) -> Double? {
        let source = signa.replacingOccurrences(of: ",", with: ".")
        guard let regex = try? NSRegularExpression(
            pattern: "(\\d+(?:\\.\\d+)?)\\s*(?:кап\\.|капель|капля|капли|кап)",
            options: [.caseInsensitive]
        ) else { return nil }
        let range = NSRange(location: 0, length: source.utf16.count)
        guard let match = regex.firstMatch(in: source, options: [], range: range),
              match.numberOfRanges >= 2,
              let valueRange = Range(match.range(at: 1), in: source) else {
            return nil
        }
        return Double(source[valueRange])
    }

    private static func isMassUnit(_ unit: UnitCode) -> Bool {
        let value = unit.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "g" || value == "г"
    }

    private static func resolvedTargetVolumeMl(draft: ExtempRecipeDraft) -> Double? {
        if let explicit = draft.explicitLiquidTargetMl, explicit > 0 { return explicit }
        if let legacy = draft.legacyAdOrQsLiquidTargetMl, legacy > 0 { return legacy }
        if let solutionVolume = draft.solVolumeMl, solutionVolume > 0 { return solutionVolume }
        return nil
    }

    private static func drySolidsForKuo(from draft: ExtempRecipeDraft) -> [(massG: Double, kuo: Double?)] {
        let numero = max(1, draft.numero ?? 1)
        return draft.ingredients.compactMap { ingredient in
            guard !ingredient.isAd, !ingredient.isQS else { return nil }
            guard isMassUnit(ingredient.unit) else { return nil }
            let multiplier = ingredient.scope == .perDose ? Double(numero) : 1.0
            let mass = max(0, ingredient.amountValue * multiplier)
            guard mass > 0 else { return nil }
            let kuo = ingredient.refKuoMlPerG ?? fallbackKuo(for: ingredient.displayName)
            return (massG: mass, kuo: kuo)
        }
    }

    private static func fallbackKuo(for name: String) -> Double? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        return fallbackKuoByName.first(where: { normalized.contains($0.needle) })?.kuo
    }

    private static func format(_ value: Double) -> String {
        if value >= 100 {
            return String(format: "%.2f", value)
        }
        if value >= 10 {
            return String(format: "%.3f", value)
        }
        return String(format: "%.4f", value)
    }
}
