import Foundation

struct RxFixtureScenario {
    let id: String
    let title: String
    let draft: ExtempRecipeDraft
    let expectedActivatedBlocks: [String]
    let forbiddenActivatedBlocks: [String]
    let expectedSectionTitles: [String]
    let expectedLineFragments: [String]
    let forbiddenLineFragments: [String]
    let validator: ((RuleResult) -> [String])?

    init(
        id: String,
        title: String,
        draft: ExtempRecipeDraft,
        expectedActivatedBlocks: [String],
        forbiddenActivatedBlocks: [String],
        expectedSectionTitles: [String],
        expectedLineFragments: [String] = [],
        forbiddenLineFragments: [String] = [],
        validator: ((RuleResult) -> [String])? = nil
    ) {
        self.id = id
        self.title = title
        self.draft = draft
        self.expectedActivatedBlocks = expectedActivatedBlocks
        self.forbiddenActivatedBlocks = forbiddenActivatedBlocks
        self.expectedSectionTitles = expectedSectionTitles
        self.expectedLineFragments = expectedLineFragments
        self.forbiddenLineFragments = forbiddenLineFragments
        self.validator = validator
    }
}

struct RxFixtureResult {
    let scenarioId: String
    let passed: Bool
    let details: [String]
}

enum RxFixtureScenarios {
    static func all() -> [RxFixtureScenario] {
        var scenarios: [RxFixtureScenario] = [
            waterKuoScenario(),
            aqueousAdNoKuoScenario(),
            natriiBromideNoDarkGlassScenario(),
            aqueousAdWithKuoScenario(),
            aqueousAdMixedDryNoBuretteScenario(),
            aqueousAdBuretteAllConcentratesScenario(),
            waterFrequencyFromAbbreviatedSignaScenario(),
            standardDemyanovichScenario(),
            hydrochloricAcidDilutionScenario(),
            hydrogenPeroxideDilutionScenario(),
            ethanolExternalSolutionScenario(),
            ethanolSolutionScenario(),
            glycerinSolutionScenario(),
            glycerinIodineComplexScenario(),
            ethanolRinseMeasuredByDropsScenario(),
            oilEarDropsScenario(),
            dropsDoseScenario(),
            internalDropsNoFalsePoisonScenario(),
            nasalDropsConcentrationControlScenario(),
            ophthalmicDropsNoExtraNaClScenario(),
            furacilinRatioSolutionScenario(),
            silverNitrateSolutionScenario(),
            iodineKiAqueousScenario(),
            iodineKiFromSolutionAqueousScenario(),
            tweenSpanConflictWaterScenario(),
            concentratedPermanganateScenario(),
            platyphylliniDropsScenario(),
            platyphylliniListADropsScenario(),
            infusionScenario(),
            decoctionTanninHotFiltrationScenario(),
            vmsProtargolGlycerinScenario(),
            nonAqueousTweenSpanConflictScenario(),
            nonAqueousChloroformParaffinScenario(),
            powderNewbornAsepticScenario(),
            listAPowderScenario(),
            listBPowderScenario(),
            buretteAqueousConcentratesScenario(),
            nonBuretteEquivalentScenario(),
            multipleSolutionIngredientsScenario(),
            buretteMassDerivationFailureScenario(),
            adaptiveQsAboveThreePercentScenario(),
            ppkKuoApproxAndQsScenario(),
            ppkNoFalseLightSensitiveForBromideScenario(),
            ppkSectionSeparationScenario(),
            kuoMissingReferenceInKuoModeScenario(),
            ppkNoFalseKuoBlockingWhenKuoSkippedScenario(),
            expertiseRinseNoDropsRationaleScenario(),
            expertiseDropsAndRinsePriorityScenario(),
            expertiseNoFalseDilutionByWaterWordScenario()
        ]
        scenarios.append(contentsOf: dailyShadowParityRegressionScenarios())
        return scenarios
    }

    static func run(engine: RuleEngineProtocol = DefaultRuleEngine()) -> [RxFixtureResult] {
        all().map { scenario in
            let evaluated = engine.evaluate(draft: scenario.draft)

            var details: [String] = []
            var ok = true

            for block in scenario.expectedActivatedBlocks {
                if !evaluated.derived.activatedBlocks.contains(block) {
                    ok = false
                    details.append("missing block: \(block)")
                }
            }

            for block in scenario.forbiddenActivatedBlocks {
                if evaluated.derived.activatedBlocks.contains(block) {
                    ok = false
                    details.append("unexpected block: \(block)")
                }
            }

            let sectionTitles = Set(evaluated.derived.ppkSections.map(\.title))
            for title in scenario.expectedSectionTitles {
                if !sectionTitles.contains(title) {
                    ok = false
                    details.append("missing section: \(title)")
                }
            }

            let renderedLines = evaluated.derived.ppkSections
                .flatMap(\.lines)
                .joined(separator: "\n")
            for fragment in scenario.expectedLineFragments {
                if !renderedLines.contains(fragment) {
                    ok = false
                    details.append("missing fragment: \(fragment)")
                }
            }
            for fragment in scenario.forbiddenLineFragments {
                if renderedLines.contains(fragment) {
                    ok = false
                    details.append("unexpected fragment: \(fragment)")
                }
            }
            if let validator = scenario.validator {
                let validatorIssues = validator(evaluated)
                if !validatorIssues.isEmpty {
                    ok = false
                    details.append(contentsOf: validatorIssues)
                }
            }

            if details.isEmpty {
                details.append("ok")
            }

            return RxFixtureResult(scenarioId: scenario.id, passed: ok, details: details)
        }
    }

    private static func waterKuoScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.signa = "По 1 столовой ложке 3 раза в день"
        d.targetValue = 100
        d.targetUnit = UnitCode(rawValue: "ml")
        d.ingredients = [
            IngredientDraft(
                displayName: "Natrii bromidum",
                role: .active,
                amountValue: 4,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refKuoMlPerG: 0.27,
            ),
            IngredientDraft(
                displayName: "Aqua purificata",
                role: .solvent,
                amountValue: 100,
                unit: UnitCode(rawValue: "ml"),
                isAd: true,
                refType: "solvent"
            )
        ]

        return RxFixtureScenario(
            id: "water_kuo",
            title: "Water solution >=3% with KUO",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, WaterSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [],
            expectedSectionTitles: ["Розрахунки", "Технологія", "Контроль якості"]
        )
    }

    private static func aqueousAdNoKuoScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.useBuretteSystem = false
        d.signa = "По 1 столовой ложке 3 раза в день"
        d.targetValue = 150
        d.targetUnit = UnitCode(rawValue: "ml")
        d.ingredients = [
            IngredientDraft(
                displayName: "Natrii bromidum",
                role: .active,
                amountValue: 3,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Natrii bromidum",
                refKuoMlPerG: 0.23
            ),
            IngredientDraft(
                displayName: "Aqua purificata",
                role: .solvent,
                amountValue: 150,
                unit: UnitCode(rawValue: "ml"),
                isAd: true,
                refType: "solvent"
            )
        ]

        return RxFixtureScenario(
            id: "aqueous_ad_no_kuo",
            title: "Aqueous ad solution below 3% keeps branch true-solution and skips KUO",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, WaterSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [BuretteSystemBlock.blockId],
            expectedSectionTitles: ["Розрахунки", "Технологія"],
            expectedLineFragments: [
                "КУО не враховується",
                "Aqua purificata q.s. ad 150 ml"
            ],
            validator: { evaluated in
                var errors: [String] = []
                if evaluated.derived.routeBranch != "aqueous_true_solution" {
                    errors.append("branch expected=aqueous_true_solution actual=\(evaluated.derived.routeBranch ?? "nil")")
                }
                if evaluated.derived.calculations["kuo_volume_ml"] != nil {
                    errors.append("unexpected kuo_volume_ml for <3% case")
                }
                return errors
            }
        )
    }

    private static func natriiBromideNoDarkGlassScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.useBuretteSystem = false
        d.signa = "По 1 столовой ложке 3 раза в день"
        d.targetValue = 150
        d.targetUnit = UnitCode(rawValue: "ml")
        d.ingredients = [
            IngredientDraft(
                displayName: "Natrii bromidum",
                role: .active,
                amountValue: 3,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Natrii bromidum",
                refKuoMlPerG: 0.24,
                refStorage: "Зберігати у звичайних умовах"
            ),
            IngredientDraft(
                displayName: "Aqua purificata",
                role: .solvent,
                amountValue: 150,
                unit: UnitCode(rawValue: "ml"),
                isAd: true,
                refType: "solvent"
            )
        ]

        return RxFixtureScenario(
            id: "natrii_bromide_no_dark_glass",
            title: "Natrii bromidi 3g/150ml must not trigger light-sensitive packaging",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, WaterSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [BuretteSystemBlock.blockId],
            expectedSectionTitles: ["Розрахунки", "Стабільність", "Технологія"],
            expectedLineFragments: [
                "КУО не враховується",
                "Aqua purificata q.s. ad 150 ml",
                "Речовина добре розчиняється у воді."
            ],
            forbiddenLineFragments: [
                "Флакон з темного скла",
                "Флакон з оранжевого скла",
                "Зберігати в захищеному від світла місці"
            ],
            validator: { evaluated in
                var errors: [String] = []
                guard let ppkDocument = evaluated.derived.ppkDocument else {
                    errors.append("missing ppkDocument")
                    return errors
                }
                let techRationale = ppkDocument.backSide
                    .first(where: { $0.title == "Технологічне обґрунтування" })?
                    .lines
                    .joined(separator: "\n")
                    .lowercased() ?? ""
                if techRationale.contains("темного скла") || techRationale.contains("оранжевого скла") {
                    errors.append("technology rationale still contains dark-glass claim for natrii bromidi")
                }
                if !techRationale.contains("речовина добре розчиняється у воді") {
                    errors.append("technology rationale must contain water-solubility phrase for natrii bromidi")
                }
                let sourceData = ppkDocument.backSide
                    .first(where: { $0.title == "Вихідні дані" })?
                    .lines
                    .joined(separator: "\n")
                    .lowercased() ?? ""
                if !sourceData.contains("форма: розчин") {
                    errors.append("source data must present dosage form as 'Розчин'")
                }

                let packaging = ppkDocument.control
                    .first(where: { $0.title == "Оформлення та зберігання" })?
                    .lines
                    .joined(separator: "\n")
                    .lowercased() ?? ""
                if packaging.contains("темного скла")
                    || packaging.contains("оранжевого скла")
                    || packaging.contains("берегти від світла")
                    || packaging.contains("захищеному від світла") {
                    errors.append("control packaging contains false light-protection constraints")
                }
                if !packaging.contains("флакон") || !packaging.contains("етикетка: «внутрішнє»") {
                    errors.append("control packaging must contain neutral vial + internal-use label")
                }
                return errors
            }
        )
    }

    private static func aqueousAdWithKuoScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.useBuretteSystem = false
        d.signa = "По 1 столовой ложке 3 раза в день"
        d.targetValue = 150
        d.targetUnit = UnitCode(rawValue: "ml")
        d.ingredients = [
            IngredientDraft(
                displayName: "Natrii bromidum",
                role: .active,
                amountValue: 5,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Natrii bromidum",
                refKuoMlPerG: 0.23
            ),
            IngredientDraft(
                displayName: "Aqua purificata",
                role: .solvent,
                amountValue: 150,
                unit: UnitCode(rawValue: "ml"),
                isAd: true,
                refType: "solvent"
            )
        ]

        return RxFixtureScenario(
            id: "aqueous_ad_with_kuo",
            title: "Aqueous ad solution >=3% applies KUO",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, WaterSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [BuretteSystemBlock.blockId],
            expectedSectionTitles: ["Розрахунки", "Технологія"],
            expectedLineFragments: [
                "Кількість розчинника розрахована з урахуванням КУО"
            ],
            validator: { evaluated in
                var errors: [String] = []
                if evaluated.derived.routeBranch != "aqueous_true_solution" {
                    errors.append("branch expected=aqueous_true_solution actual=\(evaluated.derived.routeBranch ?? "nil")")
                }
                guard let kuoText = evaluated.derived.calculations["kuo_volume_ml"],
                      let kuo = Double(kuoText.replacingOccurrences(of: ",", with: ".")),
                      kuo > 0 else {
                    errors.append("expected kuo_volume_ml > 0 for >=3% case")
                    return errors
                }
                return errors
            }
        )
    }

    private static func aqueousAdMixedDryNoBuretteScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.useBuretteSystem = false
        d.signa = "По 1 столовой ложке 3 раза в день"
        d.targetValue = 150
        d.targetUnit = UnitCode(rawValue: "ml")
        d.ingredients = [
            IngredientDraft(
                displayName: "Natrii bromidum",
                role: .active,
                amountValue: 3,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Natrii bromidum",
                refKuoMlPerG: 0.23
            ),
            IngredientDraft(
                displayName: "Coffeini-natrii benzoas",
                role: .active,
                amountValue: 1,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Coffeini-natrii benzoas",
                refKuoMlPerG: 0.60
            ),
            IngredientDraft(
                displayName: "Glucosi",
                role: .active,
                amountValue: 6,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Glucosi",
                refKuoMlPerG: 0.69
            ),
            IngredientDraft(
                displayName: "Aqua purificata",
                role: .solvent,
                amountValue: 150,
                unit: UnitCode(rawValue: "ml"),
                isAd: true,
                refType: "solvent"
            )
        ]

        return RxFixtureScenario(
            id: "aqueous_ad_mixed_dry_no_burette",
            title: "Mixed dry solids without burette stays aqueous true-solution with KUO",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, WaterSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [BuretteSystemBlock.blockId],
            expectedSectionTitles: ["Розрахунки", "Технологія"],
            expectedLineFragments: [
                "Кількість розчинника розрахована з урахуванням КУО"
            ],
            validator: { evaluated in
                var errors: [String] = []
                if evaluated.derived.routeBranch != "aqueous_true_solution" {
                    errors.append("branch expected=aqueous_true_solution actual=\(evaluated.derived.routeBranch ?? "nil")")
                }
                if evaluated.derived.calculations["ignore_kuo_for_burette"] != nil {
                    errors.append("unexpected ignore_kuo_for_burette in non-burette case")
                }
                return errors
            }
        )
    }

    private static func aqueousAdBuretteAllConcentratesScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.useBuretteSystem = true
        d.signa = "По 1 столовой ложке 3 раза в день"
        d.targetValue = 150
        d.targetUnit = UnitCode(rawValue: "ml")
        d.ingredients = [
            IngredientDraft(
                displayName: "Natrii bromidum",
                role: .active,
                amountValue: 3,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Natrii bromidum",
                refKuoMlPerG: 0.23
            ),
            IngredientDraft(
                displayName: "Coffeini-natrii benzoas",
                role: .active,
                amountValue: 1,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Coffeini-natrii benzoas",
                refKuoMlPerG: 0.60
            ),
            IngredientDraft(
                displayName: "Glucosi",
                role: .active,
                amountValue: 6,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Glucosi",
                refKuoMlPerG: 0.69
            ),
            IngredientDraft(
                displayName: "Aqua purificata",
                role: .solvent,
                amountValue: 150,
                unit: UnitCode(rawValue: "ml"),
                isAd: true,
                refType: "solvent"
            )
        ]

        return RxFixtureScenario(
            id: "aqueous_ad_burette_all_concentrates",
            title: "Burette active with all concentrates uses aqueous_burette_solution branch",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, BuretteSystemBlock.blockId, WaterSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [],
            expectedSectionTitles: ["Бюреточні розрахунки", "Розрахунки", "Технологія"],
            expectedLineFragments: [
                "Раствор натрия бромида 20%: V_conc = 3 / 0,2 = 15 ml",
                "Раствор кофеина-натрия бензоата 10%: V_conc = 1 / 0,1 = 10 ml",
                "Раствор глюкозы 50%: V_conc = 6 / 0,5 = 12 ml",
                "ΣV_концентратів = 37 ml",
                "Aqua purificata = 113 ml"
            ],
            validator: { evaluated in
                var errors: [String] = []
                if evaluated.derived.routeBranch != "aqueous_burette_solution" {
                    errors.append("branch expected=aqueous_burette_solution actual=\(evaluated.derived.routeBranch ?? "nil")")
                }
                if evaluated.derived.calculations["ignore_kuo_for_burette"] != "true" {
                    errors.append("missing calculation flag: ignore_kuo_for_burette")
                }
                if evaluated.issues.contains(where: { $0.message.contains("КУО") && $0.message.contains("бракує") }) {
                    errors.append("unexpected KUO-missing issue in all-concentrates burette case")
                }
                return errors
            }
        )
    }

    private static func waterFrequencyFromAbbreviatedSignaScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.signa = "По 1 столовой ложке 3 р в день"
        d.targetValue = 150
        d.targetUnit = UnitCode(rawValue: "ml")
        d.ingredients = [
            IngredientDraft(
                displayName: "Natrii bromidum",
                role: .active,
                amountValue: 3,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Natrii bromidum",
                refVrdG: 1.0,
                refVsdG: 3.0
            ),
            IngredientDraft(
                displayName: "Aqua purificata",
                role: .solvent,
                amountValue: 150,
                unit: UnitCode(rawValue: "ml"),
                isAd: true,
                refType: "solvent"
            )
        ]

        return RxFixtureScenario(
            id: "water_frequency_abbrev_signa",
            title: "Water solution parses abbreviated intake frequency from signa",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, WaterSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [NonAqueousSolutionsBlock.blockId],
            expectedSectionTitles: ["Контроль доз"],
            expectedLineFragments: [
                "Кратність: 3 р/добу",
                "Natrii bromidum",
                "на 1 прийом 0.3000 g",
                "на добу 0.9000 g"
            ]
        )
    }

    private static func standardDemyanovichScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.useStandardSolutionsBlock = true
        d.signa = "Раствор №2 по Демьяновичу"
        d.ingredients = [
            IngredientDraft(
                displayName: "Acidum hydrochloricum 6%",
                role: .active,
                amountValue: 200,
                unit: UnitCode(rawValue: "ml"),
                refType: "act",
                refNameLatNom: "Acidum hydrochloricum 6%",
            )
        ]

        return RxFixtureScenario(
            id: "std_demyanovich",
            title: "Standard solution Demyanovich #2",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, StandardSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [],
            expectedSectionTitles: ["Розрахунки (ГФ: стандартні розчини)", "Технологія"],
            expectedLineFragments: [
                "Фармакопейний еквівалент для розчину №2 за Дем'яновичем: кислота 24,8–25,2% 12 ml + Aqua purificata ad 200 ml",
                "Фактичне виготовлення з Acidum hydrochloricum dilutum 8,3%: 36 ml + Aqua purificata 164 ml",
                "У підставку: Aqua purificata 164 ml",
                "Додати: Кислота хлористоводородная разведенная 8,3% 36 ml"
            ]
        )
    }

    private static func hydrochloricAcidDilutionScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.useStandardSolutionsBlock = true
        d.signa = "По 1 чайной ложке 3 раза в день"
        d.ingredients = [
            IngredientDraft(
                displayName: "Acidum hydrochloricum 2%",
                role: .active,
                amountValue: 200,
                unit: UnitCode(rawValue: "ml"),
                refType: "act",
                refNameLatNom: "Acidum hydrochloricum 2%"
            )
        ]

        return RxFixtureScenario(
            id: "std_hcl_2pct",
            title: "Hydrochloric acid 2% uses stock-solution percent rule",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, StandardSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [],
            expectedSectionTitles: ["Розрахунки (ГФ: стандартні розчини)", "Технологія"],
            expectedLineFragments: [
                "Кислота хлористоводородная разведенная 2%: 4 ml + Aqua purificata ad 200 ml",
                "Додати: Кислота хлористоводородная разведенная 8,3% 4 ml"
            ]
        )
    }

    private static func hydrogenPeroxideDilutionScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.useStandardSolutionsBlock = true
        d.signa = "Зовнішньо"
        d.ingredients = [
            IngredientDraft(
                displayName: "Hydrogenii peroxydi 5%",
                role: .active,
                amountValue: 100,
                unit: UnitCode(rawValue: "ml"),
                refType: "act",
                refNameLatNom: "Hydrogenii peroxydi 5%"
            )
        ]

        return RxFixtureScenario(
            id: "std_h2o2_5pct",
            title: "Peroxide 5% uses concentrated stock ratio",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, StandardSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [],
            expectedSectionTitles: ["Розрахунки (ГФ: стандартні розчини)", "Технологія"],
            expectedLineFragments: ["Відміряти: Раствор водорода перекиси концентрированный 30% 16.667 ml"]
        )
    }

    private static func ethanolExternalSolutionScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .alcoholSolution
        d.signa = "Протирать кожу лица"
        d.ingredients = [
            IngredientDraft(
                displayName: "Spiritus salicylicus 1%",
                role: .active,
                amountValue: 10,
                unit: UnitCode(rawValue: "ml"),
                refType: "act",
                refNameLatNom: "Spiritus salicylicus 1%",
                refSolventType: "ethanol"
            )
        ]

        return RxFixtureScenario(
            id: "ethanol_external_solution",
            title: "External alcohol solution is not mouth rinse",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, NonAqueousSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [DropDoseSupportBlock.blockId, DropsBlock.blockId],
            expectedSectionTitles: ["Технологія виготовлення", "Логіка неводного розчину"]
        )
    }

    private static func ethanolSolutionScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .alcoholSolution
        d.signa = "Зовнішньо"
        d.targetValue = 100
        d.targetUnit = UnitCode(rawValue: "ml")
        d.ingredients = [
            IngredientDraft(
                displayName: "Iodi",
                role: .active,
                amountValue: 2,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Iodi",
                refSolubility: "Дуже мало розчинний у воді, розчинний у спирті"
            ),
            IngredientDraft(
                displayName: "Spiritus aethylici 70%",
                role: .solvent,
                amountValue: 100,
                unit: UnitCode(rawValue: "ml"),
                isAd: true,
                refType: "solvent",
                refNameLatNom: "Spiritus aethylici 70%",
                refDensity: 0.89,
                refSolventType: "ethanol"
            )
        ]

        return RxFixtureScenario(
            id: "ethanol_solution",
            title: "Non-aqueous ethanol solution uses dedicated block",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, NonAqueousSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [DropsBlock.blockId],
            expectedSectionTitles: ["Розрахунки", "Технологія виготовлення", "Контроль якості", "Логіка неводного розчину"]
        )
    }

    private static func glycerinSolutionScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.signa = "Для змащування"
        d.targetValue = 50
        d.targetUnit = UnitCode(rawValue: "ml")
        d.ingredients = [
            IngredientDraft(
                displayName: "Natrii tetraboratis",
                role: .active,
                amountValue: 5,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Natrii tetraboratis",
                refSolubility: "Розчинний у гліцерині при нагріванні"
            ),
            IngredientDraft(
                displayName: "Glycerinum",
                role: .solvent,
                amountValue: 50,
                unit: UnitCode(rawValue: "ml"),
                isAd: true,
                refType: "solvent",
                refNameLatNom: "Glycerinum",
                refDensity: 1.228,
                refSolventType: "glycerin"
            )
        ]

        return RxFixtureScenario(
            id: "glycerin_solution",
            title: "Glycerin solution auto-routes as non-aqueous",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, NonAqueousSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [DropsBlock.blockId, StrongControlBlock.blockId, PoisonControlBlock.blockId],
            expectedSectionTitles: ["Розрахунки", "Технологія виготовлення", "Контроль якості", "Логіка неводного розчину"]
        )
    }

    private static func glycerinIodineComplexScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.signa = "Для зовнішнього застосування"
        d.targetValue = 10
        d.targetUnit = UnitCode(rawValue: "g")
        d.ingredients = [
            IngredientDraft(
                displayName: "Iodum",
                role: .active,
                amountValue: 0.05,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Iodum"
            ),
            IngredientDraft(
                displayName: "Kalii iodidum",
                role: .active,
                amountValue: 0.1,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Kalii iodidum"
            ),
            IngredientDraft(
                displayName: "Glycerinum",
                role: .solvent,
                amountValue: 10,
                unit: UnitCode(rawValue: "g"),
                isAd: true,
                refType: "solvent",
                refNameLatNom: "Glycerinum",
                refDensity: 1.228,
                refSolventType: "glycerin"
            )
        ]

        return RxFixtureScenario(
            id: "glycerin_iodine_complex",
            title: "Iodine in glycerin requires iodide complex path",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, NonAqueousSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [DropsBlock.blockId],
            expectedSectionTitles: ["Розрахунки", "Технологія виготовлення", "Контроль якості", "Логіка неводного розчину"]
        )
    }

    private static func ethanolRinseMeasuredByDropsScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .drops
        d.liquidTechnologyMode = .alcoholSolution
        d.signa = "По 10 капель на 0,5 стакана воды для полоскания"
        d.ingredients = [
            IngredientDraft(
                displayName: "Mentholi",
                role: .active,
                amountValue: 0.1,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Mentholum",
                refSolubility: "Практично нерозчинний у воді, дуже легко розчинний у спирті"
            ),
            IngredientDraft(
                displayName: "Thymoli",
                role: .active,
                amountValue: 0.1,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Thymolum",
                refSolubility: "1:1100 H2O, 1:1 Alcohol, 1:3 Oils",
                refInteractionNotes: "Образует эвтектические смеси с камфорой, ментолом и хлоралгидратом"
            ),
            IngredientDraft(
                displayName: "Spiritus aethylici 90%",
                role: .solvent,
                amountValue: 10,
                unit: UnitCode(rawValue: "ml"),
                refType: "solvent",
                refNameLatNom: "Spiritus aethylici 90%",
                refDensity: 0.833,
                refSolventType: "ethanol"
            )
        ]

        return RxFixtureScenario(
            id: "ethanol_rinse_measured_by_drops",
            title: "Drops in signa can still mean alcohol rinse solution",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, NonAqueousSolutionsBlock.blockId, DropDoseSupportBlock.blockId],
            forbiddenActivatedBlocks: [DropsBlock.blockId],
            expectedSectionTitles: ["Технологія виготовлення", "Логіка неводного розчину", "Контроль доз"]
        )
    }

    private static func oilEarDropsScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .drops
        d.signa = "По 2 капли в ухо 2 раза в день"
        d.ingredients = [
            IngredientDraft(
                displayName: "Acidi carbolici",
                role: .active,
                amountValue: 0.1,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Phenolum"
            ),
            IngredientDraft(
                displayName: "Oleum Helianthi",
                role: .solvent,
                amountValue: 5,
                unit: UnitCode(rawValue: "ml"),
                refType: "solvent",
                refNameLatNom: "Oleum Helianthi",
                refSolventType: "fatty_oil"
            )
        ]

        return RxFixtureScenario(
            id: "oil_ear_drops",
            title: "Non-aqueous ear drops combine solvent tech and drop metrology",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, NonAqueousSolutionsBlock.blockId, DropsBlock.blockId],
            forbiddenActivatedBlocks: [],
            expectedSectionTitles: ["Технологія виготовлення", "Контроль доз", "Оформлення"]
        )
    }

    private static func dropsDoseScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .drops
        d.isOphthalmicDrops = false
        d.signa = "По 10 капель 3 раза в день"
        d.ingredients = [
            IngredientDraft(
                displayName: "Tinctura Valerianae",
                role: .active,
                amountValue: 20,
                unit: UnitCode(rawValue: "ml"),
                refType: "tincture",
                refGttsPerMl: 50,
            ),
            IngredientDraft(
                displayName: "Natrii bromidum",
                role: .active,
                amountValue: 2,
                unit: UnitCode(rawValue: "g"),
                refType: "act"
            )
        ]

        return RxFixtureScenario(
            id: "drops_dose",
            title: "Drops with dose control",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, DropsBlock.blockId],
            forbiddenActivatedBlocks: [NonAqueousSolutionsBlock.blockId],
            expectedSectionTitles: ["Розрахунки", "Контроль доз", "Технологія"]
        )
    }

    private static func internalDropsNoFalsePoisonScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .drops
        d.isOphthalmicDrops = false
        d.signa = "По 20 капель 3 раза в день"
        d.ingredients = [
            IngredientDraft(
                displayName: "Tinctura Valerianae",
                role: .active,
                amountValue: 10,
                unit: UnitCode(rawValue: "ml"),
                refType: "tincture",
                refNameLatNom: "Tinctura Valerianae"
            ),
            IngredientDraft(
                displayName: "Tinctura Leonuri",
                role: .active,
                amountValue: 10,
                unit: UnitCode(rawValue: "ml"),
                refType: "tincture",
                refNameLatNom: "Tinctura Leonuri"
            ),
            IngredientDraft(
                displayName: "Aqua purificata",
                role: .solvent,
                amountValue: 30,
                unit: UnitCode(rawValue: "ml"),
                refType: "solvent"
            )
        ]

        return RxFixtureScenario(
            id: "internal_drops_no_false_poison",
            title: "Internal drops should not auto-add List A/poison controls",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, DropsBlock.blockId],
            forbiddenActivatedBlocks: [PoisonControlBlock.blockId],
            expectedSectionTitles: ["Контроль доз", "Оформлення"],
            expectedLineFragments: [
                "Тара: Флакон-крапельниця",
                "Маркування: «Внутрішнє»"
            ],
            forbiddenLineFragments: [
                "Список А",
                "ЯД",
                "подвійний контроль",
                "опечат"
            ],
            validator: { evaluated in
                evaluated.derived.routeBranch == "internal_drops"
                    ? []
                    : ["routeBranch expected=internal_drops actual=\(evaluated.derived.routeBranch ?? "nil")"]
            }
        )
    }

    private static func nasalDropsConcentrationControlScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .drops
        d.isOphthalmicDrops = false
        d.signa = "Капли в нос"
        d.targetValue = 10
        d.targetUnit = UnitCode(rawValue: "ml")
        d.ingredients = [
            IngredientDraft(
                displayName: "Ephedrini hydrochloridum",
                role: .active,
                amountValue: 0.1,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Ephedrini hydrochloridum"
            ),
            IngredientDraft(
                displayName: "Aqua purificata",
                role: .solvent,
                amountValue: 10,
                unit: UnitCode(rawValue: "ml"),
                isAd: true,
                refType: "solvent"
            )
        ]

        return RxFixtureScenario(
            id: "nasal_drops_concentration_control",
            title: "Nasal drops use concentration control and nasal labeling",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, DropsBlock.blockId],
            forbiddenActivatedBlocks: [],
            expectedSectionTitles: ["Контроль концентрації", "Оформлення"],
            expectedLineFragments: [
                "пероральний дозовий контроль не застосовується",
                "Маркування: «Краплі в ніс»"
            ],
            forbiddenLineFragments: [
                "Разовий прийом",
                "столова ложка"
            ],
            validator: { evaluated in
                evaluated.derived.routeBranch == "nasal_drops"
                    ? []
                    : ["routeBranch expected=nasal_drops actual=\(evaluated.derived.routeBranch ?? "nil")"]
            }
        )
    }

    private static func ophthalmicDropsNoExtraNaClScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .drops
        d.isOphthalmicDrops = false
        d.signa = "Капли глазные"
        d.targetValue = 100
        d.targetUnit = UnitCode(rawValue: "ml")
        d.ingredients = [
            IngredientDraft(
                displayName: "Natrii chloridum",
                role: .active,
                amountValue: 0.9,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Natrii chloridum"
            ),
            IngredientDraft(
                displayName: "Aqua purificata",
                role: .solvent,
                amountValue: 100,
                unit: UnitCode(rawValue: "ml"),
                isAd: true,
                refType: "solvent"
            )
        ]

        return RxFixtureScenario(
            id: "ophthalmic_drops_no_extra_nacl",
            title: "Ophthalmic drops should detect already isotonic NaCl recipe",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, OphthalmicDropsBlock.blockId],
            forbiddenActivatedBlocks: [DropsBlock.blockId],
            expectedSectionTitles: ["Розрахунки", "Оформлення"],
            expectedLineFragments: [
                "Ізотонічність уже забезпечена рецептом",
                "Маркування: «Очні краплі. Стерильно.»"
            ],
            forbiddenLineFragments: [
                "Додати NaCl:"
            ],
            validator: { evaluated in
                evaluated.derived.routeBranch == "ophthalmic_drops"
                    ? []
                    : ["routeBranch expected=ophthalmic_drops actual=\(evaluated.derived.routeBranch ?? "nil")"]
            }
        )
    }

    private static func furacilinRatioSolutionScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.targetValue = 250
        d.targetUnit = UnitCode(rawValue: "ml")
        d.signa = "Полоскання"
        d.ingredients = [
            IngredientDraft(
                displayName: "Furacilinum",
                role: .active,
                amountValue: 250,
                unit: UnitCode(rawValue: "ml"),
                presentationKind: .solution,
                refType: "act",
                refNameLatNom: "Solutionis Furacilini 1:5000"
            ),
            IngredientDraft(
                displayName: "Aqua purificata",
                role: .solvent,
                amountValue: 250,
                unit: UnitCode(rawValue: "ml"),
                isAd: true,
                refType: "solvent"
            )
        ]

        return RxFixtureScenario(
            id: "furacilin_ratio_solution",
            title: "Furacilinum 1:5000 uses ratio mass calculation and boiling-water notes",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, WaterSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [NonAqueousSolutionsBlock.blockId],
            expectedSectionTitles: ["Розрахунки", "Стабільність", "Технологія"],
            expectedLineFragments: [
                "повному розчиненні кристалів",
                "Берегти від дітей"
            ]
        )
    }

    private static func silverNitrateSolutionScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.targetValue = 300
        d.targetUnit = UnitCode(rawValue: "ml")
        d.signa = "Для промивання сечового міхура"
        d.ingredients = [
            IngredientDraft(
                displayName: "Argenti nitras",
                role: .active,
                amountValue: 1.5,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Argenti nitras",
                refListA: true
            ),
            IngredientDraft(
                displayName: "Aqua purificata",
                role: .solvent,
                amountValue: 300,
                unit: UnitCode(rawValue: "ml"),
                isAd: true,
                refType: "solvent"
            )
        ]

        return RxFixtureScenario(
            id: "silver_nitrate_solution",
            title: "Silver nitrate water solution triggers List A and distilled-water technology notes",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, WaterSolutionsBlock.blockId, PoisonControlBlock.blockId],
            forbiddenActivatedBlocks: [NonAqueousSolutionsBlock.blockId],
            expectedSectionTitles: ["Контроль доз", "Технологія", "Упаковка/Маркування"],
            expectedLineFragments: []
        )
    }

    private static func iodineKiAqueousScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.targetValue = 10
        d.targetUnit = UnitCode(rawValue: "ml")
        d.signa = "Для обробки шкіри"
        d.ingredients = [
            IngredientDraft(
                displayName: "Iodi",
                role: .active,
                amountValue: 0.05,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Iodi"
            ),
            IngredientDraft(
                displayName: "Kalii iodidum",
                role: .active,
                amountValue: 0.1,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Kalii iodidum"
            ),
            IngredientDraft(
                displayName: "Aqua purificata",
                role: .solvent,
                amountValue: 10,
                unit: UnitCode(rawValue: "ml"),
                isAd: true,
                refType: "solvent"
            )
        ]

        return RxFixtureScenario(
            id: "iodine_ki_aqueous",
            title: "Iodine + iodide in water builds sequential complex-formation instructions",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, WaterSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [NonAqueousSolutionsBlock.blockId],
            expectedSectionTitles: ["Розрахунки", "Технологія"],
            expectedLineFragments: [
                "Iodine/KI:",
                "Йодну систему готувати послідовно"
            ]
        )
    }

    private static func iodineKiFromSolutionAqueousScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.targetValue = 10
        d.targetUnit = UnitCode(rawValue: "ml")
        d.signa = "Для змазування зева"
        d.ingredients = [
            IngredientDraft(
                displayName: "Sol. Kalii iodidi 2%",
                role: .active,
                amountValue: 10,
                unit: UnitCode(rawValue: "ml"),
                presentationKind: .solution,
                refType: "act",
                refNameLatNom: "Sol. Kalii iodidi 2%"
            ),
            IngredientDraft(
                displayName: "Iodi",
                role: .active,
                amountValue: 0.05,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Iodi"
            )
        ]

        return RxFixtureScenario(
            id: "iodine_ki_from_solution_aqueous",
            title: "Iodine with iodide provided as Sol.% keeps complex-first order in TechnologyOrder",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, WaterSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [NonAqueousSolutionsBlock.blockId],
            expectedSectionTitles: ["Розрахунки", "Технологія"],
            validator: { evaluated in
                var errors: [String] = []
                guard let ppkDocument = evaluated.derived.ppkDocument else {
                    errors.append("missing ppkDocument")
                    return errors
                }
                let orderLines = ppkDocument.faceSide
                    .first(where: { $0.title == "Порядок внесення (TechnologyOrder)" })?
                    .lines ?? []
                if orderLines.isEmpty {
                    errors.append("missing TechnologyOrder lines")
                    return errors
                }

                let iodideLineIndex = orderLines.firstIndex { $0.lowercased().contains("iodid") }
                let iodineLineIndex = orderLines.firstIndex { line in
                    let lower = line.lowercased()
                    return lower.contains("iodi ") || lower.contains("iodine")
                }
                if iodideLineIndex == nil || iodineLineIndex == nil {
                    errors.append("missing iodide/iodine steps in TechnologyOrder")
                } else if iodideLineIndex! > iodineLineIndex! {
                    errors.append("iodide step must be placed before iodine step")
                }

                let hasSplitNote = orderLines.contains { $0.lowercased().contains("частину розчину йодиду") }
                if !hasSplitNote {
                    errors.append("missing note about using part of iodide solution for pre-complex")
                }
                return errors
            }
        )
    }

    private static func tweenSpanConflictWaterScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.targetValue = 100
        d.targetUnit = UnitCode(rawValue: "ml")
        d.signa = "Зовнішньо"
        d.ingredients = [
            IngredientDraft(
                displayName: "Tween-80",
                role: .active,
                amountValue: 1,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Tween-80"
            ),
            IngredientDraft(
                displayName: "Natrii salicylatis",
                role: .active,
                amountValue: 1,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Natrii salicylatis"
            ),
            IngredientDraft(
                displayName: "Aqua purificata",
                role: .solvent,
                amountValue: 100,
                unit: UnitCode(rawValue: "ml"),
                isAd: true,
                refType: "solvent"
            )
        ]

        return RxFixtureScenario(
            id: "water_tween_span_conflict",
            title: "Tween/Span incompatibility is raised in aqueous solutions",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, WaterSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [NonAqueousSolutionsBlock.blockId],
            expectedSectionTitles: ["Стабільність", "Технологія"],
            expectedLineFragments: [
                "несумісні із саліцилатами/фенолами/похідними параоксибензойної кислоти"
            ]
        )
    }

    private static func concentratedPermanganateScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.targetValue = 100
        d.targetUnit = UnitCode(rawValue: "ml")
        d.signa = "Зовнішньо"
        d.ingredients = [
            IngredientDraft(
                displayName: "Kalii permanganatis",
                role: .active,
                amountValue: 4,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Kalii permanganatis"
            ),
            IngredientDraft(
                displayName: "Aqua purificata",
                role: .solvent,
                amountValue: 100,
                unit: UnitCode(rawValue: "ml"),
                isAd: true,
                refType: "solvent"
            )
        ]

        return RxFixtureScenario(
            id: "water_permanganate_concentrated",
            title: "Concentrated potassium permanganate uses trituration pre-step",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, WaterSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [NonAqueousSolutionsBlock.blockId],
            expectedSectionTitles: ["Стабільність", "Технологія"],
            expectedLineFragments: [
                "концентрованого розчину 4%",
                "попередньо обережно розтерти кристали"
            ]
        )
    }

    private static func decoctionTanninHotFiltrationScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .decoction
        d.signa = "По 1 столовій ложці 3 рази на день"
        d.ingredients = [
            IngredientDraft(
                displayName: "Cortex Quercus",
                role: .active,
                amountValue: 10,
                unit: UnitCode(rawValue: "g"),
                refType: "herbalraw",
                refPrepMethod: "decoctum",
                refHerbalRatio: "1:10"
            ),
            IngredientDraft(
                displayName: "Aqua purificata",
                role: .solvent,
                amountValue: 100,
                unit: UnitCode(rawValue: "ml"),
                isAd: true,
                refType: "solvent"
            )
        ]

        return RxFixtureScenario(
            id: "decoction_tannin_hot_filtration",
            title: "Tannin-rich decoction requires immediate hot filtration",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, InfusionDecoctionBlock.decoctionBlockId],
            forbiddenActivatedBlocks: [],
            expectedSectionTitles: ["Технологія"],
            expectedLineFragments: [
                "відразу проціджувати гарячим"
            ]
        )
    }

    private static func vmsProtargolGlycerinScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.useVmsColloidsBlock = true
        d.targetValue = 10
        d.targetUnit = UnitCode(rawValue: "ml")
        d.signa = "Для промивання"
        d.ingredients = [
            IngredientDraft(
                displayName: "Protargolum",
                role: .active,
                amountValue: 0.3,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Protargolum"
            ),
            IngredientDraft(
                displayName: "Glycerinum",
                role: .excipient,
                amountValue: 0.3,
                unit: UnitCode(rawValue: "ml"),
                refType: "aux",
                refNameLatNom: "Glycerinum"
            ),
            IngredientDraft(
                displayName: "Aqua purificata",
                role: .solvent,
                amountValue: 10,
                unit: UnitCode(rawValue: "ml"),
                isAd: true,
                refType: "solvent"
            )
        ]

        return RxFixtureScenario(
            id: "vms_protargol_glycerin",
            title: "Protargol with glycerin uses pre-trituration path",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, NonAqueousSolutionsBlock.blockId, VMSColloidsBlock.blockId],
            forbiddenActivatedBlocks: [],
            expectedSectionTitles: ["Технологія"],
            expectedLineFragments: [
                "6–8 краплями гліцерину"
            ]
        )
    }

    private static func nonAqueousTweenSpanConflictScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.signa = "Зовнішньо"
        d.targetValue = 30
        d.targetUnit = UnitCode(rawValue: "g")
        d.ingredients = [
            IngredientDraft(
                displayName: "Tween-80",
                role: .active,
                amountValue: 0.5,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Tween-80"
            ),
            IngredientDraft(
                displayName: "Natrii salicylatis",
                role: .active,
                amountValue: 0.5,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Natrii salicylatis"
            ),
            IngredientDraft(
                displayName: "Glycerinum",
                role: .solvent,
                amountValue: 30,
                unit: UnitCode(rawValue: "g"),
                isAd: true,
                refType: "solvent",
                refNameLatNom: "Glycerinum",
                refDensity: 1.228,
                refSolventType: "glycerin"
            )
        ]

        return RxFixtureScenario(
            id: "nonaqueous_tween_span_conflict",
            title: "Tween/Span incompatibility is raised in non-aqueous solutions",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, NonAqueousSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [WaterSolutionsBlock.blockId],
            expectedSectionTitles: ["Технологія виготовлення", "Логіка неводного розчину"],
            expectedLineFragments: []
        )
    }

    private static func nonAqueousChloroformParaffinScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .alcoholSolution
        d.signa = "Зовнішньо"
        d.targetValue = 20
        d.targetUnit = UnitCode(rawValue: "ml")
        d.ingredients = [
            IngredientDraft(
                displayName: "Paraffinum",
                role: .active,
                amountValue: 1,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Paraffinum"
            ),
            IngredientDraft(
                displayName: "Chloroformium",
                role: .solvent,
                amountValue: 20,
                unit: UnitCode(rawValue: "ml"),
                isAd: true,
                refType: "solvent",
                refNameLatNom: "Chloroformium",
                refSolventType: "chloroform"
            )
        ]

        return RxFixtureScenario(
            id: "nonaqueous_chloroform_paraffin",
            title: "Chloroform with paraffin gets cautious heating instruction",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, NonAqueousSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [WaterSolutionsBlock.blockId],
            expectedSectionTitles: ["Технологія виготовлення", "Логіка неводного розчину"],
            expectedLineFragments: [
                "Chloroformium + Paraffinum"
            ]
        )
    }

    private static func powderNewbornAsepticScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .powders
        d.numero = 10
        d.signa = "Для новонародженого: по 1 порошку 2 рази на день"
        d.ingredients = [
            IngredientDraft(
                displayName: "Zinci oxydum",
                role: .active,
                amountValue: 0.1,
                unit: UnitCode(rawValue: "g"),
                scope: .perDose,
                refType: "act",
                refNameLatNom: "Zinci oxydum"
            ),
            IngredientDraft(
                displayName: "Sacchari lactis",
                role: .excipient,
                amountValue: 0.25,
                unit: UnitCode(rawValue: "g"),
                scope: .perDose,
                refType: "aux",
                refNameLatNom: "Sacchari lactis"
            )
        ]

        return RxFixtureScenario(
            id: "powder_newborn_aseptic",
            title: "Powders for newborns require aseptic manufacturing",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, PowdersTriturationsBlock.blockId],
            forbiddenActivatedBlocks: [PoisonControlBlock.blockId, StrongControlBlock.blockId],
            expectedSectionTitles: ["Технологія", "Оформлення та зберігання"],
            expectedLineFragments: [
                "порошок для новонародженого"
            ]
        )
    }

    private static func platyphylliniDropsScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .drops
        d.isOphthalmicDrops = false
        d.signa = "По 10 капель 3 раза в день"
        d.ingredients = [
            IngredientDraft(
                displayName: "Platyphyllini hydrotartras",
                role: .active,
                amountValue: 0.04,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Platyphyllini hydrotartras",
                refVrdG: 0.01,
                refVsdG: 0.03,
                refListB: true
            ),
            IngredientDraft(
                displayName: "Aqua purificata",
                role: .solvent,
                amountValue: 20,
                unit: UnitCode(rawValue: "ml"),
                refType: "solvent"
            )
        ]

        return RxFixtureScenario(
            id: "platyphyllini_drops",
            title: "List B drops (Platyphyllini) should be included in dose checks",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, DropsBlock.blockId],
            forbiddenActivatedBlocks: [NonAqueousSolutionsBlock.blockId],
            expectedSectionTitles: ["Контроль доз"]
        )
    }

    private static func platyphylliniListADropsScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .drops
        d.isOphthalmicDrops = false
        d.signa = "По 10 капель 3 раза в день"
        d.ingredients = [
            IngredientDraft(
                displayName: "Platyphyllini hydrotartras",
                role: .active,
                amountValue: 0.05,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Platyphyllini hydrotartras",
                refVrdG: 0.01,
                refVsdG: 0.03,
                refListA: true
            ),
            IngredientDraft(
                displayName: "Aqua purificata",
                role: .solvent,
                amountValue: 10,
                unit: UnitCode(rawValue: "ml"),
                refType: "solvent"
            )
        ]

        return RxFixtureScenario(
            id: "platyphyllini_lista_drops",
            title: "List A drops (Platyphyllini) should not block dose calculation when VRD/VSD are present",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, DropsBlock.blockId, PoisonControlBlock.blockId],
            forbiddenActivatedBlocks: [NonAqueousSolutionsBlock.blockId],
            expectedSectionTitles: ["Контроль доз", "Контроль списку А"]
        )
    }

    private static func infusionScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .infusion
        d.signa = "По 1/3 стакана 3 раза в день"
        d.ingredients = [
            IngredientDraft(
                displayName: "Herba Leonuri",
                role: .active,
                amountValue: 10,
                unit: UnitCode(rawValue: "g"),
                refType: "herbalraw",
                refPrepMethod: "infusum",
                refHerbalRatio: "1:10",
                refWaterTempC: 100,
                refHeatBathMin: 15,
                refStandMin: 45,
                refStrain: true,
                refBringToVolume: true
            ),
            IngredientDraft(
                displayName: "Aqua purificata",
                role: .solvent,
                amountValue: 100,
                unit: UnitCode(rawValue: "ml"),
                isAd: true,
                refType: "solvent"
            )
        ]

        return RxFixtureScenario(
            id: "infusion",
            title: "Infusion by reference metadata",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, InfusionDecoctionBlock.infusionBlockId],
            forbiddenActivatedBlocks: [],
            expectedSectionTitles: ["Технологія"]
        )
    }

    private static func listAPowderScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .powders
        d.numero = 10
        d.ingredients = [
            IngredientDraft(
                displayName: "Atropini sulfatis",
                role: .active,
                amountValue: 0.0005,
                unit: UnitCode(rawValue: "g"),
                scope: .perDose,
                refType: "act",
                refNameLatNom: "Atropini sulfatis",
                refVrdG: 0.001,
                refVsdG: 0.003,
                refListA: true
            ),
            IngredientDraft(
                displayName: "Sacchari lactis",
                role: .excipient,
                amountValue: 0.3,
                unit: UnitCode(rawValue: "g"),
                scope: .perDose,
                refType: "aux",
                refNameLatNom: "Sacchari lactis"
            )
        ]

        return RxFixtureScenario(
            id: "lista_powder",
            title: "List A powders use poison powder resolver only",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, PoisonControlBlock.blockId],
            forbiddenActivatedBlocks: [StrongControlBlock.blockId],
            expectedSectionTitles: ["Розрахунки", "Контроль доз", "Технологія Списку А"]
        )
    }

    private static func listBPowderScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .powders
        d.numero = 10
        d.ingredients = [
            IngredientDraft(
                displayName: "Substantia fortis",
                role: .active,
                amountValue: 0.002,
                unit: UnitCode(rawValue: "g"),
                scope: .perDose,
                refType: "act",
                refNameLatNom: "Substantia fortis",
                refVrdG: 0.01,
                refVsdG: 0.03,
                refListB: true,
                refPharmActivity: "Сильнодействующие"
            ),
            IngredientDraft(
                displayName: "Sacchari lactis",
                role: .excipient,
                amountValue: 0.3,
                unit: UnitCode(rawValue: "g"),
                scope: .perDose,
                refType: "aux",
                refNameLatNom: "Sacchari lactis"
            )
        ]

        return RxFixtureScenario(
            id: "listb_powder",
            title: "List B powders use strong powder resolver only",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, StrongControlBlock.blockId],
            forbiddenActivatedBlocks: [PoisonControlBlock.blockId],
            expectedSectionTitles: ["Розрахунки", "Контроль доз", "Технологія Списку Б"]
        )
    }

    private static func buretteAqueousConcentratesScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.useBuretteSystem = true
        d.targetValue = 150
        d.targetUnit = UnitCode(rawValue: "ml")
        d.signa = "По 1 столовой ложке 3 раза в день"
        d.solPercent = 2
        d.solPercentInputText = "2"
        d.solVolumeMl = 150
        d.ingredients = [
            IngredientDraft(
                displayName: "Sol. Natrii bromidi 2%",
                role: .active,
                amountValue: 150,
                unit: UnitCode(rawValue: "ml"),
                presentationKind: .solution,
                refType: "act",
                refNameLatNom: "Sol. Natrii bromidi 2%"
            ),
            IngredientDraft(
                displayName: "Coffeini-natrii benzoas",
                role: .active,
                amountValue: 1,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Coffeini-natrii benzoas"
            ),
            IngredientDraft(
                displayName: "Glucosi",
                role: .active,
                amountValue: 6,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Glucosi"
            )
        ]

        return RxFixtureScenario(
            id: "burette_aqueous_concentrates",
            title: "Burette aqueous recipe derives masses and volumes from Sol.% + V",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, BuretteSystemBlock.blockId, WaterSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [],
            expectedSectionTitles: ["Бюреточні розрахунки", "Розрахунки", "Технологія"],
            expectedLineFragments: [
                "Раствор натрия бромида 20%: V_conc = 3 / 0,2 = 15 ml",
                "Раствор кофеина-натрия бензоата 10%: V_conc = 1 / 0,1 = 10 ml",
                "Раствор глюкозы 50%: V_conc = 6 / 0,5 = 12 ml",
                "ΣV_концентратів = 37 ml",
                "Aqua purificata = 113 ml"
            ],
            forbiddenLineFragments: [
                "Раствор натрия бромида 20%: V_conc = 0",
                "КУО перевищує 3% від об'єму",
                "Гілка: ≥3% (з КУО)"
            ],
            validator: { evaluated in
                var errors: [String] = []
                if evaluated.derived.calculations["ignore_kuo_for_burette"] != "true" {
                    errors.append("missing calculation flag: ignore_kuo_for_burette")
                }
                if evaluated.issues.contains(where: { $0.message.contains("КУО перевищує 3%") }) {
                    errors.append("unexpected KУО>3% warning in burette mode")
                }
                return errors
            }
        )
    }

    private static func nonBuretteEquivalentScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.useBuretteSystem = false
        d.targetValue = 150
        d.targetUnit = UnitCode(rawValue: "ml")
        d.signa = "По 1 столовой ложке 3 раза в день"
        d.ingredients = [
            IngredientDraft(
                displayName: "Natrii bromidum",
                role: .active,
                amountValue: 3,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Natrii bromidum",
                refKuoMlPerG: 0.23
            ),
            IngredientDraft(
                displayName: "Coffeini-natrii benzoas",
                role: .active,
                amountValue: 1,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Coffeini-natrii benzoas",
                refKuoMlPerG: 0.6
            ),
            IngredientDraft(
                displayName: "Glucosi",
                role: .active,
                amountValue: 6,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Glucosi",
                refKuoMlPerG: 0.69
            ),
            IngredientDraft(
                displayName: "Aqua purificata",
                role: .solvent,
                amountValue: 150,
                unit: UnitCode(rawValue: "ml"),
                isAd: true,
                refType: "solvent"
            )
        ]

        return RxFixtureScenario(
            id: "non_burette_equivalent",
            title: "Equivalent aqueous recipe without burette uses standard KUO branch",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, WaterSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [BuretteSystemBlock.blockId],
            expectedSectionTitles: ["Розрахунки", "Технологія"],
            expectedLineFragments: [
                "Кількість розчинника розрахована з урахуванням КУО",
                "ΣКУО ="
            ],
            forbiddenLineFragments: [
                "Компоненти вводяться у вигляді концентрованих розчинів; КУО для них не застосовують"
            ],
            validator: { evaluated in
                evaluated.derived.calculations["ignore_kuo_for_burette"] == nil
                    ? []
                    : ["unexpected calculation flag: ignore_kuo_for_burette"]
            }
        )
    }

    private static func multipleSolutionIngredientsScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.targetValue = 100
        d.targetUnit = UnitCode(rawValue: "ml")
        d.signa = "По 1 столовой ложке 3 раза в день"
        d.solPercent = 2
        d.solPercentInputText = "2"
        d.solVolumeMl = 50
        d.ingredients = [
            IngredientDraft(
                displayName: "Sol. Natrii bromidi 2%",
                role: .active,
                amountValue: 50,
                unit: UnitCode(rawValue: "ml"),
                presentationKind: .solution,
                refType: "act",
                refNameLatNom: "Sol. Natrii bromidi 2%"
            ),
            IngredientDraft(
                displayName: "Sol. Magnesii sulfatis 20%",
                role: .active,
                amountValue: 50,
                unit: UnitCode(rawValue: "ml"),
                presentationKind: .solution,
                refType: "act",
                refNameLatNom: "Sol. Magnesii sulfatis 20%"
            )
        ]

        return RxFixtureScenario(
            id: "multiple_solution_ingredients",
            title: "Normalizer keeps multiple solution ingredients untouched",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, WaterSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [],
            expectedSectionTitles: ["Склад"],
            validator: { evaluated in
                var errors: [String] = []
                let solutionCount = evaluated.normalizedDraft.ingredients.filter { $0.presentationKind == .solution }.count
                if solutionCount < 2 {
                    errors.append("normalizer changed solution presentation kinds; expected >=2, got \(solutionCount)")
                }
                let hasExpectedWarning = evaluated.issues.contains {
                    $0.code == "sol.multiple"
                        && $0.message == "У рецепті кілька Sol.-компонентів; нормалізатор не повинен змінювати їх presentationKind"
                }
                if !hasExpectedWarning {
                    errors.append("missing warning sol.multiple with updated message")
                }
                return errors
            }
        )
    }

    private static func buretteMassDerivationFailureScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.useBuretteSystem = true
        d.targetValue = 100
        d.targetUnit = UnitCode(rawValue: "ml")
        d.signa = "По 1 столовой ложке 3 раза в день"
        d.ingredients = [
            IngredientDraft(
                displayName: "Natrii bromidum",
                role: .active,
                amountValue: 10,
                unit: UnitCode(rawValue: "ml"),
                presentationKind: .substance,
                refType: "act",
                refNameLatNom: "Natrii bromidum"
            )
        ]

        return RxFixtureScenario(
            id: "burette_mass_derivation_failure",
            title: "Burette mode reports blocking issue when solute mass cannot be derived",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, BuretteSystemBlock.blockId, WaterSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [],
            expectedSectionTitles: ["Розрахунки"],
            forbiddenLineFragments: [
                "Раствор натрия бромида 20%: V_conc = 0"
            ],
            validator: { evaluated in
                var errors: [String] = []
                let hasBlocking = evaluated.issues.contains {
                    $0.code == "burette.mass_derivation_failed" && $0.severity == .blocking
                }
                if !hasBlocking {
                    errors.append("missing blocking issue burette.mass_derivation_failed")
                }
                let renderedLines = evaluated.derived.ppkSections.flatMap(\.lines).joined(separator: "\n")
                if renderedLines.contains("Раствор натрия бромида 20%: V_conc") {
                    errors.append("invalid burette line rendered despite mass derivation failure")
                }
                return errors
            }
        )
    }

    private static func adaptiveQsAboveThreePercentScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.signa = "По 1 столовой ложке 3 раза в день"
        d.targetValue = 100
        d.targetUnit = UnitCode(rawValue: "ml")
        d.ingredients = [
            IngredientDraft(
                displayName: "Glucosum",
                role: .active,
                amountValue: 5,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Glucosum",
                refKuoMlPerG: 0.10
            ),
            IngredientDraft(
                displayName: "Aqua purificata",
                role: .solvent,
                amountValue: 100,
                unit: UnitCode(rawValue: "ml"),
                isAd: true,
                refType: "solvent"
            )
        ]

        return RxFixtureScenario(
            id: "adaptive_qs_above_3pct",
            title: "Adaptive q.s. ad mode above 3% when volume effect is low",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, WaterSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [BuretteSystemBlock.blockId],
            expectedSectionTitles: ["Розрахунки", "Технологія"],
            expectedLineFragments: [
                "КУО не враховується (режим доведення q.s. ad V)",
                "Aqua purificata q.s. ad 100 ml"
            ],
            validator: { evaluated in
                var errors: [String] = []
                if evaluated.derived.calculations["solvent_calculation_mode"] != "qs_to_volume" {
                    errors.append("expected solvent_calculation_mode=qs_to_volume")
                }
                if evaluated.derived.calculations["kuo_volume_ml"] != nil {
                    errors.append("unexpected kuo_volume_ml in adaptive q.s. mode")
                }
                let hasAdaptiveInfo = evaluated.issues.contains { $0.code == "water.kuo.adaptive_skip" }
                if !hasAdaptiveInfo {
                    errors.append("missing info issue water.kuo.adaptive_skip")
                }
                return errors
            }
        )
    }

    private static func ppkKuoApproxAndQsScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.signa = "По 1 столовой ложке 3 раза в день"
        d.targetValue = 150
        d.targetUnit = UnitCode(rawValue: "ml")
        d.ingredients = [
            IngredientDraft(
                displayName: "Natrii bromidum",
                role: .active,
                amountValue: 5,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Natrii bromidum",
                refKuoMlPerG: 0.24
            ),
            IngredientDraft(
                displayName: "Aqua purificata",
                role: .solvent,
                amountValue: 150,
                unit: UnitCode(rawValue: "ml"),
                isAd: true,
                refType: "solvent"
            )
        ]

        return RxFixtureScenario(
            id: "ppk_kuo_approx_and_qs",
            title: "PPK KUO mode must include both approximate water and q.s. ad line",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, WaterSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [],
            expectedSectionTitles: ["Розрахунки", "Стабільність"],
            expectedLineFragments: [
                "Aqua purificata ≈",
                "q.s. ad 150 ml"
            ],
            validator: { evaluated in
                var errors: [String] = []
                guard let ppkDocument = evaluated.derived.ppkDocument else {
                    errors.append("missing ppkDocument")
                    return errors
                }
                let mathLines = ppkDocument.backSide
                    .first(where: { $0.title == "Математичне обґрунтування" })?
                    .lines ?? []
                if !mathLines.contains(where: { $0.contains("Aqua purificata ≈") }) {
                    errors.append("back-side math missing approximate water line")
                }
                if !mathLines.contains(where: { $0.lowercased().contains("q.s. ad") }) {
                    errors.append("back-side math missing q.s. ad line")
                }
                return errors
            }
        )
    }

    private static func ppkNoFalseLightSensitiveForBromideScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.signa = "По 1 столовой ложке 3 раза в день"
        d.targetValue = 150
        d.targetUnit = UnitCode(rawValue: "ml")
        d.ingredients = [
            IngredientDraft(
                displayName: "Natrii bromidum",
                role: .active,
                amountValue: 5,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Natrii bromidum",
                refKuoMlPerG: 0.24
            ),
            IngredientDraft(
                displayName: "Aqua purificata",
                role: .solvent,
                amountValue: 150,
                unit: UnitCode(rawValue: "ml"),
                isAd: true,
                refType: "solvent"
            )
        ]

        return RxFixtureScenario(
            id: "ppk_no_false_light_for_bromide",
            title: "NaBr solution should not receive fake light-sensitive or dark-glass claims",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, WaterSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [],
            expectedSectionTitles: ["Стабільність", "Упаковка/Маркування"],
            forbiddenLineFragments: ["світлочутлив", "светочувств"],
            validator: { evaluated in
                var errors: [String] = []
                guard let ppkDocument = evaluated.derived.ppkDocument else {
                    errors.append("missing ppkDocument")
                    return errors
                }
                let stabilityLines = ppkDocument.backSide
                    .first(where: { $0.title == "Стабільність" })?
                    .lines ?? []
                if !stabilityLines.contains(where: { $0.lowercased().contains("стабіль") }) {
                    errors.append("stability block must contain neutral stability wording")
                }
                let packagingLines = ppkDocument.control
                    .first(where: { $0.title == "Оформлення та зберігання" })?
                    .lines ?? []
                let packagingText = packagingLines.joined(separator: "\n").lowercased()
                if packagingText.contains("берегти від світла")
                    || packagingText.contains("темного")
                    || packagingText.contains("оранжевого")
                    || packagingText.contains("захищеному від світла") {
                    errors.append("unexpected storage/light constraints for stable bromide solution")
                }
                return errors
            }
        )
    }

    private static func ppkSectionSeparationScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.signa = "По 1 столовой ложке 3 раза в день"
        d.targetValue = 150
        d.targetUnit = UnitCode(rawValue: "ml")
        d.ingredients = [
            IngredientDraft(
                displayName: "Natrii bromidum",
                role: .active,
                amountValue: 5,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Natrii bromidum",
                refKuoMlPerG: 0.24
            ),
            IngredientDraft(
                displayName: "Aqua purificata",
                role: .solvent,
                amountValue: 150,
                unit: UnitCode(rawValue: "ml"),
                isAd: true,
                refType: "solvent"
            )
        ]

        return RxFixtureScenario(
            id: "ppk_section_separation",
            title: "PPK sections keep math/technology/control lines separated",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, WaterSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [],
            expectedSectionTitles: [
                "Розрахунки",
                "Стабільність",
                "Технологія",
                "Контроль якості"
            ],
            validator: { evaluated in
                var errors: [String] = []
                guard let ppkDocument = evaluated.derived.ppkDocument else {
                    errors.append("missing ppkDocument")
                    return errors
                }
                let back = ppkDocument.backSide
                let face = ppkDocument.faceSide
                let control = ppkDocument.control

                let mathLines = back.first(where: { $0.title == "Математичне обґрунтування" })?.lines ?? []
                let techLines = (
                    face.first(where: { $0.title == "Порядок внесення" })?.lines ?? []
                ) + (
                    face.first(where: { $0.title == "Ключові операції" })?.lines ?? []
                )
                let controlLines = control.flatMap(\.lines)

                if mathLines.contains(where: { line in
                    let lower = line.lowercased()
                    return lower.contains("розчинити")
                        || lower.contains("процід")
                        || lower.contains("нагр")
                        || lower.contains("охолод")
                }) {
                    errors.append("technology operation leaked into math section")
                }

                if techLines.contains(where: { line in
                    let lower = line.lowercased()
                    return lower.contains("на 1 прийом")
                        || lower.contains("на добу")
                }) {
                    errors.append("dose calculation leaked into technology section")
                }

                if controlLines.contains(where: { line in
                    let lower = line.lowercased()
                    return lower.contains("σкуо")
                        || lower.contains("куо:")
                        || lower.contains("з урахуванням куо")
                }) {
                    errors.append("KUO computation leaked into control section")
                }
                return errors
            }
        )
    }

    private static func kuoMissingReferenceInKuoModeScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.signa = "По 1 столовой ложке 3 раза в день"
        d.targetValue = 100
        d.targetUnit = UnitCode(rawValue: "ml")
        d.ingredients = [
            IngredientDraft(
                displayName: "Coffeini-natrii benzoas",
                role: .active,
                amountValue: 2,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Coffeini-natrii benzoas",
                refKuoMlPerG: 0.60
            ),
            IngredientDraft(
                displayName: "Glucosum",
                role: .active,
                amountValue: 3,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Glucosum"
            ),
            IngredientDraft(
                displayName: "Aqua purificata",
                role: .solvent,
                amountValue: 100,
                unit: UnitCode(rawValue: "ml"),
                isAd: true,
                refType: "solvent"
            )
        ]

        return RxFixtureScenario(
            id: "kuo_missing_reference_in_kuo_mode",
            title: "KUO mode must raise blocking issue when at least one solid has no KUO reference",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, WaterSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [],
            expectedSectionTitles: ["Розрахунки", "Стабільність"],
            expectedLineFragments: ["ΣКУО ="],
            validator: { evaluated in
                var errors: [String] = []
                let hasBlockingKuoIssue = evaluated.issues.contains {
                    $0.code == "water.kuo.missing" && $0.severity == .blocking
                }
                if !hasBlockingKuoIssue {
                    errors.append("missing blocking issue water.kuo.missing in KUO mode")
                }
                guard let ppkDocument = evaluated.derived.ppkDocument else {
                    errors.append("missing ppkDocument")
                    return errors
                }
                let warningLines = ppkDocument.control
                    .first(where: { $0.title == "Зауваження" })?
                    .lines ?? []
                if !warningLines.contains(where: { $0.lowercased().contains("бракує куо") }) {
                    errors.append("control warnings do not include KUO-missing message")
                }
                return errors
            }
        )
    }

    private static func ppkNoFalseKuoBlockingWhenKuoSkippedScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.signa = "По 30-40 крапель на півсклянки води для полоскання"
        d.targetValue = 150
        d.targetUnit = UnitCode(rawValue: "ml")
        d.ingredients = [
            IngredientDraft(
                displayName: "Kalii permanganatis",
                role: .active,
                amountValue: 2.5,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: "Kalii permanganatis"
            ),
            IngredientDraft(
                displayName: "Aqua purificata",
                role: .solvent,
                amountValue: 150,
                unit: UnitCode(rawValue: "ml"),
                isAd: true,
                refType: "solvent"
            )
        ]

        return RxFixtureScenario(
            id: "ppk_no_false_kuo_blocking_when_kuo_skipped",
            title: "PPK must not raise KUO-missing blocking when math says KUO is not applied",
            draft: d,
            expectedActivatedBlocks: [BaseTechnologyBlock.blockId, WaterSolutionsBlock.blockId],
            forbiddenActivatedBlocks: [NonAqueousSolutionsBlock.blockId],
            expectedSectionTitles: [
                "Розрахунки",
                "Стабільність",
                "Технологія",
                "Контроль якості"
            ],
            expectedLineFragments: ["КУО не враховується"],
            validator: { evaluated in
                var errors: [String] = []
                let hasFalseBlocking = evaluated.issues.contains {
                    $0.code == "ppk.validation.kou.missing_in_reference"
                }
                if hasFalseBlocking {
                    errors.append("unexpected blocking issue ppk.validation.kou.missing_in_reference when KUO is skipped")
                }
                return errors
            }
        )
    }

    private static func expertiseRinseNoDropsRationaleScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .solutions
        d.liquidTechnologyMode = .waterSolution
        d.signa = "Полоскання"
        d.targetValue = 50
        d.targetUnit = UnitCode(rawValue: "ml")
        d.ingredients = [
            IngredientDraft(
                displayName: "Sol. Acidi borici 2%",
                role: .active,
                amountValue: 50,
                unit: UnitCode(rawValue: "ml"),
                presentationKind: .solution,
                refType: "act",
                refNameLatNom: "Solutio Acidi borici"
            )
        ]

        return RxFixtureScenario(
            id: "expertise_rinse_no_drops_rationale",
            title: "Rinse recipe must not mention drops rationale when there is no drops marker",
            draft: d,
            expectedActivatedBlocks: [],
            forbiddenActivatedBlocks: [],
            expectedSectionTitles: [],
            validator: { evaluated in
                var errors: [String] = []
                guard let expertise = ExtempFormExpertiseAnalyzer.summarize(draft: evaluated.normalizedDraft) else {
                    errors.append("missing expertise summary")
                    return errors
                }
                if expertise.title != "Розчин для полоскання" {
                    errors.append("unexpected expertise title: \(expertise.title)")
                }
                if expertise.rationale.lowercased().contains("крапельне дозування") {
                    errors.append("rationale incorrectly mentions drops dosing")
                }
                return errors
            }
        )
    }

    private static func expertiseDropsAndRinsePriorityScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .auto
        d.liquidTechnologyMode = .waterSolution
        d.signa = "По 10 крапель для полоскання горла"
        d.targetValue = 25
        d.targetUnit = UnitCode(rawValue: "ml")
        d.ingredients = [
            IngredientDraft(
                displayName: "Tinctura Calendulae",
                role: .active,
                amountValue: 25,
                unit: UnitCode(rawValue: "ml"),
                refType: "tincture",
                refNameLatNom: "Tinctura Calendulae"
            )
        ]

        return RxFixtureScenario(
            id: "expertise_drops_and_rinse_priority",
            title: "Rinse route must have higher priority than drops markers",
            draft: d,
            expectedActivatedBlocks: [],
            forbiddenActivatedBlocks: [],
            expectedSectionTitles: [],
            validator: { evaluated in
                var errors: [String] = []
                guard let expertise = ExtempFormExpertiseAnalyzer.summarize(draft: evaluated.normalizedDraft) else {
                    errors.append("missing expertise summary")
                    return errors
                }
                if expertise.title != "Розчин для полоскання" {
                    errors.append("expected rinse expertise, got: \(expertise.title)")
                }
                return errors
            }
        )
    }

    private static func expertiseNoFalseDilutionByWaterWordScenario() -> RxFixtureScenario {
        var d = ExtempRecipeDraft()
        d.formMode = .drops
        d.liquidTechnologyMode = .waterSolution
        d.signa = "По 10 крапель 3 рази на день, запивати водою"
        d.targetValue = 10
        d.targetUnit = UnitCode(rawValue: "ml")
        d.ingredients = [
            IngredientDraft(
                displayName: "Tinctura Valerianae",
                role: .active,
                amountValue: 10,
                unit: UnitCode(rawValue: "ml"),
                refType: "tincture",
                refNameLatNom: "Tinctura Valerianae"
            )
        ]

        return RxFixtureScenario(
            id: "expertise_no_false_dilution_by_water_word",
            title: "Word 'water' in free text must not force dilution marker logic",
            draft: d,
            expectedActivatedBlocks: [],
            forbiddenActivatedBlocks: [],
            expectedSectionTitles: [],
            validator: { evaluated in
                var errors: [String] = []
                let semantics = SignaUsageAnalyzer.analyze(signa: evaluated.normalizedDraft.signa.lowercased())
                if semantics.requiresDilutionBeforeUse {
                    errors.append("requiresDilutionBeforeUse is true for 'запивати водою' text")
                }
                if semantics.dropMeasurementOnly {
                    errors.append("dropMeasurementOnly unexpectedly true")
                }
                guard let expertise = ExtempFormExpertiseAnalyzer.summarize(draft: evaluated.normalizedDraft) else {
                    errors.append("missing expertise summary")
                    return errors
                }
                if expertise.title != "Краплі" {
                    errors.append("expected drops expertise, got: \(expertise.title)")
                }
                return errors
            }
        )
    }

    private static func dailyShadowParityRegressionScenarios() -> [RxFixtureScenario] {
        func baseDraft(signa: String, targetMl: Double) -> ExtempRecipeDraft {
            var d = ExtempRecipeDraft()
            d.formMode = .solutions
            d.liquidTechnologyMode = .waterSolution
            d.targetValue = targetMl
            d.targetUnit = UnitCode(rawValue: "ml")
            d.signa = signa
            return d
        }

        func solid(_ name: String, _ g: Double, ref: String? = nil) -> IngredientDraft {
            IngredientDraft(
                displayName: name,
                role: .active,
                amountValue: g,
                unit: UnitCode(rawValue: "g"),
                refType: "act",
                refNameLatNom: ref ?? name
            )
        }

        func liquid(_ name: String, _ ml: Double, role: IngredientRole = .active, refType: String = "act", ad: Bool = false) -> IngredientDraft {
            IngredientDraft(
                displayName: name,
                role: role,
                amountValue: ml,
                unit: UnitCode(rawValue: "ml"),
                isAd: ad,
                refType: refType,
                refNameLatNom: name
            )
        }

        func scenario(id: String, title: String, draft: ExtempRecipeDraft) -> RxFixtureScenario {
            RxFixtureScenario(
                id: id,
                title: title,
                draft: draft,
                expectedActivatedBlocks: [BaseTechnologyBlock.blockId],
                forbiddenActivatedBlocks: [],
                expectedSectionTitles: ["Технологія"],
                validator: { evaluated in
                    guard SignaUsageAnalyzer.effectiveFormMode(for: evaluated.normalizedDraft) == .solutions else { return [] }
                    guard let shadow = evaluated.derived.solutionEngineShadowReport else {
                        return ["missing shadow report"]
                    }
                    if shadow.mismatchSeverity == .critical {
                        return ["critical shadow mismatch: \(shadow.mismatchReasons.joined(separator: ","))"]
                    }
                    return []
                }
            )
        }

        var cases: [RxFixtureScenario] = []

        do {
            var d = baseDraft(signa: "Полоскание", targetMl: 50)
            d.ingredients = [solid("Acidum boricum", 1.0), liquid("Aqua purificata", 50, role: .solvent, refType: "solvent", ad: true)]
            cases.append(scenario(id: "shadow_boric_2pct_50", title: "Boric acid 2% 50 ml", draft: d))
        }
        do {
            var d = baseDraft(signa: "Полоскание", targetMl: 200)
            d.ingredients = [solid("Acidum boricum", 1.0), liquid("Aqua purificata", 200, role: .solvent, refType: "solvent", ad: true)]
            cases.append(scenario(id: "shadow_boric_05pct_200", title: "Boric acid 0.5% 200 ml", draft: d))
        }
        do {
            var d = baseDraft(signa: "Полоскание", targetMl: 250)
            d.ingredients = [solid("Furacilinum", 0.05), liquid("Aqua purificata", 250, role: .solvent, refType: "solvent", ad: true)]
            cases.append(scenario(id: "shadow_furacilin_250", title: "Furacilin 1:5000 250 ml", draft: d))
        }
        do {
            var d = baseDraft(signa: "Полоскание", targetMl: 200)
            d.ingredients = [solid("Ethacridini lactas", 0.2), liquid("Aqua purificata", 200, role: .solvent, refType: "solvent", ad: true)]
            cases.append(scenario(id: "shadow_ethacridine_200", title: "Ethacridine 1:1000 200 ml", draft: d))
        }
        do {
            var d = baseDraft(signa: "Для промывания мочевого пузыря", targetMl: 300)
            d.ingredients = [solid("Argenti nitras", 1.5), liquid("Aqua purificata", 300, role: .solvent, refType: "solvent", ad: true)]
            cases.append(scenario(id: "shadow_silver_nitrate_05pct_300", title: "Silver nitrate 0.5% 300 ml", draft: d))
        }
        do {
            var d = baseDraft(signa: "Для промывания мочевого пузыря", targetMl: 200)
            d.ingredients = [solid("Argenti nitras", 2.0), liquid("Aqua purificata", 200, role: .solvent, refType: "solvent", ad: true)]
            cases.append(scenario(id: "shadow_silver_nitrate_1pct_200", title: "Silver nitrate 1% 200 ml", draft: d))
        }
        do {
            var d = baseDraft(signa: "По 30-40 капель на половину стакана воды для полоскания", targetMl: 150)
            d.ingredients = [solid("Kalii permanganas", 2.5), liquid("Aqua purificata", 150, role: .solvent, refType: "solvent", ad: true)]
            cases.append(scenario(id: "shadow_permanganate_2_5g_150", title: "Permanganate 2.5 g / 150 ml", draft: d))
        }
        do {
            var d = baseDraft(signa: "Для полоскания", targetMl: 300)
            d.ingredients = [solid("Kalii permanganas", 0.3), liquid("Aqua purificata", 300, role: .solvent, refType: "solvent", ad: true)]
            cases.append(scenario(id: "shadow_permanganate_0_3g_300", title: "Permanganate 0.3 g / 300 ml", draft: d))
        }
        do {
            var d = baseDraft(signa: "Для смазывания зева", targetMl: 10)
            d.ingredients = [solid("Iodum", 0.1), solid("Kalii iodidum", 0.2), liquid("Aqua purificata", 10, role: .solvent, refType: "solvent", ad: true)]
            cases.append(scenario(id: "shadow_lugol_external", title: "Lugol external 10 ml", draft: d))
        }
        do {
            var d = baseDraft(signa: "По 10 капель 2 раза в день с молоком", targetMl: 10)
            d.ingredients = [solid("Iodum", 0.1), solid("Kalii iodidum", 0.2), liquid("Aqua purificata", 10, role: .solvent, refType: "solvent", ad: true)]
            cases.append(scenario(id: "shadow_lugol_internal", title: "Lugol internal drops", draft: d))
        }
        do {
            var d = baseDraft(signa: "По 1 столовой ложке 3 раза в день", targetMl: 200)
            d.useBuretteSystem = true
            d.ingredients = [solid("Coffeini-natrii benzoas", 1.0), solid("Natrii bromidum", 2.0), liquid("Aqua purificata", 200, role: .solvent, refType: "solvent", ad: true)]
            cases.append(scenario(id: "shadow_pavlov_mix", title: "Pavlov mixture", draft: d))
        }
        do {
            var d = baseDraft(signa: "По 1 столовой ложке 3 раза в день", targetMl: 150)
            d.useBuretteSystem = true
            d.ingredients = [solid("Kalii iodidum", 3.0), solid("Natrii bromidum", 2.0), liquid("Aqua purificata", 150, role: .solvent, refType: "solvent", ad: true)]
            cases.append(scenario(id: "shadow_ki_nb_mix", title: "KI + NaBr mixture", draft: d))
        }
        do {
            var d = baseDraft(signa: "По 1 столовой ложке 3 раза в день", targetMl: 200)
            d.useBuretteSystem = true
            d.ingredients = [solid("Natrii hydrocarbonas", 3.0), solid("Natrii bromidum", 3.0), liquid("Aqua purificata", 200, role: .solvent, refType: "solvent", ad: true)]
            cases.append(scenario(id: "shadow_hco3_bromide_mix", title: "NaHCO3 + NaBr", draft: d))
        }
        do {
            var d = baseDraft(signa: "По 1 десертной ложке 3 раза в день ребенку 10 лет", targetMl: 100)
            d.ingredients = [solid("Kalii iodidum", 1.0), solid("Natrii salicylas", 2.0), liquid("Aqua purificata", 100, role: .solvent, refType: "solvent", ad: true)]
            cases.append(scenario(id: "shadow_ki_salicylate_child", title: "KI + sodium salicylate child", draft: d))
        }
        do {
            var d = baseDraft(signa: "По 1 столовой ложке 3 раза в день", targetMl: 200)
            d.ingredients = [solid("Calcii chloridum", 5.0), solid("Natrii bromidum", 3.0), liquid("Aqua purificata", 200, role: .solvent, refType: "solvent", ad: true)]
            cases.append(scenario(id: "shadow_calcium_bromide_mix", title: "Calcium chloride + bromide", draft: d))
        }
        do {
            var d = baseDraft(signa: "По 1 чайной ложке 3 раза в день ребенку 5 лет", targetMl: 100)
            d.ingredients = [solid("Kalii iodidum", 2.0), solid("Natrii salicylas", 1.0), liquid("Sirupus simplex", 5.0), liquid("Aqua purificata", 100, role: .solvent, refType: "solvent", ad: true)]
            cases.append(scenario(id: "shadow_ki_salicylate_syrup", title: "KI + salicylate + syrup", draft: d))
        }
        do {
            var d = baseDraft(signa: "По 1 десертной ложке 3 раза в день ребенку 14 лет", targetMl: 150)
            d.useBuretteSystem = true
            d.ingredients = [solid("Coffeini-natrii benzoas", 0.5), solid("Natrii bromidum", 2.0), liquid("Tinctura Valerianae", 3.0), liquid("Aqua purificata", 150, role: .solvent, refType: "solvent", ad: true)]
            cases.append(scenario(id: "shadow_pavlov_valerian", title: "Caffeine-benzoate + bromide + valerian", draft: d))
        }
        do {
            var d = baseDraft(signa: "По 1 десертной ложке 3 раза в день ребенку 6 лет", targetMl: 100)
            d.ingredients = [solid("Natrii hydrocarbonas", 1.0), solid("Hexamethylentetraminum", 1.0), liquid("Tinctura Leonuri", 2.0), liquid("Aqua purificata", 100, role: .solvent, refType: "solvent", ad: true)]
            cases.append(scenario(id: "shadow_hco3_hexamine_motherwort", title: "NaHCO3 + hexamine + motherwort", draft: d))
        }
        do {
            var d = baseDraft(signa: "По 1 чайной ложке 3 раза в день ребенку 5 лет", targetMl: 100)
            d.ingredients = [solid("Coffeini-natrii benzoas", 0.3), solid("Kalii iodidum", 2.0), liquid("Tinctura Valerianae", 3.0), liquid("Aqua purificata", 100, role: .solvent, refType: "solvent", ad: true)]
            cases.append(scenario(id: "shadow_caffeine_ki_valerian", title: "Caffeine-benzoate + KI + valerian", draft: d))
        }
        do {
            var d = baseDraft(signa: "По 1 столовой ложке 3 раза в день", targetMl: 200)
            d.ingredients = [solid("Natrii salicylas", 3.0), solid("Natrii benzoas", 3.0), liquid("Sirupus simplex", 5.0), liquid("Aqua purificata", 200, role: .solvent, refType: "solvent", ad: true)]
            cases.append(scenario(id: "shadow_salicylate_benzoate_syrup", title: "Na salicylate + Na benzoate + syrup", draft: d))
        }

        return cases
    }
}
