import Foundation

struct OintmentsBlock: RxProcessingBlock {
    static let blockId = "ointments"
    let id = blockId

    private enum Limits {
        static let insolublePowderFracWarn: Double = 0.25
    }

    func apply(context: inout RxPipelineContext) {
        context.routeBranch = "ointments"

        let draft = context.draft
        let signa = draft.signa.lowercased()
        let result = OintmentsCalculator.calculate(draft: draft)
        let hasSulfurIngredient = draft.ingredients.contains(where: isSulfurIngredient)

        if result.hadMlApproximation {
            context.addIssue(
                code: "ointment.ml.as.g",
                severity: .warning,
                message: "Є компоненти у ml — масу оцінено як 1 ml ≈ 1 g (наближено)"
            )
        }

        context.calculations["ointment_total_mass_g"] = format(result.totalMassG)
        context.calculations["ointment_vaselin_g"] = format(result.vaselinG)
        context.calculations["ointment_lanolin_anhydricum_g"] = format(result.lanolinAnhydG)
        context.calculations["ointment_lanolin_hydricum_g"] = format(result.lanolinHydrG)
        context.calculations["ointment_base_class"] = result.baseClass.rawValue
        context.calculations["ointment_water_need_g"] = format(result.waterNeededG)
        context.calculations["ointment_water_capacity_g"] = format(result.baseWaterCapacityG)

        if result.isOphthalmic {
            context.addIssue(
                code: "ointment.ophthalmic.aseptic",
                severity: .warning,
                message: "Очна мазь: асептика, стерильна тара, дуже тонке подрібнення (ризик абразивності)"
            )
        }

        if result.suggestedExtraLanolinAnhydG > 0 {
            let deficit = result.waterNeededG - result.baseWaterCapacityG
            context.addIssue(
                code: "ointment.water.capacity",
                severity: .warning,
                message: "Основа не утримує водну фазу: дефіцит \(format(deficit)) g. Рекомендовано додати Lanolinum anhydricum ≈ \(format(result.suggestedExtraLanolinAnhydG)) g"
            )
            context.calculations["ointment_suggest_add_lanolin_anhyd_g"] = format(result.suggestedExtraLanolinAnhydG)
        }

        if result.waterPhasePresent && !result.isOphthalmic {
            context.addIssue(
                code: "ointment.preservative.consider",
                severity: .info,
                message: "Є водна фаза — врахувати мікробну стабільність/консервант і коротший термін придатності"
            )
        }

        if result.waterPhasePresent && result.isOphthalmic {
            context.addIssue(
                code: "ointment.ophthalmic.waterphase",
                severity: .warning,
                message: "Очна мазь + водна фаза — високі вимоги до мікробної чистоти/стабільності; перевірити методику/консервант"
            )
        }

        if result.eutecticCandidates.count >= 2 {
            context.addIssue(
                code: "ointment.eutectic",
                severity: .info,
                message: "Потенційна евтектика: попереднє розтирання до розрідження; уникати перегріву/випаровування"
            )
        }

        if result.isOphthalmic, !result.groups.insoluble.isEmpty {
            context.addIssue(
                code: "ointment.ophthalmic.insoluble",
                severity: .warning,
                message: "Очна мазь + нерозчинні порошки: потрібне надтонке подрібнення/просіювання, ризик подразнення"
            )
        }

        if result.totalMassG > 0, result.insolubleMassG / result.totalMassG > Limits.insolublePowderFracWarn {
            context.addIssue(
                code: "ointment.susp.high",
                severity: .warning,
                message: "Нерозчинні речовини >25% — мазь може бути грубою/піщаною; потрібна пульпа + контроль дисперсності"
            )
        }
        if hasSulfurIngredient {
            context.addIssue(
                code: "ointment.sulfur.trituration",
                severity: .warning,
                message: "Сірку слід ретельно розтирати у злегка підігрітій ступці з поступовим введенням частини основи."
            )
        }

        var pasteLines: [String] = []
        for rec in result.pulpRecommendations {
            if let kv = rec.kvGPer100G, let wettingMassG = rec.wettingMassG {
                pasteLines.append(
                    "Пульпа для \(rec.ingredientName): \(format(rec.ingredientMassG)) g × Kv \(format(kv))/100 → \(format(wettingMassG)) g змочувача"
                )
            } else {
                pasteLines.append(
                    "Пульпа для \(rec.ingredientName): Kv невідомий → взяти приблизно 1:1 (≈ \(format(rec.ingredientMassG)) g основи/олії)"
                )
                context.addIssue(
                    code: "ointment.kv.missing",
                    severity: .info,
                    message: "Kv відсутній для \(rec.ingredientName) — пульпа по 1:1 приблизно"
                )
            }
        }

        if result.hasAcid && result.hasCarbonate {
            context.addIssue(
                code: "ointment.incompat.acid.carbonate",
                severity: .warning,
                message: "Ймовірна несумісність: кислота + карбонат/гідрокарбонат (виділення CO₂/зміна pH)"
            )
        }

        if let targetMass = result.targetMassG {
            let delta = result.targetMassDeltaG ?? 0
            if delta > max(0.5, targetMass * 0.02) {
                context.addIssue(
                    code: "ointment.mass.delta",
                    severity: .warning,
                    message: "Сумарна маса компонентів відрізняється від target"
                )
            }
            context.calculations["ointment_target_mass_g"] = format(targetMass)
        }

        var calcLines: [String] = [
            "Сумарна маса (оцінка): \(format(result.totalMassG)) g",
            "Клас основи: \(result.baseClass.rawValue)",
            "Основа: Vaselinum \(format(result.vaselinG)) g; Paraffinum \(format(result.paraffinG)) g; Oleum \(format(result.oilsG)) g; Lanolinum anhyd \(format(result.lanolinAnhydG)) g; Lanolinum hydr \(format(result.lanolinHydrG)) g",
            "Водна фаза (по Kv): \(format(result.waterNeededG)) g",
            "Водоємність основи (оцінка): \(format(result.baseWaterCapacityG)) g"
        ]

        if result.suggestedExtraLanolinAnhydG > 0 {
            calcLines.append(
                "Рекомендація: додати Lanolinum anhydricum ≈ \(format(result.suggestedExtraLanolinAnhydG)) g (для утримання водної фази)"
            )
        }

        if !pasteLines.isEmpty {
            calcLines.append("— Пульпа (змочування нерозчинних) —")
            calcLines.append(contentsOf: pasteLines)
        }

        if !result.groups.waterSoluble.isEmpty {
            calcLines.append("Водо-розчинні: " + result.groups.waterSoluble.map(\.displayName).sorted().joined(separator: ", "))
        }
        if !result.groups.oilSoluble.isEmpty {
            calcLines.append("Жиро-розчинні: " + result.groups.oilSoluble.map(\.displayName).sorted().joined(separator: ", "))
        }
        if !result.groups.ethanolSoluble.isEmpty {
            calcLines.append("Спирто-розчинні: " + result.groups.ethanolSoluble.map(\.displayName).sorted().joined(separator: ", "))
        }
        if !result.groups.insoluble.isEmpty {
            calcLines.append("Нерозчинні (суспензія): " + result.groups.insoluble.map(\.displayName).sorted().joined(separator: ", "))
        }
        if !result.groups.mixed.isEmpty {
            calcLines.append("Змішана розчинність: " + result.groups.mixed.map(\.displayName).sorted().joined(separator: ", "))
        }
        if !result.groups.unknown.isEmpty {
            calcLines.append("Розчинність невідома: " + result.groups.unknown.map(\.displayName).sorted().joined(separator: ", "))
        }

        context.appendSection(title: "Розрахунки", lines: calcLines)

        context.addStep(
            TechStep(
                kind: .trituration,
                title: "Подрібнення/розтирання твердих речовин до тонкодисперсного стану",
                isCritical: result.isOphthalmic
            )
        )
        context.addStep(TechStep(kind: .mixing, title: "Введення речовин в основу до однорідності", isCritical: true))
        context.addStep(TechStep(kind: .packaging, title: "Фасування та маркування"))

        var techLines: [String] = []
        var step = 1

        techLines.append("\(step). Підготувати основу (\(result.baseClass.rawValue))")
        step += 1

        if result.hasVolatiles || result.eutecticCandidates.count >= 2 {
            techLines.append("\(step). Уникати перегріву (леткі/евтектичні компоненти)")
            step += 1
        } else {
            techLines.append("\(step). За потреби основу можна злегка розм’якшити (без перегріву)")
            step += 1
        }

        if !result.groups.oilSoluble.isEmpty {
            techLines.append("\(step). Жиро-розчинні речовини розчинити в розплавленій частині основи у фарфоровій чашці при обережному нагріванні на водяній бані")
            step += 1
        }

        if !result.groups.waterSoluble.isEmpty {
            if result.baseClass == .hydrophobic {
                techLines.append("\(step). Водо-розчинні речовини: перейти на абсорбційну/емульсійну основу (Lanolinum anhydricum/емульгатор)")
                step += 1
                context.addIssue(
                    code: "ointment.water.on.hydrophobic",
                    severity: .warning,
                    message: "Є водорозчинні речовини, але основа гідрофобна — потрібен ланолін/емульгатор"
                )
            } else {
                techLines.append("\(step). Водо-розчинні речовини розчинити у мінімальній кількості води, емульгувати з Lanolinum anhydricum/основою")
                step += 1
            }
        }

        if !result.groups.ethanolSoluble.isEmpty {
            techLines.append("\(step). Спирто-розчинні: розчинити в етанолі; вводити в кінці при охолодженні (зменшити випаровування)")
            step += 1
        }

        if !result.groups.insoluble.isEmpty {
            if hasSulfurIngredient {
                techLines.append("\(step). Sulfur praecipitatum: обережно, але ретельно розтерти у злегка підігрітій ступці; додати частину основи та диспергувати до однорідної пульпи")
            } else {
                techLines.append("\(step). Нерозчинні: розтерти, приготувати пульпу (змочування) та вводити геометрично")
            }
            step += 1
        }

        if result.eutecticCandidates.count >= 2 {
            let names = result.eutecticCandidates.map(\.displayName).sorted()
            techLines.append("\(step). Евтектика: попередньо розтерти \(names.joined(separator: " + ")) до розрідження, потім вводити в основу")
            step += 1
        }

        techLines.append("\(step). Довести до однорідності (ретельне розтирання/змішування)")
        step += 1

        let packaging = OintmentsCalculator.suggestPackaging(
            isOphthalmic: result.isOphthalmic,
            signa: signa,
            baseClass: result.baseClass
        )

        techLines.append("\(step). Фасувати у \(packaging), маркувати")
        context.appendSection(title: "Технологія", lines: techLines)

        var labelLines: [String] = []
        var storageLines: [String] = []

        if result.isOphthalmic {
            labelLines.append("Маркування: «Очна мазь. Стерильно.»")
            labelLines.append("Попередження: «Не торкатися наконечником ока/повік.»")
            storageLines.append("Зберігати у прохолодному місці, захищати від світла")
            storageLines.append("Термін придатності: короткий (за методикою/правилами)")
        } else {
            labelLines.append(signa.contains("внутр") ? "Маркування: «Внутрішньо»" : "Маркування: «Зовнішньо»")
            storageLines.append("Зберігати у прохолодному місці, захищати від світла")
            if result.waterPhasePresent {
                storageLines.append("Термін придатності: коротший через водну фазу")
            } else {
                storageLines.append("Термін придатності: стандартний (залежить від компонентів)")
            }
        }

        context.appendSection(title: "Оформлення", lines: ["Тара: \(packaging)"] + labelLines)
        context.appendSection(title: "Зберігання", lines: storageLines)
    }

    private func isSulfurIngredient(_ ingredient: IngredientDraft) -> Bool {
        let hay = [
            ingredient.displayName,
            ingredient.refNameLatNom ?? "",
            ingredient.refInnKey ?? ""
        ]
        .joined(separator: " ")
        .lowercased()
        return hay.contains("sulfur")
            || hay.contains("sulphur")
            || hay.contains("sulfuris")
            || hay.contains("сірк")
            || hay.contains("сера")
    }

    private func format(_ v: Double) -> String {
        if v == floor(v) { return String(Int(v)) }
        return String(format: "%.3f", v)
    }
}
