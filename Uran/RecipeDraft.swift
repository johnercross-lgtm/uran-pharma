import Foundation

enum LiquidTechnologyMode: String, CaseIterable {
    case waterSolution
    case alcoholSolution
    case infusion
    case decoction

    var title: String {
        switch self {
        case .waterSolution:
            return "Розчин (водний)"
        case .alcoholSolution:
            return "Розчин (спиртовий)"
        case .infusion:
            return "Настій"
        case .decoction:
            return "Відвар"
        }
    }
}

enum MetrologicalScaleSelection: String, CaseIterable {
    case auto
    case vr1
    case vr5
    case vr20
    case vr100
    case vkt1000

    var title: String {
        switch self {
        case .auto: return "Авто"
        case .vr1: return "ВР-1"
        case .vr5: return "ВР-5"
        case .vr20: return "ВР-20"
        case .vr100: return "ВР-100"
        case .vkt1000: return "ВКТ-1000"
        }
    }
}

enum MetrologicalDropperMode: String, CaseIterable {
    case standard
    case nonStandard

    var title: String {
        switch self {
        case .standard:
            return "Стандартный (20 кап/мл)"
        case .nonStandard:
            return "Нестандартный (калибровка)"
        }
    }
}

struct ExtempRecipeDraft {

    // FORM
    var formMode: FormMode = .auto
    var numero: Int?
    var powderMassMode: PowderMassMode = .dispensa
    var liquidTechnologyMode: LiquidTechnologyMode = .waterSolution
    var isOphthalmicDrops: Bool = false
    var useVmsColloidsBlock: Bool = false
    var useStandardSolutionsBlock: Bool = false
    var useBuretteSystem: Bool = false
    var metrologyScale: MetrologicalScaleSelection = .auto
    var metrologyDropperMode: MetrologicalDropperMode = .standard
    var metrologyDropperDropsPerMlWater: Double?
    var metrologyCorrectionVolumeMl: Double?
    var metrologyCorrectionActualPercent: Double?
    var metrologyCorrectionTargetPercent: Double?
    var metrologyCorrectionStockPercent: Double?

    // TARGET
    var targetValue: Double?
    var targetUnit: UnitCode?

    // PATIENT
    var patientName: String = ""
    var patientAgeYears: Int?
    var rxNumber: String = ""

    // SIGNA
    var signa: String = ""

    // COMPOSITION
    var ingredients: [IngredientDraft] = []

    // SOL
    var solPercent: Double?
    var solPercentInputText: String = ""
    var solVolumeMl: Double?
    var standardSolutionSourceKey: SolutionKey?
    var standardSolutionInputNameKind: DilutionInputNameKind?
    var standardSolutionSpecialCase: StandardSolutionSpecialCase?
    var standardSolutionManualStockMl: Double?
    var standardSolutionManualWaterMl: Double?
    var standardSolutionManualNote: String = ""

    // FLAGS
    var isExpertMode: Bool = false
    var isCompactMode: Bool = false
}

extension ExtempRecipeDraft {
    var normalizedTargetValue: Double? {
        guard let targetValue, targetValue > 0 else { return nil }
        return targetValue
    }

    var resolvedTargetUnit: UnitCode? {
        if let targetUnit, !targetUnit.rawValue.isEmpty {
            return targetUnit
        }

        if let ingredientUnit = ingredients.last(where: { $0.isAd || $0.isQS })?.unit,
           !ingredientUnit.rawValue.isEmpty {
            return ingredientUnit
        }

        if formMode == .solutions || formMode == .drops {
            return UnitCode(rawValue: "ml")
        }

        return nil
    }

    var explicitLiquidTargetMl: Double? {
        guard let target = normalizedTargetValue else { return nil }
        guard let unit = resolvedTargetUnit?.rawValue else { return nil }
        guard unit == "ml" || unit == "мл" else { return nil }
        return target
    }

    var legacyAdOrQsLiquidTargetMl: Double? {
        ingredients.last(where: {
            ($0.isAd || $0.isQS)
                && ($0.unit.rawValue == "ml" || $0.unit.rawValue == "мл")
                && $0.amountValue > 0
        })?.amountValue
    }

    var explicitPowderTargetG: Double? {
        guard let target = normalizedTargetValue else { return nil }
        guard let unit = resolvedTargetUnit?.rawValue else { return nil }
        guard unit == "g" || unit == "г" else { return nil }
        return target
    }

    func solutionDisplayPercent(for ingredient: IngredientDraft) -> Double? {
        guard ingredient.presentationKind == .solution else { return nil }
        guard let percent = solPercent, percent > 0 else { return nil }
        return percent
    }

    func solutionPercentRepresentsSolventStrength(for ingredient: IngredientDraft) -> Bool {
        guard ingredient.presentationKind == .solution else { return false }
        guard NonAqueousSolventCatalog.classify(ingredient: ingredient) == .ethanol else { return false }
        return NonAqueousSolventCatalog.officinalAlcoholSolution(for: ingredient) == nil
    }

    func solutionActivePercent(for ingredient: IngredientDraft) -> Double? {
        guard !solutionPercentRepresentsSolventStrength(for: ingredient) else { return nil }
        return solutionDisplayPercent(for: ingredient)
    }

    func solutionVolumeMl(for ingredient: IngredientDraft) -> Double? {
        guard ingredient.presentationKind == .solution else { return nil }
        if let explicit = solVolumeMl, explicit > 0 {
            return explicit
        }
        let unit = ingredient.unit.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if (unit == "ml" || unit == "мл"), ingredient.amountValue > 0 {
            return ingredient.amountValue
        }
        return nil
    }

    func solutionActiveMassG(for ingredient: IngredientDraft) -> Double? {
        guard let volume = solutionVolumeMl(for: ingredient), volume > 0 else {
            return nil
        }
        if let percent = solutionActivePercent(for: ingredient), percent > 0 {
            return percent * volume / 100.0
        }

        let descriptor = (ingredient.refNameLatNom ?? ingredient.displayName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !descriptor.isEmpty else { return nil }
        return Self.inferMassFromDescriptor(text: descriptor, volumeMl: volume)
    }

    var hasManualStandardSolutionMix: Bool {
        let stock = standardSolutionManualStockMl ?? 0
        let water = standardSolutionManualWaterMl ?? 0
        return stock > 0 || water > 0
    }

    var standardSolutionManualTotalMl: Double? {
        guard hasManualStandardSolutionMix else { return nil }
        return max(0, standardSolutionManualStockMl ?? 0) + max(0, standardSolutionManualWaterMl ?? 0)
    }

    func selectedStandardSolution(repo: StandardSolutionsRepository = .shared) -> StandardSolution? {
        guard let key = standardSolutionSourceKey else { return nil }
        return repo.get(key)
    }

    func effectiveLiquidVolumeMl(for ingredient: IngredientDraft) -> Double {
        if let solutionVolume = solutionVolumeMl(for: ingredient) {
            return max(0, solutionVolume)
        }

        let unit = ingredient.unit.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if unit == "ml" || unit == "мл" {
            return max(0, ingredient.amountValue)
        }

        return 0
    }

    func inferredActiveMassG(for ingredient: IngredientDraft) -> Double {
        let unit = ingredient.unit.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if unit == "g" || unit == "г" {
            return max(0, ingredient.amountValue)
        }

        if let solutionMass = solutionActiveMassG(for: ingredient) {
            return max(0, solutionMass)
        }

        if (unit == "ml" || unit == "мл"),
           ingredient.amountValue > 0
        {
            let descriptor = (ingredient.refNameLatNom ?? ingredient.displayName)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let inferred = Self.inferMassFromDescriptor(text: descriptor, volumeMl: ingredient.amountValue),
               inferred > 0 {
                return inferred
            }
        }

        return 0
    }

    private static func inferMassFromDescriptor(text: String, volumeMl: Double) -> Double? {
        guard volumeMl > 0 else { return nil }

        if let percent = parsePercent(from: text), percent > 0 {
            return percent * volumeMl / 100.0
        }

        if let denominator = parseDilutionDenominator(from: text), denominator > 0 {
            return volumeMl / denominator
        }

        if let ex = parseExMassVolume(from: text),
           ex.volumeMl > 0,
           ex.massG > 0 {
            return volumeMl * (ex.massG / ex.volumeMl)
        }

        return nil
    }

    private static func parsePercent(from text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard let range = normalized.range(of: "(\\d{1,2}(?:\\.\\d+)?)\\s*%", options: .regularExpression) else {
            return nil
        }
        let raw = String(normalized[range])
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(raw)
    }

    private static func parseDilutionDenominator(from text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard let range = normalized.range(
            of: "(?<!\\d)1\\s*[:/]\\s*([0-9]+(?:\\.[0-9]+)?)",
            options: .regularExpression
        ) else {
            return nil
        }

        let matched = String(normalized[range])
        guard let denominatorRange = matched.range(of: "[0-9]+(?:\\.[0-9]+)?$", options: .regularExpression) else {
            return nil
        }
        return Double(String(matched[denominatorRange]))
    }

    private static func parseExMassVolume(from text: String) -> (massG: Double, volumeMl: Double)? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard let range = normalized.range(
            of: "\\bex\\s*([0-9]+(?:\\.[0-9]+)?)\\s*(?:g|г|гр)?\\s*[-–—]\\s*([0-9]+(?:\\.[0-9]+)?)\\s*(?:ml|мл)\\b",
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return nil
        }

        let matched = String(normalized[range])
        let ns = matched as NSString
        let regex = try? NSRegularExpression(pattern: "([0-9]+(?:\\.[0-9]+)?)", options: [])
        let fullRange = NSRange(location: 0, length: ns.length)
        let matches = regex?.matches(in: matched, options: [], range: fullRange) ?? []
        guard matches.count >= 2 else { return nil }

        let mass = ns.substring(with: matches[0].range)
        let volume = ns.substring(with: matches[1].range)
        guard let massG = Double(mass), let volumeMl = Double(volume), massG > 0, volumeMl > 0 else {
            return nil
        }
        return (massG, volumeMl)
    }
}
