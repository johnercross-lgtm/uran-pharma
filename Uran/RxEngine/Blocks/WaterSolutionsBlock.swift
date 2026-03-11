import Foundation

struct WaterSolutionsBlock: RxProcessingBlock {
    static let blockId = "water_solutions"
    let id = blockId

    private struct OralDoseAnalysisResult {
        var lines: [String]
        var issues: [RxIssue]
    }

    private enum LiquidAdditiveKind {
        case viscous
        case aromaticWater
        case lateAddedActive
        case volatileAqueous
        case aromaticAlcoholic
        case other
    }

    private struct LiquidAdditive {
        let ingredient: IngredientDraft
        let volumeMl: Double
        let kind: LiquidAdditiveKind
    }

    private struct SingleDoseInfo {
        let volumeMl: Double
        let sourceLabel: String
        let spoonKind: SpoonKind?
    }

    private struct SpecialWaterRuleResult {
        var calculationLines: [String]
        var stabilityLines: [String]
        var technologyLines: [String]
        var issues: [RxIssue]
    }

    private enum SpoonKind {
        case teaspoon
        case dessertspoon
        case tablespoon
        case measured
    }

    func apply(context: inout RxPipelineContext) {
        context.routeBranch = "water_solution"
        if shouldBypassForStandardSolutions(context: context) {
            context.calculations["solvent_calculation_mode"] = SolventCalculationMode.pharmacopoeial.rawValue
            return
        }
        let hasPepsin = context.draft.ingredients.contains(where: isPepsin)
        let burette = BuretteSystem.evaluateBurette(draft: context.draft)
        let buretteVolumeMl = burette.totalConcentrateVolumeMl
        let buretteIngredientIds = burette.matchedIngredientIds

        let targetMl = context.facts.inferredLiquidTargetMl ?? 0
        let hasAdOrQs = context.draft.ingredients.contains(where: { $0.isAd || $0.isQS })
        let hasExplicitAdOrQsTarget = context.draft.explicitLiquidTargetMl != nil
            || context.draft.legacyAdOrQsLiquidTargetMl != nil
        let allActiveIngredients = context.draft.ingredients.filter { !$0.isQS && !$0.isAd }
        let primaryAqueousIngredient = primaryAqueousIngredient(in: context.draft)
        let primaryAqueousDisplayName = {
            if allActiveIngredients.contains(where: requiresFreshlyDistilledWater) {
                return "Aqua purificata recenter destillata"
            }
            return primaryAqueousIngredient.map(primaryAqueousName) ?? "Aqua purificata"
        }()
        let inferredTargetAquaIngredientId: UUID? = {
            guard !hasExplicitAdOrQsTarget else { return nil }

            return context.draft.ingredients
                .filter { ing in
                    !ing.isAd
                    && !ing.isQS
                    && ing.unit.rawValue == "ml"
                    && ing.amountValue > 0
                    && isAquaPurificata(ing)
                }
                .max(by: { $0.amountValue < $1.amountValue })?
                .id
        }()
        let inferredTargetSolutionIngredientId: UUID? = {
            guard !hasExplicitAdOrQsTarget else { return nil }
            guard inferredTargetAquaIngredientId == nil else { return nil }

            let candidates = context.draft.ingredients
                .filter { !$0.isAd && !$0.isQS && $0.presentationKind == .solution }
                .compactMap { ing -> (UUID, Double)? in
                    guard let v = context.draft.solutionVolumeMl(for: ing), v > 0 else { return nil }
                    return (ing.id, v)
                }

            return candidates.max(by: { $0.1 < $1.1 })?.0
        }()
        let inferredPrimaryAqueousIngredientId: UUID? = {
            let candidates = context.draft.ingredients
                .filter { ing in
                    !ing.isAd
                    && !ing.isQS
                    && ing.unit.rawValue == "ml"
                    && isPrimaryAqueousLiquid(ing)
                }
            return candidates.max(by: { $0.amountValue < $1.amountValue })?.id
        }()

        let liquidAdditives = collectLiquidAdditives(
            draft: context.draft,
            inferredTargetAquaIngredientId: inferredTargetAquaIngredientId,
            inferredTargetSolutionIngredientId: inferredTargetSolutionIngredientId,
            inferredPrimaryAqueousIngredientId: inferredPrimaryAqueousIngredientId,
            buretteIngredientIds: buretteIngredientIds
        )
        let viscousAdditives = liquidAdditives.filter { $0.kind == .viscous }
        let aromaticWaterAdditives = liquidAdditives.filter { $0.kind == .aromaticWater }
        let lateAddedActiveAdditives = liquidAdditives.filter { $0.kind == .lateAddedActive }
        let volatileAqueousAdditives = liquidAdditives.filter { $0.kind == .volatileAqueous }
        let aromaticAdditives = liquidAdditives.filter { $0.kind == .aromaticAlcoholic }
        let otherAdditives = liquidAdditives.filter { $0.kind == .other }

        let viscousMl = viscousAdditives.reduce(0.0) { $0 + $1.volumeMl }
        let aromaticWaterMl = aromaticWaterAdditives.reduce(0.0) { $0 + $1.volumeMl }
        let lateAddedActiveMl = lateAddedActiveAdditives.reduce(0.0) { $0 + $1.volumeMl }
        let volatileAqueousMl = volatileAqueousAdditives.reduce(0.0) { $0 + $1.volumeMl }
        let aromaticMl = aromaticAdditives.reduce(0.0) { $0 + $1.volumeMl }
        let otherAdditivesMl = otherAdditives.reduce(0.0) { $0 + $1.volumeMl }
        let additiveLiquidsMl = viscousMl + aromaticWaterMl + lateAddedActiveMl + volatileAqueousMl + aromaticMl + otherAdditivesMl

        var otherLiquidsMl = liquidAdditives.map(\.volumeMl)
        if buretteVolumeMl > 0 {
            otherLiquidsMl.append(buretteVolumeMl)
        }
        let solidComponents = context.draft.ingredients.compactMap { ing -> (ingredient: IngredientDraft, weight: Double, kuo: Double?, volumeEffect: Bool)? in
            guard !ing.isAd, !ing.isQS else { return nil }
            if buretteIngredientIds.contains(ing.id) { return nil }
            guard ing.unit.rawValue == "g" else { return nil }
            guard !isLiquidIngredient(ing) else { return nil }
            let explicit = max(0, ing.amountValue)
            if explicit > 0 {
                return (
                    ingredient: ing,
                    weight: explicit,
                    kuo: ing.refKuoMlPerG,
                    volumeEffect: hasVolumeEffectForKuo(ing)
                )
            }

            guard let inferredMass = context.draft.solutionActiveMassG(for: ing), inferredMass > 0 else { return nil }
            guard inferredMass > 0 else { return nil }
            return (
                ingredient: ing,
                weight: inferredMass,
                kuo: ing.refKuoMlPerG,
                volumeEffect: hasVolumeEffectForKuo(ing)
            )
        }
        let solids = solidComponents.map { (weight: $0.weight, kuo: $0.kuo) }
        let derivedSolutionSolidsMass = context.draft.ingredients.reduce(0.0) { partial, ing in
            guard !ing.isAd, !ing.isQS else { return partial }
            guard !buretteIngredientIds.contains(ing.id) else { return partial }
            guard ing.presentationKind == .solution else { return partial }
            guard let inferredMass = context.draft.solutionActiveMassG(for: ing), inferredMass > 0 else { return partial }
            return partial + inferredMass
        }
        let allSolidsCoveredByBurette = context.draft.ingredients
            .filter { ing in
                !ing.isAd
                    && !ing.isQS
                    && ing.unit.rawValue == "g"
                    && ing.amountValue > 0
                    && !isLiquidIngredient(ing)
            }
            .allSatisfy { buretteIngredientIds.contains($0.id) }
        let ignoreKuoForBurette = buretteVolumeMl > 0 && (solidComponents.isEmpty || allSolidsCoveredByBurette)
        if ignoreKuoForBurette {
            context.calculations["ignore_kuo_for_burette"] = "true"
        }
        context.routeBranch = buretteVolumeMl > 0 ? "aqueous_burette_solution" : "aqueous_true_solution"
        context.calculations["solution_branch"] = context.routeBranch

        let solidsPercentPrecalc = targetMl > 0
            ? (solidComponents.reduce(0.0) { $0 + $1.weight } / targetMl) * 100.0
            : 0.0
        let displacementByVolumeEffect = solidComponents.reduce(0.0) { partial, component in
            guard component.volumeEffect else { return partial }
            guard let kuo = component.kuo, kuo > 0 else { return partial }
            return partial + component.weight * kuo
        }
        let hasAnyVolumeEffect = solidComponents.contains { $0.volumeEffect }
        let solventCalculationMode: SolventCalculationMode = {
            if ignoreKuoForBurette || buretteVolumeMl > 0 {
                return .dilution
            }
            if solidsPercentPrecalc <= 3.0 {
                return .qsToVolume
            }
            if hasAnyVolumeEffect && displacementByVolumeEffect >= 0.8 {
                return .kouCalculation
            }
            return .qsToVolume
        }()
        let kuoPolicy: KuoCalculationPolicy = {
            switch solventCalculationMode {
            case .kouCalculation:
                return .forceApply
            case .qsToVolume, .dilution, .pharmacopoeial, .nonAqueous:
                return .forceDisable
            }
        }()
        context.calculations["solvent_calculation_mode"] = solventCalculationMode.rawValue
        context.calculations["volume_effect_displacement_ml"] = format(displacementByVolumeEffect)

        let adResult = PharmaCalculator.calculateAdWater(
            targetVolume: targetMl,
            otherLiquids: otherLiquidsMl,
            solids: solids,
            kuoPolicy: kuoPolicy
        )
        let reportedSolidsWeight = max(adResult.solidsWeight, derivedSolutionSolidsMass)
        let hasCalculatedAd = adResult.targetVolume > 0 && abs(adResult.amountToMeasure - adResult.targetVolume) > 0.0001
        let displayLiquidsMl: Double = {
            if inferredTargetSolutionIngredientId != nil, !context.facts.hasQSorAd, targetMl > 0 {
                return targetMl
            }
            return adResult.componentsVolume
        }()

        let aquaPurificataMlForAd: Double? = adResult.targetVolume > 0 ? adResult.amountToMeasure : nil

        context.calculations["target_ml"] = format(adResult.targetVolume)
        context.calculations["components_ml"] = format(displayLiquidsMl)
        context.calculations["solids_mass_g"] = format(reportedSolidsWeight)
        if buretteVolumeMl > 0 {
            context.calculations["burette_concentrates_ml"] = format(buretteVolumeMl)
        }
        if aromaticWaterMl > 0 {
            context.calculations["aromatic_waters_ml"] = format(aromaticWaterMl)
        }
        if lateAddedActiveMl > 0 {
            context.calculations["late_added_active_liquids_ml"] = format(lateAddedActiveMl)
        }
        if volatileAqueousMl > 0 {
            context.calculations["volatile_aqueous_ml"] = format(volatileAqueousMl)
        }
        if viscousMl > 0 {
            context.calculations["viscous_liquids_ml"] = format(viscousMl)
        }
        if aromaticMl > 0 {
            context.calculations["aromatic_alcoholic_liquids_ml"] = format(aromaticMl)
        }
        if adResult.targetVolume > 0 {
            let solidsPercent = (reportedSolidsWeight / adResult.targetVolume) * 100.0
            context.calculations["solids_percent"] = String(format: "%.2f%%", solidsPercent)
        }
        if adResult.needsKuo && !ignoreKuoForBurette {
            context.calculations["kuo_volume_ml"] = format(adResult.displacementVolume)
        }
        if let aquaPurificataMlForAd {
            context.calculations["primary_aqueous_to_measure_ml"] = format(aquaPurificataMlForAd)
        }

        if adResult.needsKuo && !ignoreKuoForBurette {
            context.addIssue(code: "water.kuo.applied", severity: .info, message: "Застосовано режим розрахунку з урахуванням КУО")
        } else if solventCalculationMode == .qsToVolume, solidsPercentPrecalc > 3.0 {
            context.addIssue(
                code: "water.kuo.adaptive_skip",
                severity: .info,
                message: "КУО не застосовано: обрано режим q.s. ad V за низького об’ємного впливу речовин"
            )
        }
        if adResult.needsKuo && !ignoreKuoForBurette && adResult.missingKuoCount > 0 {
            context.addIssue(
                code: "water.kuo.missing",
                severity: .blocking,
                message: "Для розрахунку ad з урахуванням КУО бракує КУО для \(adResult.missingKuoCount) твердих компонентів"
            )
        }
        if hasAdOrQs, adResult.targetVolume <= 0 {
            context.addIssue(code: "water.target.missing", severity: .blocking, message: "Для розрахунку ad потрібен цільовий обʼєм")
        }
        if hasAdOrQs, adResult.targetVolume > 0, adResult.isImpossible {
            context.addIssue(code: "water.ad.impossible", severity: .blocking, message: "Неможливо довести до об’єму: вода ≤ 0 мл після розрахунку")
        }

        let activeIngredientsForFiltration = allActiveIngredients
        let needsIsotonizingNaCl = activeIngredientsForFiltration.contains(where: requiresNaClIsotonization)
            && !context.draft.ingredients.contains(where: isExplicitNatriiChloridum)
        let hasBoilingDissolution = activeIngredientsForFiltration.contains(where: requiresBoilingWaterDissolution)
        let hasHotDissolution = hasBoilingDissolution || activeIngredientsForFiltration.contains(where: requiresHotWaterDissolution)
        let hasGentleHotDissolution = activeIngredientsForFiltration.contains {
            isEthacridineIngredient($0) || isPapaverineHydrochlorideIngredient($0)
        }
        let dissolutionTargets = dissolutionTargetsPhrase(
            activeIngredients: activeIngredientsForFiltration,
            includeNaCl: needsIsotonizingNaCl
        )

        let measuredAquaPrefix: String? = aquaPurificataMlForAd.map {
            "Відміряти \($0 == floor($0) ? String(Int($0)) : format($0)) ml \(primaryAqueousDisplayName)"
        }
        let shouldDescribePartialSolvent = hasAdOrQs || hasCalculatedAd
        if buretteVolumeMl > 0 {
            let title = measuredAquaPrefix.map { "\($0); після цього послідовно додати бюреточні концентрати та перемішати" }
                ?? "Відміряти розрахований об’єм \(primaryAqueousDisplayName); після цього послідовно додати бюреточні концентрати та перемішати"
            context.addStep(TechStep(kind: .dissolution, title: title))
        } else {
            let title: String
            if hasBoilingDissolution {
                if shouldDescribePartialSolvent {
                    title = "Відміряти частину \(primaryAqueousDisplayName), довести до кипіння, розчинити \(dissolutionTargets)"
                } else {
                    title = measuredAquaPrefix.map { "\($0), довести до кипіння, розчинити \(dissolutionTargets)" }
                        ?? "Відміряти частину \(primaryAqueousDisplayName), довести до кипіння, розчинити \(dissolutionTargets)"
                }
            } else if hasHotDissolution {
                let hotRange = hasGentleHotDissolution ? "70-80°C" : "80-90°C"
                if shouldDescribePartialSolvent {
                    title = "Відміряти частину \(primaryAqueousDisplayName), підігріти до \(hotRange), розчинити \(dissolutionTargets)"
                } else {
                    title = measuredAquaPrefix.map { "\($0), підігріти до \(hotRange), розчинити \(dissolutionTargets)" }
                        ?? "Відміряти частину \(primaryAqueousDisplayName), підігріти до \(hotRange), розчинити \(dissolutionTargets)"
                }
            } else {
                if shouldDescribePartialSolvent {
                    title = "Розчинити \(dissolutionTargets) у частині \(primaryAqueousDisplayName)"
                } else {
                    title = measuredAquaPrefix.map { "\($0) та розчинити \(dissolutionTargets)" }
                        ?? "Відміряти частину \(primaryAqueousDisplayName) та розчинити \(dissolutionTargets)"
                }
            }
            context.addStep(TechStep(kind: .dissolution, title: title))
        }
        if (hasBoilingDissolution || hasHotDissolution), !hasAdOrQs, !hasCalculatedAd {
            context.addStep(
                TechStep(
                    kind: .bringToVolume,
                    title: "Після нагрівання/проціджування компенсувати втрати на випаровування гарячою Aqua purificata та перевірити відповідність кінцевого об’єму",
                    isCritical: true
                )
            )
        }

        let shouldCottonFilter = hasPepsin
            || !solidComponents.isEmpty
            || !aromaticWaterAdditives.isEmpty
            || !volatileAqueousAdditives.isEmpty
            || hasBoilingDissolution
            || hasHotDissolution
            || context.draft.ingredients.contains(where: isPrimaryAromaticWater)
        if context.facts.needsFiltration || shouldCottonFilter {
            let useOptionalFiltration = shouldUseOptionalFiltrationForSimpleSolution(
                activeIngredients: activeIngredientsForFiltration,
                hasBoilingDissolution: hasBoilingDissolution,
                hasHotDissolution: hasHotDissolution,
                hasPepsin: hasPepsin,
                hasLateAddedLiquids: !aromaticWaterAdditives.isEmpty
                    || !lateAddedActiveAdditives.isEmpty
                    || !volatileAqueousAdditives.isEmpty
                    || !aromaticAdditives.isEmpty
                    || !viscousAdditives.isEmpty,
                usesBurette: buretteVolumeMl > 0
            )
            let title: String = useOptionalFiltration
                ? "За потреби процідити крізь пухкий ватний тампон для видалення механічних домішок"
                : preferredFiltrationTechnologyLine(
                    activeIngredients: activeIngredientsForFiltration,
                    shouldCottonFilter: shouldCottonFilter,
                    needsFiltration: context.facts.needsFiltration
                )
            context.addStep(TechStep(kind: .filtration, title: title, isCritical: useOptionalFiltration ? false : (hasPepsin || shouldCottonFilter)))
        }
        if !aromaticWaterAdditives.isEmpty {
            context.addStep(
                TechStep(
                    kind: .mixing,
                    title: "Додати ароматні води після проціджування без нагрівання; підтримувати прохолодний режим",
                    isCritical: true
                )
            )
        }
        if !viscousAdditives.isEmpty {
            context.addStep(
                TechStep(
                    kind: .mixing,
                    title: "Додати в’язкі рідини (сиропи/гліцерин) після проціджування та перемішати"
                )
            )
        }
        if !lateAddedActiveAdditives.isEmpty {
            context.addStep(
                TechStep(
                    kind: .mixing,
                    title: "Додати готові рідкі активні препарати після проціджування: \(describeLiquidAdditives(lateAddedActiveAdditives))",
                    isCritical: true
                )
            )
        }
        if !volatileAqueousAdditives.isEmpty {
            context.addStep(
                TechStep(
                    kind: .mixing,
                    title: "Додати леткі ароматні/антисептичні води в останню чергу без інтенсивного збовтування",
                    isCritical: true
                )
            )
        }
        if !aromaticAdditives.isEmpty {
            let hasPremixDrops = aromaticAdditives.contains { requiresPremixWithMixture($0.ingredient) }
            context.addStep(
                TechStep(
                    kind: .mixing,
                    title: hasPremixDrops
                        ? "Спиртові ароматичні краплі попередньо змішати 1:1-1:2 з частиною готової мікстури, потім внести у флакон"
                        : "Додати настойки/спиртовмісні рідини у відпускний флакон в останню чергу та перемішати",
                    isCritical: true
                )
            )
        }
        if hasAdOrQs {
            if !aromaticAdditives.isEmpty, adResult.targetVolume > 0 {
                context.addStep(
                    TechStep(
                        kind: .bringToVolume,
                        title: "Перевірити кінцевий об’єм мікстури: має бути \(format(adResult.targetVolume)) ml",
                        isCritical: true
                    )
                )
            } else {
                if adResult.targetVolume > 0 {
                    context.addStep(
                        TechStep(
                            kind: .bringToVolume,
                            title: "Довести \(primaryAqueousDisplayName) до \(format(adResult.targetVolume)) ml (ad V)",
                            isCritical: true
                        )
                    )
                } else {
                    context.addStep(TechStep(kind: .bringToVolume, title: "Довести \(primaryAqueousDisplayName) до заданого об’єму (ad V)", isCritical: true))
                }
            }
        } else if hasCalculatedAd, buretteVolumeMl <= 0 {
            if !aromaticAdditives.isEmpty, adResult.targetVolume > 0 {
                context.addStep(
                    TechStep(
                        kind: .bringToVolume,
                        title: "Перевірити кінцевий об’єм мікстури: має бути \(format(adResult.targetVolume)) ml",
                        isCritical: true
                    )
                )
            } else {
                context.addStep(TechStep(kind: .bringToVolume, title: "За потреби перевірити та скоригувати об’єм розчину до розрахованого", isCritical: true))
            }
        }

        var calc: [String] = []
        if adResult.targetVolume > 0 {
            calc.append("Vtarget = \(format(adResult.targetVolume)) ml")
        }
        if buretteVolumeMl > 0 {
            calc.append("Σ(бюреточні концентрати) = \(format(buretteVolumeMl)) ml")
        }
        if viscousMl > 0 {
            calc.append("Σ(в’язкі рідини: сиропи/гліцерин) = \(format(viscousMl)) ml")
        }
        if aromaticMl > 0 {
            calc.append("Σ(настойки/спиртовмісні рідини) = \(format(aromaticMl)) ml")
        }
        if otherAdditivesMl > 0 {
            calc.append("Σ(інші рідкі компоненти) = \(format(otherAdditivesMl)) ml")
        }
        calc.append("Σ(рідини, крім ad) = \(format(adResult.componentsVolume)) ml")
        calc.append("Σ(тверді) = \(format(reportedSolidsWeight)) g")
        if adResult.targetVolume > 0 {
            let solidsPercent = (reportedSolidsWeight / adResult.targetVolume) * 100.0
            calc.append("\(format(reportedSolidsWeight)) / \(format(adResult.targetVolume)) × 100% = \(format(solidsPercent))%")
            if ignoreKuoForBurette {
                calc.append("Компоненти вводяться у вигляді концентрованих розчинів; КУО для них не застосовують")
            } else {
                switch solventCalculationMode {
                case .kouCalculation:
                    calc.append("Кількість розчинника розрахована з урахуванням КУО")
                case .qsToVolume:
                    calc.append("КУО не враховується (режим доведення q.s. ad V)")
                case .dilution:
                    calc.append("Режим розрахунку: розведення концентрованих розчинів")
                case .pharmacopoeial:
                    calc.append("Режим розрахунку: використання стандартного фармакопейного розчину")
                case .nonAqueous:
                    calc.append("Режим розрахунку: неводний розчин (КУО не застосовується)")
                }
            }
        }
        if adResult.needsKuo && !ignoreKuoForBurette {
            calc.append("ΣКУО = \(format(adResult.displacementVolume)) ml")
            for comp in solidComponents {
                guard let kuo = comp.kuo, kuo > 0 else { continue }
                let name = comp.ingredient.displayName.isEmpty ? "Subst." : comp.ingredient.displayName
                calc.append("КУО: \(name) — \(format(comp.weight)) × \(format(kuo)) = \(format(comp.weight * kuo)) ml")
            }
        }
        if aromaticWaterMl > 0 {
            calc.append("Σ(ароматні води) = \(format(aromaticWaterMl)) ml")
        }
        if lateAddedActiveMl > 0 {
            calc.append("Σ(готові рідкі активні препарати) = \(format(lateAddedActiveMl)) ml")
        }
        if volatileAqueousMl > 0 {
            calc.append("Σ(леткі ароматні/антисептичні води) = \(format(volatileAqueousMl)) ml")
        }
        if let aquaPurificataMlForAd {
            if hasAdOrQs, adResult.targetVolume > 0 {
                if solventCalculationMode == .kouCalculation {
                    calc.append("\(primaryAqueousDisplayName) ≈ \(format(aquaPurificataMlForAd)) ml")
                    calc.append("q.s. ad \(format(adResult.targetVolume)) ml")
                } else {
                    if abs(aquaPurificataMlForAd - adResult.targetVolume) <= 0.0001 {
                        calc.append("\(primaryAqueousDisplayName) q.s. ad \(format(adResult.targetVolume)) ml")
                    } else {
                        calc.append("\(primaryAqueousDisplayName) = \(format(aquaPurificataMlForAd)) ml (q.s. ad \(format(adResult.targetVolume)) ml)")
                    }
                }
            } else {
                calc.append("\(primaryAqueousDisplayName) = \(format(aquaPurificataMlForAd)) ml")
            }
            if adResult.targetVolume > 0 {
                if !hasAdOrQs, buretteVolumeMl > 0 {
                    if let buretteEquation = waterEquationLine(
                        primaryAqueousName: primaryAqueousDisplayName,
                        targetVolume: adResult.targetVolume,
                        liquidComponents: buretteVolumeMl + additiveLiquidsMl,
                        displacementVolume: ignoreKuoForBurette ? 0 : adResult.displacementVolume,
                        result: aquaPurificataMlForAd
                    ) {
                        calc.append(buretteEquation)
                    }
                } else if !hasAdOrQs, let commonEquation = waterEquationLine(
                    primaryAqueousName: primaryAqueousDisplayName,
                    targetVolume: adResult.targetVolume,
                    liquidComponents: adResult.componentsVolume,
                    displacementVolume: adResult.displacementVolume,
                    result: aquaPurificataMlForAd
                ) {
                    calc.append(commonEquation)
                }
            }
        }

        if solventCalculationMode == .kouCalculation, adResult.targetVolume > 0 {
            let hasQsAdLine = calc.contains { $0.lowercased().contains("q.s. ad") }
            if !hasQsAdLine {
                calc.append("q.s. ad \(format(adResult.targetVolume)) ml")
                context.addIssue(
                    code: "water.kuo.qs_added",
                    severity: .warning,
                    message: "Для режиму з КУО автоматично додано рядок q.s. ad до кінцевого об’єму."
                )
            }
        }

        let doseChecks = buildOralDoseChecks(context: context, totalVolumeMl: adResult.targetVolume)
        if !doseChecks.issues.isEmpty {
            context.issues.append(contentsOf: doseChecks.issues)
        }

        let activeIngredients = context.draft.ingredients.filter { !$0.isQS && !$0.isAd }
        let salicylateStability = sodiumSalicylateStabilityNotes(context: context)
        let catalogStability = catalogStabilityNotes(context: context)
        let bicarbonateStability = bicarbonateAndHexamineStabilityNotes(context: context)
        let tweenSpanCompatibility = tweenSpanCompatibilityNotes(context: context)
        let aromaticIssues = aromaticVolatileNotes(context: context, solidsPercent: adResult.targetVolume > 0 ? (reportedSolidsWeight / adResult.targetVolume) * 100.0 : nil)
        let specialRules = specialWaterRules(context: context, targetVolumeMl: adResult.targetVolume)
        let stabilityIssues = salicylateStability.issues
            + catalogStability.issues
            + bicarbonateStability.issues
            + tweenSpanCompatibility.issues
            + aromaticIssues.issues
            + specialRules.issues
        if !stabilityIssues.isEmpty {
            context.issues.append(contentsOf: stabilityIssues)
        }
        if !specialRules.calculationLines.isEmpty {
            calc.append(contentsOf: specialRules.calculationLines)
        }

        context.appendSection(title: "Розрахунки", lines: calc.isEmpty ? ["—"] : calc)
        if !doseChecks.lines.isEmpty {
            context.appendSection(title: "Контроль доз", lines: doseChecks.lines)
        }
        let stabilityLines = salicylateStability.lines
            + catalogStability.lines
            + bicarbonateStability.lines
            + tweenSpanCompatibility.lines
            + aromaticIssues.lines
            + specialRules.stabilityLines
        let normalizedStabilityLines: [String] = {
            if !stabilityLines.isEmpty {
                return stabilityLines
            }
            return ["Розчин стабільний у водному середовищі."]
        }()
        if !normalizedStabilityLines.isEmpty {
            context.appendSection(title: "Стабільність", lines: normalizedStabilityLines)
        }
        let technologyLines: [String] = {
            var raw: [String] = []
            let buretteBlockRendered = context.calculations["burette_block_rendered"] == "true"
            raw.append("Підготувати робоче місце, посуд, мірний циліндр, фільтр за потреби")

            if buretteVolumeMl > 0 {
                let waterLineAmount = aquaPurificataMlForAd.map { "\(format($0)) ml" } ?? "розрахований об’єм"
                let buretteDetails = burette.items
                    .map { "\($0.concentrate.titleRu) — \(format($0.concentrateVolumeMl)) ml" }
                    .joined(separator: "; ")
                raw.append("Відміряти \(waterLineAmount) \(primaryAqueousDisplayName) у відпускний флакон")
                if buretteBlockRendered {
                    raw.append("Компоненти внесені через бюреточні концентрати згідно блоку бюреточної системи")
                } else {
                    raw.append(
                        buretteDetails.isEmpty
                            ? "Додати бюреточні концентрати у розрахованих об’ємах та перемішати"
                            : "Додати бюреточні концентрати: \(buretteDetails)"
                    )
                }
            } else {
                raw.append("Відміряти \(primaryAqueousDisplayName) у розрахованому об’ємі")
                raw.append("Розчинити компоненти у первинному водному розчиннику у технологічному порядку")
            }

            if context.facts.needsFiltration || shouldCottonFilter {
                raw.append(
                    preferredFiltrationTechnologyLine(
                        activeIngredients: activeIngredients,
                        shouldCottonFilter: shouldCottonFilter,
                        needsFiltration: context.facts.needsFiltration
                    )
                )
            }
            raw.append(contentsOf: specialRules.technologyLines)

            if context.draft.ingredients.contains(where: isPrimaryAromaticWater) {
                raw.append("Ароматну воду використовувати як готовий водний розчин ефірної олії 1:1000; очищену воду окремо не додавати.")
                raw.append("Не нагрівати. Якщо при відновленні концентрату виникає різка мутність, допускається фільтрація через змочений водою паперовий фільтр; у робочій технології мікстури проціджування виконувати через вату.")
            }
            if !aromaticWaterAdditives.isEmpty {
                raw.append("Додати ароматні води після проціджування основного розчину: \(describeLiquidAdditives(aromaticWaterAdditives))")
            }
            if !viscousAdditives.isEmpty {
                raw.append("Додати в’язкі рідини (сиропи/гліцерин): \(describeLiquidAdditives(viscousAdditives))")
            }
            if !lateAddedActiveAdditives.isEmpty {
                raw.append("Додати готові рідкі активні препарати після проціджування: \(describeLiquidAdditives(lateAddedActiveAdditives))")
            }
            if !volatileAqueousAdditives.isEmpty {
                raw.append("Додати леткі ароматні/антисептичні води без інтенсивного збовтування: \(describeLiquidAdditives(volatileAqueousAdditives))")
            }
            if !aromaticAdditives.isEmpty {
                let line: String
                if aromaticAdditives.contains(where: { requiresPremixWithMixture($0.ingredient) }) {
                    line = "Спиртові ароматичні краплі попередньо змішати з частиною готової мікстури 1:1-1:2, потім ввести: \(describeLiquidAdditives(aromaticAdditives))"
                } else {
                    line = "Додати настойки/спиртовмісні рідини в останню чергу: \(describeLiquidAdditives(aromaticAdditives))"
                }
                raw.append(line)
            }
            if let heatingLine = gentleHeatingTechnologyLine(context: context) {
                raw.append(heatingLine)
            }
            if hasHeatSensitiveVolatileComponents(context: context) {
                raw.append("Леткі компоненти не нагрівати; змішування проводити при кімнатній температурі.")
            }
            if let acidLine = acidSensitiveTechnologyLine(context: context) {
                raw.append(acidLine)
            }
            if let alkaliLine = alkaliSensitiveTechnologyLine(context: context) {
                raw.append(alkaliLine)
            }
            if let glycerinPhLine = glycerinPhShiftTechnologyLine(context: context) {
                raw.append(glycerinPhLine)
            }
            if let bicarbonateLine = bicarbonateTechnologyLine(context: context) {
                raw.append(bicarbonateLine)
            }
            if activeIngredients.contains(where: { $0.refSterile }) {
                raw.append("Готувати асептично; відпускати у стерильній тарі з мінімізацією ризику мікробної контамінації.")
            }

            if hasAdOrQs {
                raw.append("Розчинити у частині розчинника, після чого довести до заданого об'єму")
            } else if buretteVolumeMl > 0 {
                raw.append("Спочатку відміряти основний об’єм Aqua purificata у флакон відпуску, далі послідовно додати бюреточні концентрати у розрахованих об’ємах і перемішати")
            } else if !hasCalculatedAd {
                raw.append("Об’єм прийнято за рецептом без ad")
            }

            if hasBoilingDissolution || hasHotDissolution {
                raw.append("Охолодити розчин перед відпуском до кімнатної температури")
            }

            return raw.enumerated().map { "\($0.offset + 1). \($0.element)" }
        }()
        context.appendSection(title: "Технологія", lines: technologyLines)

        var qualityLines: [String] = ["Прозорість", "Відсутність механічних включень", "Відповідність об’єму"]
        if hasPepsin {
            qualityLines.append("Допускається слабка опалесценція (білкова природа пепсину)")
        }
        if context.draft.ingredients.contains(where: isPrimaryAromaticWater),
           !aromaticAdditives.isEmpty
        {
            qualityLines.append("Допускається легка опалесценція після додавання настойок/спиртовмісних компонентів")
        }
        if buretteVolumeMl > 0 {
            qualityLines.append("Опис: прозора рідина без механічних включень")
        }
        context.appendSection(title: "Контроль якості", lines: qualityLines)

        let needsDarkGlass = DropsAnalysis.requiresDarkGlass(draft: context.draft)
        let defaultRouteLabel = routeLabelForSpecialAqueousSolutions(
            signa: context.draft.signa,
            defaultLabel: "Внутрішнє"
        )
        var packagingLines: [String] = [
            "Флакон",
            "Етикетка: «\(defaultRouteLabel)»"
        ]
        if defaultRouteLabel == "Внутрішнє" {
            packagingLines.append("Зберігати у прохолодному місці")
        }
        if hasPepsin {
            packagingLines = [
                "Флакон з оранжевого скла",
                "Зберігати у холодильнику (2–8°C)",
                "Термін придатності: 10 діб",
                "Етикетки: «Внутрішнє», «Зберігати в прохолодному та захищеному від світла місці», «Перед вживанням збовтувати»"
            ]
        } else if let specialPackaging = specialWaterPackagingLines(
            activeIngredients: activeIngredients,
            signa: context.draft.signa
        ) {
            packagingLines = specialPackaging
        } else if context.draft.ingredients.contains(where: isVolatileAqueousLiquid)
            || context.draft.ingredients.contains(where: requiresPremixWithMixture)
            || context.draft.ingredients.contains(where: isPrimaryAromaticWater)
        {
            packagingLines = [
                "Флакон з темного скла",
                "Щільно закоркувати / герметичний ковпачок",
                "Зберігати в прохолодному та захищеному від світла місці",
                context.draft.ingredients.contains(where: isPrimaryAromaticWater)
                    ? "Для ароматних вод: CoolPlace (8-15°C)"
                    : "Уникати нагрівання під час зберігання"
            ]
        } else if buretteVolumeMl > 0 {
            packagingLines = [
                needsDarkGlass ? "Флакон з темного скла" : "Флакон відповідної місткості",
                "Етикетка: «Внутрішнє»",
                "Зберігати в прохолодному та захищеному від світла місці",
                "Термін придатності: 2 доби (або до 10 діб у холодильнику, якщо це дозволено локальними НД)"
            ]
        } else if needsDarkGlass {
            packagingLines = [
                "Флакон з оранжевого скла",
                "Етикетка та умови зберігання",
                "Зберігати в захищеному від світла місці"
            ]
        }

        if activeIngredients.contains(where: isEthacridineIngredient) {
            if !packagingLines.contains(where: { line in
                let l = line.lowercased()
                return l.contains("темного") || l.contains("оранжевого")
            }) {
                if packagingLines.isEmpty {
                    packagingLines.append("Флакон з темного (оранжевого) скла")
                } else {
                    packagingLines[0] = "Флакон з темного (оранжевого) скла"
                }
            }
            if !packagingLines.contains(where: { $0.lowercased().contains("берегти від світла") }) {
                packagingLines.append("Берегти від світла")
            }
            packagingLines.append("Попередження: етакридину лактат забарвлює шкіру та обладнання; працювати в рукавичках")
        }

        if activeIngredients.contains(where: isBoricAcidIngredient) {
            packagingLines.append("Зберігати в недоступному для дітей місці")
        }
        if activeIngredients.contains(where: isFuracilinIngredient) {
            packagingLines.append("Берегти від дітей")
        }
        if activeIngredients.contains(where: isIodideIngredient)
            || activeIngredients.contains(where: isStableHalideWithoutExplicitPhotolability)
        {
            packagingLines.append("Берегти від дітей")
        }
        if activeIngredients.contains(where: { $0.refSterile }) {
            if !packagingLines.contains(where: { $0.lowercased().contains("стериль") }) {
                if packagingLines.isEmpty {
                    packagingLines.append("Стерильний флакон/контейнер для відпуску")
                } else {
                    packagingLines[0] = "Стерильний флакон/контейнер для відпуску"
                }
            }
            packagingLines.append("Етикетки: «Приготовлено асептично», «Зберігати в прохолодному місці»")
        }

        let sanitizedPackagingLines = sanitizePackagingClaimsWithoutEvidence(
            packagingLines,
            activeIngredients: activeIngredients
        )
        if sanitizedPackagingLines.count < packagingLines.count {
            context.addIssue(
                code: "water.packaging.unsupported_storage_removed",
                severity: .warning,
                message: "Видалено непідтверджені спеціальні умови зберігання/тари без явної довідкової підстави."
            )
        }
        context.appendSection(title: "Упаковка/Маркування", lines: deduplicatedLines(sanitizedPackagingLines))
    }

    private func shouldBypassForStandardSolutions(context: RxPipelineContext) -> Bool {
        guard context.draft.useStandardSolutionsBlock else { return false }
        let repo = StandardSolutionsRepository.shared

        func parsePercent(from text: String) -> Double? {
            let s = text.replacingOccurrences(of: ",", with: ".")
            guard let r = s.range(of: "(\\d{1,2}(?:\\.\\d+)?)\\s*%", options: .regularExpression) else { return nil }
            let m = String(s[r]).replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(m)
        }

        let matches: [IngredientDraft] = context.draft.ingredients.compactMap { ing in
            guard !ing.isQS, !ing.isAd else { return nil }
            let explicitPercent = context.draft.solutionDisplayPercent(for: ing)
                ?? parsePercent(from: ing.refNameLatNom ?? ing.displayName)
            if context.draft.standardSolutionSourceKey != nil, ing.presentationKind == .solution {
                return ing
            }
            guard repo.matchIngredient(ing, parsedPercent: explicitPercent) != nil else { return nil }
            return ing
        }
        guard !matches.isEmpty else { return false }

        let hasOtherSolids = context.draft.ingredients.contains { ing in
            guard !ing.isQS, !ing.isAd else { return false }
            if matches.contains(where: { $0.id == ing.id }) { return false }
            guard ing.unit.rawValue == "g", ing.amountValue > 0 else { return false }
            return !isLiquidIngredient(ing)
        }
        if hasOtherSolids { return false }

        let hasOtherNonWaterLiquids = context.draft.ingredients.contains { ing in
            guard !ing.isQS, !ing.isAd else { return false }
            if matches.contains(where: { $0.id == ing.id }) { return false }
            if PurifiedWaterHeuristics.isPurifiedWater(ing) { return false }
            if isPrimaryAqueousLiquid(ing) { return false }
            return ing.unit.rawValue == "ml" || ing.presentationKind == .solution
        }
        return !hasOtherNonWaterLiquids
    }

    private func buildOralDoseChecks(context: RxPipelineContext, totalVolumeMl: Double) -> OralDoseAnalysisResult {
        let signa = context.draft.signa.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !signa.isEmpty else { return OralDoseAnalysisResult(lines: [], issues: []) }
        let routeLabel = routeLabelForSpecialAqueousSolutions(signa: signa, defaultLabel: "Внутрішнє")
        if routeLabel != "Внутрішнє" {
            return OralDoseAnalysisResult(
                lines: ["ℹ Дозовий контроль разового прийому (ml/ложка) не застосовується для зовнішнього застосування."],
                issues: []
            )
        }

        guard let singleDose = parseSingleDoseInfo(from: signa), singleDose.volumeMl > 0 else {
            return OralDoseAnalysisResult(
                lines: ["⚠ Не вдалося визначити об’єм разового прийому зі Signa (ml/ложка)"],
                issues: []
            )
        }

        guard totalVolumeMl > 0 else {
            return OralDoseAnalysisResult(
                lines: ["⚠ Не вдалося визначити загальний об’єм для контролю доз"],
                issues: []
            )
        }

        let frequency = parseFrequency(from: signa)
        let singleDoseMl = singleDose.volumeMl
        let dosesCount = totalVolumeMl / singleDoseMl
        var lines: [String] = [
            "Разовий прийом: \(singleDose.sourceLabel) = \(format(singleDoseMl)) ml",
            "Кількість прийомів у всьому об’ємі: \(format(totalVolumeMl)) / \(format(singleDoseMl)) = \(String(format: "%.2f", dosesCount))",
            "Кратність: \(frequency) р/добу"
        ]
        var issues: [RxIssue] = []
        var hasAnalyzedIngredients = false

        if context.draft.patientAgeYears == nil {
            switch singleDose.spoonKind {
            case .teaspoon?, .dessertspoon?:
                lines.append("⚠ Вік пацієнта не вказано: для дорослих мікстур частіше використовують столову ложку (15 ml), перевірте Signa")
            default:
                break
            }
        }
        if context.draft.patientAgeYears != nil, hasIodideIngredient(context.draft.ingredients) {
            lines.append("ℹ Для йодидів дитячий дозовий контроль є критичним; розрахунок виконано з урахуванням вказаного віку")
        } else if context.draft.patientAgeYears == nil, hasIodideIngredient(context.draft.ingredients) {
            let msg = "Для препаратів йодидів бажано вказати вік пацієнта для коректної оцінки дитячих доз"
            lines.append("⚠ \(msg)")
            issues.append(RxIssue(code: "solution.age.missingForIodides", severity: .warning, message: msg))
        }

        for ing in context.draft.ingredients {
            if ing.isQS || ing.isAd { continue }

            let perDoseLimit = resolvedPerDoseLimit(ingredient: ing, ageYears: context.draft.patientAgeYears)
            let perDayLimit = resolvedPerDayLimit(ingredient: ing, ageYears: context.draft.patientAgeYears)
            let hasRegistryRestriction = ing.isReferenceListB || ing.refIsNarcotic
            let hasLimits = perDoseLimit != nil || perDayLimit != nil
            guard hasRegistryRestriction || hasLimits else { continue }

            var tags: [String] = []
            if ing.isReferenceListA { tags.append("List A") }
            if ing.isReferenceListB { tags.append("List B") }
            if ing.refIsNarcotic { tags.append("Narcotic") }
            let suffix = tags.isEmpty ? "" : " [\(tags.joined(separator: ", "))]"
            if shouldDoseByVolume(ing),
               let totalVolume = totalDoseVolumeMl(for: ing, draft: context.draft),
               totalVolume > 0
            {
                hasAnalyzedIngredients = true

                let perDoseMl = totalVolume * (singleDoseMl / totalVolumeMl)
                let perDayMl = perDoseMl * Double(frequency)
                var line = "— \(ing.displayName)\(suffix): на 1 прийом \(String(format: "%.3f", perDoseMl)) ml; на добу \(String(format: "%.3f", perDayMl)) ml"
                if let approxDrops = approximateDrops(for: ing, volumeMl: perDoseMl) {
                    line += " (≈ \(approxDrops) gtt)"
                }
                lines.append(line)

                if isAdonisidum(ing) {
                    lines.append("ℹ Для \(ing.displayName) контроль виведено у ml як для готового рідкого серцевого глікозиду.")
                }

                if let perDoseLimit, perDoseMl > perDoseLimit.value {
                    let msg = "ПЕРЕВИЩЕННЯ ВРД (\(perDoseLimit.label)) для \(ing.displayName): \(String(format: "%.3f", perDoseMl)) ml > \(format(perDoseLimit.value)) ml"
                    lines.append("❌ \(msg)")
                    issues.append(RxIssue(code: "solution.vrd.exceeded.\(ing.id)", severity: .blocking, message: msg))
                }

                if let perDayLimit, perDayMl > perDayLimit.value {
                    let msg = "ПЕРЕВИЩЕННЯ ВСД (\(perDayLimit.label)) для \(ing.displayName): \(String(format: "%.3f", perDayMl)) ml > \(format(perDayLimit.value)) ml"
                    lines.append("❌ \(msg)")
                    issues.append(RxIssue(code: "solution.vsd.exceeded.\(ing.id)", severity: .blocking, message: msg))
                }
                continue
            }

            guard let totalMassG = totalMassG(for: ing, draft: context.draft), totalMassG > 0 else { continue }
            hasAnalyzedIngredients = true

            let perDoseG = totalMassG * (singleDoseMl / totalVolumeMl)
            let perDayG = perDoseG * Double(frequency)
            lines.append("— \(ing.displayName)\(suffix): на 1 прийом \(String(format: "%.4f", perDoseG)) g; на добу \(String(format: "%.4f", perDayG)) g")

            if let perDoseLimit, perDoseG > perDoseLimit.value {
                let msg = "ПЕРЕВИЩЕННЯ ВРД (\(perDoseLimit.label)) для \(ing.displayName): \(String(format: "%.4f", perDoseG)) > \(format(perDoseLimit.value))"
                lines.append("❌ \(msg)")
                issues.append(RxIssue(code: "solution.vrd.exceeded.\(ing.id)", severity: .blocking, message: msg))
            }

            if let perDayLimit, perDayG > perDayLimit.value {
                let msg = "ПЕРЕВИЩЕННЯ ВСД (\(perDayLimit.label)) для \(ing.displayName): \(String(format: "%.4f", perDayG)) > \(format(perDayLimit.value))"
                lines.append("❌ \(msg)")
                issues.append(RxIssue(code: "solution.vsd.exceeded.\(ing.id)", severity: .blocking, message: msg))
            }
        }

        if !hasAnalyzedIngredients {
            lines.append("ℹ Для дозового контролю бракує довідкових меж у поточному складі")
        }

        return OralDoseAnalysisResult(lines: lines, issues: issues)
    }

    private func parseSingleDoseInfo(from signa: String) -> SingleDoseInfo? {
        let s = signa.lowercased()

        if let qty = firstMatchNumber(
            in: s,
            patterns: ["(\\d+(?:[\\.,]\\d+)?)\\s*(?:десерт\\w*\\s*ложк\\w*|дес\\.?\\s*л\\.?)"]
        ) {
            return SingleDoseInfo(volumeMl: qty * 10.0, sourceLabel: "десертна ложка", spoonKind: .dessertspoon)
        }
        if let qty = firstMatchNumber(
            in: s,
            patterns: ["(\\d+(?:[\\.,]\\d+)?)\\s*(?:чайн\\w*\\s*ложк\\w*|ч\\.\\s*л\\.?)"]
        ) {
            return SingleDoseInfo(volumeMl: qty * 5.0, sourceLabel: "чайна ложка", spoonKind: .teaspoon)
        }
        if let qty = firstMatchNumber(
            in: s,
            patterns: ["(\\d+(?:[\\.,]\\d+)?)\\s*(?:столов\\w*\\s*ложк\\w*|ст\\.\\s*л\\.?)"]
        ) {
            return SingleDoseInfo(volumeMl: qty * 15.0, sourceLabel: "столова ложка", spoonKind: .tablespoon)
        }
        if let qty = firstMatchNumber(
            in: s,
            patterns: ["(\\d+(?:[\\.,]\\d+)?)\\s*(?:dessert\\s*spoon(?:s)?|dsp)"]
        ) {
            return SingleDoseInfo(volumeMl: qty * 10.0, sourceLabel: "dessert spoon", spoonKind: .dessertspoon)
        }
        if let qty = firstMatchNumber(
            in: s,
            patterns: ["(\\d+(?:[\\.,]\\d+)?)\\s*(?:teaspoon(?:s)?|tsp)"]
        ) {
            return SingleDoseInfo(volumeMl: qty * 5.0, sourceLabel: "teaspoon", spoonKind: .teaspoon)
        }
        if let qty = firstMatchNumber(
            in: s,
            patterns: ["(\\d+(?:[\\.,]\\d+)?)\\s*(?:tablespoon(?:s)?|tbsp)"]
        ) {
            return SingleDoseInfo(volumeMl: qty * 15.0, sourceLabel: "tablespoon", spoonKind: .tablespoon)
        }
        if let qty = firstMatchNumber(in: s, patterns: ["(\\d+(?:[\\.,]\\d+)?)\\s*(?:мл|ml)"]) {
            return SingleDoseInfo(volumeMl: qty, sourceLabel: "мірний об’єм", spoonKind: .measured)
        }
        return nil
    }

    private func parseFrequency(from signa: String) -> Int {
        SignaFrequencyParser.frequencyPerDay(from: signa) ?? 1
    }

    private func firstMatchNumber(in source: String, patterns: [String]) -> Double? {
        for pattern in patterns {
            guard let r = source.range(of: pattern, options: .regularExpression) else { continue }
            let match = String(source[r])
            guard let numR = match.range(of: "\\d+(?:[\\.,]\\d+)?", options: .regularExpression) else { continue }
            let raw = String(match[numR]).replacingOccurrences(of: ",", with: ".")
            if let v = Double(raw), v > 0 { return v }
        }
        return nil
    }

    private func totalMassG(for ing: IngredientDraft, draft: ExtempRecipeDraft) -> Double? {
        let inferred = draft.inferredActiveMassG(for: ing)
        if inferred > 0 {
            return inferred
        }

        let unit = ing.unit.rawValue.lowercased()
        if unit == "g" || unit == "гр" || unit == "gram" || unit == "grams" {
            return ing.amountValue > 0 ? ing.amountValue : nil
        }
        if unit == "mg" || unit == "мг" {
            return ing.amountValue > 0 ? (ing.amountValue / 1000.0) : nil
        }
        if unit == "mcg" || unit == "мкг" || unit == "µg" {
            return ing.amountValue > 0 ? (ing.amountValue / 1_000_000.0) : nil
        }
        if unit == "kg" || unit == "кг" {
            return ing.amountValue > 0 ? (ing.amountValue * 1000.0) : nil
        }

        return nil
    }

    private func resolvedPerDoseLimit(ingredient ing: IngredientDraft, ageYears: Int?) -> (value: Double, label: String)? {
        if let ageYears {
            if ageYears < 1, let v = ing.refVrdChild0_1, v > 0 { return (v, "0–1 рік") }
            if ageYears >= 1, ageYears <= 6, let v = ing.refVrdChild1_6, v > 0 { return (v, "1–6 років") }
            if ageYears > 6, ageYears <= 14, let v = ing.refVrdChild7_14, v > 0 { return (v, "7–14 років") }
            if ageYears <= 14, let v = ing.refPedsVrdG, v > 0 { return (v, "дитяча") }
        }
        if let v = ing.refVrdG, v > 0 { return (v, "доросла") }
        return nil
    }

    private func resolvedPerDayLimit(ingredient ing: IngredientDraft, ageYears: Int?) -> (value: Double, label: String)? {
        if let ageYears, ageYears <= 14, let v = ing.refPedsRdG, v > 0 {
            return (v, "дитяча")
        }
        if let v = ing.refVsdG, v > 0 { return (v, "доросла") }
        return nil
    }

    private func parsePercent(from text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard let r = normalized.range(of: "(\\d{1,2}(?:\\.\\d+)?)\\s*%", options: .regularExpression) else {
            return nil
        }
        let raw = String(normalized[r])
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(raw)
    }

    private func collectLiquidAdditives(
        draft: ExtempRecipeDraft,
        inferredTargetAquaIngredientId: UUID?,
        inferredTargetSolutionIngredientId: UUID?,
        inferredPrimaryAqueousIngredientId: UUID?,
        buretteIngredientIds: Set<UUID>
    ) -> [LiquidAdditive] {
        draft.ingredients.compactMap { ing in
            guard !ing.isAd, !ing.isQS else { return nil }
            if let inferredTargetAquaIngredientId, ing.id == inferredTargetAquaIngredientId { return nil }
            if let inferredTargetSolutionIngredientId, ing.id == inferredTargetSolutionIngredientId { return nil }
            if let inferredPrimaryAqueousIngredientId, ing.id == inferredPrimaryAqueousIngredientId { return nil }
            if buretteIngredientIds.contains(ing.id) { return nil }
            if isAquaPurificata(ing) { return nil }

            guard let volumeMl = liquidVolumeMl(for: ing, draft: draft), volumeMl > 0 else { return nil }
            return LiquidAdditive(ingredient: ing, volumeMl: volumeMl, kind: classifyLiquidAdditive(ing))
        }
    }

    private func liquidVolumeMl(for ing: IngredientDraft, draft: ExtempRecipeDraft) -> Double? {
        if ing.presentationKind == .solution {
            return max(0, draft.solutionVolumeMl(for: ing) ?? 0)
        }
        if ing.unit.rawValue == "ml" {
            return max(0, ing.amountValue)
        }
        return nil
    }

    private func classifyLiquidAdditive(_ ing: IngredientDraft) -> LiquidAdditiveKind {
        if isAromaticWater(ing) { return .aromaticWater }
        if isLateAddedReadyLiquid(ing) { return .lateAddedActive }
        if isVolatileAqueousLiquid(ing) { return .volatileAqueous }
        if isAromaticAlcoholicLiquid(ing) { return .aromaticAlcoholic }
        if isViscousLiquid(ing) { return .viscous }
        return .other
    }

    private func isViscousLiquid(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        let t = (ing.refType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if hay.contains("syrup") || hay.contains("sirup") || hay.contains("sirupi") || hay.contains("сироп") {
            return true
        }
        if hay.contains("glycer") || hay.contains("гліцерин") || hay.contains("глицерин") {
            return true
        }
        return t == "syrup"
    }

    private func isAromaticAlcoholicLiquid(_ ing: IngredientDraft) -> Bool {
        if ing.rpPrefix == .tincture { return true }
        let t = (ing.refType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t == "tincture" { return true }

        let hay = normalizedHay(ing)
        if requiresPremixWithMixture(ing) { return true }
        if hay.contains("tinct") || hay.contains("настойк") || hay.contains("настоянк") {
            return true
        }
        if hay.contains("spirit") || hay.contains("alcohol") || hay.contains("спирт") {
            return true
        }
        return false
    }

    private func isPrimaryAqueousLiquid(_ ing: IngredientDraft) -> Bool {
        isAquaPurificata(ing) || isPrimaryAromaticWater(ing) || isAromaticWater(ing)
    }

    private func primaryAqueousIngredient(in draft: ExtempRecipeDraft) -> IngredientDraft? {
        draft.ingredients
            .filter { !$0.isAd && !$0.isQS && isPrimaryAqueousLiquid($0) }
            .max(by: { $0.amountValue < $1.amountValue })
    }

    private func primaryAqueousName(_ ing: IngredientDraft) -> String {
        let value = (ing.refNameLatNom ?? ing.displayName).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Aqua purificata" : value
    }

    private func isPrimaryAromaticWater(_ ing: IngredientDraft) -> Bool {
        isAromaticWater(ing) && !isVolatileAqueousLiquid(ing)
    }

    private func isAromaticWater(_ ing: IngredientDraft) -> Bool {
        ing.isReferenceAromaticWater
    }

    private func isVolatileAqueousLiquid(_ ing: IngredientDraft) -> Bool {
        ing.isReferenceVolatileAqueousLiquid
    }

    private func requiresPremixWithMixture(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        return hay.contains("liquor ammonii anisati")
            || hay.contains("ammonii anisati")
            || hay.contains("нашатирно-аніс")
            || hay.contains("нашатырно-анис")
            || hay.contains("spiritus menthae")
            || hay.contains("spirit of peppermint")
    }

    private func isLateAddedReadyLiquid(_ ing: IngredientDraft) -> Bool {
        isAdonisidum(ing)
    }

    private func isAdonisidum(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        return hay.contains("adonisid")
            || hay.contains("adonizid")
            || hay.contains("adonis")
    }

    private func hasHeatSensitiveVolatileComponents(context: RxPipelineContext) -> Bool {
        context.draft.ingredients.contains(where: isAromaticWater)
            || context.draft.ingredients.contains(where: isVolatileAqueousLiquid)
            || context.draft.ingredients.contains(where: requiresPremixWithMixture)
    }

    private func aromaticVolatileNotes(context: RxPipelineContext, solidsPercent: Double?) -> OralDoseAnalysisResult {
        let active = context.draft.ingredients.filter { !$0.isQS && !$0.isAd }
        let aromaticWaters = active.filter(isAromaticWater)
        let volatileAqueous = active.filter(isVolatileAqueousLiquid)
        let premixDrops = active.filter(requiresPremixWithMixture)

        var lines: [String] = []
        var issues: [RxIssue] = []

        if !aromaticWaters.isEmpty {
            let names = aromaticWaters.map { $0.displayName.isEmpty ? ($0.refNameLatNom ?? "Subst.") : $0.displayName }.joined(separator: ", ")
            lines.append("ℹ \(names): готові ароматні води розглядати як леткі водні системи 1:1000; не нагрівати, зберігати при 8-15°C.")
            lines.append("ℹ \(names): якщо ароматну воду відновлюють із концентрату і при розведенні виникає різка мутність, допускається фільтрація через змочений водою паперовий фільтр; у готовій мікстурі робочу фільтрацію виконують через вату.")
        }

        if !volatileAqueous.isEmpty {
            let names = volatileAqueous.map { $0.displayName.isEmpty ? ($0.refNameLatNom ?? "Subst.") : $0.displayName }.joined(separator: ", ")
            lines.append("ℹ \(names): вводити в кінці без інтенсивного збовтування; флакон щільно закоркувати.")
            if let solidsPercent, solidsPercent >= 5 {
                let msg = "\(names): у концентрованому сольовому середовищі можливе часткове висолювання летких компонентів; додавати тільки наприкінці"
                lines.append("⚠ \(msg)")
                issues.append(RxIssue(code: "solution.volatile.saltingOut", severity: .warning, message: msg))
            }
        }

        if !premixDrops.isEmpty {
            let names = premixDrops.map { $0.displayName.isEmpty ? ($0.refNameLatNom ?? "Subst.") : $0.displayName }.joined(separator: ", ")
            lines.append("ℹ \(names): перед внесенням попередньо змішати з частиною готової мікстури у співвідношенні 1:1-1:2, щоб уникнути помутніння й випадіння ефірної олії.")
        }

        if active.contains(where: isPrimaryAromaticWater), !active.filter(isAromaticAlcoholicLiquid).isEmpty {
            lines.append("ℹ Для мікстур на ароматних водах після внесення настойок можлива легка опалесценція через виділення ефірних олій; це технологічно допустимо.")
        }

        return OralDoseAnalysisResult(lines: lines, issues: issues)
    }

    private func shouldDoseByVolume(_ ing: IngredientDraft) -> Bool {
        let type = (ing.refType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard type == "act" || ing.isReferenceListA || ing.isReferenceListB || ing.refIsNarcotic else { return false }
        return ing.unit.rawValue == "ml"
            || ing.unit.rawValue == "мл"
            || isAdonisidum(ing)
    }

    private func totalDoseVolumeMl(for ing: IngredientDraft, draft: ExtempRecipeDraft) -> Double? {
        let unit = ing.unit.rawValue.lowercased()
        if (unit == "ml" || unit == "мл"), ing.amountValue > 0 {
            return ing.amountValue
        }
        if ing.presentationKind == .solution, let v = draft.solutionVolumeMl(for: ing), v > 0 {
            return v
        }
        return nil
    }

    private func approximateDrops(for ing: IngredientDraft, volumeMl: Double) -> Int? {
        guard volumeMl > 0 else { return nil }
        let dropsPerMl = ing.refGttsPerMl ?? defaultDropsPerMl(for: ing)
        guard dropsPerMl > 0 else { return nil }
        return Int((volumeMl * dropsPerMl).rounded())
    }

    private func defaultDropsPerMl(for ing: IngredientDraft) -> Double {
        if isAdonisidum(ing) { return 35 }
        if let solventType = NonAqueousSolventCatalog.classify(ingredient: ing) {
            let ethanolStrength = solventType == .ethanol
                ? NonAqueousSolventCatalog.requestedEthanolStrength(from: ing)
                : nil
            if let value = NonAqueousSolventCatalog.standardDropsPerMl(for: solventType, ethanolStrength: ethanolStrength) {
                return value
            }
        }
        return 20
    }

    private func describeLiquidAdditives(_ items: [LiquidAdditive]) -> String {
        let text = items.map { item in
            let name = item.ingredient.displayName.isEmpty ? "Subst." : item.ingredient.displayName
            return "\(name) — \(format(item.volumeMl)) ml"
        }
        return text.joined(separator: "; ")
    }

    private func sodiumSalicylateStabilityNotes(context: RxPipelineContext) -> OralDoseAnalysisResult {
        let hasSodiumSalicylate = context.draft.ingredients.contains(where: isSodiumSalicylate)
        guard hasSodiumSalicylate else { return OralDoseAnalysisResult(lines: [], issues: []) }

        let acidicIngredients = context.draft.ingredients.filter { isAcidicIngredient($0) }
        if acidicIngredients.isEmpty {
            return OralDoseAnalysisResult(
                lines: ["Натрію саліцилат: кислі компоненти не виявлені, ризик випадіння саліцилової кислоти в осад у цьому складі мінімальний."],
                issues: []
            )
        }

        let names = acidicIngredients.map { $0.displayName.isEmpty ? "Subst." : $0.displayName }.joined(separator: ", ")
        let msg = "Натрію саліцилат чутливий до кислого середовища; можливе випадіння осаду саліцилової кислоти при поєднанні з: \(names)"
        return OralDoseAnalysisResult(
            lines: ["⚠ \(msg)"],
            issues: [RxIssue(code: "solution.salicylate.acidicRisk", severity: .warning, message: msg)]
        )
    }

    private func tweenSpanCompatibilityNotes(context: RxPipelineContext) -> OralDoseAnalysisResult {
        let activeIngredients = context.draft.ingredients.filter { !$0.isQS && !$0.isAd }
        let surfactants = activeIngredients.filter(isTweenOrSpanIngredient)
        guard !surfactants.isEmpty else { return OralDoseAnalysisResult(lines: [], issues: []) }

        let conflicting = activeIngredients.filter { ingredient in
            !surfactants.contains(where: { $0.id == ingredient.id })
                && (isSalicylateIngredient(ingredient)
                    || isPhenolFamilyIngredient(ingredient)
                    || isParaHydroxyBenzoicDerivativeIngredient(ingredient))
        }
        guard !conflicting.isEmpty else { return OralDoseAnalysisResult(lines: [], issues: []) }

        let surfactantNames = surfactants
            .map { $0.displayName.isEmpty ? ($0.refNameLatNom ?? "Subst.") : $0.displayName }
            .joined(separator: ", ")
        let conflictingNames = conflicting
            .map { $0.displayName.isEmpty ? ($0.refNameLatNom ?? "Subst.") : $0.displayName }
            .joined(separator: ", ")
        let msg = "\(surfactantNames) несумісні із саліцилатами/фенолами/похідними параоксибензойної кислоти; виявлено конфлікт із: \(conflictingNames)"
        return OralDoseAnalysisResult(
            lines: ["⚠ \(msg)"],
            issues: [RxIssue(code: "solution.tweenspan.incompatibility", severity: .blocking, message: msg)]
        )
    }

    private func catalogStabilityNotes(context: RxPipelineContext) -> OralDoseAnalysisResult {
        let activeIngredients = context.draft.ingredients.filter { !$0.isQS && !$0.isAd }
        guard !activeIngredients.isEmpty else {
            return OralDoseAnalysisResult(lines: [], issues: [])
        }

        let acidicIngredients = activeIngredients.filter(isAcidifyingIngredient)
        let alkalineIngredients = activeIngredients.filter(isAlkalizingIngredient)
        let hasGlycerin = activeIngredients.contains(where: isGlycerinIngredient)
        var lines: [String] = []
        var issues: [RxIssue] = []

        for ing in activeIngredients {
            guard let profile = ing.propertyOverride else { continue }
            let ingredientName = ing.displayName.isEmpty ? (ing.refNameLatNom ?? "Subst.") : ing.displayName

            if profile.technologyRules.contains(.avoidProlongedHeatingInSolution) {
                lines.append("ℹ \(ingredientName): не піддавати тривалому нагріванню під час розчинення, щоб не прискорювати гідроліз.")
            }

            if profile.interactionRules.contains(.incompatibleWithAcids) {
                let conflicting = acidicIngredients.filter { $0.id != ing.id }
                if !conflicting.isEmpty {
                    let names = conflicting.map { $0.displayName.isEmpty ? ($0.refNameLatNom ?? "Subst.") : $0.displayName }
                        .joined(separator: ", ")
                    let msg = "\(ingredientName) нестійкий у кислому середовищі; можливий розклад з виділенням формальдегіду при поєднанні з: \(names)"
                    lines.append("⚠ \(msg)")
                    issues.append(RxIssue(code: "solution.catalog.acidSensitive", severity: .blocking, message: msg))
                }
            }
            if profile.interactionRules.contains(.incompatibleWithAlkalies) {
                let conflicting = alkalineIngredients.filter { $0.id != ing.id }
                if !conflicting.isEmpty {
                    let names = conflicting.map { $0.displayName.isEmpty ? ($0.refNameLatNom ?? "Subst.") : $0.displayName }
                        .joined(separator: ", ")
                    let msg = "\(ingredientName) несовместим со щелочной средой; возможно выпадение кодеин-основания в осадок при сочетании с: \(names)"
                    lines.append("⚠ \(msg)")
                    issues.append(RxIssue(code: "solution.catalog.alkaliSensitive", severity: .blocking, message: msg))
                }
            }
            if profile.technologyRules.contains(.acidifiesInGlycerin), hasGlycerin {
                let msg = "\(ingredientName) при растворении в глицерине образует глицероборную кислоту; возможен сдвиг pH раствора."
                lines.append("ℹ \(msg)")
                issues.append(RxIssue(code: "solution.catalog.glycerinPhShift", severity: .warning, message: msg))
            }
        }

        return OralDoseAnalysisResult(lines: lines, issues: issues)
    }

    private func gentleHeatingTechnologyLine(context: RxPipelineContext) -> String? {
        let names = context.draft.ingredients.compactMap { ing -> String? in
            guard !ing.isQS, !ing.isAd else { return nil }
            guard ing.propertyOverride?.technologyRules.contains(.avoidProlongedHeatingInSolution) == true else { return nil }
            return ing.displayName.isEmpty ? (ing.refNameLatNom ?? "Subst.") : ing.displayName
        }

        guard !names.isEmpty else { return nil }
        return "Термолабільні/гідролізно чутливі речовини (\(names.joined(separator: ", "))) вводити без тривалого нагрівання, за можливості при кімнатній температурі."
    }

    private func acidSensitiveTechnologyLine(context: RxPipelineContext) -> String? {
        let activeIngredients = context.draft.ingredients.filter { !$0.isQS && !$0.isAd }
        let acidSensitiveNames = activeIngredients.compactMap { ing -> String? in
            guard ing.propertyOverride?.interactionRules.contains(.incompatibleWithAcids) == true else { return nil }
            return ing.displayName.isEmpty ? (ing.refNameLatNom ?? "Subst.") : ing.displayName
        }
        let acidicNames = activeIngredients
            .filter(isAcidifyingIngredient)
            .map { $0.displayName.isEmpty ? ($0.refNameLatNom ?? "Subst.") : $0.displayName }

        guard !acidSensitiveNames.isEmpty, !acidicNames.isEmpty else { return nil }
        return "Уникати кислого середовища для \(acidSensitiveNames.joined(separator: ", ")); у поточному складі кислі компоненти: \(acidicNames.joined(separator: ", "))."
    }

    private func alkaliSensitiveTechnologyLine(context: RxPipelineContext) -> String? {
        let activeIngredients = context.draft.ingredients.filter { !$0.isQS && !$0.isAd }
        let alkaliSensitiveNames = activeIngredients.compactMap { ing -> String? in
            guard ing.propertyOverride?.interactionRules.contains(.incompatibleWithAlkalies) == true else { return nil }
            return ing.displayName.isEmpty ? (ing.refNameLatNom ?? "Subst.") : ing.displayName
        }
        let alkalineNames = activeIngredients
            .filter(isAlkalizingIngredient)
            .map { $0.displayName.isEmpty ? ($0.refNameLatNom ?? "Subst.") : $0.displayName }

        guard !alkaliSensitiveNames.isEmpty, !alkalineNames.isEmpty else { return nil }
        return "Уникати лужного середовища для \(alkaliSensitiveNames.joined(separator: ", ")); у поточному складі лужні компоненти: \(alkalineNames.joined(separator: ", "))."
    }

    private func glycerinPhShiftTechnologyLine(context: RxPipelineContext) -> String? {
        let activeIngredients = context.draft.ingredients.filter { !$0.isQS && !$0.isAd }
        let affectedNames = activeIngredients.compactMap { ing -> String? in
            guard ing.propertyOverride?.technologyRules.contains(.acidifiesInGlycerin) == true else { return nil }
            return ing.displayName.isEmpty ? (ing.refNameLatNom ?? "Subst.") : ing.displayName
        }
        guard !affectedNames.isEmpty else { return nil }
        guard activeIngredients.contains(where: isGlycerinIngredient) else { return nil }
        return "Для \(affectedNames.joined(separator: ", ")) у присутності гліцерину врахувати утворення гліцероборної кислоти та можливий зсув pH."
    }

    private func bicarbonateAndHexamineStabilityNotes(context: RxPipelineContext) -> OralDoseAnalysisResult {
        let activeIngredients = context.draft.ingredients.filter { !$0.isQS && !$0.isAd }
        let hasBicarbonate = activeIngredients.contains(where: isSodiumBicarbonate)
        let hasHexamine = activeIngredients.contains(where: isHexamethylenetetramine)
        guard hasBicarbonate || hasHexamine else {
            return OralDoseAnalysisResult(lines: [], issues: [])
        }

        let acidicNames = activeIngredients
            .filter(isAcidifyingIngredient)
            .map { $0.displayName.isEmpty ? ($0.refNameLatNom ?? "Subst.") : $0.displayName }

        var lines: [String] = []
        var issues: [RxIssue] = []

        if hasBicarbonate {
            lines.append("Натрію гідрокарбонат: розчиняти без нагрівання та без інтенсивного збовтування, щоб мінімізувати втрати CO2 і зміну pH.")
        }

        if hasHexamine {
            if acidicNames.isEmpty {
                lines.append("Гексаметилентетрамін: у поточному нейтрально-лужному складі стабільний; слід уникати додавання кислих компонентів.")
            } else {
                let msg = "Гексаметилентетрамін нестійкий у кислому середовищі; можливий розклад при поєднанні з: \(acidicNames.joined(separator: ", "))"
                lines.append("⚠ \(msg)")
                issues.append(RxIssue(code: "solution.hexamine.acidicRisk", severity: .blocking, message: msg))
            }
        }

        return OralDoseAnalysisResult(lines: lines, issues: issues)
    }

    private func bicarbonateTechnologyLine(context: RxPipelineContext) -> String? {
        let activeIngredients = context.draft.ingredients.filter { !$0.isQS && !$0.isAd }
        guard activeIngredients.contains(where: isSodiumBicarbonate) else { return nil }
        return "Натрію гідрокарбонат розчиняти при кімнатній температурі без нагрівання та без інтенсивного збовтування."
    }

    private func potassiumPermanganateConcentrationPercent(
        ingredient: IngredientDraft,
        context: RxPipelineContext,
        targetVolumeMl: Double
    ) -> Double? {
        if ingredient.presentationKind == .solution,
           let solutionPercent = context.draft.solutionDisplayPercent(for: ingredient),
           solutionPercent > 0 {
            return solutionPercent
        }
        let activeMassG = context.draft.inferredActiveMassG(for: ingredient)
        guard activeMassG > 0 else { return nil }
        guard targetVolumeMl > 0 else { return nil }
        return (activeMassG / targetVolumeMl) * 100.0
    }

    private func specialWaterRules(context: RxPipelineContext, targetVolumeMl: Double) -> SpecialWaterRuleResult {
        let activeIngredients = context.draft.ingredients.filter { !$0.isQS && !$0.isAd }
        guard !activeIngredients.isEmpty else {
            return SpecialWaterRuleResult(calculationLines: [], stabilityLines: [], technologyLines: [], issues: [])
        }

        var calculationLines: [String] = []
        var stabilityLines: [String] = []
        var technologyLines: [String] = []
        var issues: [RxIssue] = []
        var heatingLines: Set<String> = []
        var markerStabilityLines: Set<String> = []
        var markerTechnologyLines: Set<String> = []
        var hasSilverNitrateProcedure = false

        for ing in activeIngredients {
            let name = operationIngredientName(ing)
            let ratio = WaterSolubilityHeuristics.waterRatioDenominator(ing.refSolubility)
            let needsBoiling = requiresBoilingWaterDissolution(ing) || (ratio ?? 0) >= 100
            let needsHotHeating = requiresHotWaterDissolution(ing) || (ratio ?? 0) > 50
            let needsWarmHeating = requiresWarmWaterDissolution(ing)

            if needsBoiling {
                heatingLines.insert("Для \(name) застосувати киплячу воду або гарячу воду 90-100°C; після розчинення охолодити до кімнатної температури.")
            } else if needsWarmHeating {
                heatingLines.insert("Для \(name) застосувати теплу Aqua purificata (40-50°C) для повного розчинення.")
            } else if needsHotHeating {
                if isEthacridineIngredient(ing) || isPapaverineHydrochlorideIngredient(ing) {
                    heatingLines.insert("Для \(name) використовувати гарячу Aqua purificata (70-80°C) під час розчинення.")
                } else {
                    heatingLines.insert("Для \(name) використовувати гарячу Aqua purificata (80-90°C) під час розчинення.")
                }
            }

            if requiresNaClIsotonization(ing), targetVolumeMl > 0 {
                let nacl = 0.009 * targetVolumeMl
                calculationLines.append("\(name): ізотонування NaCl 0,9% = \(format(nacl)) g (Instruction_ID/Process_Note).")
                markerTechnologyLines.insert("\(name): перед розчиненням основної речовини відважити Natrii chloridum \(format(nacl)) g та розчинити у воді.")
            }

            if requiresFreshlyDistilledWater(ing) {
                markerStabilityLines.insert("\(name): використовувати лише Aqua purificata recenter destillata без іонів хлориду; забезпечити світлозахист.")
                markerTechnologyLines.insert("\(name): готувати лише на Aqua purificata recenter destillata; уникати контакту з хлоридовмісними розчинами.")
                issues.append(
                    RxIssue(
                        code: "solution.marker.freshDistilled.\(ing.id)",
                        severity: .warning,
                        message: "\(name): потрібна свіжоперегнана вода без хлоридів."
                    )
                )
            }

            if requiresGlassFilterOnly(ing) {
                markerTechnologyLines.insert("\(name): фільтрація тільки через скляний фільтр або скляну вату; органічні фільтри (папір, вата) не використовувати.")
            } else if requiresWarmCottonFilter(ing) {
                markerTechnologyLines.insert("\(name): проціджувати теплим через пухкий ватний тампон, поки розчин не кристалізується.")
            }

            if isStrongOxidizerIngredient(ing) {
                markerStabilityLines.insert("\(name): сильний окисник; уникати контакту з органічними речовинами під час виготовлення.")
                markerTechnologyLines.insert("\(name): розчиняти в окремому посуді; не допускати контакту з органікою (папір, цукор, гліцерин).")
                markerTechnologyLines.insert("\(name): кристали не розтирати у ступці з органічними залишками; працювати окремими інструментами.")
                issues.append(
                    RxIssue(
                        code: "solution.marker.oxidizer.\(ing.id)",
                        severity: .warning,
                        message: "\(name): працювати як із сильним окисником, окрема тара та інструменти."
                    )
                )
            }

            if isEthacridineIngredient(ing) {
                markerStabilityLines.insert("\(name): світлочутливий барвник; фасувати у темне скло та захищати від світла.")
                markerTechnologyLines.insert("\(name): уникати контакту з металевими предметами; використовувати скляний/фарфоровий інструмент.")
                markerTechnologyLines.insert("\(name): працювати в рукавичках — можливе інтенсивне забарвлення шкіри та обладнання.")
            }

            if isPotassiumPermanganateIngredient(ing) {
                markerTechnologyLines.insert("\(name): розчиняти у теплій Aqua purificata (40-50°C) до повного зникнення кристалів на дні.")
                markerTechnologyLines.insert("\(name): фільтрація тільки через скляний фільтр або скляну вату; контакт з папером/ватою не допускається.")
                if let concentrationPercent = potassiumPermanganateConcentrationPercent(
                    ingredient: ing,
                    context: context,
                    targetVolumeMl: targetVolumeMl
                ), concentrationPercent >= 3, concentrationPercent <= 5 {
                    markerTechnologyLines.insert("\(name): для концентрованого розчину \(format(concentrationPercent))% попередньо обережно розтерти кристали у ступці з частиною теплої профільтрованої води, потім додати решту розчинника.")
                    markerStabilityLines.insert("\(name): концентровані розчини 3-5% потребують попереднього диспергування у теплій воді для прискорення розчинення та рівномірності.")
                    issues.append(
                        RxIssue(
                            code: "solution.permanganate.concentrated.\(ing.id)",
                            severity: .warning,
                            message: "\(name): для 3-5% розчинів застосувати попереднє розтирання з частиною теплої очищеної води."
                        )
                    )
                }
            }

            if isHydrogenPeroxideIngredient(ing) {
                markerStabilityLines.insert("\(name): окисник і світлочутлива речовина; уникати контакту з органічними матеріалами.")
                markerTechnologyLines.insert("\(name): фільтрація тільки через скляний фільтр або скляну вату; органічні фільтри (папір, вата) не використовувати.")
            }

            if isFuracilinIngredient(ing) {
                markerTechnologyLines.insert("\(name): до фільтрації обов'язково переконатися у повному розчиненні кристалів; за наявності осаду продовжити нагрівання та перемішування.")
            }

            if isLightSensitiveByMarker(ing), !isPrimaryAqueousLiquid(ing) {
                markerStabilityLines.insert("\(name): розчин світлочутливий, фасувати у темне скло.")
            }

            if isNatriiBromidumIngredient(ing) {
                markerStabilityLines.insert("\(name): суха речовина гігроскопічна, але водний розчин стабільний.")
            }

            if isSilverNitrateIngredient(ing), !hasSilverNitrateProcedure {
                hasSilverNitrateProcedure = true
                let silverMassG = context.draft.inferredActiveMassG(for: ing)
                technologyLines.append("Використати абсолютно чистий хімічний посуд (попередньо обполоснутий свіжою водою).")
                technologyLines.append("Срібла нітрат зважувати на окремих вагах; використовувати лише скляні або фарфорові інструменти (без металу).")
                if targetVolumeMl > 0 {
                    technologyLines.append("Відміряти \(format(targetVolumeMl)) ml свіжоперегнаної води.")
                } else {
                    technologyLines.append("Відміряти свіжоперегнану воду у розрахованому об'ємі.")
                }
                if silverMassG > 0 {
                    technologyLines.append("Відібрати 5-10 ml із відміряної води, розчинити \(format(silverMassG)) g срібла нітрату у цьому об'ємі та повернути концентрат у основний розчин (без зміни кінцевого об'єму).")
                } else {
                    technologyLines.append("Додати срібла нітрат, розчинити при обережному перемішуванні скляною паличкою.")
                }
                technologyLines.append("Перед фільтрацією промити скляний фільтр свіжоперегнаною водою.")
                technologyLines.append("Фільтрація: Тільки крізь скляний фільтр №1 або №2.")
                technologyLines.append("Фасувати у флакон з темного скла з притертою пробкою.")
                technologyLines.append("Опечатати флакон.")
            }
        }
        if !heatingLines.isEmpty {
            stabilityLines.append(contentsOf: heatingLines.sorted())
        }
        if !markerStabilityLines.isEmpty {
            stabilityLines.append(contentsOf: markerStabilityLines.sorted())
        }
        if !markerTechnologyLines.isEmpty {
            technologyLines.append(contentsOf: markerTechnologyLines.sorted())
        }

        let hasIodine = activeIngredients.contains(where: isIodineIngredient)
        let hasIodide = activeIngredients.contains(where: isIodideIngredient)
        let hasLugol = activeIngredients.contains(where: isLugolIngredient)

        if hasIodine && !hasIodide && !hasLugol {
            let msg = "Йод у водному розчині потребує Kalii/Natrii iodidum для попереднього комплексоутворення."
            stabilityLines.append("⚠ \(msg)")
            issues.append(RxIssue(code: "solution.iodine.iodide.required", severity: .blocking, message: msg))
        }

        if hasIodine && hasIodide {
            let iodineMass = activeIngredients
                .filter(isIodineIngredient)
                .reduce(0.0) { $0 + context.draft.inferredActiveMassG(for: $1) }
            let iodideMass = activeIngredients
                .filter(isIodideIngredient)
                .reduce(0.0) { $0 + context.draft.inferredActiveMassG(for: $1) }

            if iodineMass > 0, iodideMass > 0 {
                let ratio = iodideMass / iodineMass
                calculationLines.append("Iodine/KI: \(format(iodideMass)) g / \(format(iodineMass)) g = \(format(ratio)) : 1")
                if ratio < 2.0 {
                    let msg = "Для надійного розчинення Iodum рекомендовано щонайменше 2 частини KI на 1 частину Iodum."
                    stabilityLines.append("⚠ \(msg)")
                    issues.append(RxIssue(code: "solution.iodine.iodide.ratio", severity: .warning, message: msg))
                }
            }

            let minimalWaterMl = max(iodideMass, 0.2)
            technologyLines.append("Йодну систему готувати послідовно: спочатку розчинити KI у мінімальному об'ємі води (орієнтир \(format(minimalWaterMl)) ml, близько 1:1 до маси KI), далі розчинити Iodum у концентраті KI.")
            if context.facts.hasQSorAd || targetVolumeMl > 0 {
                technologyLines.append("Після утворення комплексу йоду довести Aqua purificata до кінцевого об'єму (ad V).")
            }
            technologyLines.append("За потреби фільтрувати йодний розчин через скляний фільтр.")
        } else if hasLugol {
            stabilityLines.append("Solutio Lugoli: офіцинальний розчин; використовується як готова форма з контролем світлозахисту.")
        }

        return SpecialWaterRuleResult(
            calculationLines: calculationLines,
            stabilityLines: stabilityLines,
            technologyLines: technologyLines,
            issues: issues
        )
    }

    private func hasTechnologyRule(_ ingredient: IngredientDraft, _ rule: SubstanceTechnologyRule) -> Bool {
        ingredient.propertyOverride?.technologyRules.contains(rule) == true
    }

    private func isAquaPurificata(_ ing: IngredientDraft) -> Bool {
        PurifiedWaterHeuristics.isPurifiedWater(ing)
    }

    private func isLiquidIngredient(_ ing: IngredientDraft) -> Bool {
        if ing.unit.rawValue == "ml" { return true }
        let t = (ing.refType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t == "solvent"
            || t == "buffersolution"
            || t == "standardsolution"
            || t == "liquidstandard"
            || t == "tincture"
            || t == "extract"
            || t == "syrup"
        {
            return true
        }
        let hay = normalizedHay(ing)
        return hay.contains("syrup")
            || hay.contains("sirup")
            || hay.contains("сироп")
            || hay.contains("glycer")
            || hay.contains("гліцерин")
            || hay.contains("глицерин")
    }

    private func normalizedHay(_ ing: IngredientDraft) -> String {
        let a = (ing.refNameLatNom ?? ing.displayName).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let b = (ing.refInnKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return a + " " + b
    }

    private func isPepsin(_ ing: IngredientDraft) -> Bool {
        normalizedHay(ing).contains("pepsin")
    }

    private func hasIodideIngredient(_ ingredients: [IngredientDraft]) -> Bool {
        ingredients.contains(where: isIodideIngredient)
    }

    private func isIodideIngredient(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        return hay.contains("iodid")
            || hay.contains("iodidum")
            || hay.contains("іодид")
            || hay.contains("йодид")
    }

    private func isIodineIngredient(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        if hay.contains("iodid") || hay.contains("йодид") || hay.contains("іодид") {
            return false
        }
        return hay.contains("iodum")
            || hay.contains(" iodi ")
            || hay.hasPrefix("iodi ")
            || hay.contains("iodine")
            || hay.contains(" йод ")
            || hay.hasPrefix("йод ")
    }

    private func isLugolIngredient(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        return hay.contains("lugol")
            || hay.contains("люгол")
    }

    private func isSilverNitrateIngredient(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        return hay.contains("argenti nitrat")
            || hay.contains("silver nitrate")
            || hay.contains("нитрат серебр")
            || hay.contains("нітрат срібл")
            || hay.contains("ляпіс")
    }

    private func isBoricAcidIngredient(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        return hay.contains("acidum boric")
            || hay.contains("acidi borici")
            || hay.contains("boric acid")
            || hay.contains("борна кислот")
            || hay.contains("кислота борн")
    }

    private func isEthacridineIngredient(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        return hay.contains("aethacrid")
            || hay.contains("ethacrid")
            || hay.contains("етакрид")
            || hay.contains("этакрид")
            || hay.contains("риванол")
            || hay.contains("rivanol")
    }

    private func isPotassiumPermanganateIngredient(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        return hay.contains("permangan")
            || hay.contains("перманганат")
    }

    private func isHydrogenPeroxideIngredient(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        return hay.contains("hydrogenii perox")
            || hay.contains("hydrogen peroxide")
            || hay.contains("перекис водню")
            || hay.contains("перекись водор")
            || hay.contains("пергідрол")
            || hay.contains("пергидрол")
    }

    private func isPapaverineHydrochlorideIngredient(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        return hay.contains("papaverin")
            && (hay.contains("hydrochlorid") || hay.contains("гидрохлорид") || hay.contains("гідрохлорид"))
    }

    private func isFuracilinIngredient(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        return hay.contains("furacil")
            || hay.contains("nitrofural")
            || hay.contains("фурацил")
    }

    private func markerMatch(_ ing: IngredientDraft, keys: [String], values: [String]) -> Bool {
        ing.referenceHasMarkerValue(keys: keys, expectedValues: values)
            || ing.referenceContainsMarkerToken(values)
    }

    private func requiresBoilingWaterDissolution(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        if hay.contains("furacil") || hay.contains("nitrofural") || hay.contains("фурацил") {
            return true
        }
        if hasTechnologyRule(ing, .requiresBoilingWaterDissolution) { return true }
        if let temp = ing.refWaterTempC, temp >= 95 { return true }
        return markerMatch(
            ing,
            keys: ["instruction_id", "process_note", "solubility_speed"],
            values: [
                "boiling_water",
                "boilingwater",
                "boil_water",
                "heat_solvent_100c",
                "hot_solvent_100c",
                "кипляч"
            ]
        )
    }

    private func requiresHotWaterDissolution(_ ing: IngredientDraft) -> Bool {
        if isEthacridineIngredient(ing) || isPapaverineHydrochlorideIngredient(ing) {
            return true
        }
        if hasTechnologyRule(ing, .requiresHeatingForDissolution) { return true }
        if let temp = ing.refWaterTempC, temp >= 70, temp < 95 { return true }
        return markerMatch(
            ing,
            keys: ["instruction_id", "process_note", "solubility_speed"],
            values: [
                "heat_water_80c",
                "hot_solvent",
                "hot_water",
                "hotsolvent",
                "heat_solvent",
                "гаряч"
            ]
        )
    }

    private func requiresWarmWaterDissolution(_ ing: IngredientDraft) -> Bool {
        if isPotassiumPermanganateIngredient(ing) {
            return true
        }
        if let temp = ing.refWaterTempC, temp >= 35, temp < 70 { return true }
        return markerMatch(
            ing,
            keys: ["instruction_id", "process_note", "solubility_speed"],
            values: [
                "warm_solvent",
                "warm_water",
                "warmsolvent",
                "40_50c",
                "40-50c",
                "тепл"
            ]
        )
    }

    private func requiresNaClIsotonization(_ ing: IngredientDraft) -> Bool {
        if hasTechnologyRule(ing, .furacilinAddSodiumChloride) { return true }
        if ing.referenceHasMarkerValue(
            keys: ["needs_isotonization", "needsisotonization", "needs_isotonisation", "needsisotonisation"],
            expectedValues: ["yes", "true", "1"]
        ) {
            return true
        }
        return markerMatch(
            ing,
            keys: ["instruction_id", "process_note", "interaction_notes", "needs_isotonization"],
            values: [
                "add_nacl",
                "nacl_0_9",
                "nacl09",
                "isoton",
                "furacilin_add_sodium_chloride",
                "needs_isotonization"
            ]
        )
    }

    private func requiresFreshlyDistilledWater(_ ing: IngredientDraft) -> Bool {
        if hasTechnologyRule(ing, .requiresFreshDistilledWater) { return true }
        return markerMatch(
            ing,
            keys: ["instruction_id", "process_note", "solvent_type"],
            values: [
                "freshly_distilled_water",
                "fresh_distilled_water",
                "freshlydistilledwater",
                "recenter_destillata",
                "chloride_free_water",
                "безхлорид"
            ]
        )
    }

    private func requiresGlassFilterOnly(_ ing: IngredientDraft) -> Bool {
        if isPotassiumPermanganateIngredient(ing) || isHydrogenPeroxideIngredient(ing) {
            return true
        }
        if hasTechnologyRule(ing, .avoidPaperFilter) { return true }
        return markerMatch(
            ing,
            keys: ["filter_type", "instruction_id", "process_note"],
            values: [
                "glass_filter_only",
                "glassfilteronly",
                "glass_filter",
                "glassfilter",
                "no_organic_filter",
                "noorganicfilter",
                "avoid_paper_filter"
            ]
        )
    }

    private func requiresWarmCottonFilter(_ ing: IngredientDraft) -> Bool {
        markerMatch(
            ing,
            keys: ["filter_type", "instruction_id", "process_note"],
            values: [
                "warm_cotton_filter",
                "warmcottonfilter",
                "cotton_filter_warm"
            ]
        )
    }

    private func isStrongOxidizerIngredient(_ ing: IngredientDraft) -> Bool {
        if isPotassiumPermanganateIngredient(ing) || isHydrogenPeroxideIngredient(ing) {
            return true
        }
        if hasTechnologyRule(ing, .oxidizerHandleSeparately) { return true }
        return markerMatch(
            ing,
            keys: ["instruction_id", "process_note", "interaction_notes"],
            values: [
                "strong_oxidizer",
                "oxidizer_handle_separately",
                "сильнийокисник"
            ]
        )
    }

    private func isLightSensitiveByMarker(_ ing: IngredientDraft) -> Bool {
        if isStableHalideWithoutExplicitPhotolability(ing) {
            return false
        }
        if isEthacridineIngredient(ing) { return true }
        if ing.isReferenceLightSensitive { return true }
        return markerMatch(
            ing,
            keys: ["light_sensitive", "instruction_id", "process_note", "storage"],
            values: [
                "lightprotected",
                "protectfromlight",
                "light_sensitive",
                "amberglass",
                "темнескло",
                "захищеновідсвітла"
            ]
        )
    }

    private func isNatriiBromidumIngredient(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        return hay.contains("natrii bromid")
            || hay.contains("sodium bromide")
            || hay.contains("натрия бромид")
            || hay.contains("натрію бромід")
    }

    private func isStableHalideWithoutExplicitPhotolability(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        let hasBromide = hay.contains("natrii bromid")
            || hay.contains("kalii bromid")
            || hay.contains("sodium bromide")
            || hay.contains("potassium bromide")
            || hay.contains("натрия бромид")
            || hay.contains("натрію бромід")
            || hay.contains("калия бромид")
            || hay.contains("калію бромід")
        let hasHydrobromide = hay.contains("hydrobromid")
            || hay.contains("гидробромид")
            || hay.contains("гідробромід")
        return hasBromide && !hasHydrobromide
    }

    private func hasVolumeEffectForKuo(_ ing: IngredientDraft) -> Bool {
        if let kuo = ing.refKuoMlPerG, kuo >= 0.2 {
            return true
        }
        if ing.referenceHasMarkerValue(
            keys: ["volume_effect", "needs_kou", "needs_kou_when_percent_gt"],
            expectedValues: ["yes", "true", "1"]
        ) {
            return true
        }
        return markerMatch(
            ing,
            keys: ["instruction_id", "process_note", "volume_effect"],
            values: ["volume_effect", "needs_kou", "kuo_required"]
        )
    }

    private func isListAIngredient(_ ing: IngredientDraft) -> Bool {
        ing.isReferenceListA
    }

    private func preferredFiltrationTechnologyLine(
        activeIngredients: [IngredientDraft],
        shouldCottonFilter: Bool,
        needsFiltration: Bool
    ) -> String {
        if activeIngredients.contains(where: isSilverNitrateIngredient) {
            return "Фільтрація: Тільки крізь скляний фільтр №1 або №2."
        }

        let hasBoilingDissolution = activeIngredients.contains(where: requiresBoilingWaterDissolution)
        let hasHotDissolution = hasBoilingDissolution || activeIngredients.contains(where: requiresHotWaterDissolution)

        if activeIngredients.contains(where: requiresGlassFilterOnly) {
            return "Процідити тільки через скляний фільтр або промиту скляну вату; органічні фільтри (вата, папір) не використовувати."
        }

        if activeIngredients.contains(where: isStrongOxidizerIngredient) {
            return "Процідити тільки через скляний фільтр або скляну вату; контакт із папером чи ватою не допускається."
        }

        if activeIngredients.contains(where: requiresWarmCottonFilter) {
            if hasBoilingDissolution {
                return "Процідити гарячим через пухкий ватний тампон, поки розчин не почав кристалізуватися."
            }
            return "Процідити теплим через пухкий ватний тампон, поки розчин не почав кристалізуватися."
        }

        if activeIngredients.contains(where: isFuracilinIngredient) {
            if hasBoilingDissolution {
                return "Перед фільтрацією переконатися у повному розчиненні кристалів фурациліну; за наявності осаду продовжити нагрівання/перемішування. Процідити розчин гарячим крізь пухкий ватний тампон (паперовий фільтр не використовувати)"
            }
            if hasHotDissolution {
                return "Перед фільтрацією переконатися у повному розчиненні кристалів фурациліну; за наявності осаду продовжити підігрівання/перемішування. Процідити розчин теплим крізь пухкий ватний тампон (паперовий фільтр не використовувати)"
            }
            return "Перед фільтрацією переконатися у повному розчиненні кристалів фурациліну; за наявності осаду продовжити перемішування. Процідити крізь пухкий ватний тампон (паперовий фільтр не використовувати)"
        }

        if shouldCottonFilter {
            if hasBoilingDissolution {
                return "Процідити розчин гарячим крізь пухкий ватний тампон (паперовий фільтр не використовувати)"
            }
            if hasHotDissolution {
                return "Процідити розчин теплим крізь пухкий ватний тампон (паперовий фільтр не використовувати)"
            }
            return "Процідити крізь пухкий ватний тампон (паперовий фільтр не використовувати)"
        }

        return needsFiltration ? "За потреби профільтрувати" : "Фільтрація не потрібна"
    }

    private func shouldUseOptionalFiltrationForSimpleSolution(
        activeIngredients: [IngredientDraft],
        hasBoilingDissolution: Bool,
        hasHotDissolution: Bool,
        hasPepsin: Bool,
        hasLateAddedLiquids: Bool,
        usesBurette: Bool
    ) -> Bool {
        guard activeIngredients.count == 1, let ingredient = activeIngredients.first else { return false }
        guard !hasBoilingDissolution, !hasHotDissolution else { return false }
        guard !hasPepsin, !hasLateAddedLiquids, !usesBurette else { return false }
        if requiresGlassFilterOnly(ingredient) { return false }
        if isStrongOxidizerIngredient(ingredient) { return false }
        if isSilverNitrateIngredient(ingredient) { return false }
        if requiresWarmCottonFilter(ingredient) { return false }
        return true
    }

    private func specialWaterPackagingLines(
        activeIngredients: [IngredientDraft],
        signa: String
    ) -> [String]? {
        let hasListA = activeIngredients.contains(where: isListAIngredient)
        let hasFreshlyDistilledWater = activeIngredients.contains(where: requiresFreshlyDistilledWater)
        if hasListA, hasFreshlyDistilledWater {
            return [
                "Флакон з темного (оранжевого) скла",
                "Щільно закоркувати та опечатати",
                "Етикетки: «Обережно», «Зберігати в захищеному від світла місці»",
                "Зберігати під замком (Список А)"
            ]
        }

        let hasIodineSystem = activeIngredients.contains(where: isIodineIngredient)
            || activeIngredients.contains(where: isIodideIngredient)
            || activeIngredients.contains(where: isLugolIngredient)
        if hasIodineSystem {
            let routeLabel = routeLabelForSpecialAqueousSolutions(signa: signa, defaultLabel: "Зовнішнє")
            return [
                "Флакон з темного скла",
                "Щільно закоркувати",
                "Етикетка: «\(routeLabel)»",
                "Зберігати в прохолодному та захищеному від світла місці"
            ]
        }

        if activeIngredients.contains(where: isLightSensitiveByMarker) {
            let routeLabel = routeLabelForSpecialAqueousSolutions(signa: signa, defaultLabel: "Зовнішнє")
            return [
                "Флакон з темного скла",
                "Етикетка: «\(routeLabel)»",
                "Зберігати в прохолодному та захищеному від світла місці"
            ]
        }

        return nil
    }

    private func sanitizePackagingClaimsWithoutEvidence(
        _ lines: [String],
        activeIngredients: [IngredientDraft]
    ) -> [String] {
        guard !hasExplicitStorageRequirement(activeIngredients: activeIngredients) else {
            return lines
        }

        let filtered = lines.filter { line in
            !isStorageClaimLine(line)
        }
        if filtered.isEmpty {
            return ["Флакон", "Етикетка: «Внутрішнє»"]
        }
        return filtered
    }

    private func hasExplicitStorageRequirement(activeIngredients: [IngredientDraft]) -> Bool {
        activeIngredients.contains { ingredient in
            hasExplicitStorageRequirement(ingredient)
        }
    }

    private func hasExplicitStorageRequirement(_ ingredient: IngredientDraft) -> Bool {
        if isEthacridineIngredient(ingredient) {
            return true
        }
        if ingredient.isReferenceLightSensitive
            || ingredient.isReferenceListA
            || ingredient.refSterile
            || ingredient.isReferenceVolatileAqueousLiquid {
            return true
        }

        let storage = (ingredient.refStorage ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if !storage.isEmpty {
            if storage.contains("світл")
                || storage.contains("light")
                || storage.contains("темн")
                || storage.contains("оранж")
                || storage.contains("прохолод")
                || storage.contains("холод")
                || storage.contains("cool")
                || storage.contains("cold")
                || storage.contains("зберіг")
                || storage.contains("store") {
                return true
            }
        }

        return markerMatch(
            ingredient,
            keys: ["storage", "instruction_id", "process_note", "light_sensitive", "packaging"],
            values: [
                "lightprotected",
                "protectfromlight",
                "light_sensitive",
                "amberglass",
                "darkglass",
                "темнескло",
                "coolplace",
                "cool_storage",
                "store_cool",
                "tight_closure"
            ]
        )
    }

    private func isStorageClaimLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("зберіг")
            || lower.contains("прохолод")
            || lower.contains("холод")
            || lower.contains("cool")
            || lower.contains("cold")
            || lower.contains("берегти від світла")
            || lower.contains("захищен")
            || lower.contains("темного")
            || lower.contains("оранжевого")
            || lower.contains("dark")
            || lower.contains("amber")
    }

    private func routeLabelForSpecialAqueousSolutions(signa: String, defaultLabel: String) -> String {
        let semantics = SignaUsageAnalyzer.analyze(signa: signa)
        let lower = signa.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let hasExternalMarker = semantics.isExternalRoute
            || semantics.isRinseOrGargle
            || semantics.isEyeRoute
            || semantics.isNasalRoute
            || lower.contains("промив")
            || lower.contains("промыван")
            || lower.contains("обробк")
            || lower.contains("обработк")
            || lower.contains("сечов")
            || lower.contains("мочев")
            || lower.contains("кож")
            || lower.contains("шкір")
            || lower.contains("зів")
            || lower.contains("зева")
        if hasExternalMarker {
            return "Зовнішнє"
        }

        let hasInternalMarker = lower.contains("внутр")
            || lower.contains("всеред")
            || lower.contains("внутрь")
            || lower.contains("per os")
            || lower.contains("peroral")
            || lower.contains("з молоком")
            || lower.contains("с молоком")
            || semantics.hasSpoonDose
            || semantics.isTrueDropsDosageForm
            || (lower.contains("по ") && (lower.contains("раз") || lower.contains("день")))
        if hasInternalMarker {
            return "Внутрішнє"
        }

        return defaultLabel
    }

    private func dissolutionTargetsPhrase(activeIngredients: [IngredientDraft], includeNaCl: Bool) -> String {
        var targets: [String] = []
        if includeNaCl {
            targets.append("NaCl")
        }

        if activeIngredients.count == 1, let active = activeIngredients.first {
            let normalized = normalizedHay(active)
            if normalized.contains("furacil") || normalized.contains("nitrofural") || normalized.contains("фурацил") {
                targets.append("фурацилін")
            } else {
                let name = operationIngredientName(active)
                targets.append(name.isEmpty ? "речовини" : name)
            }
        } else if !activeIngredients.isEmpty {
            let ordered = activeIngredients.sorted { lhs, rhs in
                let lp = dissolutionPriority(lhs)
                let rp = dissolutionPriority(rhs)
                if lp != rp { return lp < rp }
                return operationIngredientName(lhs).localizedCaseInsensitiveCompare(operationIngredientName(rhs)) == .orderedAscending
            }

            if ordered.count == 2 {
                let first = operationIngredientName(ordered[0])
                let second = operationIngredientName(ordered[1])
                if !first.isEmpty, !second.isEmpty {
                    targets.append("\(first), потім \(second)")
                } else {
                    targets.append("активні речовини")
                }
            } else if let first = ordered.first {
                let firstName = operationIngredientName(first)
                if !firstName.isEmpty {
                    targets.append("\(firstName), далі решту активних речовин")
                } else {
                    targets.append("активні речовини")
                }
            } else {
                targets.append("активні речовини")
            }
        }

        if targets.isEmpty {
            return "речовини"
        }
        return targets.joined(separator: " та ")
    }

    private func dissolutionPriority(_ ingredient: IngredientDraft) -> Int {
        if requiresBoilingWaterDissolution(ingredient) { return 0 }
        if requiresHotWaterDissolution(ingredient) { return 1 }
        if requiresWarmWaterDissolution(ingredient) { return 2 }
        let ratio = WaterSolubilityHeuristics.waterRatioDenominator(ingredient.refSolubility) ?? 0
        if ratio >= 50 { return 3 }
        if ratio > 0, ratio <= 10 { return 5 }
        return 4
    }

    private func operationIngredientName(_ ingredient: IngredientDraft) -> String {
        let latin = (ingredient.refNameLatNom ?? ingredient.refNameLatGen ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !latin.isEmpty, latin.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil {
            let cleaned = latin
                .replacingOccurrences(of: #"(?i)^solutionis\s+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s+\d+(?:[.,]\d+)?\s*%$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                return cleaned
            }
        }
        return ingredient.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isExplicitNatriiChloridum(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("natrii chlorid")
            || hay.contains("natrii chloridi")
            || hay.contains("sodium chlorid")
            || hay.contains("натрію хлорид")
            || hay.contains("натрия хлорид")
    }

    private func waterEquationLine(
        primaryAqueousName: String,
        targetVolume: Double,
        liquidComponents: Double,
        displacementVolume: Double,
        result: Double
    ) -> String? {
        guard targetVolume > 0 else { return nil }
        let epsilon = 0.0001
        var terms: [String] = [format(targetVolume)]
        if liquidComponents > epsilon {
            terms.append(format(liquidComponents))
        }
        if displacementVolume > epsilon {
            terms.append(format(displacementVolume))
        }
        guard terms.count > 1 else { return nil }
        return "\(primaryAqueousName) = \(terms.joined(separator: " - ")) = \(format(result)) ml"
    }

    private func deduplicatedLines(_ lines: [String]) -> [String] {
        var seen: Set<String> = []
        return lines.filter { seen.insert($0).inserted }
    }

    private func isSodiumSalicylate(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        return hay.contains("natrii salicyl")
            || hay.contains("sodium salicyl")
            || hay.contains("саліцилат натрію")
            || hay.contains("натрия салицилат")
    }

    private func isSalicylateIngredient(_ ing: IngredientDraft) -> Bool {
        normalizedHay(ing).contains("salicyl")
    }

    private func isTweenOrSpanIngredient(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        return hay.contains("tween")
            || hay.contains("polysorbat")
            || hay.contains("polysorbate")
            || hay.contains("твин")
            || hay.contains("span")
            || hay.contains("sorbitan monooleat")
            || hay.contains("сорбитан моноолеат")
            || hay.contains("спан")
    }

    private func isPhenolFamilyIngredient(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        return hay.contains("phenol")
            || hay.contains("phenolum")
            || hay.contains("carbol")
            || hay.contains("тимол")
            || hay.contains("thymol")
            || hay.contains("resorcin")
            || hay.contains("фенол")
    }

    private func isParaHydroxyBenzoicDerivativeIngredient(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        return hay.contains("paraben")
            || hay.contains("parahydroxybenzo")
            || hay.contains("параокси")
            || hay.contains("парагидроксибенз")
            || hay.contains("nipagin")
            || hay.contains("nipazol")
    }

    private func isSodiumBicarbonate(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        return hay.contains("natrii hydrocarbon")
            || hay.contains("natrii bicarbon")
            || hay.contains("sodium bicarb")
            || hay.contains("натрію гідрокарбонат")
            || hay.contains("натрия гидрокарбонат")
    }

    private func isHexamethylenetetramine(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        return hay.contains("hexamethylenetetramin")
            || hay.contains("urotrop")
            || hay.contains("уротроп")
    }

    private func isAcidicIngredient(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        if hay.contains("acid") || hay.contains("acidi") || hay.contains("кислот") {
            return true
        }
        let notes = ((ing.refInteractionNotes ?? "") + " " + (ing.refSolventType ?? "")).lowercased()
        return notes.contains("acid")
            || notes.contains("кисл")
    }

    private func isAcidifyingIngredient(_ ing: IngredientDraft) -> Bool {
        if ing.propertyOverride?.interactionRules.contains(.incompatibleWithAcids) == true {
            return false
        }
        return isAcidicIngredient(ing)
    }

    private func isAlkalineIngredient(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        if hay.contains("hydrocarbonas") || hay.contains("tetraboras") || hay.contains("hydroxyd") || hay.contains("щел") || hay.contains("луг") {
            return true
        }
        let notes = ((ing.refInteractionNotes ?? "") + " " + (ing.refSolventType ?? "")).lowercased()
        return notes.contains("alkali")
            || notes.contains("alkal")
            || notes.contains("луж")
            || notes.contains("щел")
    }

    private func isAlkalizingIngredient(_ ing: IngredientDraft) -> Bool {
        if ing.propertyOverride?.interactionRules.contains(.incompatibleWithAlkalies) == true {
            return false
        }
        return isAlkalineIngredient(ing)
    }

    private func isGlycerinIngredient(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        return hay.contains("glycer")
            || hay.contains("glycerin")
            || hay.contains("glycerinum")
            || hay.contains("гліцерин")
            || hay.contains("глицерин")
    }

    private func isAntibioticIngredient(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        let activity = (ing.refPharmActivity ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if hay.contains("antibiot")
            || hay.contains("антибіот")
            || hay.contains("антибиот")
        {
            return true
        }
        return hay.contains("penicillin")
            || hay.contains("benzylpenicillin")
            || hay.contains("streptomycin")
            || hay.contains("gentamicin")
            || hay.contains("chloramphenicol")
            || hay.contains("levomycetin")
            || hay.contains("erythromycin")
            || hay.contains("tetracyclin")
            || hay.contains("цеф")
            || hay.contains("cef")
            || activity.contains("антибіот")
            || activity.contains("антибиот")
    }

    private func format(_ v: Double) -> String {
        if v == floor(v) { return String(Int(v)) }
        return String(format: "%.3f", v)
    }
}
