import Foundation

struct BaseTechnologyBlock: RxProcessingBlock {
    static let blockId = "base"
    let id = blockId

    func apply(context: inout RxPipelineContext) {
        context.addStep(TechStep(kind: .prep, title: "Перевірити склад, підготувати тару та етикетки", ingredientIds: context.draft.ingredients.map(\.id)))

        let inferredTargetSolutionIngredientId: UUID? = {
            let hasExplicitAdOrQsTarget = context.draft.explicitLiquidTargetMl != nil
                || context.draft.legacyAdOrQsLiquidTargetMl != nil
            guard !hasExplicitAdOrQsTarget else { return nil }
            let hasAquaPurificataIngredient = context.draft.ingredients.contains { ing in
                !ing.isQS && !ing.isAd && ing.unit.rawValue == "ml" && PurifiedWaterHeuristics.isPurifiedWater(ing)
            }
            guard !hasAquaPurificataIngredient else { return nil }

            let candidates = context.draft.ingredients
                .filter { !$0.isQS && !$0.isAd && $0.presentationKind == .solution }
                .compactMap { ing -> (UUID, Double)? in
                    guard let v = context.draft.solutionVolumeMl(for: ing), v > 0 else { return nil }
                    return (ing.id, v)
                }
            return candidates.max(by: { $0.1 < $1.1 })?.0
        }()
        let inferredWaterAmounts = inferredPurifiedWaterAmounts(
            context: context,
            inferredTargetSolutionIngredientId: inferredTargetSolutionIngredientId
        )
        let inferredSolutionMasses = inferredSolutionSolidMasses(context: context)

        let lines = context.draft.ingredients.map { ing in
            if let solutionAmount = solutionAmountText(for: ing, draft: context.draft) {
                return "• \(ing.displayName.isEmpty ? "Subst." : ing.displayName) — \(solutionAmount)"
            }

            let inferredWater = inferredWaterAmounts[ing.id]
            let inferredMass = inferredSolutionMasses[ing.id]
            let displayAmount = inferredWater ?? inferredMass ?? ing.amountValue
            let displayUnit = {
                if ing.isAd || ing.isQS {
                    return context.draft.resolvedTargetUnit?.rawValue ?? ing.unit.rawValue
                }
                return inferredMass == nil ? ing.unit.rawValue : "g"
            }()
            let amountUnit: String = {
                if displayAmount > 0 {
                    return "\(format(displayAmount)) \(displayUnit)"
                }
                if ing.isAd {
                    return "ad \(ing.unit.rawValue)"
                }
                return "\(format(displayAmount)) \(displayUnit)"
            }()

            let note: String = {
                if inferredWater != nil { return " (для відмірювання)" }
                if inferredMass != nil { return " (розраховано з % та ml)" }
                return ""
            }()
            return "• \(ing.displayName.isEmpty ? "Subst." : ing.displayName) — \(amountUnit)\(note)"
        }
        var finalLines = lines
        if let syntheticAqua = inferredSyntheticWaterAmount(
            context: context,
            inferredTargetSolutionIngredientId: inferredTargetSolutionIngredientId
        ) {
            finalLines.append("• Aqua purificata — \(format(syntheticAqua)) ml (розраховано)")
        }

        context.appendSection(title: "Склад", lines: finalLines.isEmpty ? ["—"] : finalLines)

        let referenceLines = referenceDataLines(context: context)
        if !referenceLines.isEmpty {
            context.appendSection(title: "Довідкові дані", lines: referenceLines)
        }

        let rationaleLines = universalRationaleLines(context: context)
        if !rationaleLines.isEmpty {
            context.appendSection(title: "Технологія", lines: rationaleLines)
        }

        let reasoningLines = reasoningMatrixLines(context: context)
        if !reasoningLines.isEmpty {
            context.appendSection(title: "Логіка обґрунтування", lines: reasoningLines)
        }
    }

    private func inferredPurifiedWaterAmounts(
        context: RxPipelineContext,
        inferredTargetSolutionIngredientId: UUID?
    ) -> [UUID: Double] {
        let targetMl = context.facts.inferredLiquidTargetMl ?? 0
        guard targetMl > 0 else { return [:] }
        let burette = BuretteSystem.evaluateBurette(draft: context.draft)
        let buretteVolumeMl = burette.totalConcentrateVolumeMl
        let buretteIngredientIds = burette.matchedIngredientIds

        let waterCandidates = context.draft.ingredients.filter { ing in
            !ing.isQS
            && ing.unit.rawValue == "ml"
            && PurifiedWaterHeuristics.isPurifiedWater(ing)
        }
        guard !waterCandidates.isEmpty else { return [:] }

        let selectedWater: IngredientDraft? = {
            if let explicitAd = waterCandidates.last(where: { $0.isAd }) {
                return explicitAd
            }
            return waterCandidates.max(by: { $0.amountValue < $1.amountValue })
        }()
        guard let selectedWater else { return [:] }

        let shouldOverrideOriginalAmount = selectedWater.isAd
            || selectedWater.amountValue <= 0
            || context.draft.explicitLiquidTargetMl == nil

        var otherLiquids = context.draft.ingredients.compactMap { ing -> Double? in
            guard !ing.isAd, !ing.isQS else { return nil }
            if ing.id == selectedWater.id { return nil }
            if buretteIngredientIds.contains(ing.id) { return nil }
            if let inferredTargetSolutionIngredientId, ing.id == inferredTargetSolutionIngredientId { return nil }
            let volume = context.draft.effectiveLiquidVolumeMl(for: ing)
            return volume > 0 ? volume : nil
        }
        if buretteVolumeMl > 0 {
            otherLiquids.append(buretteVolumeMl)
        }

        let solids = context.draft.ingredients.compactMap { ing -> (weight: Double, kuo: Double?)? in
            guard !ing.isAd, !ing.isQS else { return nil }
            if buretteIngredientIds.contains(ing.id) { return nil }
            guard ing.unit.rawValue == "g", ing.amountValue > 0 else { return nil }
            guard !isLiquidIngredient(ing) else { return nil }
            return (weight: ing.amountValue, kuo: ing.refKuoMlPerG)
        }

        let adResult = PharmaCalculator.calculateAdWater(
            targetVolume: targetMl,
            otherLiquids: otherLiquids,
            solids: solids,
            kuoPolicy: .adaptive
        )
        guard adResult.amountToMeasure > 0 else { return [:] }

        let hasMeaningfulCorrection = abs(adResult.amountToMeasure - selectedWater.amountValue) > 0.0001
        guard shouldOverrideOriginalAmount || hasMeaningfulCorrection else { return [:] }

        return [selectedWater.id: adResult.amountToMeasure]
    }

    private func inferredSolutionSolidMasses(context: RxPipelineContext) -> [UUID: Double] {
        return Dictionary(uniqueKeysWithValues: context.draft.ingredients.compactMap { ing in
            guard !ing.isQS, !ing.isAd else { return nil }
            guard ing.presentationKind == .solution else { return nil }
            guard ing.unit.rawValue == "g" else { return nil }
            guard !isLiquidIngredient(ing) else { return nil }
            guard ing.amountValue <= 0 else { return nil }
            guard let mass = context.draft.solutionActiveMassG(for: ing), mass > 0 else { return nil }
            guard mass > 0 else { return nil }
            return (ing.id, mass)
        })
    }

    private func inferredSyntheticWaterAmount(
        context: RxPipelineContext,
        inferredTargetSolutionIngredientId: UUID?
    ) -> Double? {
        let targetMl = context.facts.inferredLiquidTargetMl ?? 0
        guard targetMl > 0 else { return nil }
        guard inferredTargetSolutionIngredientId != nil else { return nil }
        let burette = BuretteSystem.evaluateBurette(draft: context.draft)
        let buretteVolumeMl = burette.totalConcentrateVolumeMl
        let buretteIngredientIds = burette.matchedIngredientIds

        let hasMeasuredWaterIngredient = context.draft.ingredients.contains { ing in
            !ing.isQS && !ing.isAd && ing.unit.rawValue == "ml" && ing.amountValue > 0 && PurifiedWaterHeuristics.isPurifiedWater(ing)
        }
        guard !hasMeasuredWaterIngredient else { return nil }

        var otherLiquids = context.draft.ingredients.compactMap { ing -> Double? in
            guard !ing.isQS, !ing.isAd else { return nil }
            if let inferredTargetSolutionIngredientId, ing.id == inferredTargetSolutionIngredientId { return nil }
            if buretteIngredientIds.contains(ing.id) { return nil }
            if ing.presentationKind == .solution {
                return max(0, context.draft.solutionVolumeMl(for: ing) ?? 0)
            }
            guard ing.unit.rawValue == "ml" else { return nil }
            return max(0, ing.amountValue)
        }
        if buretteVolumeMl > 0 {
            otherLiquids.append(buretteVolumeMl)
        }

        let solids = context.draft.ingredients.compactMap { ing -> (weight: Double, kuo: Double?)? in
            guard !ing.isQS, !ing.isAd else { return nil }
            if buretteIngredientIds.contains(ing.id) { return nil }
            guard ing.unit.rawValue == "g" else { return nil }
            guard !isLiquidIngredient(ing) else { return nil }

            let explicit = max(0, ing.amountValue)
            if explicit > 0 {
                return (weight: explicit, kuo: ing.refKuoMlPerG)
            }

            guard let inferred = context.draft.solutionActiveMassG(for: ing), inferred > 0 else { return nil }
            guard inferred > 0 else { return nil }
            return (weight: inferred, kuo: ing.refKuoMlPerG)
        }

        let adResult = PharmaCalculator.calculateAdWater(
            targetVolume: targetMl,
            otherLiquids: otherLiquids,
            solids: solids,
            kuoPolicy: .adaptive
        )
        guard adResult.amountToMeasure > 0 else { return nil }
        return adResult.amountToMeasure
    }

    private func solutionAmountText(for ing: IngredientDraft, draft: ExtempRecipeDraft) -> String? {
        guard ing.presentationKind == .solution else { return nil }
        guard let volume = draft.solutionVolumeMl(for: ing), volume > 0 else { return nil }

        if let percent = draft.solutionDisplayPercent(for: ing) {
            return "\(format(percent))% \(format(volume)) ml"
        }

        return "\(format(volume)) ml"
    }

    private func universalRationaleLines(context: RxPipelineContext) -> [String] {
        let effectiveFormMode = SignaUsageAnalyzer.effectiveFormMode(for: context.draft)
        let systemType: String = {
            switch effectiveFormMode {
            case .solutions:
                return "розчином (рідкою дисперсною системою)"
            case .drops:
                return "краплями (рідкою дозованою системою)"
            case .powders:
                return "порошковою дисперсною системою"
            case .ointments:
                return "м'якою дисперсною системою"
            case .suppositories:
                return "супозиторною системою"
            case .auto:
                return "екстемпоральною системою"
            }
        }()

        let hasPepsin = context.draft.ingredients.contains(where: isPepsin)
        let hasProtargol = context.draft.ingredients.contains(where: isProtargol)
        let hasCollargol = context.draft.ingredients.contains(where: isCollargol)
        let hasStarch = context.draft.ingredients.contains(where: isStarch)
        let hasEssentialOil = context.draft.ingredients.contains(where: isEssentialOil)
        let hasCalciumChloride = context.draft.ingredients.contains(where: isCalciumChloride)

        let factorLine: String = {
            if hasPepsin {
                return "2) Фактор стабільності: враховуючи термолабільність ферменту та потребу кислого pH, важливо дотриматись послідовності: підкислення води -> введення пепсину при кімнатній температурі."
            }
            if hasProtargol || hasCollargol {
                return "2) Фактор стабільності: враховуючи колоїдну природу частинок, критично не допускати агрегації та коагуляції при грубому перемішуванні."
            }
            if hasStarch {
                return "2) Фактор стабільності: враховуючи властивості крохмалю як ВМС, критично забезпечити коректний тепловий режим для утворення однорідного клейстеру."
            }
            if hasEssentialOil {
                return "2) Фактор стабільності: враховуючи леткість компонентів, важливо контролювати температуру та порядок введення, щоб мінімізувати втрати."
            }
            if context.facts.hasVmsOrColloid {
                return "2) Фактор стабільності: враховуючи високомолекулярну/колоїдну природу системи, важливо контролювати pH, температуру та інтенсивність перемішування."
            }
            if effectiveFormMode == .powders {
                return "2) Фактор стабільності: враховуючи дисперсність твердих компонентів, важливо дотриматись послідовного змішування для рівномірності доз."
            }
            return "2) Фактор стабільності: враховуючи фізико-хімічні властивості компонентів, важливо дотриматись температурного режиму, порядку введення та сумісності."
        }()

        let criticalLine: String = {
            if hasPepsin {
                return "3) Критична точка технології: обрано ватний фільтр, щоб запобігти втратам діючої речовини через адсорбцію на паперовому фільтрі."
            }
            if hasProtargol || hasCollargol {
                return "3) Критична точка технології: обрано метод нашарування на воду (без інтенсивного збовтування), щоб забезпечити стабільний колоїдний стан."
            }
            if hasStarch {
                return "3) Критична точка технології: обрано гарячу воду та поетапне введення, щоб забезпечити повне клейстероутворення."
            }
            if hasEssentialOil {
                return "3) Критична точка технології: леткі олії вводяться в останню чергу до охолодженого середовища для збереження концентрації."
            }
            if effectiveFormMode == .powders {
                return "3) Критична точка технології: використано поетапну тритурацію, щоб досягти максимальної однорідності суміші."
            }
            return "3) Критична точка технології: технологічні операції підібрані для збереження стабільності, однорідності та відтворюваності лікарської форми."
        }()

        var lines: [String] = [
            "Універсальне обґрунтування (Природа речовини -> Критична умова -> Технологічне рішення):",
            "1) Класифікація: дана лікарська форма є \(systemType).",
            factorLine,
            criticalLine
        ]

        if hasPepsin {
            lines.append("Дана лікарська форма є розчином високомолекулярної сполуки. Оскільки пепсин - це фермент, що активується в кислому середовищі та денатурує при нагріванні, я спочатку підкислив воду, а потім розчинив пепсин при кімнатній температурі. Використано ватний фільтр, щоб уникнути втрати діючої речовини через електростатичну адсорбцію на папері.")
        }

        if hasProtargol {
            lines.append("Адаптація для Protargolum: захищений колоїд, вводити методом нашарування на воду без грубого перемішування.")
        }
        if hasCollargol {
            lines.append("Адаптація для Collargolum: повільне набухання та пептизація, уникати різкого механічного впливу.")
        }
        if hasStarch {
            lines.append("Адаптація для Amylum: для переходу в золь потрібна гаряча вода та коректний режим нагрівання.")
        }
        if hasEssentialOil {
            lines.append("Адаптація для ефірних олій: вводити в останню чергу до охолодженого розчину, щоб мінімізувати випаровування.")
        }
        if context.draft.useBuretteSystem, hasCalciumChloride {
            lines.append("Адаптація для Calcii chloridum: через виражену гігроскопічність речовину доцільно вводити у вигляді концентрованого розчину (бюреточний метод), а не зважувати як сухий порошок.")
        }

        return lines
    }

    private func reasoningMatrixLines(context: RxPipelineContext) -> [String] {
        let summary = reasoningSummary(context: context)
        return summary.isEmpty ? [] : [summary]
    }

    private func reasoningSummary(context: RxPipelineContext) -> String {
        let classification = reasoningClassification(context: context)
        let mathSentence = reasoningMathSentence(context: context)
        let protectionSentence = reasoningProtectionSentence(context: context)
        guard !classification.isEmpty else { return "" }

        return "Дана лікарська форма — \(classification). \(mathSentence) \(protectionSentence)"
    }

    private func reasoningClassification(context: RxPipelineContext) -> String {
        switch SignaUsageAnalyzer.effectiveFormMode(for: context.draft) {
        case .powders:
            let activeIngredients = context.draft.ingredients.filter { !$0.isAd && !$0.isQS }
            let isDosed = (context.draft.numero ?? 0) > 0
            if activeIngredients.count <= 1 {
                return isDosed ? "простий дозований порошок" : "простий порошок"
            }
            return isDosed ? "складний дозований порошок" : "складний порошок"
        case .ointments:
            let result = OintmentsCalculator.calculate(draft: context.draft)
            if !result.groups.insoluble.isEmpty && (!result.groups.waterSoluble.isEmpty || !result.groups.oilSoluble.isEmpty || !result.groups.ethanolSoluble.isEmpty) {
                return "комбінована мазь"
            }
            if !result.groups.insoluble.isEmpty {
                if result.totalMassG > 0, result.insolubleMassG / result.totalMassG >= 0.25 {
                    return "паста"
                }
                return "суспензійна мазь"
            }
            return "гомогенна мазь"
        case .solutions, .drops:
            if hasOilWaterPair(context: context) {
                return "емульсія"
            }
            if hasProtectedColloid(context: context) {
                return "колоїдний розчин"
            }
            if hasVmsSolution(context: context) {
                return "розчин ВМС"
            }
            if hasInsolublePowder(context: context) {
                return "суспензія"
            }
            return "істинний водний розчин"
        case .suppositories:
            return "дозована супозиторна форма"
        case .auto:
            return "екстемпоральна лікарська форма"
        }
    }

    private func reasoningMathSentence(context: RxPipelineContext) -> String {
        switch SignaUsageAnalyzer.effectiveFormMode(for: context.draft) {
        case .powders:
            if context.facts.hasTriturationRisk {
                return "Оскільки у складі є малі дози активних речовин, змішування проведено методом геометричного розведення або тритурації для рівномірності доз."
            }
            return "Оскільки компоненти мають різну насипну масу, змішування проведено від меншої кількості до більшої для однорідності суміші."
        case .ointments:
            let result = OintmentsCalculator.calculate(draft: context.draft)
            if result.totalMassG > 0, result.insolubleMassG / result.totalMassG >= 0.25 {
                return "Оскільки вміст сухих речовин перевищує 25%, технологію побудовано як для пасти з попереднім приготуванням пульпи."
            }
            if !result.groups.insoluble.isEmpty {
                return "Оскільки частина речовин не розчиняється в основі, їх попередньо вводять через пульпу для досягнення тонкої дисперсності."
            }
            return "Оскільки речовини розподіляються у відповідній фазі основи, їх вводять через розчинення або рівномірне змішування."
        case .solutions, .drops:
            let solventMode = (context.calculations["solvent_calculation_mode"] ?? "").lowercased()
            let usesKuoMode = solventMode == "kou_calculation"
            let usesQsToVolumeMode = solventMode == "qs_to_volume"
            if context.draft.useStandardSolutionsBlock, context.facts.hasStandardSolutionAlias {
                return "Оскільки застосовано стандартний фармакопейний розчин, розведення виконують за формулою X = V·B/A з урахуванням фактичної концентрації."
            }
            if hasOilWaterPair(context: context) {
                return "Оскільки у складі є олійна та водна фази, систему формують як емульсію з поетапним введенням фаз."
            }
            if hasInsolublePowder(context: context) {
                return "Оскільки дисперсна фаза не розчиняється у середовищі, препарат готують як суспензію зі стабілізацією частинок."
            }
            if hasPrimaryAromaticWater(context: context), let solidsPercent = context.facts.solidsPercentOfTarget {
                let shouldUseKuo = usesKuoMode || (!usesQsToVolumeMode && solidsPercent >= 3)
                return "Оскільки ароматна вода використовується як основний розчинник і є готовою леткою водною системою 1:1000, сухі речовини розчиняють безпосередньо в ній; сумарна концентрація сухих речовин становить \(formatPercent(solidsPercent))%, тому \(shouldUseKuo ? "об'єм розчинника розраховано з урахуванням КУО" : "КУО не застосовують")."
            }
            if hasPremixVolatileDrops(context: context) {
                return "Оскільки спиртовий розчин ароматичних речовин при прямому контакті з водою може дати каламуть, його попередньо змішують з частиною готової мікстури у співвідношенні 1:1-1:2."
            }
            if context.draft.useBuretteSystem {
                return "Оскільки у складі використовуються готові концентровані розчини (бюреточний метод), розрахунок розчинника виконано за сумою введених об'ємів; КУО сухих речовин не застосовують."
            }
            if let solidsPercent = context.facts.solidsPercentOfTarget {
                if usesKuoMode {
                    return "Оскільки концентрація сухих речовин становить \(formatPercent(solidsPercent))%, кількість розчинника розрахована з урахуванням КУО для забезпечення точності об'єму."
                }
                if usesQsToVolumeMode {
                    return "Оскільки концентрація сухих речовин становить \(formatPercent(solidsPercent))%, розчинник доводять до кінцевого об'єму (q.s. ad V) без обов'язкового розрахунку КУО."
                }
                if solidsPercent >= 3 {
                    return "Оскільки концентрація сухих речовин становить \(formatPercent(solidsPercent))%, рішення щодо КУО прийнято за технологічним режимом та довідковими властивостями речовин."
                }
                return "Оскільки сумарна концентрація сухих речовин становить \(formatPercent(solidsPercent))%, кількість рідкого носія прийнято без урахування КУО."
            }
            if hasProtectedColloid(context: context) || hasVmsSolution(context: context) {
                return "Оскільки система має колоїдну або високомолекулярну природу, обрано спеціальний режим введення та розчинення."
            }
            return "Оскільки компоненти утворюють однорідну рідку систему, розрахунок розчинника проведено для отримання заданого кінцевого об'єму."
        case .suppositories:
            return "Оскільки маса кожного супозиторія має бути точною, розрахунок виконано з урахуванням заміщення та дозування на одну одиницю."
        case .auto:
            return "Оскільки фізико-хімічні властивості компонентів визначають технологію, розрахунки виконано за профілем лікарської форми."
        }
    }

    private func reasoningProtectionSentence(context: RxPipelineContext) -> String {
        var actions: [String] = []
        let effectiveFormMode = SignaUsageAnalyzer.effectiveFormMode(for: context.draft)

        if hasLightSensitiveIngredient(context: context) {
            actions.append("препарат готують у флаконі з темного скла")
        }
        if context.draft.ingredients.contains(where: isPepsin) {
            actions.append("воду спочатку підкислюють, а фермент вводять без нагрівання")
        }
        let listAIngredients = context.draft.ingredients.filter(isListAIngredient)
        if !listAIngredients.isEmpty {
            let hasListALiquid = listAIngredients.contains(where: \.requiresVolumeMeasurement)
            let hasListASolid = listAIngredients.contains(where: { !$0.requiresVolumeMeasurement })
            if effectiveFormMode == .powders && context.draft.ingredients.contains(where: { requiresListAPowderTrituration($0, context: context) }) {
                actions.append("речовини Списку А зважують окремо, для мікродоз спочатку затирають пори ступки наповнювачем, потім вводять тритурацію в середину і продовжують геометричне розведення")
            } else if hasListASolid && hasListALiquid {
                actions.append("речовини Списку А вводять першими: тверді зважують окремо, а рідкі відмірюють окремо у мірному посуді (на терезах не зважують), з подвійним контролем")
            } else if hasListALiquid {
                actions.append("речовини Списку А відмірюють окремо у мірному посуді (на терезах не зважують), вводять першими та перевіряють подвійним контролем")
            } else {
                actions.append("речовини Списку А зважують окремо, вводять першими та перевіряють подвійним контролем")
            }
        }
        if context.draft.ingredients.contains(where: isListBIngredient) {
            if effectiveFormMode == .powders {
                actions.append("речовини Списку Б вносять після затирання пор ступки індиферентним наповнювачем і змішують методом геометричного розведення")
            } else if effectiveFormMode == .solutions || effectiveFormMode == .drops {
                switch NonAqueousSolventCatalog.primarySolvent(in: context.draft)?.type {
                case .ethanol:
                    actions.append("речовини Списку Б у спиртових розчинах розчиняють по черзі безпосередньо у спирті в сухому флаконі; звичайну фільтрацію не застосовують")
                case .ether, .chloroform, .volatileOther, .fattyOil, .mineralOil, .glycerin, .vinylin, .viscousOther:
                    actions.append("речовини Списку Б у неводних системах вводять на ранньому етапі в частину розчинника з урахуванням його леткості та в'язкості")
                case .none:
                    actions.append("речовини Списку Б розчиняють на ранньому етапі та проціджують систему до введення сиропів або настойок")
                }
            } else {
                actions.append("речовини Списку Б вводять під посиленим дозовим контролем")
            }
        }
        if hasAromaticWaters(context: context) {
            actions.append("ароматні води 1:1000 не нагрівають, зберігають при 8-15°C, а робоче проціджування проводять крізь вату")
            actions.append("при різкому помутнінні під час відновлення концентрату допускають фільтрацію крізь змочений водою паперовий фільтр")
        }
        if hasProtectedColloid(context: context) {
            actions.append("колоїдні компоненти вводять без грубого збовтування")
        }
        if hasViscousLiquid(context: context) {
            if let solventType = NonAqueousSolventCatalog.primarySolvent(in: context.draft)?.type,
               solventType.isViscous {
                actions.append("для неводних в'язких систем основний розчинник вводять до/під час розчинення, за потреби застосовують помірне нагрівання на водяній бані (40-60°C), а не після фільтрації")
            } else {
                actions.append("для водних систем в'язкі допоміжні рідини (сиропи тощо) додають після фільтрації")
            }
        }
        if hasVolatileAqueousLiquids(context: context) {
            actions.append("леткі ароматні та антисептичні води додають у кінці без інтенсивного збовтування і флакон щільно закорковують")
        }
        if hasPremixVolatileDrops(context: context) {
            actions.append("спиртові ароматичні краплі попередньо змішують з частиною мікстури перед внесенням")
        }
        if hasLateAddedReadyLiquid(context: context) {
            actions.append("готові рідкі активні препарати додають після фільтрації в останню чергу")
        }
        if hasAntibioticIngredient(context: context) {
            actions.append("антибіотиковмісні препарати готують асептично та відпускають у стерильній тарі")
        }
        if context.draft.ingredients.contains(where: isEssentialOil) {
            actions.append("леткі компоненти вводять в останню чергу")
        }
        if effectiveFormMode == .powders && requiresAsepticPowderForWoundsOrNewborn(context: context) {
            actions.append("порошки для ушкодженої шкіри/відкритих ран і для новонароджених готують асептично; за термостійкості проводять стерилізацію")
        }
        if effectiveFormMode == .powders && context.draft.ingredients.contains(where: isStronglyHygroscopic) {
            actions.append("порошок фасують у захисний папір")
        }
        if effectiveFormMode == .ointments {
            let result = OintmentsCalculator.calculate(draft: context.draft)
            if result.waterPhasePresent {
                actions.append("водну фазу вводять у мінімальному об'ємі з урахуванням стабільності основи")
            }
        }

        if actions.isEmpty {
            if isSimpleWaterSolubleAqueousSolution(context: context) {
                return "Речовина добре розчиняється у воді."
            }
            return "Враховуючи фармацевтичні властивості компонентів, дотримано послідовності введення та умов стабільності."
        }

        return "Враховуючи фармацевтичні властивості компонентів, " + joinClauses(actions) + "."
    }

    private func formatPercent(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == floor(rounded) { return String(Int(rounded)) }
        return String(format: "%.2f", rounded).replacingOccurrences(of: ",", with: ".")
    }

    private func joinClauses(_ clauses: [String]) -> String {
        guard let first = clauses.first else { return "" }
        guard clauses.count > 1 else { return first }

        return clauses.dropFirst().reduce(first) { partial, clause in
            partial + ", а " + clause
        }
    }

    private func isSimpleWaterSolubleAqueousSolution(context: RxPipelineContext) -> Bool {
        guard SignaUsageAnalyzer.effectiveFormMode(for: context.draft) == .solutions
                || SignaUsageAnalyzer.effectiveFormMode(for: context.draft) == .drops
        else { return false }

        if context.draft.useBuretteSystem { return false }
        if NonAqueousSolventCatalog.primarySolvent(in: context.draft) != nil { return false }
        if hasOilWaterPair(context: context)
            || hasProtectedColloid(context: context)
            || hasVmsSolution(context: context)
            || hasInsolublePowder(context: context)
            || hasAromaticWaters(context: context)
            || hasVolatileAqueousLiquids(context: context)
            || hasPremixVolatileDrops(context: context)
            || hasLateAddedReadyLiquid(context: context)
            || hasAntibioticIngredient(context: context)
        {
            return false
        }

        let solidActives = context.draft.ingredients.filter { ingredient in
            !ingredient.isAd
                && !ingredient.isQS
                && ingredient.unit.rawValue == "g"
                && ingredient.amountValue > 0
                && !isLiquidIngredient(ingredient)
        }
        guard solidActives.count == 1, let ingredient = solidActives.first else { return false }
        if isWaterInsolubleOrSparinglySoluble(ingredient) { return false }
        if isStableHalideWithoutExplicitPhotolability(ingredient) { return true }
        return WaterSolubilityHeuristics.hasExplicitWaterSolubility(cleaned(ingredient.refSolubility))
    }

    private func referenceDataLines(context: RxPipelineContext) -> [String] {
        context.draft.ingredients.compactMap { ing in
            if ing.isQS || ing.isAd { return nil }

            var chunks: [String] = []
            if ing.isReferenceListA { chunks.append("Список A") }
            if ing.isReferenceListB { chunks.append("Список B") }
            if ing.refIsNarcotic { chunks.append("Наркотична речовина") }

            if let activity = cleaned(ing.refPharmActivity) {
                chunks.append("Фарм. активність: \(activity)")
            }
            if let state = cleaned(ing.refPhysicalState), !isBooleanLiteral(state) {
                chunks.append("Фіз. стан: \(state)")
            }
            if let storage = cleaned(ing.refStorage) {
                chunks.append("Зберігання: \(short(storage))")
            }
            if let interaction = cleaned(ing.refInteractionNotes) {
                chunks.append("Несумісність: \(short(interaction))")
            }
            if let composition = cleaned(ing.propertyOverride?.standardComposition) {
                chunks.append("Фармакопейний склад: \(short(composition))")
            }
            if ing.refNeedsTrituration {
                chunks.append("Потребує тритурації")
            }

            guard !chunks.isEmpty else { return nil }
            let name = cleaned(ing.refNameLatNom) ?? cleaned(ing.displayName) ?? "Subst."
            return "• \(name): \(chunks.joined(separator: " | "))"
        }
    }

    private func normalizedHay(_ ing: IngredientDraft) -> String {
        let a = (ing.refNameLatNom ?? ing.displayName).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let b = (ing.refInnKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return a + " " + b
    }

    private func isPepsin(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        return hay.contains("pepsin") || hay.contains("pepsinum")
    }

    private func isProtargol(_ ing: IngredientDraft) -> Bool {
        normalizedHay(ing).contains("protarg")
    }

    private func isCollargol(_ ing: IngredientDraft) -> Bool {
        normalizedHay(ing).contains("collarg")
    }

    private func isStarch(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        return hay.contains("amylum") || hay.contains("starch") || hay.contains("крохмал")
    }

    private func isEssentialOil(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        let volatileMarkers = ["olei menthae", "oleum menthae", "peppermint oil", "olei eucalypti", "eucalyptus oil", "anisi oleum", "oleum anisi", "thymi", "lavand", "terebinth", "ефірн"]
        return volatileMarkers.contains(where: { hay.contains($0) })
    }

    private func isCalciumChloride(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        return hay.contains("calcii chlor")
            || hay.contains("calcium chlor")
            || hay.contains("кальция хлорид")
    }

    private func hasProtectedColloid(context: RxPipelineContext) -> Bool {
        context.draft.ingredients.contains(where: isProtargol) || context.draft.ingredients.contains(where: isCollargol)
    }

    private func hasVmsSolution(context: RxPipelineContext) -> Bool {
        let hasStarch = context.draft.ingredients.contains(where: isStarch)
        let hasPepsin = context.draft.ingredients.contains(where: isPepsin)
        return hasStarch || hasPepsin
    }

    private func hasInsolublePowder(context: RxPipelineContext) -> Bool {
        let solventType = NonAqueousSolventCatalog.primarySolvent(in: context.draft)?.type
        return context.draft.ingredients.contains { ing in
            guard !ing.isAd, !ing.isQS else { return false }
            guard ing.unit.rawValue == "g" else { return false }
            guard !isLiquidIngredient(ing) else { return false }
            if isSolubleInSelectedLiquid(ing, solventType: solventType) { return false }
            return isWaterInsolubleOrSparinglySoluble(ing)
        }
    }

    private func isWaterInsolubleOrSparinglySoluble(_ ing: IngredientDraft) -> Bool {
        WaterSolubilityHeuristics.isWaterInsolubleOrSparinglySoluble(cleaned(ing.refSolubility))
    }

    private func isSolubleInSelectedLiquid(_ ing: IngredientDraft, solventType: NonAqueousSolventType?) -> Bool {
        guard let solventType else { return false }
        let solubility = cleaned(ing.refSolubility)?.lowercased() ?? ""
        guard !solubility.isEmpty else { return false }

        switch solventType {
        case .ethanol:
            return solubility.contains("спирт")
                || solubility.contains("alcohol")
                || solubility.contains("ethanol")
        case .glycerin:
            return solubility.contains("гліцерин")
                || solubility.contains("глицерин")
                || solubility.contains("glycer")
        case .fattyOil, .mineralOil, .vinylin, .viscousOther:
            return solubility.contains("ол")
                || solubility.contains("oil")
        case .ether:
            return solubility.contains("ефір")
                || solubility.contains("ether")
        case .chloroform:
            return solubility.contains("хлороформ")
                || solubility.contains("chloroform")
        case .volatileOther:
            return false
        }
    }

    private func hasOilWaterPair(context: RxPipelineContext) -> Bool {
        let hasWater = context.draft.ingredients.contains { ing in
            PurifiedWaterHeuristics.isPurifiedWater(ing)
                || ((ing.refSolventType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased().contains("water"))
        }
        let hasOil = context.draft.ingredients.contains { ing in
            let hay = normalizedHay(ing)
            return hay.contains("ole")
                || hay.contains("oleum")
                || hay.contains("олія")
                || hay.contains("масл")
                || hay.contains("oil")
        }
        return hasWater && hasOil
    }

    private func isStronglyHygroscopic(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        let storage = cleaned(ing.refStorage)?.lowercased() ?? ""
        return hay.contains("calcii chlor")
            || hay.contains("calcium chlor")
            || hay.contains("кальция хлорид")
            || storage.contains("гігроскоп")
            || storage.contains("hygroscop")
    }

    private func hasLightSensitiveIngredient(context: RxPipelineContext) -> Bool {
        context.draft.ingredients.contains { ing in
            if ing.isAd || ing.isQS { return false }
            if PurifiedWaterHeuristics.isPurifiedWater(ing) { return false }
            return isLightSensitive(ing)
        }
    }

    private func isLightSensitive(_ ing: IngredientDraft) -> Bool {
        if isStableHalideWithoutExplicitPhotolability(ing) {
            return false
        }
        let storage = cleaned(ing.refStorage)?.lowercased() ?? ""
        return ing.isReferenceLightSensitive
            || storage.contains("світл")
            || storage.contains("light")
            || ing.referenceHasMarkerValue(
                keys: ["light_sensitive", "instruction_id", "process_note", "storage"],
                expectedValues: [
                    "lightprotected",
                    "protectfromlight",
                    "light_sensitive",
                    "amberglass",
                    "darkglass",
                    "темнескло",
                    "захищеновідсвітла"
                ]
            )
            || ing.referenceContainsMarkerToken([
                "lightprotected",
                "light_sensitive",
                "amberglass",
                "darkglass"
            ])
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

    private func hasViscousLiquid(context: RxPipelineContext) -> Bool {
        context.draft.ingredients.contains(where: isViscousLiquid)
    }

    private func hasAromaticWaters(context: RxPipelineContext) -> Bool {
        context.draft.ingredients.contains(where: isAromaticWater)
    }

    private func hasPrimaryAromaticWater(context: RxPipelineContext) -> Bool {
        context.draft.ingredients.contains(where: isPrimaryAromaticWater)
    }

    private func hasVolatileAqueousLiquids(context: RxPipelineContext) -> Bool {
        context.draft.ingredients.contains(where: isVolatileAqueousLiquid)
    }

    private func hasPremixVolatileDrops(context: RxPipelineContext) -> Bool {
        context.draft.ingredients.contains(where: requiresPremixWithMixture)
    }

    private func hasLateAddedReadyLiquid(context: RxPipelineContext) -> Bool {
        context.draft.ingredients.contains(where: isLateAddedReadyLiquid)
    }

    private func hasAntibioticIngredient(context: RxPipelineContext) -> Bool {
        context.draft.ingredients.contains(where: isAntibiotic)
    }

    private func isViscousLiquid(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        let type = (ing.refType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return hay.contains("syrup")
            || hay.contains("sirup")
            || hay.contains("сироп")
            || hay.contains("glycer")
            || hay.contains("гліцерин")
            || hay.contains("глицерин")
            || type == "syrup"
    }

    private func isAromaticWater(_ ing: IngredientDraft) -> Bool {
        ing.isReferenceAromaticWater
    }

    private func isListAIngredient(_ ing: IngredientDraft) -> Bool {
        ing.isReferenceListA
    }

    private func isListBIngredient(_ ing: IngredientDraft) -> Bool {
        ing.isReferenceListB
    }

    private func requiresListAPowderTrituration(_ ing: IngredientDraft, context: RxPipelineContext) -> Bool {
        guard ing.isReferenceListA else { return false }
        guard ing.unit.rawValue == "g", ing.amountValue > 0 else { return false }
        let n = max(1, context.draft.numero ?? 1)
        let totalMass: Double = {
            switch ing.scope {
            case .perDose:
                return ing.amountValue * Double(n)
            case .total:
                return ing.amountValue
            case .auto:
                return context.draft.powderMassMode == .dispensa ? (ing.amountValue * Double(n)) : ing.amountValue
            }
        }()
        return totalMass > 0 && totalMass < 0.05
    }

    private func isPrimaryAromaticWater(_ ing: IngredientDraft) -> Bool {
        isAromaticWater(ing) && !isVolatileAqueousLiquid(ing)
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
        let hay = normalizedHay(ing)
        return hay.contains("adonisid")
            || hay.contains("adonizid")
            || hay.contains("adonis")
    }

    private func isAntibiotic(_ ing: IngredientDraft) -> Bool {
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
            || hay.contains("cef")
            || hay.contains("цеф")
            || activity.contains("антибіот")
            || activity.contains("антибиот")
    }

    private func requiresAsepticPowderForWoundsOrNewborn(context: RxPipelineContext) -> Bool {
        requiresSterileExternalUse(signa: context.draft.signa)
            || requiresAsepticForNewborn(signa: context.draft.signa, patientAgeYears: context.draft.patientAgeYears)
    }

    private func requiresSterileExternalUse(signa: String) -> Bool {
        let s = signa.lowercased()
        return s.contains("рана")
            || s.contains("рану")
            || s.contains("ушкоджен")
            || s.contains("поврежден")
            || s.contains("открыт")
    }

    private func requiresAsepticForNewborn(signa: String, patientAgeYears: Int?) -> Bool {
        if let patientAgeYears, patientAgeYears <= 1 {
            return true
        }
        let s = signa.lowercased()
        return s.contains("новорож")
            || s.contains("новонарод")
            || s.contains("неонат")
            || s.contains("немовля")
            || s.contains("груднич")
            || s.contains("infant")
            || s.contains("newborn")
    }

    private func isLiquidIngredient(_ ing: IngredientDraft) -> Bool {
        if ing.unit.rawValue == "ml" { return true }
        let t = (ing.refType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t == "solvent"
            || t == "buffersolution"
            || t == "standardsolution"
            || t == "liquidstandard"
            || t == "tincture"
            || t == "extract"
    }

    private func format(_ v: Double) -> String {
        if v == floor(v) { return String(Int(v)) }
        return String(format: "%.3f", v)
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func short(_ value: String, max: Int = 180) -> String {
        guard value.count > max else { return value }
        let prefix = String(value.prefix(max)).trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix)…"
    }

    private func isBooleanLiteral(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "true"
            || normalized == "false"
            || normalized == "yes"
            || normalized == "no"
            || normalized == "да"
            || normalized == "нет"
            || normalized == "так"
            || normalized == "ні"
            || normalized == "1"
            || normalized == "0"
    }
}
