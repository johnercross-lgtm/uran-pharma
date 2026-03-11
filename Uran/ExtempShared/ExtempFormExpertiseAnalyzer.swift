import Foundation

@MainActor
enum ExtempFormExpertiseAnalyzer {
    static func summarize(draft: ExtempRecipeDraft) -> ExtempFormExpertiseSummary? {
        if LivingDeathEasterEgg.isActive(draft: draft) {
            return makeSummary(
                title: LivingDeathEasterEgg.expertiseTitle(),
                rationale: "Класифікація навмисно підмінена спеціальним сценарієм.",
                reasons: LivingDeathEasterEgg.expertiseReasons()
            )
        }

        let ingredients = draft.ingredients.filter { !$0.isAd && !$0.isQS }
        guard !ingredients.isEmpty else { return nil }

        let effectiveFormMode = SignaUsageAnalyzer.effectiveFormMode(for: draft)
        let signa = draft.signa.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let semantics = SignaUsageAnalyzer.analyze(signa: signa)
        let hasSpoonDose = semantics.hasSpoonDose
        let hasDropsDose = semantics.hasDropsDose
        let isEyeRoute = semantics.isEyeRoute || draft.isOphthalmicDrops
        let isNasalRoute = semantics.isNasalRoute
        let isRinseRoute = semantics.isRinseOrGargle
        let isRectalOrVaginalRoute = semantics.isRectalOrVaginalRoute
        let isExternalRoute = semantics.isExternalRoute
        let isSterileMarker = signa.contains("steril") || signa.contains("стерил")
        let shakeMarker = hasShakeMarker(in: signa)
        let hasSyrup = ingredients.contains(where: isSyrupLike)
        let hasTincture = ingredients.contains(where: isTinctureLike)
        let hasPrimaryAromaticWater = ingredients.contains(where: isPrimaryAromaticWater)
        let hasLateAddedReadyLiquid = ingredients.contains(where: isLateAddedReadyLiquid)
        let nonAqueousSolvent = NonAqueousSolventCatalog.primarySolvent(in: draft)?.type
        let hasInsolubleSolid = ingredients.contains { isInsolubleSolidLike($0, solventType: nonAqueousSolvent) }
        let hasLiquidTargetFromAdOrTarget = hasLiquidTargetContext(draft: draft)
        let hasLiquidComponent = hasLiquidTargetFromAdOrTarget || ingredients.contains(where: isLiquidLike)
        let hasOilComponent = ingredients.contains(where: isOilLike)
        let hasWaterComponent = ingredients.contains(where: isWaterLike)
        let hasEmulsionMarker = ingredients.contains(where: isEmulsionLike)
        let hasSuspensionMarker = ingredients.contains { isSuspensionLike($0, solventType: nonAqueousSolvent) }
        let hasProtectedColloid = ingredients.contains(where: isProtectedColloidLike)
        let hasVmsSolution = ingredients.contains(where: isVmsLike)
        let componentCount = ingredients.count
        let liquidMixtureComponentCount = componentCount + draft.ingredients.filter { $0.isAd }.count
        let hasSemisolidBase = ingredients.contains(where: isSemisolidBaseLike)
        let powderPercent = semisolidPowderPercent(ingredients: ingredients)

        if isEyeRoute {
            var reasons = ["Маршрут введення вказує на очі"]
            if hasDropsDose || (hasLiquidComponent && effectiveFormMode == .drops) { reasons.append("Дозування краплями") }
            if isSterileMarker || draft.isOphthalmicDrops { reasons.append("Є маркер стерильності") }
            return makeSummaryWithGlobalChecks(
                title: "Очні краплі",
                rationale: "Очний шлях введення переводить рідку форму в категорію крапель для асептичного застосування.",
                reasons: reasons,
                ingredients: ingredients,
                effectiveFormMode: effectiveFormMode,
                solventType: nonAqueousSolvent
            )
        }

        if isRectalOrVaginalRoute {
            return makeSummaryWithGlobalChecks(
                title: "Супозиторії",
                rationale: "Ректальний або вагінальний шлях введення відповідає супозиторній лікарській формі.",
                reasons: ["Маршрут введення ректально/вагінально"],
                ingredients: ingredients,
                effectiveFormMode: effectiveFormMode,
                solventType: nonAqueousSolvent
            )
        }

        if hasSemisolidBase {
            let summary = ointmentSummary(draft: draft, powderPercent: powderPercent)
            return applyGlobalExpertiseChecks(
                to: summary,
                ingredients: ingredients,
                effectiveFormMode: effectiveFormMode,
                solventType: nonAqueousSolvent
            )
        }

        if effectiveFormMode == .powders {
            if let powderSummary = powderSummary(
                draft: draft,
                ingredients: ingredients,
                signa: signa,
                isExternalRoute: isExternalRoute
            ) {
                return applyGlobalExpertiseChecks(
                    to: powderSummary,
                    ingredients: ingredients,
                    effectiveFormMode: effectiveFormMode,
                    solventType: nonAqueousSolvent
                )
            }
        }

        if hasLiquidComponent {
            if semantics.dropMeasurementOnly || isRinseRoute {
                var reasons = ["Препарат призначений для полоскання/ополіскування"]
                if hasDropsDose {
                    reasons.append("Доза відмірюється краплями лише перед розведенням водою")
                }
                if hasTincture || nonAqueousSolvent == .ethanol {
                    reasons.append("Спиртова рідина використовується як концентрований розчин")
                }
                let rationale: String = hasDropsDose
                    ? "Краплі в Signa у цьому випадку інтерпретуються як спосіб відмірювання концентрату перед розведенням для полоскання/ополіскування."
                    : "Маршрут застосування (полоскання/ополіскування) відповідає зовнішньому водному розчину."
                return makeSummaryWithGlobalChecks(
                    title: "Розчин для полоскання",
                    rationale: rationale,
                    reasons: reasons,
                    ingredients: ingredients,
                    effectiveFormMode: effectiveFormMode,
                    solventType: nonAqueousSolvent
                )
            }

            if (hasDropsDose || (effectiveFormMode == .drops && hasLiquidComponent)) && !semantics.dropMeasurementOnly {
                if isNasalRoute {
                    return makeSummaryWithGlobalChecks(
                        title: "Назальні краплі",
                        rationale: "Крапельне дозування разом із назальним маршрутом відповідає формі назальних крапель.",
                        reasons: ["Маркер крапель + назальний шлях введення"],
                        ingredients: ingredients,
                        effectiveFormMode: effectiveFormMode,
                        solventType: nonAqueousSolvent
                    )
                }
                return makeSummaryWithGlobalChecks(
                    title: "Краплі",
                    rationale: "Крапельне дозування є ключовою технологічною ознакою дозованої рідкої форми.",
                    reasons: ["Маркер дозування краплями або обрана форма крапель"],
                    ingredients: ingredients,
                    effectiveFormMode: effectiveFormMode,
                    solventType: nonAqueousSolvent
                )
            }

            if isExternalRoute && hasOilComponent && hasWaterComponent {
                return makeSummaryWithGlobalChecks(
                    title: "Лінімент-емульсія",
                    rationale: "Для зовнішнього застосування система з водною та олійною фазами класифікується як емульсійний лінімент.",
                    reasons: ["Зовнішній шлях застосування", "У складі є олійна та водна фази"],
                    ingredients: ingredients,
                    effectiveFormMode: effectiveFormMode,
                    solventType: nonAqueousSolvent
                )
            }

            if isExternalRoute && hasOilComponent && !hasInsolubleSolid {
                return makeSummaryWithGlobalChecks(
                    title: "Лінімент",
                    rationale: "Зовнішня рідка або м’яка олійна система без мазевої основи відповідає лініменту.",
                    reasons: ["Зовнішній шлях застосування", "Рідка/м’яка олійна система без мазевої основи"],
                    ingredients: ingredients,
                    effectiveFormMode: effectiveFormMode,
                    solventType: nonAqueousSolvent
                )
            }

            if hasEmulsionMarker || (hasOilComponent && hasWaterComponent) {
                return makeSummaryWithGlobalChecks(
                    title: isExternalRoute ? "Емульсія для зовнішнього застосування" : "Емульсія",
                    rationale: "Наявність двох взаємно нерозчинних рідких фаз вказує на емульсійну дисперсну систему.",
                    reasons: [
                        hasEmulsionMarker ? "Є прямий маркер емульсії" : "У складі є олійна та водна фази",
                        isExternalRoute ? "Маршрут введення: зовнішньо" : "Дисперсна система типу рідина в рідині"
                    ],
                    ingredients: ingredients,
                    effectiveFormMode: effectiveFormMode,
                    solventType: nonAqueousSolvent
                )
            }

            if hasProtectedColloid {
                return makeSummaryWithGlobalChecks(
                    title: "Колоїдний розчин",
                    rationale: "Колоїдні срібловмісні системи потребують окремого режиму приготування і не є істинними розчинами.",
                    reasons: ["Виявлено колоїдний компонент (Protargolum/Collargolum)"],
                    ingredients: ingredients,
                    effectiveFormMode: effectiveFormMode,
                    solventType: nonAqueousSolvent
                )
            }

            if hasVmsSolution {
                return makeSummaryWithGlobalChecks(
                    title: "Розчин ВМС",
                    rationale: "Високомолекулярні речовини формують специфічний розчин із особливим режимом набухання або розчинення.",
                    reasons: ["Виявлено високомолекулярну речовину або слизоутворюючий компонент"],
                    ingredients: ingredients,
                    effectiveFormMode: effectiveFormMode,
                    solventType: nonAqueousSolvent
                )
            }

            if hasSuspensionMarker || hasInsolubleSolid {
                var reasons: [String] = []
                if hasInsolubleSolid {
                    reasons.append("Є тверді речовини з ознаками нерозчинності")
                }
                if shakeMarker || hasSuspensionMarker {
                    reasons.append("Є маркер збовтування/суспензії")
                }
                if isExternalRoute {
                    reasons.append("Маршрут введення: зовнішньо")
                }
                return makeSummaryWithGlobalChecks(
                    title: isExternalRoute ? "Суспензія для зовнішнього застосування" : "Суспензія",
                    rationale: "Нерозчинна тверда фаза в рідкому середовищі переводить систему у суспензійну лікарську форму.",
                    reasons: reasons,
                    ingredients: ingredients,
                    effectiveFormMode: effectiveFormMode,
                    solventType: nonAqueousSolvent
                )
            }

            if hasPrimaryAromaticWater && (hasSpoonDose || liquidMixtureComponentCount >= 2) {
                var reasons = ["Ароматна вода використовується як основний розчинник"]
                if ingredients.contains(where: { $0.hasReferenceAromaticWaterRatio }) {
                    reasons.append("Довідник позначає її як стандартну ароматну воду 1:1000")
                }
                if hasSpoonDose { reasons.append("Дозування ложками характерне для мікстури") }
                if hasSyrup { reasons.append("Сироп додається після розчинення та проціджування") }
                if hasTincture { reasons.append("Настойка вводиться у флакон в останню чергу") }
                if hasLateAddedReadyLiquid { reasons.append("Готовий рідкий препарат додається після фільтрації") }
                if ingredients.contains(where: { $0.isReferenceCoolPlaceSensitive }) {
                    reasons.append("Потрібне зберігання в прохолодному місці 8-15°C")
                }
                if draft.patientAgeYears != nil { reasons.append("Є дані для дитячого дозового контролю") }

                let rationale: String = {
                    if hasLateAddedReadyLiquid {
                        return "Ароматна вода виконує роль основного розчинника, тому очищену воду в розрахунок не включають. Довідниково це готова летка водна система 1:1000: сухі речовини розчиняють безпосередньо в ній, робоче проціджування виконують через вату, а готові рідкі активні препарати та інші рідкі добавки вводять після фільтрації. Зберігання - у прохолодному місці 8-15°C."
                    }
                    if hasTincture {
                        return "Ароматна вода виконує роль основного розчинника, тому сухі речовини розчиняють безпосередньо в ній без нагрівання. Це готова ефірноолійна система 1:1000, тому настойки вводять у відпускний флакон наприкінці, а зберігання призначають у прохолодному місці 8-15°C."
                    }
                    if hasSyrup {
                        return "Ароматна вода є основним розчинником, тому очищена вода для цієї мікстури не потрібна. Як готову ароматну воду 1:1000 її не нагрівають; після розчинення солей розчин проціджують через вату, а в’язкі рідини на кшталт сиропу додають уже після фільтрації. Зберігання - у прохолодному місці 8-15°C."
                    }
                    return "Ароматна вода виступає основним розчинником, тому лікарська форма технологічно відповідає мікстурі на ароматній воді: це готова летка водна система 1:1000, сухі речовини розчиняють безпосередньо в ній без нагрівання, а проціджування проводять через ватний тампон. За сильної мутності при відновленні концентрату допустимий змочений водою паперовий фільтр."
                }()

                let title = draft.patientAgeYears != nil ? "Дитяча мікстура на ароматній воді" : "Мікстура на ароматній воді"
                return makeSummaryWithGlobalChecks(
                    title: title,
                    rationale: rationale,
                    reasons: reasons,
                    ingredients: ingredients,
                    effectiveFormMode: effectiveFormMode,
                    solventType: nonAqueousSolvent
                )
            }

            if isPavlovMixture(ingredients: ingredients) {
                return makeSummaryWithGlobalChecks(
                    title: "Мікстура Павлова",
                    rationale: "Комбінація Coffeini-natrii benzoatis та Natrii bromidi у водному середовищі класифікується як класична мікстура Павлова.",
                    reasons: [
                        "У складі присутні Coffeini-natrii benzoatis і Natrii bromidi",
                        hasSpoonDose ? "Дозування ложками відповідає мікстурі" : "Рідка форма для внутрішнього застосування"
                    ],
                    ingredients: ingredients,
                    effectiveFormMode: effectiveFormMode,
                    solventType: nonAqueousSolvent
                )
            }

            if hasSyrup {
                return makeSummaryWithGlobalChecks(
                    title: hasSpoonDose ? "Мікстура з сиропом" : "Сироп/мікстура з сиропом",
                    rationale: "Сиропна основа формує в’язку рідку форму, яка технологічно ближча до мікстури або сиропу.",
                    reasons: ["Виявлено сироп або сиропну основу"],
                    ingredients: ingredients,
                    effectiveFormMode: effectiveFormMode,
                    solventType: nonAqueousSolvent
                )
            }

            if hasSpoonDose && liquidMixtureComponentCount >= 2 {
                return makeSummaryWithGlobalChecks(
                    title: "Мікстура",
                    rationale: "Багатокомпонентний рідкий склад із дозуванням ложками відповідає мікстурі.",
                    reasons: ["Дозування ложками", "Склад містить \(liquidMixtureComponentCount) компоненти(ів)"],
                    ingredients: ingredients,
                    effectiveFormMode: effectiveFormMode,
                    solventType: nonAqueousSolvent
                )
            }

            var reasons = [isExternalRoute ? "Рідка гомогенна система для зовнішнього застосування" : "Рідка гомогенна система"]
            if hasTincture { reasons.append("Містить настойку/спиртову рідину") }
            return makeSummaryWithGlobalChecks(
                title: isExternalRoute ? "Розчин для зовнішнього застосування" : "Розчин",
                rationale: "Однорідна рідка система без ознак дисперсної фази класифікується як розчин.",
                reasons: reasons,
                ingredients: ingredients,
                effectiveFormMode: effectiveFormMode,
                solventType: nonAqueousSolvent
            )
        }

        return makeSummaryWithGlobalChecks(
            title: effectiveFormMode.title,
            rationale: "Склад не містить достатніх технологічних ознак для точнішої автоматичної класифікації.",
            reasons: ["Недостатньо маркерів у складі для точнішого автоматичного висновку"],
            ingredients: ingredients,
            effectiveFormMode: effectiveFormMode,
            solventType: nonAqueousSolvent
        )
    }

    private static func makeSummary(
        title: String,
        rationale: String,
        reasons: [String]
    ) -> ExtempFormExpertiseSummary {
        ExtempFormExpertiseSummary(title: title, rationale: rationale, reasons: reasons)
    }

    private static func makeSummaryWithGlobalChecks(
        title: String,
        rationale: String,
        reasons: [String],
        ingredients: [IngredientDraft],
        effectiveFormMode: FormMode,
        solventType: NonAqueousSolventType?
    ) -> ExtempFormExpertiseSummary {
        applyGlobalExpertiseChecks(
            to: makeSummary(title: title, rationale: rationale, reasons: reasons),
            ingredients: ingredients,
            effectiveFormMode: effectiveFormMode,
            solventType: solventType
        )
    }

    private static func applyGlobalExpertiseChecks(
        to summary: ExtempFormExpertiseSummary,
        ingredients: [IngredientDraft],
        effectiveFormMode: FormMode,
        solventType: NonAqueousSolventType?
    ) -> ExtempFormExpertiseSummary {
        var updated = summary

        if let viscousCheck = viscousNonAqueousMassSwitchCheck(
            ingredients: ingredients,
            effectiveFormMode: effectiveFormMode,
            solventType: solventType
        ) {
            var reasons = updated.reasons.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if !reasons.contains(viscousCheck.reason) {
                reasons.insert(viscousCheck.reason, at: 0)
            }

            var rationale = updated.rationale
            if !rationale.contains(viscousCheck.rationaleAddition) {
                rationale += " " + viscousCheck.rationaleAddition
            }

            updated = ExtempFormExpertiseSummary(
                title: updated.title,
                rationale: rationale,
                reasons: reasons
            )
        }

        return updated
    }

    private static func viscousNonAqueousMassSwitchCheck(
        ingredients: [IngredientDraft],
        effectiveFormMode: FormMode,
        solventType: NonAqueousSolventType?
    ) -> (reason: String, rationaleAddition: String)? {
        guard effectiveFormMode == .solutions || effectiveFormMode == .drops else { return nil }
        guard let solventType, solventType.isViscous else { return nil }

        let mlComponents = ingredients.filter { ingredient in
            !ingredient.isAd
                && !ingredient.isQS
                && isMlUnit(ingredient.unit.rawValue)
                && !PurifiedWaterHeuristics.isPurifiedWater(ingredient)
        }

        let rationaleAddition = "Для в'язких неводних систем експертиза обов'язково перевіряє перемикання дозування у картці речовини з ml на g за формулою m = V × ρ."

        guard !mlComponents.isEmpty else {
            return (
                reason: "Контроль картки речовини: в'язка неводна система — дозування має бути в g (перехід ml → g перевірено).",
                rationaleAddition: rationaleAddition
            )
        }

        let missingDensity = mlComponents.filter { ingredient in
            let density = ingredient.refDensity ?? 0
            return density <= 0 && !isGlycerinLike(ingredient)
        }

        if !missingDensity.isEmpty {
            let names = missingDensity.prefix(3).map { ingredientDisplayName($0) }.joined(separator: ", ")
            return (
                reason: "Контроль картки речовини: перевірити ml → g; для \(names) відсутня густина ρ, перерахунок неможливий.",
                rationaleAddition: rationaleAddition
            )
        }

        let names = mlComponents.prefix(3).map { ingredientDisplayName($0) }.joined(separator: ", ")
        return (
            reason: "Контроль картки речовини: перевірити перемикання ml → g для \(names) (в'язкий неводний розчин).",
            rationaleAddition: rationaleAddition
        )
    }

    private static func normalizedHay(_ ingredient: IngredientDraft) -> String {
        let a = (ingredient.refNameLatNom ?? ingredient.displayName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let b = (ingredient.refInnKey ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return a + " " + b
    }

    private static func ingredientDisplayName(_ ingredient: IngredientDraft) -> String {
        let name = (ingredient.refNameLatNom ?? ingredient.displayName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Subst." : name
    }

    private static func isMlUnit(_ rawUnit: String) -> Bool {
        let unit = rawUnit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return unit == "ml" || unit == "мл"
    }

    private static func isGlycerinLike(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        let solventType = (ingredient.refSolventType ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return hay.contains("glycer")
            || hay.contains("гліцерин")
            || hay.contains("глицерин")
            || solventType.contains("glycer")
    }

    private static func hasShakeMarker(in signa: String) -> Bool {
        signa.contains("збовт")
            || signa.contains("взболт")
            || signa.contains("shake")
    }

    private static func ointmentSummary(
        draft: ExtempRecipeDraft,
        powderPercent: Double?
    ) -> ExtempFormExpertiseSummary {
        let result = OintmentsCalculator.calculate(draft: draft)
        let activeIngredients = draft.ingredients.filter {
            guard !$0.isAd, !$0.isQS, $0.amountValue > 0 else { return false }
            let type = ($0.refType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return type != "base"
        }

        let hasSolutionPhase =
            !result.groups.waterSoluble.isEmpty
            || !result.groups.oilSoluble.isEmpty
            || !result.groups.ethanolSoluble.isEmpty
            || !result.groups.mixed.isEmpty

        if !result.groups.insoluble.isEmpty && hasSolutionPhase {
            var reasons = [
                "Є мазева основа",
                "У складі одночасно є розчинні та нерозчинні речовини"
            ]
            if let powderPercent, powderPercent >= 25 {
                reasons.append("Частка порошків ≈ \(String(format: "%.1f", powderPercent))%")
            }
            return makeSummary(
                title: "Комбінована мазь",
                rationale: "Частина речовин переходить у розчин або фазу основи, а частина вводиться як суспензія, тому мазь є комбінованою.",
                reasons: reasons
            )
        }

        if !result.groups.insoluble.isEmpty {
            var reasons = [
                "Є мазева основа",
                "Нерозчинні порошки вводяться дисперсно"
            ]
            if let powderPercent, powderPercent >= 25 {
                reasons.append("Частка порошків ≈ \(String(format: "%.1f", powderPercent))% (пастоподібна система)")
            }
            return makeSummary(
                title: "Суспензійна мазь",
                rationale: "Нерозчинні тверді речовини не розчиняються в основі і вводяться як тонка суспензія.",
                reasons: reasons
            )
        }

        let title = activeIngredients.count <= 1 ? "Проста мазь" : "Складна мазь"
        let rationale = activeIngredients.count <= 1
            ? "Мазева основа містить одну лікарську речовину, тому форма класифікується як проста мазь."
            : "Мазева основа містить декілька лікарських речовин або компонентів дії, тому форма класифікується як складна мазь."

        return makeSummary(
            title: title,
            rationale: rationale,
            reasons: ["Є м’яка мазева основа", activeIngredients.count <= 1 ? "Одна активна речовина у складі" : "Кілька активних компонентів у складі"]
        )
    }

    private static func isSemisolidBaseLike(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        let type = (ingredient.refType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if type == "base" { return true }
        let markers = ["vaselin", "ланол", "lanolin", "paraffin", "petrolat", "adeps", "butyrum cacao", "oleum cacao", "macrogol", "peg"]
        return markers.contains(where: { hay.contains($0) })
    }

    private static func isLiquidLike(_ ingredient: IngredientDraft) -> Bool {
        if ingredient.unit.rawValue == "ml"
            || ingredient.presentationKind == .solution
            || ingredient.presentationKind == .standardSolution {
            return true
        }

        let type = (ingredient.refType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let physicalState = (ingredient.refPhysicalState ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hay = normalizedHay(ingredient)

        let liquidTypes: Set<String> = [
            "solv",
            "solvent",
            "buffersolution",
            "standardsolution",
            "liquidstandard",
            "tincture",
            "extract",
            "syrup",
            "juice",
            "viscous liquid",
            "viscousliquid",
            "liquid",
            "alcoholic"
        ]
        if liquidTypes.contains(type) {
            return true
        }

        if physicalState.contains("liquid") || physicalState.contains("жидк") || physicalState.contains("рідк") {
            return true
        }

        return hay.contains("tinct")
            || hay.contains("настойк")
            || hay.contains("настоянк")
            || hay.contains("extract")
            || hay.contains("sirup")
            || hay.contains("syrup")
            || hay.contains("сироп")
            || hay.contains("succus")
            || hay.contains("juice")
            || hay.contains("vinyl")
    }

    private static func isOilLike(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        let solventType = (ingredient.refSolventType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return hay.contains("oleum")
            || hay.contains("olei")
            || hay.contains(" oil")
            || hay.contains("олія")
            || hay.contains("масл")
            || hay.contains("вазелінова олія")
            || hay.contains("vaseline oil")
            || solventType.contains("oil")
    }

    private static func isWaterLike(_ ingredient: IngredientDraft) -> Bool {
        if PurifiedWaterHeuristics.isPurifiedWater(ingredient) {
            return true
        }

        let solventType = (ingredient.refSolventType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if solventType.contains("water") {
            return true
        }

        return isPrimaryAromaticWater(ingredient)
    }

    private static func isEmulsionLike(_ ingredient: IngredientDraft) -> Bool {
        if ingredient.rpPrefix == .emulsion {
            return true
        }

        let type = (ingredient.refType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hay = normalizedHay(ingredient)
        return type == "emulsion"
            || hay.contains("emuls")
            || hay.contains("емуль")
    }

    private static func isSuspensionLike(
        _ ingredient: IngredientDraft,
        solventType: NonAqueousSolventType?
    ) -> Bool {
        if ingredient.rpPrefix == .suspension {
            return true
        }

        let type = (ingredient.refType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hay = normalizedHay(ingredient)
        return (type == "suspension" && !isSolubleInSelectedLiquid(ingredient, solventType: solventType))
            || hay.contains("susp")
            || hay.contains("сусп")
    }

    private static func isProtectedColloidLike(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("protarg") || hay.contains("collarg")
    }

    private static func isVmsLike(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("amylum")
            || hay.contains("крохмал")
            || hay.contains("starch")
            || hay.contains("pepsin")
            || hay.contains("пепсин")
            || hay.contains("mucil")
            || hay.contains("слиз")
    }

    private static func isPrimaryAromaticWater(_ ingredient: IngredientDraft) -> Bool {
        ingredient.isReferenceAromaticWater
    }

    private static func isLateAddedReadyLiquid(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("adonisid")
            || hay.contains("adonizid")
            || hay.contains("adonis")
    }

    private static func isPavlovMixture(ingredients: [IngredientDraft]) -> Bool {
        let components = ingredients.filter { !$0.isAd && !$0.isQS }
        let hasCaffeineSodiumBenzoate = components.contains(where: isCaffeineSodiumBenzoateLike)
        let hasSodiumBromide = components.contains(where: isSodiumBromideLike)
        guard hasCaffeineSodiumBenzoate, hasSodiumBromide else { return false }

        // Дозволяємо лише водний розчинник та цю пару активних речовин.
        let nonPavlovComponents = components.filter { ingredient in
            !isWaterLike(ingredient)
                && !isCaffeineSodiumBenzoateLike(ingredient)
                && !isSodiumBromideLike(ingredient)
        }
        return nonPavlovComponents.isEmpty
    }

    private static func isCaffeineSodiumBenzoateLike(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("coffeini natrii benzo")
            || hay.contains("coffeini-natrii benzo")
            || hay.contains("caffeine natrii benzo")
            || hay.contains("кофеин натрия бензо")
            || hay.contains("кофеїн натрію бензо")
            || (
                (hay.contains("coffein") || hay.contains("caffeine") || hay.contains("кофеин") || hay.contains("кофеїн"))
                    && (hay.contains("natri") || hay.contains("натри"))
                    && (hay.contains("benzo") || hay.contains("бензоат"))
            )
    }

    private static func isSodiumBromideLike(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("natrii bromid")
            || hay.contains("sodium bromid")
            || hay.contains("натрия бромид")
            || hay.contains("натрію бромід")
            || ((hay.contains("natri") || hay.contains("натри")) && (hay.contains("bromid") || hay.contains("бромид") || hay.contains("бромід")))
    }

    private static func hasLiquidTargetContext(draft: ExtempRecipeDraft) -> Bool {
        if draft.explicitLiquidTargetMl != nil || draft.legacyAdOrQsLiquidTargetMl != nil {
            return true
        }

        guard let unit = draft.resolvedTargetUnit?.rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else {
            return false
        }
        return unit == "ml" || unit == "мл"
    }

    private static func powderSummary(
        draft: ExtempRecipeDraft,
        ingredients: [IngredientDraft],
        signa: String,
        isExternalRoute: Bool
    ) -> ExtempFormExpertiseSummary? {
        guard !ingredients.isEmpty else { return nil }

        let powderLikeIngredients = ingredients.filter { ingredient in
            !isLiquidLike(ingredient) && !isSemisolidBaseLike(ingredient)
        }
        guard powderLikeIngredients.count == ingredients.count else { return nil }

        let result = PowdersCalculator.calculate(draft: draft)
        if result.components.isEmpty {
            return makeSummary(
                title: "Порошки",
                rationale: "Відсутність рідкої та мазевої основи вказує на тверду порошкову лікарську форму.",
                reasons: ["Склад не містить рідкої або мазевої основи"]
            )
        }

        let componentCount = result.components.count
        let isDosed = (draft.numero ?? 0) > 1
        let isDustingPowder = isExternalRoute
            || signa.contains("присип")
            || signa.contains("присып")

        if result.canBuildTrituration {
            return makeSummary(
                title: isDustingPowder ? "Порошки (тритурація 1:10) для зовнішнього застосування" : "Порошки (тритурація 1:10)",
                rationale: "Малі дози активної речовини потребують попередньої тритурації з носієм для точності дозування.",
                reasons: [
                    "Склад виглядає як тверда порошкова суміш",
                    "Є малі дози активних речовин < 0,05 g на дозу",
                    "Цукрового носія достатньо для тритурації 1:10"
                ]
            )
        }

        if result.tinyActivesTotalG > 0 {
            return makeSummary(
                title: "Порошки малої маси",
                rationale: "Малі навішування активних речовин потребують підвищеної точності змішування або попередньої тритурації.",
                reasons: [
                    "Склад виглядає як тверда порошкова суміш",
                    "Є малі дози активних речовин < 0,05 g на дозу",
                    "Для точної розважки бажана тритурація або інший носій"
                ]
            )
        }

        if isDustingPowder {
            return makeSummary(
                title: "Присипка",
                rationale: "Зовнішній маршрут застосування переводить порошкову суміш у форму присипки.",
                reasons: [
                    "Тверда порошкова суміш без рідкої та мазевої основи",
                    "Маршрут застосування вказує на зовнішнє нанесення"
                ]
            )
        }

        return makeSummary(
            title: powderTitle(componentCount: componentCount, isDosed: isDosed),
            rationale: isDosed
                ? "Наявність окремих доз і відсутність рідкої основи вказують на дозовані порошки."
                : "Тверда суміш без рідкої або мазевої основи класифікується як порошок.",
            reasons: [
                "Склад не містить рідкої або мазевої основи",
                isDosed ? "Вказано кількість доз" : "Суміш виглядає як тверда порошкова форма"
            ]
        )
    }

    private static func powderTitle(componentCount: Int, isDosed: Bool) -> String {
        if isDosed {
            return componentCount <= 1 ? "Прості дозовані порошки" : "Складні дозовані порошки"
        }
        return componentCount <= 1 ? "Простий порошок" : "Складні порошки"
    }

    private static func isSyrupLike(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        let type = (ingredient.refType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return type == "syrup" || hay.contains("syrup") || hay.contains("sirup") || hay.contains("сироп")
    }

    private static func isTinctureLike(_ ingredient: IngredientDraft) -> Bool {
        if ingredient.rpPrefix == .tincture { return true }
        let hay = normalizedHay(ingredient)
        let type = (ingredient.refType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return type == "tincture" || hay.contains("tinct") || hay.contains("настойк") || hay.contains("настоянк")
    }

    private static func isInsolubleSolidLike(
        _ ingredient: IngredientDraft,
        solventType: NonAqueousSolventType?
    ) -> Bool {
        guard ingredient.unit.rawValue == "g" || ingredient.unit.rawValue == "mg" || ingredient.unit.rawValue == "мг" else { return false }
        if isSolubleInSelectedLiquid(ingredient, solventType: solventType) {
            return false
        }
        return WaterSolubilityHeuristics.isWaterInsolubleOrSparinglySoluble(ingredient.refSolubility)
    }

    private static func isSolubleInSelectedLiquid(
        _ ingredient: IngredientDraft,
        solventType: NonAqueousSolventType?
    ) -> Bool {
        guard let solventType else { return false }
        let solubility = (ingredient.refSolubility ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

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

    private static func semisolidPowderPercent(ingredients: [IngredientDraft]) -> Double? {
        let massItems = ingredients.filter { $0.unit.rawValue == "g" && $0.amountValue > 0 }
        guard !massItems.isEmpty else { return nil }
        let totalG = massItems.reduce(0.0) { $0 + $1.amountValue }
        guard totalG > 0 else { return nil }
        let powderG = massItems
            .filter { !isSemisolidBaseLike($0) }
            .reduce(0.0) { $0 + $1.amountValue }
        return (powderG / totalG) * 100.0
    }
}
