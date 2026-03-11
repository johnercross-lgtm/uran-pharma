import Foundation

enum PoisonPreparationMethod: Hashable, Codable, Sendable {
    case directWeighing
    case trituration(ratio: Int)
    case concentrate(volumeMl: Double)
    case dissolvedInMinimalVolume(volumeMl: Double)
    case levigation(liquidType: String, liquidMassG: Double)
}

struct TriturationPlan: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let ingredientId: UUID
    let ingredientName: String
    let required: Bool
    let ratio: Int?
    let totalActiveMass: Double
    let totalTriturationMass: Double
    let triturationPerDose: Double
    let diluent: String

    init(
        ingredientId: UUID,
        ingredientName: String,
        required: Bool,
        ratio: Int?,
        totalActiveMass: Double,
        totalTriturationMass: Double,
        triturationPerDose: Double,
        diluent: String
    ) {
        self.id = ingredientId
        self.ingredientId = ingredientId
        self.ingredientName = ingredientName
        self.required = required
        self.ratio = ratio
        self.totalActiveMass = totalActiveMass
        self.totalTriturationMass = totalTriturationMass
        self.triturationPerDose = triturationPerDose
        self.diluent = diluent
    }
}

struct PowderTechnologyResult: Hashable, Codable, Sendable {
    let dosesCount: Int
    let triturationPlans: [TriturationPlan]
    let totalActiveMass: Double
    let correctedFillerMass: Double?
    let originalFillerMass: Double?
    let fillerIngredientName: String?
    let fillerIngredientId: UUID?
    let totalDiluentMass: Double
    let totalPowderMass: Double
    let doseMass: Double
    let fillerAdded: Double
    let roundingCorrection: Double
    let allowedDeviationPercent: Double
    let lowerDeviationMass: Double
    let upperDeviationMass: Double
    let requiresPoreRubbing: Bool
}

struct PoisonDoseValidation: Hashable, Codable, Sendable {
    let ingredientId: UUID
    let ingredientName: String
    let perDoseG: Double?
    let perDayG: Double?
    let perDoseLimitG: Double?
    let perDayLimitG: Double?
    let frequencyPerDay: Int?
    let isValid: Bool
    let requiresDoseCount: Bool
    let requiresNumericAndTextDose: Bool
}

struct PoisonControlResult: Hashable, Codable, Sendable {
    let ingredientId: UUID
    let ingredientName: String
    let method: PoisonPreparationMethod
    let doseValidation: PoisonDoseValidation
    let requiredLabels: [String]
    let packaging: String
    let requiresSeal: Bool
    let requiresDoubleCheck: Bool
    let requiresPharmacistConfirmation: Bool
    let separateWeighing: Bool
    let requiresSeparateMortar: Bool
    let mixingInstructions: [String]
    let ppkNotes: [String]
}

enum PoisonControl {
    static let microDoseThresholdG = 0.05
    static let ultraMicroThresholdG = 0.01
    static let minimumDoseMassG = 0.3
    nonisolated static let internalPrecision = 0.000001
    static let finalPrecision = 0.001
    static let defaultDiluent = "Saccharum lactis"

    static func containsListA(draft: ExtempRecipeDraft) -> Bool {
        draft.ingredients.contains(where: {
            !$0.isAd
                && !$0.isQS
                && !PurifiedWaterHeuristics.isPurifiedWater($0)
                && $0.isReferenceListA
        })
    }

    static func resolve(draft: ExtempRecipeDraft) -> (results: [PoisonControlResult], powderTechnology: PowderTechnologyResult?) {
        var effectiveDraft = draft
        effectiveDraft.formMode = SignaUsageAnalyzer.effectiveFormMode(for: effectiveDraft)

        let listAIngredients = effectiveDraft.ingredients.filter {
            !$0.isAd
                && !$0.isQS
                && !PurifiedWaterHeuristics.isPurifiedWater($0)
                && $0.isReferenceListA
        }
        guard !listAIngredients.isEmpty else { return ([], nil) }

        let powderTechnology = resolvePowderTechnology(draft: effectiveDraft, listAIngredients: listAIngredients)
        let results = listAIngredients.map { ingredient in
            buildResult(
                ingredient: ingredient,
                draft: effectiveDraft,
                powderTechnology: powderTechnology
            )
        }

        return (results, powderTechnology)
    }

    private static func buildResult(
        ingredient: IngredientDraft,
        draft: ExtempRecipeDraft,
        powderTechnology: PowderTechnologyResult?
    ) -> PoisonControlResult {
        let method = resolvePreparationMethod(ingredient: ingredient, draft: draft)
        let validation = validateDose(ingredient: ingredient, draft: draft)
        let activeName = displayName(ingredient)
        let isPhenol = isPhenolFamily(ingredient)
        let requiresVolumeMeasurement = ingredient.requiresVolumeMeasurement
        let isSilverNitrate = isSilverNitrateLike(ingredient)
        let effectiveRequiresVolumeMeasurement = requiresVolumeMeasurement && !isSilverNitrate

        var mixingInstructions: [String] = {
            switch draft.formMode {
            case .powders:
                return [
                    "Зважити \(activeName) на окремих терезах для отруйних речовин на окремому папірці/човнику",
                    "Використати окрему ступку або ретельно підготовлену окрему робочу поверхню"
                ]
            case .solutions, .drops:
                return [
                    effectiveRequiresVolumeMeasurement
                        ? "Відміряти \(activeName) окремо у мірному посуді (на терезах не зважувати)"
                        : "Зважити \(activeName) на окремих терезах для отруйних речовин на окремому папірці/човнику",
                    "Працювати на окремій підставці/у виділеному місці; використовувати окремий мірний посуд та склянку"
                ]
            case .ointments, .suppositories, .auto:
                return [
                    effectiveRequiresVolumeMeasurement
                        ? "Відміряти \(activeName) окремо у мірному посуді (на терезах не зважувати)"
                        : "Зважити \(activeName) на окремих терезах для отруйних речовин на окремому папірці/човнику",
                    "Працювати на окремій підставці/у виділеному місці"
                ]
            }
        }()

        switch draft.formMode {
        case .powders:
            if let powderTechnology,
               powderTechnology.requiresPoreRubbing,
               let plan = powderTechnology.triturationPlans.first(where: { $0.ingredientId == ingredient.id }),
               let ratio = plan.ratio
            {
                let fillerName = powderTechnology.fillerIngredientName ?? defaultDiluent
                mixingInstructions.append("Затерти пори ступки частиною \(fillerName)")
                mixingInstructions.append("Підготувати тритурацію \(ratio == 100 ? "1:100" : "1:10") з \(defaultDiluent) методом геометричного розведення")
                mixingInstructions.append("Внести тритурацію \(activeName) у середину та далі додавати решту наповнювача методом геометричного розведення")
            } else if case let .trituration(ratio) = method {
                mixingInstructions.append("Підготувати тритурацію \(ratio == 100 ? "1:100" : "1:10") з \(defaultDiluent) методом геометричного розведення")
                mixingInstructions.append("Внести \(activeName) через тритурацію з подальшим геометричним розведенням")
            } else {
                mixingInstructions.append("Внести \(activeName) першим у основу")
            }
            mixingInstructions.append("Після введення отруйної речовини додати решту компонентів і перевірити однорідність доз")
        case .solutions, .drops:
            mixingInstructions.append("Відміряти частину розчинника у склянку/циліндр")
            if case .concentrate = method {
                mixingInstructions.append("Відібрати частину вже відміряного розчинника, приготувати концентрат і повернути його у основний об’єм (кінцевий V не збільшувати)")
            } else {
                mixingInstructions.append("Розчинити \(activeName) у частині розчинника до повного розчинення")
            }
            mixingInstructions.append("Після повного розчинення додати решту компонентів (за потреби — фільтрація)")
        case .ointments:
            mixingInstructions.append("Внести \(activeName) першим у основу")
            if case .levigation(let liquidType, let liquidMassG) = method {
                mixingInstructions.append("Провести левігацію з \(liquidType) у кількості \(format3(liquidMassG)) g")
            } else {
                mixingInstructions.append("Розчинити в мінімальному об’ємі сумісної рідини і ввести в основу методом геометричного розведення")
            }
            mixingInstructions.append("Перевірити відсутність грудок та рівномірність розподілу")
        case .suppositories:
            mixingInstructions.append("Внести \(activeName) першим у основу")
            mixingInstructions.append("Розрахувати масу основи з урахуванням коефіцієнта заміщення")
            mixingInstructions.append("Ретельно розтерти з частиною розплавленої основи перед введенням у загальну масу")
        case .auto:
            mixingInstructions.append("Внести \(activeName) першим у основу")
            mixingInstructions.append("Застосувати режим, сумісний з фактичною лікарською формою")
        }
        if isPhenol && !requiresVolumeMeasurement {
            mixingInstructions.insert("Взвесить фенол на отдельных весах для ядовитых веществ во флакон отпуска.", at: 0)
        }
        if isSilverNitrate {
            mixingInstructions.append("Металеві шпателі/інструменти не використовувати; застосовувати скляні, фарфорові, пластмасові або рогові інструменти.")
        }

        var ppkNotes: [String] = [
            validation.requiresNumericAndTextDose
                ? "Перевірено відповідність ВРД/ВСД"
                : "Для зовнішнього застосування контроль ВРД/ВСД не застосовується; контролюється концентрація",
            effectiveRequiresVolumeMeasurement
                ? "Відмірювання об'єму проведено окремо; рідину на терезах не зважували"
                : "Зважування проведено окремо",
            "Маркування «Яд» нанесено",
            "Потрібен подвійний контроль та підтвердження фармацевта",
            "Підписи «виготовив» та «перевірив» обов'язкові"
        ]
        if draft.formMode == .powders || draft.formMode == .ointments || draft.formMode == .suppositories {
            ppkNotes.append("Рівномірність розподілу перевірена")
        }
        if let powderTechnology, draft.formMode == .powders, !powderTechnology.triturationPlans.isEmpty {
            ppkNotes.append("Тритурації для мікродоз розраховані окремо для кожної речовини")
        }
        if isPhenol {
            ppkNotes.append("Оформити сигнатурою (рожева смуга) та опечатати флакон")
        }

        let requiredLabels = [
            "ЯД",
            "Сигнатура (рожева смуга)",
            "Поводитись обережно",
            "Берегти від дітей"
        ]
        let packaging: String = {
            if draft.formMode == .powders {
                return "Паперові капсули, захист від світла, окреме фасування"
            }
            if isPhenol {
                return "Флакон з темного/оранжевого скла, щільна пробка, опечатати"
            }
            return "Темне скло, щільна пробка, опечатати"
        }()

        return PoisonControlResult(
            ingredientId: ingredient.id,
            ingredientName: activeName,
            method: method,
            doseValidation: validation,
            requiredLabels: requiredLabels,
            packaging: packaging,
            requiresSeal: true,
            requiresDoubleCheck: true,
            requiresPharmacistConfirmation: true,
            separateWeighing: !effectiveRequiresVolumeMeasurement,
            requiresSeparateMortar: true,
            mixingInstructions: mixingInstructions,
            ppkNotes: ppkNotes
        )
    }

    private static func resolvePowderTechnology(
        draft: ExtempRecipeDraft,
        listAIngredients: [IngredientDraft]
    ) -> PowderTechnologyResult? {
        guard draft.formMode == .powders else { return nil }

        let dosesCount = max(1, draft.numero ?? 1)
        let plans = listAIngredients.map { ingredient in
            resolveTrituration(ingredient: ingredient, draft: draft, dosesCount: dosesCount)
        }
        let planByIngredientId = Dictionary(uniqueKeysWithValues: plans.map { ($0.ingredientId, $0) })

        let carrierIngredients = draft.ingredients.filter { ingredient in
            !ingredient.isAd
                && !ingredient.isQS
                && ingredient.unit.rawValue == "g"
                && ingredient.amountValue > 0
                && isCompatibleDefaultDiluentCarrier(ingredient)
        }

        let originalFillerMass = roundInternal(carrierIngredients.reduce(0.0) { partial, ingredient in
            partial + resolvedTotalMassG(for: ingredient, draft: draft, dosesCount: dosesCount)
        })
        let requiredPlans = plans.filter(\.required)
        let requiredTriturationMass = roundInternal(requiredPlans.reduce(0.0) { $0 + $1.totalTriturationMass })
        let requiredTriturationDiluentMass = roundInternal(requiredPlans.reduce(0.0) { $0 + max(0, $1.totalTriturationMass - $1.totalActiveMass) })

        var remainingReplacement = requiredTriturationMass
        var totalPowderBeforeAutoFill = 0.0

        for ingredient in draft.ingredients {
            guard !ingredient.isAd, !ingredient.isQS else { continue }
            guard ingredient.unit.rawValue == "g", ingredient.amountValue > 0 else { continue }

            let totalMass = resolvedTotalMassG(for: ingredient, draft: draft, dosesCount: dosesCount)
            if let plan = planByIngredientId[ingredient.id], plan.required {
                totalPowderBeforeAutoFill += plan.totalTriturationMass
                continue
            }

            if isCompatibleDefaultDiluentCarrier(ingredient), remainingReplacement > 0 {
                let reduction = min(totalMass, remainingReplacement)
                totalPowderBeforeAutoFill += max(0, totalMass - reduction)
                remainingReplacement = roundInternal(remainingReplacement - reduction)
                continue
            }

            totalPowderBeforeAutoFill += totalMass
        }

        totalPowderBeforeAutoFill = roundInternal(totalPowderBeforeAutoFill)
        let requiredTotalMass = roundInternal(max(totalPowderBeforeAutoFill, minimumDoseMassG * Double(dosesCount)))
        let fillerAdded = roundInternal(max(0, requiredTotalMass - totalPowderBeforeAutoFill))
        let totalPowderMass = roundInternal(totalPowderBeforeAutoFill + fillerAdded)
        let doseMass = roundInternal(totalPowderMass / Double(dosesCount))
        let allowedDeviationPercent = PowdersCalculator.allowedDeviationPercentPowder(perDoseG: doseMass)
        let lowerDeviationMass = roundInternal(doseMass * (1.0 - allowedDeviationPercent / 100.0))
        let upperDeviationMass = roundInternal(doseMass * (1.0 + allowedDeviationPercent / 100.0))
        let correctedFillerMass = carrierIngredients.isEmpty ? nil : roundInternal(max(0, originalFillerMass - requiredTriturationMass) + fillerAdded)
        let totalDiluentMass = roundInternal((correctedFillerMass ?? fillerAdded) + requiredTriturationDiluentMass)
        let balancedTotal = roundInternal(doseMass * Double(dosesCount))
        let roundingCorrection = roundInternal(totalPowderMass - balancedTotal)
        let fillerIngredient = carrierIngredients.first

        return PowderTechnologyResult(
            dosesCount: dosesCount,
            triturationPlans: requiredPlans,
            totalActiveMass: roundInternal(plans.reduce(0.0) { $0 + $1.totalActiveMass }),
            correctedFillerMass: correctedFillerMass,
            originalFillerMass: carrierIngredients.isEmpty ? nil : originalFillerMass,
            fillerIngredientName: fillerIngredient.map(displayName),
            fillerIngredientId: fillerIngredient?.id,
            totalDiluentMass: totalDiluentMass,
            totalPowderMass: totalPowderMass,
            doseMass: doseMass,
            fillerAdded: fillerAdded,
            roundingCorrection: roundingCorrection,
            allowedDeviationPercent: allowedDeviationPercent,
            lowerDeviationMass: lowerDeviationMass,
            upperDeviationMass: upperDeviationMass,
            requiresPoreRubbing: !plans.filter(\.required).isEmpty
        )
    }

    private static func resolvePreparationMethod(ingredient: IngredientDraft, draft: ExtempRecipeDraft) -> PoisonPreparationMethod {
        switch draft.formMode {
        case .powders:
            let dosesCount = max(1, draft.numero ?? 1)
            let plan = resolveTrituration(ingredient: ingredient, draft: draft, dosesCount: dosesCount)
            if let ratio = plan.ratio {
                return .trituration(ratio: ratio)
            }
            return .directWeighing
        case .solutions, .drops:
            let totalMassG = resolvedTotalMassG(for: ingredient, draft: draft, dosesCount: max(1, draft.numero ?? 1))
            if totalMassG < microDoseThresholdG {
                return .concentrate(volumeMl: round3(max(1.0, totalMassG * 10.0)))
            }
            return .directWeighing
        case .ointments:
            if WaterSolubilityHeuristics.hasExplicitWaterSolubility(ingredient.refSolubility) {
                return .dissolvedInMinimalVolume(volumeMl: round3(max(0.1, resolvedTotalMassG(for: ingredient, draft: draft, dosesCount: max(1, draft.numero ?? 1)))))
            }
            let totalMassG = resolvedTotalMassG(for: ingredient, draft: draft, dosesCount: max(1, draft.numero ?? 1))
            return .levigation(liquidType: "Vaselinum liquidum", liquidMassG: round3(totalMassG * 0.5))
        case .suppositories:
            return .directWeighing
        case .auto:
            return .directWeighing
        }
    }

    private static func resolveTrituration(
        ingredient: IngredientDraft,
        draft: ExtempRecipeDraft,
        dosesCount: Int
    ) -> TriturationPlan {
        let totalActiveMass = roundInternal(resolvedTotalMassG(for: ingredient, draft: draft, dosesCount: dosesCount))
        let requires = draft.formMode == .powders && (totalActiveMass < microDoseThresholdG || ingredient.refNeedsTrituration)
        guard requires, totalActiveMass > 0 else {
            return TriturationPlan(
                ingredientId: ingredient.id,
                ingredientName: displayName(ingredient),
                required: false,
                ratio: nil,
                totalActiveMass: roundInternal(totalActiveMass),
                totalTriturationMass: roundInternal(totalActiveMass),
                triturationPerDose: roundInternal(totalActiveMass / Double(max(1, dosesCount))),
                diluent: defaultDiluent
            )
        }

        let ratio: Int
        if ingredient.isReferenceListA, draft.formMode == .powders {
            let borderlineMassAtOneToTen = roundInternal(totalActiveMass * 10.0)
            ratio = (totalActiveMass < ultraMicroThresholdG || borderlineMassAtOneToTen <= microDoseThresholdG) ? 100 : 10
        } else {
            ratio = totalActiveMass < ultraMicroThresholdG ? 100 : 10
        }
        let totalTriturationMass = roundInternal(totalActiveMass * Double(ratio))
        let triturationPerDose = roundInternal(totalTriturationMass / Double(max(1, dosesCount)))

        return TriturationPlan(
            ingredientId: ingredient.id,
            ingredientName: displayName(ingredient),
            required: true,
            ratio: ratio,
            totalActiveMass: roundInternal(totalActiveMass),
            totalTriturationMass: roundInternal(totalTriturationMass),
            triturationPerDose: roundInternal(triturationPerDose),
            diluent: defaultDiluent
        )
    }

    private static func validateDose(ingredient: IngredientDraft, draft: ExtempRecipeDraft) -> PoisonDoseValidation {
        let effectiveForm = SignaUsageAnalyzer.effectiveFormMode(for: draft)
        if shouldUseConcentrationControlOnly(ingredient: ingredient, draft: draft, effectiveForm: effectiveForm) {
            return PoisonDoseValidation(
                ingredientId: ingredient.id,
                ingredientName: displayName(ingredient),
                perDoseG: nil,
                perDayG: nil,
                perDoseLimitG: nil,
                perDayLimitG: nil,
                frequencyPerDay: nil,
                isValid: true,
                requiresDoseCount: false,
                requiresNumericAndTextDose: false
            )
        }

        let frequency = parseFrequency(from: draft.signa)
        let perDose = resolvedPerDoseMassG(for: ingredient, draft: draft, effectiveForm: effectiveForm)
        let perDay = perDose.flatMap { dose in
            frequency.map { roundInternal(dose * Double($0)) }
        }
        let perDoseLimit = resolvedPerDoseLimit(ingredient: ingredient, ageYears: draft.patientAgeYears)
        let perDayLimit = resolvedPerDayLimit(ingredient: ingredient, ageYears: draft.patientAgeYears)

        let isValidDose = (perDoseLimit == nil || (perDose ?? 0) <= (perDoseLimit ?? .greatestFiniteMagnitude))
            && (perDayLimit == nil || (perDay ?? 0) <= (perDayLimit ?? .greatestFiniteMagnitude))

        return PoisonDoseValidation(
            ingredientId: ingredient.id,
            ingredientName: displayName(ingredient),
            perDoseG: perDose.map(roundInternal),
            perDayG: perDay.map(roundInternal),
            perDoseLimitG: perDoseLimit.map(roundInternal),
            perDayLimitG: perDayLimit.map(roundInternal),
            frequencyPerDay: frequency,
            isValid: isValidDose,
            requiresDoseCount: effectiveForm == .powders || effectiveForm == .suppositories,
            requiresNumericAndTextDose: true
        )
    }

    private static func shouldUseConcentrationControlOnly(
        ingredient: IngredientDraft,
        draft: ExtempRecipeDraft,
        effectiveForm: FormMode
    ) -> Bool {
        guard effectiveForm == .solutions || effectiveForm == .drops else { return false }
        if NonAqueousSolventCatalog.concentrationControlProfile(for: ingredient)?.isConcentrationControlOnly == true {
            return true
        }
        let semantics = SignaUsageAnalyzer.analyze(signa: draft.signa)
        let s = semantics.normalizedSigna
        let hasEarOrNoseRoute = semantics.isNasalRoute
            || s.contains("вух")
            || s.contains("уха")
            || s.contains("ear")
            || s.contains("otic")
            || s.contains("нос")
        let hasExternalSmearMarker = s.contains("змащ")
            || s.contains("смаз")
            || s.contains("мазати")
            || s.contains("смазыват")
        if semantics.isExternalRoute {
            return true
        }
        return hasEarOrNoseRoute || hasExternalSmearMarker
    }

    private static func resolvedPerDoseMassG(
        for ingredient: IngredientDraft,
        draft: ExtempRecipeDraft,
        effectiveForm: FormMode
    ) -> Double? {
        let dosesCount = max(1, draft.numero ?? 1)
        let signaSemantics = SignaUsageAnalyzer.analyze(signa: draft.signa)
        switch effectiveForm {
        case .powders, .suppositories:
            let total = resolvedTotalMassG(for: ingredient, draft: draft, dosesCount: dosesCount)
            guard total > 0 else { return nil }
            return roundInternal(total / Double(dosesCount))
        case .solutions:
            if signaSemantics.hasDropsDose {
                return resolvedPerDoseMassByDrops(for: ingredient, draft: draft)
            }
            guard let intakeMl = parseSingleLiquidDoseMl(from: draft.signa), intakeMl > 0 else { return nil }
            let totalVolume = max(0, draft.explicitLiquidTargetMl ?? draft.legacyAdOrQsLiquidTargetMl ?? draft.ingredients.reduce(0.0) { $0 + effectiveLiquidMl($1, draft: draft) })
            guard totalVolume > 0 else { return nil }
            let totalMass = inferActiveMassG(for: ingredient, draft: draft)
            guard totalMass > 0 else { return nil }
            return roundInternal(totalMass * intakeMl / totalVolume)
        case .drops:
            return resolvedPerDoseMassByDrops(for: ingredient, draft: draft)
        case .ointments:
            return nil
        case .auto:
            return nil
        }
    }

    private static func resolvedPerDoseMassByDrops(
        for ingredient: IngredientDraft,
        draft: ExtempRecipeDraft
    ) -> Double? {
        guard let dropsPerIntake = parseDropsPerDose(from: draft.signa), dropsPerIntake > 0 else { return nil }
        let totalMass = inferActiveMassG(for: ingredient, draft: draft)
        var totalDrops = draft.ingredients.reduce(0.0) { partial, current in
            if current.isAd || current.isQS { return partial }
            let volume = effectiveLiquidMl(current, draft: draft)
            guard volume > 0, let resolution = DropsAnalysis.resolvedDropsPerMl(for: current, draft: draft) else { return partial }
            return partial + (volume * resolution.value)
        }
        if totalDrops <= 0,
           let totalVolume = resolvedTotalVolumeMlForDropsDoseControl(draft: draft),
           totalVolume > 0,
           let primary = NonAqueousSolventCatalog.primarySolvent(in: draft)
        {
            let ethanolStrength = primary.type == .ethanol
                ? NonAqueousSolventCatalog.requestedEthanolStrength(from: primary.ingredient)
                : nil
            if let gttsPerMl = NonAqueousSolventCatalog.standardDropsPerMl(for: primary.type, ethanolStrength: ethanolStrength),
               gttsPerMl > 0 {
                totalDrops = totalVolume * gttsPerMl
            }
        }
        guard totalMass > 0, totalDrops > 0 else { return nil }
        let doses = max(1.0, floor(totalDrops / dropsPerIntake))
        return roundInternal(totalMass / doses)
    }

    private static func resolvedTotalVolumeMlForDropsDoseControl(draft: ExtempRecipeDraft) -> Double? {
        if let explicit = draft.explicitLiquidTargetMl, explicit > 0 {
            return explicit
        }
        if let legacy = draft.legacyAdOrQsLiquidTargetMl, legacy > 0 {
            return legacy
        }

        let measuredMl = draft.ingredients.reduce(0.0) { partial, ingredient in
            if ingredient.isAd || ingredient.isQS { return partial }
            return partial + effectiveLiquidMl(ingredient, draft: draft)
        }
        if measuredMl > 0 {
            return measuredMl
        }

        guard let primary = NonAqueousSolventCatalog.primarySolvent(in: draft),
              primary.type.isViscous
        else { return nil }

        let density = primary.type == .glycerin
            ? 1.25
            : NonAqueousSolventCatalog.density(for: primary.type, fallback: primary.ingredient?.refDensity)
        guard let density, density > 0 else { return nil }

        let totalMassG = draft.ingredients.reduce(0.0) { partial, ingredient in
            guard !ingredient.isAd, !ingredient.isQS else { return partial }
            guard let mass = ingredientMassGForVolumeEstimate(ingredient, draft: draft, primarySolvent: primary) else { return partial }
            return partial + mass
        }
        guard totalMassG > 0 else { return nil }
        return totalMassG / density
    }

    private static func ingredientMassGForVolumeEstimate(
        _ ingredient: IngredientDraft,
        draft: ExtempRecipeDraft,
        primarySolvent: (ingredient: IngredientDraft?, type: NonAqueousSolventType)?
    ) -> Double? {
        guard ingredient.amountValue > 0 else { return nil }
        let unit = ingredient.unit.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if unit == "g" || unit == "г" {
            return ingredient.amountValue
        }
        if unit == "ml" || unit == "мл" {
            if let density = ingredient.refDensity, density > 0 {
                return ingredient.amountValue * density
            }
            if let primarySolvent,
               primarySolvent.ingredient?.id == ingredient.id
            {
                if primarySolvent.type == .glycerin {
                    return ingredient.amountValue * 1.25
                }
                if let density = NonAqueousSolventCatalog.density(
                    for: primarySolvent.type,
                    fallback: primarySolvent.ingredient?.refDensity
                ), density > 0 {
                    return ingredient.amountValue * density
                }
            }
            if PurifiedWaterHeuristics.isPurifiedWater(ingredient) {
                return ingredient.amountValue
            }
        }

        let inferred = draft.inferredActiveMassG(for: ingredient)
        return inferred > 0 ? inferred : nil
    }

    private static func inferActiveMassG(for ingredient: IngredientDraft, draft: ExtempRecipeDraft) -> Double {
        let inferred = draft.inferredActiveMassG(for: ingredient)
        guard inferred > 0 else { return 0 }
        return roundInternal(inferred)
    }

    private static func resolvedTotalMassG(
        for ingredient: IngredientDraft,
        draft: ExtempRecipeDraft,
        dosesCount: Int
    ) -> Double {
        guard ingredient.unit.rawValue == "g", ingredient.amountValue > 0 else { return 0 }
        switch ingredient.scope {
        case .perDose:
            return roundInternal(ingredient.amountValue * Double(dosesCount))
        case .total:
            return roundInternal(ingredient.amountValue)
        case .auto:
            return draft.powderMassMode == .dispensa
                ? roundInternal(ingredient.amountValue * Double(dosesCount))
                : roundInternal(ingredient.amountValue)
        }
    }

    private static func effectiveLiquidMl(_ ingredient: IngredientDraft, draft: ExtempRecipeDraft) -> Double {
        draft.effectiveLiquidVolumeMl(for: ingredient)
    }

    private static func resolvedPerDoseLimit(ingredient: IngredientDraft, ageYears: Int?) -> Double? {
        if let ageYears {
            if ageYears < 1, let value = ingredient.refVrdChild0_1, value > 0 { return value }
            if ageYears >= 1, ageYears <= 6, let value = ingredient.refVrdChild1_6, value > 0 { return value }
            if ageYears > 6, ageYears <= 14, let value = ingredient.refVrdChild7_14, value > 0 { return value }
            if ageYears <= 14, let value = ingredient.refPedsVrdG, value > 0 { return value }
        }
        if let value = ingredient.refVrdG, value > 0 { return value }
        return nil
    }

    private static func resolvedPerDayLimit(ingredient: IngredientDraft, ageYears: Int?) -> Double? {
        if let ageYears, ageYears <= 14, let value = ingredient.refPedsRdG, value > 0 {
            return value
        }
        if let value = ingredient.refVsdG, value > 0 { return value }
        return nil
    }

    private static func parseFrequency(from signa: String) -> Int? {
        SignaFrequencyParser.frequencyPerDay(from: signa)
    }

    private static func parseSingleLiquidDoseMl(from signa: String) -> Double? {
        let s = signa.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return nil }

        let mlPatterns = [
            "(\\d+(?:[\\.,]\\d+)?)\\s*ml",
            "(\\d+(?:[\\.,]\\d+)?)\\s*мл"
        ]
        for pattern in mlPatterns {
            guard let range = s.range(of: pattern, options: .regularExpression) else { continue }
            let match = String(s[range])
            guard let numRange = match.range(of: "\\d+(?:[\\.,]\\d+)?", options: .regularExpression) else { continue }
            return Double(String(match[numRange]).replacingOccurrences(of: ",", with: "."))
        }

        if s.contains("чайн") || s.contains("teaspoon") { return 5 }
        if s.contains("дес") || s.contains("dessert") { return 10 }
        if s.contains("стол") || s.contains("tablespoon") { return 15 }
        return nil
    }

    private static func parseDropsPerDose(from signa: String) -> Double? {
        let s = signa.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return nil }

        let patterns = [
            "(\\d+(?:[\\.,]\\d+)?)\\s*(?:кап\\.|капель|капля|капли|кап)",
            "(\\d+(?:[\\.,]\\d+)?)\\s*(?:к\\.|к)\\b",
            "(\\d+(?:[\\.,]\\d+)?)\\s*(?:gtts\\.|gtts|gtt\\.|gtt|guttae)"
        ]
        for pattern in patterns {
            guard let range = s.range(of: pattern, options: .regularExpression) else { continue }
            let match = String(s[range])
            guard let numRange = match.range(of: "\\d+(?:[\\.,]\\d+)?", options: .regularExpression) else { continue }
            return Double(String(match[numRange]).replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }

    nonisolated private static func displayName(_ ingredient: IngredientDraft) -> String {
        let name = (ingredient.refNameLatNom ?? ingredient.displayName).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Subst." : name
    }

    private static func isPhenolFamily(_ ingredient: IngredientDraft) -> Bool {
        let hay = [
            ingredient.displayName,
            ingredient.refNameLatNom,
            ingredient.refInnKey
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .joined(separator: " ")

        return hay.contains("phenol")
            || hay.contains("phenolum")
            || hay.contains("acidum carbol")
            || hay.contains("acidi carbol")
            || hay.contains("карбол")
            || hay.contains("фенол")
    }

    private static func isSilverNitrateLike(_ ingredient: IngredientDraft) -> Bool {
        let hay = [
            ingredient.displayName,
            ingredient.refNameLatNom,
            ingredient.refInnKey
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .joined(separator: " ")

        return hay.contains("argenti nitrat")
            || hay.contains("silver nitrate")
            || hay.contains("нітрат срібл")
            || hay.contains("нитрат серебр")
            || hay.contains("ляпіс")
    }

    private static func isCompatibleDefaultDiluentCarrier(_ ingredient: IngredientDraft) -> Bool {
        let hay = [
            ingredient.refNameLatNom,
            ingredient.refInnKey,
            ingredient.displayName
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .joined(separator: " ")

        return hay.contains("sacchar")
            || hay.contains("lactos")
    }

    nonisolated private static func roundInternal(_ value: Double) -> Double {
        (value / internalPrecision).rounded() * internalPrecision
    }

    private static func round3(_ value: Double) -> Double {
        (value / finalPrecision).rounded() * finalPrecision
    }

    private static func format3(_ value: Double) -> String {
        if value == floor(value) { return String(Int(value)) }
        return String(format: "%.3f", value).replacingOccurrences(of: ",", with: ".")
    }
}
