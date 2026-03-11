import Foundation

struct NonAqueousSolutionsBlock: RxProcessingBlock {
    static let blockId = "non_aqueous_solutions"
    let id = blockId

    private struct IodideComplexPreparation {
        let iodineMassG: Double
        let iodideMassG: Double
        let waterMl: Double
        let waterMassG: Double
        let hasExplicitWater: Bool
        let iodineNames: [String]
        let iodideNames: [String]
    }

    func apply(context: inout RxPipelineContext) {
        guard let solvent = NonAqueousSolventCatalog.primarySolvent(in: context.draft) else {
            context.addIssue(
                code: "nonaqueous.solvent.missing",
                severity: .warning,
                message: "Неводний розчинник не ідентифіковано; блок не зміг побудувати технологію"
            )
            return
        }

        context.routeBranch = "non_aqueous_solution"

        let solventType = solvent.type
        let solventIngredient = solvent.ingredient
        let officinalAlcohol = solventType == .ethanol
            ? NonAqueousSolventCatalog.officinalAlcoholSolution(for: solventIngredient)
            : nil
        let requestedSolutionStrength: Int? = {
            guard solventType == .ethanol,
                  let solventIngredient,
                  let percent = context.draft.solutionDisplayPercent(for: solventIngredient)
            else { return nil }
            let raw = Int(percent.rounded())
            switch raw {
            case 66...74:
                return 70
            case 86...94:
                return 90
            case 95...99:
                return 96
            case 1...100:
                return raw
            default:
                return nil
            }
        }()
        let ethanolStrength = solventType == .ethanol
            ? (officinalAlcohol?.ethanolStrength ?? requestedSolutionStrength ?? NonAqueousSolventCatalog.requestedEthanolStrength(from: solventIngredient))
            : nil
        let solventProfile = NonAqueousSolventCatalog.resolvedProfile(
            for: solventIngredient,
            type: solventType,
            ethanolStrength: ethanolStrength
        )
        let calculationMethod: NonAqueousCalculationMethod = solventType == .ethanol ? .massVolume : .mass
        let massUsesFinalTarget = calculationMethod == .mass
            ? usesMassFinalTarget(draft: context.draft, solventIngredient: solventIngredient)
            : false

        let fixedComponents = context.draft.ingredients.filter { ingredient in
            !ingredient.isAd && !ingredient.isQS && ingredient.id != solventIngredient?.id
        }
        let targetMl = resolvedLiquidTargetMl(in: context.draft, solventIngredient: solventIngredient)
        let ethanolUsesFinalVolume = solventType == .ethanol
            ? ((officinalAlcohol != nil && fixedComponents.isEmpty) || ethanolUsesFinalVolume(draft: context.draft, solventIngredient: solventIngredient))
            : false
        let signaSemantics = SignaUsageAnalyzer.analyze(signa: context.draft.signa)
        let ethanolKuoIgnored = solventType == .ethanol
            ? canIgnoreAlcoholKuo(
                fixedComponents: fixedComponents,
                solventVolumeMl: targetMl,
                isExternalRoute: signaSemantics.isExternalRoute
            )
            : false
        let hasIodine = containsIodine(fixedComponents)
        let hasIodide = containsIodide(fixedComponents)
        let usesIodideComplex = solventType != .ethanol && hasIodine && hasIodide
        let hasUncomplexedIodine = solventType != .ethanol && hasIodine && !hasIodide
        let iodideComplexPrep = iodideComplexPreparation(
            fixedComponents: fixedComponents,
            solventType: solventType,
            usesIodideComplex: usesIodideComplex
        )
        let hasIodideComplexInGlycerin = solventType == .glycerin && iodideComplexPrep != nil
        let glycerinDeryagin = glycerinDeryaginGroups(ingredients: fixedComponents)
        let hasVolatileActives = containsVolatileActives(fixedComponents)
        let solventTechnologyRules = solventIngredient?.propertyOverride?.technologyRules ?? []
        let solventDoseByMass = solventTechnologyRules.contains(.doseByMass)
        let solventWarmOilBath = solventTechnologyRules.contains(.fattyOilWarmWaterBath40to50)
        let solventNeedsSterileDryHeat = solventTechnologyRules.contains(.fattyOilDryHeatSterilization)
        let solventLipophilicDissolution = solventTechnologyRules.contains(.fattyOilLipophilicDissolution)
        let solventNeedsEmulsionForWaterSolubles = solventTechnologyRules.contains(.fattyOilWaterSolublesRequireEmulsion)
        let solventRancidityRisk = solventTechnologyRules.contains(.rancidityRisk)
        let hasPhenolFamilyActives = fixedComponents.contains(where: isPhenolFamily)
        let hasPhenolInGlycerin = solventType == .glycerin && hasPhenolFamilyActives
        let tweenSpanComponents = fixedComponents.filter(isTweenOrSpanIngredient)
        let tweenSpanConflicts = fixedComponents.filter { ingredient in
            !tweenSpanComponents.contains(where: { $0.id == ingredient.id })
                && (isSalicylateIngredient(ingredient)
                    || isPhenolFamily(ingredient)
                    || isParaHydroxyBenzoicDerivativeIngredient(ingredient))
        }
        let hasTweenSpanConflict = !tweenSpanComponents.isEmpty && !tweenSpanConflicts.isEmpty
        let hasLightSensitiveActives = fixedComponents.contains(where: { $0.isReferenceLightSensitive })

        var calculationLines: [String] = [
            "Метод: \(calculationMethod.title)",
            "Розчинник: \(solventProfile.title)"
        ]
        var technologyLines: [String] = []
        var qualityLines: [String] = []
        var rationaleLines: [String] = [
            "Неводний розчин: solvent != water, тому використовується окрема технологічна гілка."
        ]

        let insolubleResidue = fixedComponents.contains { hasPotentialInsolubleResidue($0, solventType: solventType) }
        let needsHeating = requiresGentleHeating(solventType: solventType, ingredients: fixedComponents)
        var ethanolPreparation: EthanolDilutionResult?

        switch calculationMethod {
        case .massVolume:
            ethanolPreparation = buildEthanolSection(
                context: &context,
                solventIngredient: solventIngredient,
                fixedComponents: fixedComponents,
                targetStrength: ethanolStrength ?? 90,
                solventVolumeMl: targetMl,
                usesFinalVolume: ethanolUsesFinalVolume,
                canIgnoreKuo: ethanolKuoIgnored,
                profile: solventProfile,
                officinalAlcohol: officinalAlcohol,
                calculationLines: &calculationLines,
                rationaleLines: &rationaleLines
            )

        case .mass:
            buildMassSection(
                context: &context,
                solventIngredient: solventIngredient,
                fixedComponents: fixedComponents,
                solventType: solventType,
                profile: solventProfile,
                usesFinalMassTarget: massUsesFinalTarget,
                iodideComplexPrep: iodideComplexPrep,
                hasPhenolInGlycerin: hasPhenolInGlycerin,
                calculationLines: &calculationLines,
                rationaleLines: &rationaleLines
            )
        }

        if solventDoseByMass {
            rationaleLines.append("Oleum Helianthi у технології дозують за масою; об'ємні призначення перераховують у грами через густину (орієнтир 0.92 g/ml).")
            if let solventIngredient,
               solventIngredient.unit.rawValue == "ml",
               solventIngredient.amountValue > 0
            {
                let density = solventIngredient.refDensity ?? 0.92
                let convertedMass = solventIngredient.amountValue * density
                calculationLines.append("Oleum Helianthi (перерахунок): \(format(solventIngredient.amountValue)) ml * \(format(density)) g/ml = \(format(convertedMass)) g")
            }
        }

        if solventType == .glycerin {
            technologyLines.append("Гліцерин відважувати безпосередньо у сухий тарований флакон темного скла; не відмірювати через мірний циліндр (втрати через в'язкість).")
            rationaleLines.append("Для Glycerinum застосовують масовий метод і тарування флакону, щоб уникнути похибки від залишку на стінках мірного посуду.")
            if fixedComponents.contains(where: PurifiedWaterHeuristics.isPurifiedWater) {
                rationaleLines.append("Тригер Solvent Mixture: у присутності Aqua purificata + Glycerinum основним компонентом вважається гліцерин, тому метод залишається масовим.")
            }

            if !hasIodideComplexInGlycerin {
                if !glycerinDeryagin.easy.isEmpty {
                    let names = glycerinDeryagin.easy.map(componentDisplayName).joined(separator: ", ")
                    technologyLines.append("Легкорозчинні у Glycerinum компоненти (\(names)) відважувати безпосередньо у флакон з гліцерином.")
                }
                if !glycerinDeryagin.hard.isEmpty {
                    let names = glycerinDeryagin.hard.map(componentDisplayName).joined(separator: ", ")
                    technologyLines.append("Труднорозчинні/крупнокристалічні компоненти (\(names)) попередньо розтерти у ступці з частиною гліцерину (орієнтовно 1/2 від маси речовини), потім перенести у флакон і змити залишком гліцерину.")
                }
            }
        }

        if hasPhenolFamilyActives {
            let warning = "ОБЕРЕЖНО! ФЕНОЛ ВИКЛИКАЄ ХІМІЧНІ ОПІКИ. ПРАЦЮВАТИ СТРОГО В РУКАВИЧКАХ У ВИТЯЖНІЙ ШАФІ."
            technologyLines.insert(warning, at: 0)
            context.addIssue(
                code: "nonaqueous.phenol.burnRisk",
                severity: .warning,
                message: warning
            )
            if hasPhenolInGlycerin {
                technologyLines.append("Порядок внесення для Phenolum purum у Glycerinum: 1) внести частину гліцерину у тарований флакон, 2) окремо відважити фенол і внести у флакон, 3) додати решту гліцерину до кінцевої маси.")
                rationaleLines.append("Для фенолу у гліцерині обов'язковий контрольований підігрів на водяній бані 40-50°C.")
            }
        }

        if solventType == .ether {
            context.addIssue(
                code: "nonaqueous.ether.fire",
                severity: .warning,
                message: "Ефірний розчин: нагрів заборонений, працювати далеко від джерел вогню"
            )
            rationaleLines.append("Ефір леткий і вогненебезпечний: нагрів не допускається.")
        }

        if solventType == .chloroform {
            context.addIssue(
                code: "nonaqueous.chloroform.safety",
                severity: .warning,
                message: "Хлороформ: нагрівання лише за потреби, не вище 60°C"
            )
            rationaleLines.append("Хлороформ допускає лише обережний нагрів до 60°C.")
            if fixedComponents.contains(where: isParaffinIngredient) {
                context.addIssue(
                    code: "nonaqueous.chloroform.paraffin.heating",
                    severity: .warning,
                    message: "Під час розчинення парафіну в хлороформі нагрівати дуже обережно, флакон тримати неповністю закритим."
                )
                technologyLines.append("Для системи Chloroformium + Paraffinum: нагрівати дуже обережно, неповністю прикривши флакон, щоб уникнути надлишкового тиску.")
                rationaleLines.append("Підігрів хлороформу з парафіном проводять у частково прикритій тарі для профілактики розриву флакону.")
            }
        }

        if solventType == .ethanol, containsEthanolIncompatibleOxidizer(fixedComponents) {
            context.addIssue(
                code: "nonaqueous.ethanol.oxidizer",
                severity: .blocking,
                message: "Етанол несумісний із сильними окисниками у даній композиції"
            )
            rationaleLines.append("Для етанолу виявлено сильний окисник: потрібна перевірка сумісності.")
        }

        if hasTweenSpanConflict {
            let surfactantNames = tweenSpanComponents.map(componentDisplayName).joined(separator: ", ")
            let conflictNames = tweenSpanConflicts.map(componentDisplayName).joined(separator: ", ")
            let msg = "\(surfactantNames) несумісні із саліцилатами/фенолами/похідними параоксибензойної кислоти; конфлікт із: \(conflictNames)"
            context.addIssue(
                code: "nonaqueous.tweenspan.incompatibility",
                severity: .blocking,
                message: msg
            )
            technologyLines.append("Комбінацію \(surfactantNames) з \(conflictNames) не використовувати без зміни складу або валідації сумісності.")
            rationaleLines.append("Для твінів/спенів діє пряме обмеження сумісності з саліцилатами, фенолами та парабенами.")
        }

        if hasUncomplexedIodine {
            context.addIssue(
                code: "nonaqueous.iodine.iodide.required",
                severity: .blocking,
                message: "Iodum слід попередньо розчиняти у концентрованому розчині йодиду калію або натрію"
            )
            rationaleLines.append("Йод у неводних системах потребує попереднього розчинення через KI/NaI.")
        }

        if usesIodideComplex {
            if let iodideComplexPrep {
                let iodideNames = iodideComplexPrep.iodideNames.isEmpty ? "Kalii/Natrii iodidum" : iodideComplexPrep.iodideNames.joined(separator: ", ")
                let iodineNames = iodideComplexPrep.iodineNames.isEmpty ? "Iodum" : iodideComplexPrep.iodineNames.joined(separator: ", ")
                if solventType == .glycerin {
                    if iodideComplexPrep.hasExplicitWater {
                        if iodideComplexPrep.waterMl > 0 {
                            technologyLines.append("\(iodideNames) розчинити у наявній Aqua purificata з рецепта та додати ще \(format(iodideComplexPrep.waterMl)) ml води (мінімум 1:1.5 до маси йодиду), потім у цьому концентраті розчинити \(iodineNames).")
                        } else {
                            technologyLines.append("\(iodideNames) розчинити у відміряній Aqua purificata з рецепта, далі в отриманому розчині розчинити \(iodineNames) до утворення комплексу (I3-).")
                        }
                    } else {
                        technologyLines.append("\(iodideNames) попередньо розчинити в Aqua purificata \(format(iodideComplexPrep.waterMl)) ml (мінімум 1:1.5 до маси йодиду), потім у цьому концентраті розчинити \(iodineNames) до утворення комплексу (I3-).")
                    }
                    technologyLines.append("До отриманого концентрату додати Glycerinum та довести до кінцевої маси за рецептом.")
                    rationaleLines.append("Для розчину Люголя в гліцерині застосовується окрема схема: KI -> вода -> Iodum -> Glycerinum до маси.")
                } else {
                    if iodideComplexPrep.hasExplicitWater {
                        if iodideComplexPrep.waterMl > 0 {
                            technologyLines.append("\(iodideNames) розчинити у наявній Aqua purificata з рецепта та додати ще \(format(iodideComplexPrep.waterMl)) ml, потім у цьому концентраті розчинити \(iodineNames) до утворення комплексу (I3-).")
                        } else {
                            technologyLines.append("\(iodideNames) попередньо розчинити у відміряній Aqua purificata з рецепта, потім у цьому концентраті розчинити \(iodineNames) до утворення комплексу (I3-).")
                        }
                    } else {
                        technologyLines.append("\(iodideNames) попередньо розчинити в Aqua purificata \(format(iodideComplexPrep.waterMl)) ml, потім у цьому концентраті розчинити \(iodineNames) до утворення комплексу (I3-).")
                    }
                    rationaleLines.append("Для Iodum у в'язкому неводному середовищі потрібне попереднє комплексоутворення з йодидом у мінімумі води; це пришвидшує та стабілізує розчинення.")
                }
            } else {
                technologyLines.append("Iodum попередньо розчинити у концентрованому розчині Kalii/Natrii iodidum у мінімумі води або відповідного співрозчинника.")
                rationaleLines.append("Для йоду використовується попереднє комплексоутворення з йодидом, а вже потім вводиться основний неводний розчинник.")
            }
            technologyLines.append("Працювати зі скляним/порцеляновим інвентарем; металеві шпателі не використовувати.")
            technologyLines.append("Йод забарвлює пластмасу та гуму; використовувати скляні палички та скляний флакон.")
            context.addIssue(
                code: "nonaqueous.iodine.metalTools",
                severity: .warning,
                message: "Йодна система: не використовувати металеві інструменти; працювати склом/порцеляною."
            )
        }

        if solventType == .glycerin, containsGlycerinPhShiftComponent(fixedComponents) {
            context.addIssue(
                code: "nonaqueous.glycerin.tetraborate.ph",
                severity: .warning,
                message: "Natrii tetraboras у гліцерині може утворювати гліцероборну кислоту; врахуйте можливий зсув pH."
            )
            technologyLines.append("Для Natrii tetraboras у Glycerinum врахувати утворення гліцероборної кислоти та можливу зміну pH.")
            rationaleLines.append("Натрію тетраборат у гліцерині утворює гліцероборну кислоту, тому pH системи може змінюватися.")
            rationaleLines.append("Утворення гліцероборної кислоти додатково прискорює процес розчинення при помірному нагріванні.")
        }

        if solventType == .fattyOil, solventNeedsEmulsionForWaterSolubles {
            let waterSolubleNames = waterSolubleInOilySolventNames(fixedComponents)
            if !waterSolubleNames.isEmpty {
                let msg = "Водорозчинні компоненти (\(waterSolubleNames.joined(separator: ", "))) не вводять безпосередньо в Oleum Helianthi; потрібна емульсійна технологія або інший розчинник."
                context.addIssue(
                    code: "nonaqueous.oleumHelianthi.waterSoluble",
                    severity: .blocking,
                    message: msg
                )
                technologyLines.append("Водорозчинні речовини в Oleum Helianthi безпосередньо не вводити; за потреби застосувати емульсійну схему.")
                rationaleLines.append("Для соняшникової олії пряме введення водорозчинних речовин технологічно некоректне без емульгатора.")
            }
        }

        if solventType == .fattyOil, solventLipophilicDissolution {
            let lipophilicNames = lipophilicOilSoluteNames(fixedComponents)
            if !lipophilicNames.isEmpty {
                technologyLines.append("Жиророзчинні компоненти (\(lipophilicNames.joined(separator: ", "))) розчиняти у попередньо підігрітому Oleum Helianthi.")
                rationaleLines.append("Камфора, ментол, фенол і тимол краще переходять у розчин у теплому жирному маслі.")
            }
        }
        if solventType == .fattyOil,
           let solventIngredient,
           isSunflowerOil(solventIngredient),
           fixedComponents.contains(where: isMentholIngredient) {
            technologyLines.append("Ментол у соняшниковій олії: у сухий флакон темного скла спочатку внести ментол, тарувати, далі відважити олію та розчинити (допускається тепла водяна баня 40-50°C).")
            rationaleLines.append("Для Mentholum + Oleum Helianthi рекомендований порядок «речовина -> тарування -> олія», що знижує втрати леткого компонента.")
        }
        if solventType == .fattyOil,
           let solventIngredient,
           isCastorOil(solventIngredient),
           fixedComponents.contains(where: isCamphorIngredient) {
            technologyLines.append("Camphora в олії рициновій: розчиняти у фарфоровій чашці при обережному нагріванні на водяній бані до 40°C.")
            rationaleLines.append("Для Camphora + Oleum Ricini застосовують м'який нагрів до 40°C для прискорення розчинення без перегріву.")
        }

        if solventType == .fattyOil, hasPhenolFamilyActives {
            technologyLines.append("Phenolum/Acidum carbolicum у жирних оліях має добру розчинність (близько 1:2); у концентраціях порядку 2% розчиняється швидко.")
            rationaleLines.append("Для фенолу в масляній системі наголос на коректному порядку внесення, а не на інтенсивному нагріванні.")
            technologyLines.append("Порядок внесення: спочатку у сухий тарований флакон відважити Oleum (усю або більшу частину), потім додати фенол.")
            rationaleLines.append("Такий порядок зменшує втрати фенолу на стінках флакона та підвищує безпеку роботи з агресивною речовиною.")
        }

        if needsHeating {
            if hasIodideComplexInGlycerin {
                technologyLines.append("Після введення Glycerinum допускається лише помірне підігрівання на водяній бані 40-45°C.")
                rationaleLines.append("Для йод-гліцеринової системи нагрівання вище 45°C небажане через ризик втрат йоду.")
            } else if solventType == .glycerin {
                technologyLines.append("Флакон щільно укупорити та нагрівати на водяній бані 40-50°C, періодично струшуючи до розчинення кристалів.")
                technologyLines.append("Не нагрівати вище 60°C (ризик розкладу гліцерину з утворенням акролеїну).")
                rationaleLines.append("Glycerinum гігроскопічний, тому нагрівання проводять у закритому флаконі; перегрів понад 60°C неприпустимий.")
            } else if solventWarmOilBath {
                technologyLines.append("Oleum Helianthi підігрівати лише на водяній бані в межах 40-50°C (не вище 50°C).")
                rationaleLines.append("Для соняшникової олії робочий підігрів обмежують 40-50°C, щоб не прискорювати окиснення та втрати летких компонентів.")
            } else {
                let limit = solventProfile.temperatureMaxC ?? 50
                technologyLines.append("Для в'язкого неводного розчинника застосувати нагрівання на водяній бані до \(format(limit))°C.")
                rationaleLines.append("Через в'язкий розчинник і слабку розчинність потрібне помірне нагрівання.")
            }
        }

        if hasVolatileActives {
            technologyLines.append("Леткі компоненти вводити в останню чергу або працювати у щільно закритому флаконі.")
            rationaleLines.append("Ментол, тимол та подібні леткі речовини потребують мінімального контакту з повітрям.")
        }

        if solventNeedsSterileDryHeat {
            technologyLines.append("Для нанесення на рани/слизові Oleum Helianthi попередньо стерилізувати сухим жаром: 180°C 30 хв або 160°C 45 хв.")
            rationaleLines.append("Стерильність соняшникової олії потрібна для ранових і слизових форм.")
        }

        if solventType == .glycerin, insolubleResidue {
            technologyLines.append("За наявності домішок процідити розчин у гарячому вигляді через багатошарову марлю або пухкий ватний тампон у флакон відпуску; паперовий фільтр не застосовувати.")
            rationaleLines.append("Для гліцеринових систем гаряче проціджування зменшує втрати на фільтрі; паперові фільтри не використовують.")
        }

        if let officinalAlcohol {
            technologyLines.insert("Офіцинальний спиртовий розчин готують за регламентованим складом; для \(officinalAlcohol.title) використовують спирт етиловий \(officinalAlcohol.ethanolStrength)% .", at: 0)
            rationaleLines.append("Оскільки назва та концентрація відповідають офіцинальному спиртовому розчину, технологія виготовлення регламентована і не потребує довільного підбору розчинника.")
        }

        if let officinalAlcohol, fixedComponents.isEmpty {
            technologyLines.append(contentsOf: officinalAlcoholTechnologyTemplate(
                spec: officinalAlcohol,
                solventVolumeMl: targetMl,
                needsHeating: needsHeating,
                insolubleResidue: insolubleResidue
            ))
        } else {
            technologyLines.append(contentsOf: technologyTemplate(
                solventType: solventType,
                profile: solventProfile,
                needsHeating: needsHeating,
                insolubleResidue: insolubleResidue,
                ethanolUsesFinalVolume: ethanolUsesFinalVolume,
                ethanolUsesLookupDilution: ethanolPreparation?.water ?? 0 > 0,
                massUsesFinalTarget: massUsesFinalTarget,
                ethanolKuoIgnored: ethanolKuoIgnored,
                usesIodideComplex: usesIodideComplex,
                iodideComplexWaterMl: iodideComplexPrep?.waterMl,
                hasVolatileActives: hasVolatileActives,
                hasPhenolFamilyActives: hasPhenolFamilyActives,
                hasPhenolInGlycerin: hasPhenolInGlycerin
            ))
        }

        qualityLines.append(contentsOf: qualityTemplate(
            solventType: solventType,
            insolubleResidue: insolubleResidue
        ))
        if solventRancidityRisk {
            qualityLines.append("Контролювати ознаки прогіркання; зберігати у прохолодному, захищеному від світла місці.")
            rationaleLines.append("Oleum Helianthi має ризик прогіркання при доступі світла й тепла.")
        }
        if usesIodideComplex {
            qualityLines.append("Розчин має бути прозорим, темно-коричневим, без видимих кристалів йоду.")
        }

        if hasPhenolFamilyActives {
            context.appendSection(title: "Упаковка/Маркування", lines: [
                "Тара: флакон з оранжевого скла (щільно закупорений).",
                "Етикетка: «Берегти від світла»."
            ])
            rationaleLines.append("Для фенолу рекомендоване оранжеве скло через окиснення на світлі та повітрі (потемніння/рожево-буре забарвлення).")
        }
        if hasLightSensitiveActives && !hasPhenolFamilyActives && !usesIodideComplex {
            context.appendSection(title: "Упаковка/Маркування", lines: [
                "Тара: флакон з темного (оранжевого) скла.",
                "Етикетка: «Берегти від світла»."
            ])
            technologyLines.append("Працювати при захищеному освітленні; відпускати у флаконі з темного (оранжевого) скла.")
            rationaleLines.append("Склад містить світлочутливі компоненти, тому потрібен світлозахист на етапі виготовлення та відпуску.")
        }
        if usesIodideComplex {
            context.appendSection(title: "Упаковка/Маркування", lines: [
                "Тара: флакон з темного скла (щільно закупорений).",
                "Етикетка: «Берегти від світла»."
            ])
            if solventType == .glycerin {
                context.appendSection(title: "Упаковка/Маркування", lines: [
                    "Контроль тари: звичайний флакон заборонено; дозволено лише темне (оранжеве) скло."
                ])
                context.addIssue(
                    code: "nonaqueous.lugol.darkGlassOnly",
                    severity: .blocking,
                    message: "Для Solutio Lugoli cum Glycerino дозволено лише флакон із темного скла."
                )
            }
        }

        context.appendSection(title: "Розрахунки", lines: calculationLines)
        context.appendSection(title: "Технологія виготовлення", lines: technologyLines)
        context.appendSection(title: "Контроль якості", lines: qualityLines)
        context.appendSection(title: "Логіка неводного розчину", lines: rationaleLines)

        let prepTitle = solventType == .glycerin
            ? "Тарувати сухий флакон темного скла та підготувати засоби безпеки"
            : "Підготувати сухий флакон та засоби безпеки"
        context.addStep(TechStep(kind: .prep, title: prepTitle, isCritical: true))

        if let iodideComplexPrep {
            let iodideNames = iodideComplexPrep.iodideNames.isEmpty ? "Kalii/Natrii iodidum" : iodideComplexPrep.iodideNames.joined(separator: ", ")
            let iodineNames = iodideComplexPrep.iodineNames.isEmpty ? "Iodum" : iodideComplexPrep.iodineNames.joined(separator: ", ")
            let waterStepTitle: String
            if iodideComplexPrep.hasExplicitWater {
                waterStepTitle = iodideComplexPrep.waterMl > 0
                    ? "Розчинити \(iodideNames) у наявній Aqua purificata та додати ще \(format(iodideComplexPrep.waterMl)) ml"
                    : "Розчинити \(iodideNames) у відміряній Aqua purificata з рецепта"
            } else {
                waterStepTitle = "Розчинити \(iodideNames) в Aqua purificata \(format(iodideComplexPrep.waterMl)) ml"
            }
            context.addStep(TechStep(
                kind: .dissolution,
                title: waterStepTitle,
                notes: solventType == .glycerin
                    ? "Сформувати концентрований розчин йодиду (мінімум 1:1.5 до маси KI)"
                    : "Сформувати концентрований розчин йодиду",
                isCritical: true
            ))
            context.addStep(TechStep(
                kind: .dissolution,
                title: "Додати \(iodineNames) та розчинити до повного утворення комплексу",
                notes: "Працювати без металевих інструментів",
                isCritical: true
            ))
        } else if usesIodideComplex {
            context.addStep(TechStep(
                kind: .dissolution,
                title: "Спочатку розчинити йодид у мінімальній кількості води/співрозчинника, потім розчинити йод",
                notes: "Працювати без металевих інструментів",
                isCritical: true
            ))
        }

        if let officinalAlcohol, fixedComponents.isEmpty {
            let activeMass = targetMl * officinalAlcohol.concentrationPercent / 100.0
            context.addStep(TechStep(kind: .prep, title: "Відважити \(officinalAlcohol.activeTitle) \(format(activeMass)) g і внести у сухий флакон", isCritical: true))
            context.addStep(TechStep(kind: .dissolution, title: "Додати Spiritus aethylici \(officinalAlcohol.ethanolStrength)% ad \(format(targetMl)) ml і розчинити речовину", isCritical: true))
        } else if solventType == .fattyOil, hasPhenolFamilyActives {
            context.addStep(TechStep(
                kind: .prep,
                title: "Спочатку відважити Oleum у сухий тарований флакон (усю або більшу частину)",
                isCritical: true
            ))
            context.addStep(TechStep(
                kind: .dissolution,
                title: "Додати Phenolum (Acidum carbolicum) у вже відважену олію та розчинити при перемішуванні",
                isCritical: true
            ))
        } else if iodideComplexPrep != nil, solventType.isViscous {
            context.addStep(TechStep(
                kind: .dissolution,
                title: "Додати в'язкий неводний розчинник до отриманого йод-йодидного концентрату та перемішати до однорідності",
                isCritical: true
            ))
        } else if solventType == .ethanol, let ethanolPreparation, ethanolPreparation.water > 0 {
            context.addStep(TechStep(
                kind: .prep,
                title: "Відміряти Aqua purificata \(format(ethanolPreparation.water)) ml у мірний циліндр",
                isCritical: true
            ))
            context.addStep(TechStep(
                kind: .dissolution,
                title: "Додати Spiritus aethylici \(format(ethanolPreparation.resolvedSourcePercent))% \(format(ethanolPreparation.ethanol)) ml у той самий циліндр та змішати (контракція) до одержання \(format(Double(ethanolPreparation.targetPercent)))% спирту",
                isCritical: true
            ))
            if !fixedComponents.isEmpty {
                context.addStep(TechStep(kind: .dissolution, title: "Розчинити сухі речовини у підготовленому спирті", isCritical: true))
            }
        } else if solventType == .ethanol {
            context.addStep(TechStep(kind: .dissolution, title: "Відміряти етанол у флакон і розчинити в ньому сухі речовини", isCritical: true))
        } else if solventType == .glycerin {
            if !glycerinDeryagin.hard.isEmpty {
                let hardNames = glycerinDeryagin.hard.map(componentDisplayName).joined(separator: ", ")
                context.addStep(TechStep(
                    kind: .trituration,
                    title: "Розтерти \(hardNames) з частиною Glycerinum",
                    notes: "Орієнтовно 1/2 від маси речовини; суспензію перенести у флакон і змити залишком гліцерину",
                    isCritical: true
                ))
            }
            if !glycerinDeryagin.easy.isEmpty {
                let easyNames = glycerinDeryagin.easy.map(componentDisplayName).joined(separator: ", ")
                context.addStep(TechStep(
                    kind: .dissolution,
                    title: "Відважити \(easyNames) безпосередньо у флакон з Glycerinum",
                    isCritical: true
                ))
            }
            context.addStep(TechStep(
                kind: .dissolution,
                title: "Додати основну кількість Glycerinum та перемішати до однорідності",
                isCritical: true
            ))
        } else {
            context.addStep(TechStep(kind: .dissolution, title: "Змішати речовини з частиною неводного розчинника", isCritical: true))
        }

        if needsHeating {
            if hasIodideComplexInGlycerin {
                context.addStep(TechStep(
                    kind: .mixing,
                    title: "За потреби підігріти на водяній бані для прискорення змішування",
                    notes: "Для йод-гліцеринової системи: 40-45°C, не вище 45°C"
                ))
            } else if solventWarmOilBath {
                context.addStep(TechStep(
                    kind: .mixing,
                    title: "Нагріти на водяній бані до повного розчинення",
                    notes: "Робочий діапазон 40-50°C; не перевищувати 50°C"
                ))
            } else if solventType == .glycerin {
                context.addStep(TechStep(
                    kind: .mixing,
                    title: "У щільно укупореному флаконі нагріти на водяній бані до повного розчинення",
                    notes: "40-50°C; не перевищувати 60°C через ризик утворення акролеїну"
                ))
            } else {
                let limit = solventProfile.temperatureMaxC ?? 50
                context.addStep(TechStep(kind: .mixing, title: "Нагріти на водяній бані до повного розчинення", notes: "Не перевищувати \(format(limit))°C"))
            }
        } else if hasPhenolInGlycerin {
            context.addStep(TechStep(
                kind: .mixing,
                title: "Нагріти флакон на водяній бані до повного розчинення фенолу",
                notes: "40-50°C; не вище 60°C"
            ))
        } else {
            context.addStep(TechStep(kind: .mixing, title: "Перемішати до повного розчинення"))
        }

        if solventNeedsSterileDryHeat {
            context.addStep(TechStep(
                kind: .sterilization,
                title: "За потреби стерильної олійної основи провести сухожарову стерилізацію",
                notes: "Oleum Helianthi: 180°C 30 хв або 160°C 45 хв"
            ))
        }

        if insolubleResidue {
            let title: String
            if solventType == .ethanol {
                title = "За потреби лише процідити через марлю, без фільтрації через вату"
            } else if solventType == .glycerin {
                title = "Процідити гарячий розчин через марлю/ватний тампон; паперовий фільтр не використовувати"
            } else {
                title = "Профільтрувати через суху вату"
            }
            context.addStep(TechStep(kind: .filtration, title: title))
        }

        if calculationMethod == .massVolume {
            if ethanolUsesFinalVolume {
                let usesLookupDilution = solventType == .ethanol && ethanolPreparation?.water ?? 0 > 0
                let bringToVolumeTitle: String
                if officinalAlcohol != nil && fixedComponents.isEmpty {
                    bringToVolumeTitle = "Довести спиртом тієї ж міцності до кінцевого об'єму"
                } else {
                    bringToVolumeTitle = "Довести відповідним спиртовим розчинником до кінцевого об'єму"
                }
                if !usesLookupDilution {
                    context.addStep(TechStep(kind: .bringToVolume, title: bringToVolumeTitle, isCritical: true))
                }
            }
        } else if massUsesFinalTarget {
            context.addStep(TechStep(kind: .bringToVolume, title: "Довести розчинником до кінцевої маси", isCritical: true))
        }
    }

    private func buildEthanolSection(
        context: inout RxPipelineContext,
        solventIngredient: IngredientDraft?,
        fixedComponents: [IngredientDraft],
        targetStrength: Int,
        solventVolumeMl: Double,
        usesFinalVolume: Bool,
        canIgnoreKuo: Bool,
        profile: NonAqueousSolventProfile,
        officinalAlcohol: OfficinalAlcoholSolutionSpec?,
        calculationLines: inout [String],
        rationaleLines: inout [String]
    ) -> EthanolDilutionResult? {
        guard solventVolumeMl > 0 else {
            context.addIssue(
                code: "nonaqueous.ethanol.target.missing",
                severity: .blocking,
                message: "Для спиртового розчину потрібен об'єм спирту або кінцевий об'єм у ml"
            )
            return nil
        }

        let solidsMass = fixedComponents.compactMap(componentMassG).reduce(0, +)

        if let officinalAlcohol, fixedComponents.isEmpty {
            let activeMass = solventVolumeMl * officinalAlcohol.concentrationPercent / 100.0
            calculationLines.append("Офіцинальний розчин: \(officinalAlcohol.title)")
            calculationLines.append("\(officinalAlcohol.activeTitle) = \(format(activeMass)) g")
            calculationLines.append("Spiritus aethylici \(officinalAlcohol.ethanolStrength)% ad \(format(solventVolumeMl)) ml")
            rationaleLines.append("Офіцинальний \(officinalAlcohol.title) готують як істинний спиртовий розчин ваго-об'ємним методом.")
            rationaleLines.append("За низької концентрації (\(format(officinalAlcohol.concentrationPercent))%) КУО для практичного розрахунку не враховують.")
            if let density = NonAqueousSolventCatalog.density(for: .ethanol, ethanolStrength: officinalAlcohol.ethanolStrength, fallback: profile.density20C) {
                let accountingMass = density * solventVolumeMl
                calculationLines.append("ПКО/облік: \(format(solventVolumeMl)) ml * \(format(density)) g/ml = \(format(accountingMass)) g")
            }
            return nil
        }

        for ingredient in fixedComponents {
            if let mass = componentMassG(ingredient) {
                calculationLines.append("\(latinName(ingredient)) = \(format(mass)) g")
            } else if ingredient.amountValue > 0 {
                context.addIssue(
                    code: "nonaqueous.ethanol.component.mass",
                    severity: .warning,
                    message: "Компонент \(latinName(ingredient)) не вдалося нормалізувати до маси"
                )
            }
        }

        let stockStrength = NonAqueousSolventCatalog.defaultEthanolSourceStrength
        let requiresDilution = targetStrength != stockStrength
        if usesFinalVolume {
            if requiresDilution,
               let dilution = try? EthanolDilutionRepository.shared.prepareEthanol(
                    sourcePercent: Double(stockStrength),
                    targetPercent: targetStrength,
                    finalAmount: solventVolumeMl,
                    mode: .volumeML
               ) {
                appendDilutionLookupLines(dilution, requestedSourcePercent: Double(stockStrength), heading: "Табличне розведення спирту", to: &calculationLines)
                appendAccountingLine(for: dilution, fallbackDensity: profile.density20C, to: &calculationLines, rationaleLines: &rationaleLines)
                rationaleLines.append("Етанол розраховується як lookup table engine: береться таблична пара source -> target при 20°C, масштабується на потрібний об'єм і не замінюється формулою без урахування контракції.")
                rationaleLines.append("Спирт потрібної міцності спочатку готують окремо за таблицею, після чого використовують у рецепті.")
                rationaleLines.append("Після табличного розведення окреме доведення розчинником не виконують: підсумковий об'єм уже враховує контракцію.")
                if dilution.usedNearestSource {
                    rationaleLines.append("Для вихідної міцності використано найближчий табличний рядок \(format(dilution.resolvedSourcePercent))%.")
                }
                if let range = dilution.interpolatedTargetRange {
                    rationaleLines.append("Цільову міцність \(targetStrength)% отримано лінійною інтерполяцією між табличними значеннями \(range.lowerBound)% і \(range.upperBound)%.")
                }
                return dilution
            } else if requiresDilution {
                context.addIssue(
                    code: "nonaqueous.ethanol.dilution.missing",
                    severity: .warning,
                    message: "Для спирту \(targetStrength)% не знайдено табличного розведення; використано прямий об'єм"
                )
                calculationLines.append("Spiritus aethylici \(targetStrength)% = \(format(solventVolumeMl)) ml")
                rationaleLines.append("Табличне розведення не знайдено, тому потрібна ручна перевірка концентрації спирту.")
            } else {
                calculationLines.append("Spiritus aethylici \(targetStrength)% ad \(format(solventVolumeMl)) ml")
                appendDirectAlcoholAccountingLine(volumeMl: solventVolumeMl, strength: targetStrength, fallbackDensity: profile.density20C, to: &calculationLines, rationaleLines: &rationaleLines)
                rationaleLines.append("Вихідна міцність спирту вже відповідає потрібній, тому табличне розведення не потрібне.")
            }
        } else {
            calculationLines.append("Spiritus aethylici \(targetStrength)% = \(format(solventVolumeMl)) ml")
            if requiresDilution,
               let dilution = try? EthanolDilutionRepository.shared.prepareEthanol(
                    sourcePercent: Double(stockStrength),
                    targetPercent: targetStrength,
                    finalAmount: solventVolumeMl,
                    mode: .volumeML
               ) {
                appendDilutionLookupLines(dilution, requestedSourcePercent: Double(stockStrength), heading: "Для попереднього приготування \(format(solventVolumeMl)) ml спирту \(targetStrength)%", to: &calculationLines)
                appendAccountingLine(for: dilution, fallbackDensity: profile.density20C, to: &calculationLines, rationaleLines: &rationaleLines)
                if dilution.usedNearestSource {
                    rationaleLines.append("Для вихідної міцності використано найближчий табличний рядок \(format(dilution.resolvedSourcePercent))%.")
                }
                if let range = dilution.interpolatedTargetRange {
                    rationaleLines.append("Цільову міцність \(targetStrength)% отримано лінійною інтерполяцією між табличними значеннями \(range.lowerBound)% і \(range.upperBound)%.")
                }
                rationaleLines.append("Спирт потрібної міцності слід приготувати окремо за таблицею 20°C, а вже потім використовувати як розчинник.")
                return dilution
            }

            if canIgnoreKuo {
                rationaleLines.append("Сумарна концентрація сухих речовин не перевищує 3% у зовнішньому спиртовому розчині до 30 ml, тому КУО можна не враховувати.")
            } else if solidsMass > 0 {
                rationaleLines.append("За точно відміряного об'єму спирту кінцевий об'єм розчину може збільшуватися через КУО; це слід врахувати в ППК.")
            }

            appendDirectAlcoholAccountingLine(volumeMl: solventVolumeMl, strength: targetStrength, fallbackDensity: profile.density20C, to: &calculationLines, rationaleLines: &rationaleLines)

            rationaleLines.append("Для спиртових розчинів з точно заданим об'ємом спирту спочатку відмірюють спирт, потім у ньому розчиняють сухі речовини.")
        }

        return nil
    }

    private func appendDilutionLookupLines(
        _ dilution: EthanolDilutionResult,
        requestedSourcePercent: Double,
        heading: String,
        to calculationLines: inout [String]
    ) {
        calculationLines.append("\(heading):")
        calculationLines.append("Таблиця: \(dilution.tableID) при \(format(dilution.temperatureC))°C")
        calculationLines.append("• Aqua purificata \(format(dilution.water)) ml")
        calculationLines.append("• Spiritus aethylici \(format(dilution.resolvedSourcePercent))% \(format(dilution.ethanol)) ml")
        calculationLines.append("• Після змішування отримують \(format(dilution.finalAmount)) ml спирту \(format(Double(dilution.targetPercent)))%")
        calculationLines.append("• Сума компонентів до контракції = \(format(dilution.mixAmountBeforeContraction)) ml")

        if dilution.usedNearestSource,
           abs(dilution.resolvedSourcePercent - requestedSourcePercent) > 0.0001 {
            calculationLines.append("• Використано найближчий табличний рядок для \(format(dilution.resolvedSourcePercent))%")
        }

        if let range = dilution.interpolatedTargetRange {
            calculationLines.append("• Цільову міцність отримано інтерполяцією між \(range.lowerBound)% та \(range.upperBound)%")
        }
    }

    private func appendAccountingLine(
        for dilution: EthanolDilutionResult,
        fallbackDensity: Double?,
        to calculationLines: inout [String],
        rationaleLines: inout [String]
    ) {
        let sourceStrength = Int(dilution.resolvedSourcePercent.rounded())
        guard let sourceDensity = NonAqueousSolventCatalog.density(
            for: .ethanol,
            ethanolStrength: sourceStrength,
            fallback: fallbackDensity
        ) else { return }

        let accountingMass = dilution.ethanol * sourceDensity
        calculationLines.append("ПКО/облік спирту: \(format(dilution.ethanol)) ml * \(format(sourceDensity)) g/ml = \(format(accountingMass)) g")
        rationaleLines.append("Для ПКО враховується маса фактично витраченого вихідного спирту, а не маса кінцевого розведеного розчину.")
    }

    private func appendDirectAlcoholAccountingLine(
        volumeMl: Double,
        strength: Int,
        fallbackDensity: Double?,
        to calculationLines: inout [String],
        rationaleLines: inout [String]
    ) {
        guard let density = NonAqueousSolventCatalog.density(
            for: .ethanol,
            ethanolStrength: strength,
            fallback: fallbackDensity
        ) else { return }

        let accountingMass = density * volumeMl
        calculationLines.append("ПКО/облік спирту: \(format(volumeMl)) ml * \(format(density)) g/ml = \(format(accountingMass)) g")
        rationaleLines.append("Для предметно-кількісного обліку об'єм спирту переводиться у масу через густину.")
    }

    private func buildMassSection(
        context: inout RxPipelineContext,
        solventIngredient: IngredientDraft?,
        fixedComponents: [IngredientDraft],
        solventType: NonAqueousSolventType,
        profile: NonAqueousSolventProfile,
        usesFinalMassTarget: Bool,
        iodideComplexPrep: IodideComplexPreparation?,
        hasPhenolInGlycerin: Bool,
        calculationLines: inout [String],
        rationaleLines: inout [String]
    ) {
        let density = solventType == .glycerin
            ? 1.25
            : (profile.density20C ?? NonAqueousSolventCatalog.density(for: solventType, fallback: solventIngredient?.refDensity))
        guard let density, density > 0 else {
            context.addIssue(
                code: "nonaqueous.density.missing",
                severity: .blocking,
                message: "Для неводного розчину відсутня густина розчинника"
            )
            return
        }

        let unresolved = fixedComponents.filter { $0.amountValue > 0 && componentMassG($0) == nil }
        if let first = unresolved.first {
            context.addIssue(
                code: "nonaqueous.mass.component.missingDensity",
                severity: .blocking,
                message: "Компонент \(latinName(first)) не можна перевести у масу: відсутня густина"
            )
            return
        }

        calculationLines.append("Густина розчинника = \(format(density)) g/ml")

        let fixedMass = fixedComponents.reduce(0.0) { partial, ingredient in
            guard let mass = componentMassG(ingredient) else { return partial }
            calculationLines.append("\(latinName(ingredient)) = \(format(mass)) g")
            return partial + mass
        }
        let iodideComplexWaterMass = iodideComplexPrep?.waterMassG ?? 0
        if let iodideComplexPrep, iodideComplexPrep.waterMassG > 0 {
            calculationLines.append("Aqua purificata (додатково для комплексу йоду) = \(format(iodideComplexPrep.waterMl)) ml (~\(format(iodideComplexWaterMass)) g)")
        }
        let totalFixedMass = fixedMass + iodideComplexWaterMass
        let phenolMass = fixedComponents
            .filter(isPhenolFamily)
            .compactMap(componentMassG)
            .reduce(0, +)

        let exactSolventMassG = resolvedSolventMassG(solventIngredient, density: density)

        if usesFinalMassTarget {
            let targetMassG: Double? = {
                if let explicit = context.draft.explicitPowderTargetG, explicit > 0 {
                    return explicit
                }
                if let targetMl = context.draft.explicitLiquidTargetMl, targetMl > 0 {
                    return targetMl * density
                }
                if let solventIngredient, (solventIngredient.isAd || solventIngredient.isQS), solventIngredient.amountValue > 0 {
                    if solventIngredient.unit.rawValue == "g" {
                        return solventIngredient.amountValue
                    }
                    if solventIngredient.unit.rawValue == "ml" {
                        return solventIngredient.amountValue * density
                    }
                }
                return nil
            }()

            guard let targetMassG, targetMassG > 0 else {
                context.addIssue(
                    code: "nonaqueous.mass.target.missing",
                    severity: .blocking,
                    message: "Для неводного масового методу потрібна кінцева маса або об'єм з відомою густиною"
                )
                return
            }

            if let targetMl = context.draft.explicitLiquidTargetMl, targetMl > 0 {
                calculationLines.append("M_final = \(format(targetMl)) ml * \(format(density)) g/ml = \(format(targetMassG)) g")
                rationaleLines.append("Для неводних розчинів, заданих у ml, кінцевий об'єм переводиться у масу через густину.")
            } else {
                calculationLines.append("M_final = \(format(targetMassG)) g")
            }

            let solventMass = max(0, targetMassG - totalFixedMass)
            calculationLines.append("\(profile.title) = \(format(solventMass)) g")
            rationaleLines.append("Неводний розчинник, крім спирту, рахується масовим методом з доведенням до кінцевої маси.")
            if hasPhenolInGlycerin, phenolMass > 0, targetMassG > 0 {
                appendPhenolConcentrationValidation(
                    context: &context,
                    phenolMass: phenolMass,
                    totalMass: targetMassG,
                    calculationLines: &calculationLines,
                    rationaleLines: &rationaleLines
                )
            }
            return
        }

        guard let exactSolventMassG, exactSolventMassG > 0 else {
            context.addIssue(
                code: "nonaqueous.mass.target.missing",
                severity: .blocking,
                message: "Для неводного масового методу потрібна кінцева маса або точна кількість розчинника з відомою густиною"
            )
            return
        }

        if let solventIngredient, solventIngredient.unit.rawValue == "ml", solventIngredient.amountValue > 0 {
            calculationLines.append("\(profile.title) = \(format(solventIngredient.amountValue)) ml * \(format(density)) g/ml = \(format(exactSolventMassG)) g")
        } else {
            calculationLines.append("\(profile.title) = \(format(exactSolventMassG)) g")
        }

        let totalMassG = totalFixedMass + exactSolventMassG
        if iodideComplexWaterMass > 0 {
            calculationLines.append("M_total = \(format(fixedMass)) g + \(format(iodideComplexWaterMass)) g + \(format(exactSolventMassG)) g = \(format(totalMassG)) g")
        } else {
            calculationLines.append("M_total = \(format(fixedMass)) g + \(format(exactSolventMassG)) g = \(format(totalMassG)) g")
        }
        rationaleLines.append("Для неводного масового методу з точно заданою кількістю розчинника загальна маса визначається як сума мас усіх компонентів.")
        if hasPhenolInGlycerin, phenolMass > 0, totalMassG > 0 {
            appendPhenolConcentrationValidation(
                context: &context,
                phenolMass: phenolMass,
                totalMass: totalMassG,
                calculationLines: &calculationLines,
                rationaleLines: &rationaleLines
            )
        }
    }

    private func appendPhenolConcentrationValidation(
        context: inout RxPipelineContext,
        phenolMass: Double,
        totalMass: Double,
        calculationLines: inout [String],
        rationaleLines: inout [String]
    ) {
        guard totalMass > 0 else { return }
        let percent = (phenolMass / totalMass) * 100
        calculationLines.append("C(Phenolum purum) = \(format(phenolMass)) / \(format(totalMass)) * 100% = \(format(percent))%")

        if percent > 5 {
            context.addIssue(
                code: "nonaqueous.phenol.glycerin.highConcentration",
                severity: .warning,
                message: "Висока концентрація фенолу у гліцерині (>5%): перевірте дозування."
            )
            rationaleLines.append("Для зовнішніх гліцеринових розчинів фенолу зазвичай орієнтуються на 2-5%; значення вище 5% потребує додаткової перевірки.")
        } else {
            let signa = SignaUsageAnalyzer.analyze(signa: context.draft.signa)
            if signa.isExternalRoute || signa.isNasalRoute || signa.normalizedSigna.contains("вух") || signa.normalizedSigna.contains("ear") {
                rationaleLines.append("Концентрація фенолу у межах норми (\(format(percent))%). Перевірка ВРД/ВСД не потрібна для зовнішнього застосування.")
            }
        }
    }

    private func technologyTemplate(
        solventType: NonAqueousSolventType,
        profile: NonAqueousSolventProfile,
        needsHeating: Bool,
        insolubleResidue: Bool,
        ethanolUsesFinalVolume: Bool,
        ethanolUsesLookupDilution: Bool,
        massUsesFinalTarget: Bool,
        ethanolKuoIgnored: Bool,
        usesIodideComplex: Bool,
        iodideComplexWaterMl: Double?,
        hasVolatileActives: Bool,
        hasPhenolFamilyActives: Bool,
        hasPhenolInGlycerin: Bool
    ) -> [String] {
        var lines: [String] = [
            "Метод: \(solventType == .ethanol ? "масо-об'ємний" : "масовий")",
            solventType == .ethanol
                ? "1. Відміряти спирт у флакон, після чого розчинити в ньому сухі речовини."
                : (solventType == .fattyOil && hasPhenolFamilyActives
                    ? "1. У сухий тарований флакон спочатку відважити Oleum (усю або більшу частину), потім додати Phenolum/Acidum carbolicum."
                    : "1. Відважити речовини та додати частину неводного розчинника.")
        ]

        if usesIodideComplex {
            if let iodideComplexWaterMl {
                if iodideComplexWaterMl > 0 {
                    lines.append("Перед введенням основного розчинника йод розчинити через концентрований розчин йодиду в Aqua purificata \(format(iodideComplexWaterMl)) ml.")
                } else {
                    lines.append("Перед введенням основного розчинника йод розчинити через концентрований розчин йодиду в наявній Aqua purificata.")
                }
            } else {
                lines.append("Перед введенням основного розчинника йод розчинити через концентрований розчин йодиду.")
            }
        }

        if needsHeating || hasPhenolInGlycerin {
            if solventType == .glycerin {
                lines.append("2. Укупорити флакон і нагрівати на водяній бані 40-50°C, періодично струшуючи; не вище 60°C.")
            } else {
                let maxC = profile.temperatureMaxC ?? 50
                lines.append("2. Нагріти на водяній бані до \(format(maxC))°C та перемішувати до розчинення.")
            }
        } else {
            lines.append("2. Перемішувати до повного розчинення без перегрівання.")
        }

        switch solventType {
        case .ether:
            lines.append("Нагрівання заборонено; працювати подалі від відкритого вогню.")
        case .chloroform:
            lines.append("За потреби допускається лише помірне нагрівання, не вище 60°C.")
        case .ethanol:
            if ethanolUsesFinalVolume {
                if ethanolUsesLookupDilution {
                    lines.append("За табличного розведення спирту працювати у мірному циліндрі; контракція врахована табличною парою.")
                } else {
                    lines.append("За потреби спирт потрібної міцності спочатку готують окремо; воду доливають до мітки під час його розведення, а не в готовий розчин.")
                }
            } else if ethanolKuoIgnored {
                lines.append("КУО для сухих речовин до 3% допускається не враховувати.")
            } else {
                lines.append("За точно заданого об'єму спирту кінцевий об'єм може збільшуватися через КУО.")
            }
            lines.append("Спиртові розчини не фільтрувати; за потреби лише обережно проціджувати.")
        case .fattyOil, .mineralOil, .glycerin, .vinylin, .viscousOther:
            if massUsesFinalTarget {
                lines.append("Для в'язких неводних систем доведення проводити після охолодження до робочої температури.")
            }
            if solventType == .glycerin {
                lines.append("Glycerinum відважувати у тарований флакон; не переливати через мірний циліндр.")
            }
        case .volatileOther:
            lines.append("Леткий неводний розчинник вводити без нагрівання та з мінімальним контактом з повітрям.")
        }

        if insolubleResidue {
            lines.append(
                solventType == .ethanol
                    ? "За наявності залишку допускається лише проціджування через марлю."
                    : (solventType == .glycerin
                        ? "За наявності домішок проціджувати в гарячому вигляді через марлю або ватний тампон; паперовий фільтр не використовувати."
                        : "За наявності нерозчинного залишку профільтрувати через суху вату.")
            )
        }

        if hasVolatileActives {
            lines.append("Леткі речовини вводити наприкінці процесу або в закритому флаконі.")
        }

        if solventType == .ethanol {
            if ethanolUsesFinalVolume {
                if ethanolUsesLookupDilution {
                    lines.append("3. Перемішати до повного розчинення; додаткове доведення розчинником не виконувати.")
                } else {
                    lines.append("3. Довести до кінцевого об'єму.")
                }
            } else {
                lines.append("3. Відпускати в тій кількості, що утворилася після розчинення речовин у відміряному спирті.")
            }
        } else {
            if massUsesFinalTarget {
                lines.append("3. Довести до кінцевої маси.")
            } else {
                lines.append("3. Відпустити після повного розчинення у точно відваженій/відміряній кількості розчинника.")
            }
        }
        return lines
    }

    private func officinalAlcoholTechnologyTemplate(
        spec: OfficinalAlcoholSolutionSpec,
        solventVolumeMl: Double,
        needsHeating: Bool,
        insolubleResidue: Bool
    ) -> [String] {
        var lines: [String] = [
            "Метод: масо-об'ємний",
            "1. Відважити \(spec.activeTitle) у розрахованій кількості та внести у сухий флакон.",
            "2. Додати Spiritus aethylici \(spec.ethanolStrength)% ad \(format(solventVolumeMl)) ml та перемішувати до повного розчинення."
        ]

        if needsHeating {
            lines.append("Допускається лише обережне підігрівання на водяній бані в щільно закритому флаконі.")
        } else {
            lines.append("Перегрівання не застосовувати; спиртова система летка.")
        }

        lines.append("КУО для низької концентрації допускається не враховувати.")
        lines.append("Воду не додавати; доведення виконувати лише спиртом тієї ж міцності.")
        lines.append("Спиртові розчини не фільтрувати; за потреби лише обережно проціджувати.")

        if insolubleResidue {
            lines.append("За наявності механічних домішок допустиме обережне проціджування через суху вату або марлю.")
        }

        lines.append("3. Відпустити у флаконі-крапельниці відповідної місткості.")
        return lines
    }

    private func qualityTemplate(
        solventType: NonAqueousSolventType,
        insolubleResidue: Bool
    ) -> [String] {
        var lines = [
            "Однорідність розчину",
            "Відсутність механічних включень"
        ]
        if insolubleResidue {
            lines.append(
                solventType == .ethanol
                    ? "Після проціджування розчин має залишатися однорідним без втрати леткого розчинника"
                    : (solventType == .glycerin
                        ? "Після гарячого проціджування фільтрат має бути прозорим; паперовий фільтр не застосовують"
                        : "Після фільтрації фільтрат має бути прозорим або рівномірно опалесцентним")
            )
        }
        if solventType.isVolatile {
            lines.append("Щільність закупорювання флакона")
        }
        return lines
    }

    private func resolvedLiquidTargetMl(in draft: ExtempRecipeDraft, solventIngredient: IngredientDraft?) -> Double {
        if let explicit = draft.explicitLiquidTargetMl, explicit > 0 { return explicit }
        if let inferred = draft.legacyAdOrQsLiquidTargetMl, inferred > 0 { return inferred }
        if let solventIngredient,
           let solutionVolume = draft.solutionVolumeMl(for: solventIngredient),
           solutionVolume > 0 {
            return solutionVolume
        }
        if let solventIngredient, solventIngredient.amountValue > 0, solventIngredient.unit.rawValue == "ml" {
            return solventIngredient.amountValue
        }
        return 0
    }

    private func componentMassG(_ ingredient: IngredientDraft) -> Double? {
        if ingredient.unit.rawValue == "g", ingredient.amountValue > 0 {
            return ingredient.amountValue
        }
        if ingredient.unit.rawValue == "ml", ingredient.amountValue > 0 {
            if let density = ingredient.refDensity, density > 0 {
                return ingredient.amountValue * density
            }
            if PurifiedWaterHeuristics.isPurifiedWater(ingredient) {
                return ingredient.amountValue
            }
        }
        return nil
    }

    private func resolvedSolventMassG(_ solventIngredient: IngredientDraft?, density: Double) -> Double? {
        guard let solventIngredient, solventIngredient.amountValue > 0 else { return nil }
        if solventIngredient.unit.rawValue == "g" {
            return solventIngredient.amountValue
        }
        if solventIngredient.unit.rawValue == "ml" {
            return solventIngredient.amountValue * density
        }
        return nil
    }

    private func usesMassFinalTarget(draft: ExtempRecipeDraft, solventIngredient: IngredientDraft?) -> Bool {
        if draft.explicitPowderTargetG != nil || draft.explicitLiquidTargetMl != nil || draft.legacyAdOrQsLiquidTargetMl != nil {
            return true
        }
        guard let solventIngredient else { return false }
        return solventIngredient.isAd || solventIngredient.isQS
    }

    private func ethanolUsesFinalVolume(draft: ExtempRecipeDraft, solventIngredient: IngredientDraft?) -> Bool {
        if draft.explicitLiquidTargetMl != nil || draft.legacyAdOrQsLiquidTargetMl != nil {
            return true
        }
        guard let solventIngredient else { return false }
        return solventIngredient.isAd || solventIngredient.isQS
    }

    private func canIgnoreAlcoholKuo(
        fixedComponents: [IngredientDraft],
        solventVolumeMl: Double,
        isExternalRoute: Bool
    ) -> Bool {
        guard isExternalRoute else { return false }
        guard solventVolumeMl > 0, solventVolumeMl <= 30 else { return false }
        let solidsMass = fixedComponents.compactMap(componentMassG).reduce(0, +)
        guard solidsMass > 0 else { return true }
        return (solidsMass / solventVolumeMl) * 100 <= 3
    }

    private func containsEthanolIncompatibleOxidizer(_ ingredients: [IngredientDraft]) -> Bool {
        ingredients.contains { ingredient in
            if ingredient.refIncompatibleWithEthanol == true {
                return true
            }
            let hay = normalizedHay(ingredient)
            return hay.contains("permangan")
                || hay.contains("argenti nitras")
                || hay.contains("silver nitrate")
                || hay.contains("perhydrol")
                || hay.contains("hydrogen peroxide")
                || hay.contains("chromat")
                || hay.contains("dichromat")
        }
    }

    private func containsGlycerinPhShiftComponent(_ ingredients: [IngredientDraft]) -> Bool {
        ingredients.contains(where: { ingredient in
            ingredient.propertyOverride?.technologyRules.contains(.acidifiesInGlycerin) == true
        })
    }

    private func containsIodine(_ ingredients: [IngredientDraft]) -> Bool {
        ingredients.contains(where: isIodineComponent)
    }

    private func containsIodide(_ ingredients: [IngredientDraft]) -> Bool {
        ingredients.contains(where: isIodideComponent)
    }

    private func containsVolatileActives(_ ingredients: [IngredientDraft]) -> Bool {
        ingredients.contains {
            let hay = normalizedHay($0)
            return hay.contains("menthol")
                || hay.contains("ментол")
                || hay.contains("thymol")
                || hay.contains("тимол")
                || hay.contains("camphor")
                || hay.contains("камфор")
        }
    }

    private func glycerinDeryaginGroups(ingredients: [IngredientDraft]) -> (easy: [IngredientDraft], hard: [IngredientDraft]) {
        let candidates = ingredients.filter { ingredient in
            !PurifiedWaterHeuristics.isPurifiedWater(ingredient)
                && !isIodineComponent(ingredient)
                && !isIodideComponent(ingredient)
        }

        var easy: [IngredientDraft] = []
        var hard: [IngredientDraft] = []

        for ingredient in candidates {
            if isGlycerinHardToDissolve(ingredient) {
                hard.append(ingredient)
            } else if isGlycerinEasySoluble(ingredient) {
                easy.append(ingredient)
            }
        }
        return (easy, hard)
    }

    private func isGlycerinEasySoluble(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("acidum boric")
            || hay.contains("acidi boric")
            || hay.contains("boric acid")
            || hay.contains("борн")
            || hay.contains("tanninum")
            || hay.contains("tannin")
            || hay.contains("tanin")
            || hay.contains("танин")
    }

    private func isGlycerinHardToDissolve(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        if hay.contains("tetrabor")
            || hay.contains("натр") && hay.contains("тетрабор")
            || hay.contains("крупнокристал")
            || hay.contains("large crystal")
        {
            return true
        }
        return isPoorlySoluble(ingredient, solventType: .glycerin)
    }

    private func componentDisplayName(_ ingredient: IngredientDraft) -> String {
        ingredient.displayName.isEmpty ? latinName(ingredient) : ingredient.displayName
    }

    private func lipophilicOilSoluteNames(_ ingredients: [IngredientDraft]) -> [String] {
        ingredients.compactMap { ingredient in
            let hay = normalizedHay(ingredient)
            let isLipophilicMarker = hay.contains("camphor")
                || hay.contains("камфор")
                || hay.contains("menthol")
                || hay.contains("ментол")
                || isPhenolFamily(ingredient)
                || hay.contains("thymol")
                || hay.contains("тимол")
            guard isLipophilicMarker else { return nil }
            return ingredient.displayName.isEmpty ? latinName(ingredient) : ingredient.displayName
        }
    }

    private func isPhenolFamily(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("phenol")
            || hay.contains("phenolum")
            || hay.contains("carbol")
            || hay.contains("acidum carbol")
            || hay.contains("acidi carbol")
            || hay.contains("фенол")
            || hay.contains("карбол")
    }

    private func isSalicylateIngredient(_ ingredient: IngredientDraft) -> Bool {
        normalizedHay(ingredient).contains("salicyl")
    }

    private func isTweenOrSpanIngredient(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("tween")
            || hay.contains("polysorbat")
            || hay.contains("polysorbate")
            || hay.contains("твин")
            || hay.contains("span")
            || hay.contains("sorbitan monooleat")
            || hay.contains("сорбитан моноолеат")
            || hay.contains("спан")
    }

    private func isParaHydroxyBenzoicDerivativeIngredient(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("paraben")
            || hay.contains("parahydroxybenzo")
            || hay.contains("параокси")
            || hay.contains("парагидроксибенз")
            || hay.contains("nipagin")
            || hay.contains("nipazol")
    }

    private func isParaffinIngredient(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("paraffin")
            || hay.contains("paraffinum")
            || hay.contains("парафин")
    }

    private func isMentholIngredient(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("menthol") || hay.contains("ментол")
    }

    private func isCamphorIngredient(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("camphor") || hay.contains("камфор")
    }

    private func isSunflowerOil(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("helianthi")
            || hay.contains("sunflower")
            || hay.contains("соняш")
    }

    private func isCastorOil(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("ricini")
            || hay.contains("castor")
            || hay.contains("рицинов")
    }

    private func isIodineComponent(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        if hay.contains("iodid") || hay.contains("йодид") { return false }
        return hay.contains("iodum")
            || hay.contains(" iodi ")
            || hay.hasPrefix("iodi ")
            || hay.contains("iodine")
            || hay.contains(" йод ")
            || hay.hasPrefix("йод ")
            || hay.contains("кристалічн")
    }

    private func isIodideComponent(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("iodid") || hay.contains("йодид")
    }

    private func iodideComplexPreparation(
        fixedComponents: [IngredientDraft],
        solventType: NonAqueousSolventType,
        usesIodideComplex: Bool
    ) -> IodideComplexPreparation? {
        guard usesIodideComplex, solventType.isViscous else { return nil }

        let iodideComponents = fixedComponents.filter(isIodideComponent)
        let iodineComponents = fixedComponents.filter(isIodineComponent)
        guard !iodideComponents.isEmpty, !iodineComponents.isEmpty else { return nil }

        let iodideMass = iodideComponents.compactMap(componentMassG).reduce(0, +)
        let iodineMass = iodineComponents.compactMap(componentMassG).reduce(0, +)
        guard iodideMass > 0 || iodineMass > 0 else { return nil }

        let explicitWaterMass = fixedComponents
            .filter { PurifiedWaterHeuristics.isPurifiedWater($0) }
            .compactMap(componentMassG)
            .reduce(0, +)
        let minimumWaterMass = solventType == .glycerin
            ? iodideMass * 1.5
            : (iodideMass + iodineMass)
        let supplementalWaterMass = max(0, minimumWaterMass - explicitWaterMass)

        return IodideComplexPreparation(
            iodineMassG: iodineMass,
            iodideMassG: iodideMass,
            waterMl: supplementalWaterMass,
            waterMassG: supplementalWaterMass,
            hasExplicitWater: explicitWaterMass > 0,
            iodineNames: iodineComponents.map { $0.displayName.isEmpty ? latinName($0) : $0.displayName },
            iodideNames: iodideComponents.map { $0.displayName.isEmpty ? latinName($0) : $0.displayName }
        )
    }

    private func waterSolubleInOilySolventNames(_ ingredients: [IngredientDraft]) -> [String] {
        ingredients.compactMap { ingredient in
            guard WaterSolubilityHeuristics.hasExplicitWaterSolubility(ingredient.refSolubility) else { return nil }
            return ingredient.displayName.isEmpty ? latinName(ingredient) : ingredient.displayName
        }
    }

    private func hasPotentialInsolubleResidue(_ ingredient: IngredientDraft, solventType: NonAqueousSolventType) -> Bool {
        if ingredient.unit.rawValue != "g" { return false }
        let solubility = normalized((ingredient.refSolubility ?? ""))
        if solubility.isEmpty { return false }

        let negative = solubility.contains("нерозчин")
            || solubility.contains("insoluble")
            || solubility.contains("praktically insoluble")
            || solubility.contains("практично нерозчин")
        guard negative else { return false }

        switch solventType {
        case .ethanol:
            return !solubility.contains("спирт") && !solubility.contains("alcohol") && !solubility.contains("ethanol")
        case .glycerin:
            return !solubility.contains("гліцерин") && !solubility.contains("glycer")
        case .fattyOil, .mineralOil, .vinylin, .viscousOther:
            return !solubility.contains("ол") && !solubility.contains("oil")
        case .ether:
            return !solubility.contains("ефір") && !solubility.contains("ether")
        case .chloroform:
            return !solubility.contains("хлороформ") && !solubility.contains("chloroform")
        case .volatileOther:
            return true
        }
    }

    private func isPoorlySoluble(_ ingredient: IngredientDraft, solventType: NonAqueousSolventType) -> Bool {
        if ingredient.unit.rawValue != "g" { return false }
        if hasPotentialInsolubleResidue(ingredient, solventType: solventType) { return true }

        let solubility = normalized((ingredient.refSolubility ?? ""))
        if solubility.contains("мало розчин") || solubility.contains("slightly soluble") || solubility.contains("важко розчин") {
            return true
        }

        let hay = normalizedHay(ingredient)
        if solventType == .glycerin, hay.contains("tetrabor") {
            return true
        }

        return false
    }

    private func requiresGentleHeating(solventType: NonAqueousSolventType, ingredients: [IngredientDraft]) -> Bool {
        guard solventType.isViscous else { return false }
        return ingredients.contains { isPoorlySoluble($0, solventType: solventType) }
    }

    private func normalizedHay(_ ingredient: IngredientDraft) -> String {
        [
            ingredient.refNameLatNom,
            ingredient.refInnKey,
            ingredient.displayName,
            ingredient.refInteractionNotes,
            ingredient.refSolubility
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    }

    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func latinName(_ ingredient: IngredientDraft) -> String {
        let raw = (ingredient.refNameLatNom ?? ingredient.displayName).trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? ingredient.displayName : raw
    }

    private func format(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000
        let integer = rounded.rounded()
        if abs(rounded - integer) < 0.0001 {
            return String(Int(integer))
        }
        if abs(rounded * 10 - (rounded * 10).rounded()) < 0.0001 {
            return String(format: "%.1f", rounded)
        }
        if abs(rounded * 100 - (rounded * 100).rounded()) < 0.0001 {
            return String(format: "%.2f", rounded)
        }
        return String(format: "%.3f", rounded)
    }
}
