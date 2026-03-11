import Foundation

enum SubstanceInteractionRule: String, Hashable {
    case incompatibleWithAcids
    case incompatibleWithAlkalies
    case incompatibleWithAlkaloidSalts
}

enum SubstanceStorageRuleFlag: String, Hashable {
    case dryPlace
    case safeStorage
    case coolPlace
}

enum SubstanceTechnologyRule: String, Hashable {
    case avoidProlongedHeatingInSolution
    case acidifiesInGlycerin
    case doseByMass
    case requiresHeatingForDissolution
    case requiresBoilingWaterDissolution
    case furacilinAddSodiumChloride
    case requiresFreshDistilledWater
    case avoidPaperFilter
    case oxidizerHandleSeparately
    case iodideComplexInWater
    case iodideComplexFormer
    case fattyOilWarmWaterBath40to50
    case fattyOilDryHeatSterilization
    case fattyOilLipophilicDissolution
    case fattyOilWaterSolublesRequireEmulsion
    case rancidityRisk
}

struct SubstancePropertyOverride {
    let aliases: [String]
    let solubility: String?
    let kuoMlPerG: Double?
    let storage: String?
    let interactionNotes: String?
    let standardComposition: String?
    let vrdG: Double?
    let vsdG: Double?
    let listA: Bool?
    let isNarcotic: Bool?
    let interactionRules: Set<SubstanceInteractionRule>
    let storageRules: Set<SubstanceStorageRuleFlag>
    let technologyRules: Set<SubstanceTechnologyRule>
}

enum SubstancePropertyCatalog {
    nonisolated private static let entries: [SubstancePropertyOverride] = [
        SubstancePropertyOverride(
            aliases: [
                "hexamethylenetetraminum",
                "methenamine",
                "metenamin",
                "метенамин",
                "уротропин"
            ],
            solubility: "1:1.5 (очень легко растворим в воде)",
            kuoMlPerG: 0.78,
            storage: "DryPlace; гигроскопичен, хранить в сухом месте",
            interactionNotes: "IncompatibleWithAcids; разлагается в кислой среде с выделением формальдегида. Несовместим с солями алкалоидов (возможен осадок).",
            standardComposition: nil,
            vrdG: nil,
            vsdG: nil,
            listA: nil,
            isNarcotic: nil,
            interactionRules: [.incompatibleWithAcids, .incompatibleWithAlkaloidSalts],
            storageRules: [.dryPlace],
            technologyRules: [.avoidProlongedHeatingInSolution]
        ),
        SubstancePropertyOverride(
            aliases: [
                "codeini phosphas",
                "codeini phosphatis",
                "codeine phosphate",
                "codeine phosphas",
                "кодеина фосфат",
                "кодеин фосфат"
            ],
            solubility: "1:4 (легко растворим в воде)",
            kuoMlPerG: 0.75,
            storage: "SafeStorage; хранить в сейфе или укрепленном шкафу по правилам ПКУ/наркотических средств",
            interactionNotes: "IncompatibleWithAlkalies; щелочи осаждают кодеин-основание из раствора фосфата.",
            standardComposition: nil,
            vrdG: nil,
            vsdG: nil,
            listA: true,
            isNarcotic: true,
            interactionRules: [.incompatibleWithAlkalies],
            storageRules: [.safeStorage],
            technologyRules: []
        ),
        SubstancePropertyOverride(
            aliases: [
                "natrii tetraboras",
                "natrii tetraboratis",
                "sodium tetraborate",
                "borax",
                "натрия тетраборат",
                "бура"
            ],
            solubility: nil,
            kuoMlPerG: nil,
            storage: nil,
            interactionNotes: "IncompatibleWithAlkaloids; при растворении в глицерине образует глицероборную кислоту, возможен сдвиг pH.",
            standardComposition: nil,
            vrdG: nil,
            vsdG: nil,
            listA: nil,
            isNarcotic: nil,
            interactionRules: [],
            storageRules: [],
            technologyRules: [.acidifiesInGlycerin]
        ),
        SubstancePropertyOverride(
            aliases: [
                "phenolum purum",
                "phenoli puri",
                "phenolum",
                "phenol",
                "acidum carbolicum",
                "acidi carbolici",
                "carbolic acid",
                "кислота карболовая",
                "карболова кислота",
                "фенол"
            ],
            solubility: "Мало розчинний у воді; добре розчинний у жирних оліях (1:2). За концентрації близько 2% у масляних системах розчиняється швидко.",
            kuoMlPerG: nil,
            storage: "LightProtected; у щільно закупореній тарі, в захищеному від світла місці (окиснюється на світлі й повітрі).",
            interactionNotes: "CausticComponent; токсичен при превышении дозировки. Викликає хімічні опіки шкіри, працювати в рукавичках.",
            standardComposition: nil,
            vrdG: 0.05,
            vsdG: 0.15,
            listA: true,
            isNarcotic: nil,
            interactionRules: [],
            storageRules: [],
            technologyRules: []
        ),
        SubstancePropertyOverride(
            aliases: [
                "oleum helianthi",
                "olei helianthi",
                "helianthi oleum",
                "sunflower oil",
                "масло подсолнечное",
                "олія соняшникова"
            ],
            solubility: "Insoluble у воді; мало розчинне у спирті; легко розчинне в ефірі та хлороформі.",
            kuoMlPerG: nil,
            storage: "CoolPlace; у прохолодному, захищеному від світла місці. RancidityRisk (ризик прогоркання при світлі/нагріванні).",
            interactionNotes: "В'язкий жирний розчинник. У технології дозувати за масою; при об'ємному призначенні перерахунок через густину 0.92 g/ml. Жиророзчинні речовини (камфора, ментол, фенол, тимол) розчиняти в теплому маслі на водяній бані 40-50°C. Водорозчинні речовини безпосередньо в масло не вводити (потрібна емульсійна технологія). Для нанесення на рани/слизові стерилізувати сухим жаром: 180°C 30 хв або 160°C 45 хв.",
            standardComposition: nil,
            vrdG: nil,
            vsdG: nil,
            listA: nil,
            isNarcotic: nil,
            interactionRules: [],
            storageRules: [.coolPlace],
            technologyRules: [
                .doseByMass,
                .fattyOilWarmWaterBath40to50,
                .fattyOilDryHeatSterilization,
                .fattyOilLipophilicDissolution,
                .fattyOilWaterSolublesRequireEmulsion,
                .rancidityRisk
            ]
        ),
        SubstancePropertyOverride(
            aliases: [
                "solutio lugoli cum glycerino",
                "solutionis lugoli cum glycerino",
                "lugol s solution with glycerin",
                "lugol solution with glycerin",
                "раствор люголя в глицерине"
            ],
            solubility: nil,
            kuoMlPerG: nil,
            storage: nil,
            interactionNotes: nil,
            standardComposition: "ГФ XI, на 100,0 g: Iodi crystallisati 1,0; Kalii iodidi 2,0; Aquae purificatae 3 ml; Glycerini ad 100,0.",
            vrdG: nil,
            vsdG: nil,
            listA: nil,
            isNarcotic: nil,
            interactionRules: [],
            storageRules: [],
            technologyRules: []
        ),
        SubstancePropertyOverride(
            aliases: [
                "tween 80",
                "tween-80",
                "tween80",
                "polysorbate 80",
                "polysorbatum 80",
                "полисорбат 80",
                "твин 80",
                "твин-80"
            ],
            solubility: nil,
            kuoMlPerG: nil,
            storage: nil,
            interactionNotes: "Несумісний з саліцилатами, фенолами та похідними параоксибензойної кислоти; перевіряти сумісність емульсійних систем.",
            standardComposition: nil,
            vrdG: nil,
            vsdG: nil,
            listA: nil,
            isNarcotic: nil,
            interactionRules: [],
            storageRules: [],
            technologyRules: []
        ),
        SubstancePropertyOverride(
            aliases: [
                "span 80",
                "span-80",
                "span80",
                "sorbitan monooleate",
                "sorbitani monooleas",
                "сорбитан моноолеат",
                "спан 80",
                "спан-80"
            ],
            solubility: nil,
            kuoMlPerG: nil,
            storage: nil,
            interactionNotes: "Несумісний з саліцилатами, фенолами та похідними параоксибензойної кислоти; перевіряти сумісність емульсійних систем.",
            standardComposition: nil,
            vrdG: nil,
            vsdG: nil,
            listA: nil,
            isNarcotic: nil,
            interactionRules: [],
            storageRules: [],
            technologyRules: []
        ),
        SubstancePropertyOverride(
            aliases: [
                "furacilinum",
                "furacilini",
                "furacilin",
                "nitrofuralum",
                "nitrofural",
                "nitrofurazon"
            ],
            solubility: "Дуже мало розчинний у воді (близько 1:4200), краще — у гарячій/киплячій воді.",
            kuoMlPerG: nil,
            storage: "LightProtected; у щільно закритій тарі, захищати від світла.",
            interactionNotes: "Для водних розчинів розчиняти у гарячій/киплячій воді; за потреби додати NaCl 0,9% для ізотонування.",
            standardComposition: nil,
            vrdG: nil,
            vsdG: nil,
            listA: nil,
            isNarcotic: nil,
            interactionRules: [],
            storageRules: [],
            technologyRules: [.requiresBoilingWaterDissolution, .furacilinAddSodiumChloride]
        ),
        SubstancePropertyOverride(
            aliases: [
                "acidum boricum",
                "acidi borici",
                "boric acid",
                "борна кислота",
                "кислота борная"
            ],
            solubility: "Розчинний у воді, значно краще розчиняється при нагріванні.",
            kuoMlPerG: nil,
            storage: nil,
            interactionNotes: nil,
            standardComposition: nil,
            vrdG: nil,
            vsdG: nil,
            listA: nil,
            isNarcotic: nil,
            interactionRules: [],
            storageRules: [],
            technologyRules: [.requiresHeatingForDissolution]
        ),
        SubstancePropertyOverride(
            aliases: [
                "aethacridini lactas",
                "aethacridini lactatis",
                "ethacridine lactate",
                "етакридин",
                "этакридин"
            ],
            solubility: "Розчинність у воді близько 1:50; при потребі використовувати підігрів.",
            kuoMlPerG: nil,
            storage: "LightProtected; у захищеному від світла місці.",
            interactionNotes: "Несумісний з лугами, хлоридами та сульфатами.",
            standardComposition: nil,
            vrdG: nil,
            vsdG: nil,
            listA: nil,
            isNarcotic: nil,
            interactionRules: [.incompatibleWithAlkalies],
            storageRules: [],
            technologyRules: [.requiresHeatingForDissolution]
        ),
        SubstancePropertyOverride(
            aliases: [
                "papaverini hydrochloridum",
                "papaverini hydrochloridi",
                "papaverine hydrochloride",
                "папаверину гідрохлорид",
                "папаверина гидрохлорид"
            ],
            solubility: "Розчинність у воді близько 1:40; для стабільного прозорого розчину використовувати підігрів.",
            kuoMlPerG: nil,
            storage: "LightProtected; зберігати в захищеному від світла місці.",
            interactionNotes: "Розчиняти у гарячій Aqua purificata (70-80°C) до повної прозорості.",
            standardComposition: nil,
            vrdG: nil,
            vsdG: nil,
            listA: nil,
            isNarcotic: nil,
            interactionRules: [],
            storageRules: [],
            technologyRules: [.requiresHeatingForDissolution]
        ),
        SubstancePropertyOverride(
            aliases: [
                "argenti nitras",
                "argenti nitratis",
                "silver nitrate",
                "нітрат срібла",
                "нитрат серебра"
            ],
            solubility: nil,
            kuoMlPerG: nil,
            storage: "LightProtected; зберігати в оранжевому склі, захищати від світла.",
            interactionNotes: "Потребує свіжоперегнаної води без хлоридів; паперову фільтрацію уникати.",
            standardComposition: nil,
            vrdG: 0.03,
            vsdG: 0.10,
            listA: true,
            isNarcotic: nil,
            interactionRules: [],
            storageRules: [.safeStorage],
            technologyRules: [.requiresFreshDistilledWater, .avoidPaperFilter]
        ),
        SubstancePropertyOverride(
            aliases: [
                "kalii permanganas",
                "kalii permanganatis",
                "potassium permanganate",
                "калію перманганат",
                "калия перманганат"
            ],
            solubility: nil,
            kuoMlPerG: nil,
            storage: "DryPlace; зберігати окремо від органічних речовин.",
            interactionNotes: "Сильний окисник.",
            standardComposition: nil,
            vrdG: nil,
            vsdG: nil,
            listA: nil,
            isNarcotic: nil,
            interactionRules: [],
            storageRules: [.dryPlace],
            technologyRules: [.oxidizerHandleSeparately]
        ),
        SubstancePropertyOverride(
            aliases: [
                "hydrogenii peroxydum",
                "hydrogenii peroxydi",
                "hydrogen peroxide",
                "перекис водню",
                "перекись водорода",
                "пергідроль",
                "пергидроль"
            ],
            solubility: nil,
            kuoMlPerG: nil,
            storage: "LightProtected; зберігати в щільно закупореній тарі з темного скла.",
            interactionNotes: "Окисник; уникати контакту з органічними матеріалами під час фільтрації.",
            standardComposition: nil,
            vrdG: nil,
            vsdG: nil,
            listA: nil,
            isNarcotic: nil,
            interactionRules: [],
            storageRules: [.safeStorage],
            technologyRules: [.oxidizerHandleSeparately, .avoidPaperFilter]
        ),
        SubstancePropertyOverride(
            aliases: [
                "iodum",
                "iodi",
                "iodine",
                "йод"
            ],
            solubility: "Дуже мало розчинний у воді; розчиняється через комплекс із йодидом калію/натрію.",
            kuoMlPerG: nil,
            storage: "LightProtected",
            interactionNotes: "У водних системах спочатку розчиняти через KI/NaI.",
            standardComposition: nil,
            vrdG: nil,
            vsdG: nil,
            listA: nil,
            isNarcotic: nil,
            interactionRules: [],
            storageRules: [],
            technologyRules: [.iodideComplexInWater]
        ),
        SubstancePropertyOverride(
            aliases: [
                "kalii iodidum",
                "kalii iodidi",
                "potassium iodide",
                "калия йодид",
                "калію йодид"
            ],
            solubility: nil,
            kuoMlPerG: nil,
            storage: nil,
            interactionNotes: nil,
            standardComposition: nil,
            vrdG: nil,
            vsdG: nil,
            listA: nil,
            isNarcotic: nil,
            interactionRules: [],
            storageRules: [],
            technologyRules: [.iodideComplexFormer]
        )
    ]

    nonisolated static func overrideFor(
        innKey: String?,
        nameLatNom: String?,
        nameRu: String?
    ) -> SubstancePropertyOverride? {
        let candidates = Set(normalizedCandidates(innKey: innKey, nameLatNom: nameLatNom, nameRu: nameRu))
        guard !candidates.isEmpty else { return nil }

        return entries.first { entry in
            let aliases = Set(entry.aliases.map(normalize))
            return !aliases.isDisjoint(with: candidates)
        }
    }

    nonisolated static func mergedReferenceValues(
        innKey: String?,
        nameLatNom: String?,
        nameRu: String?,
        solubility: String?,
        kuoMlPerG: Double?,
        storage: String?,
        interactionNotes: String?,
        vrdG: Double?,
        vsdG: Double?,
        listA: Bool,
        isNarcotic: Bool
    ) -> (
        solubility: String?,
        kuoMlPerG: Double?,
        storage: String?,
        interactionNotes: String?,
        vrdG: Double?,
        vsdG: Double?,
        listA: Bool,
        isNarcotic: Bool
    ) {
        guard let overrideValue = overrideFor(innKey: innKey, nameLatNom: nameLatNom, nameRu: nameRu) else {
            return (solubility, kuoMlPerG, storage, interactionNotes, vrdG, vsdG, listA, isNarcotic)
        }

        let mergedStorage = mergeText(storage, overrideValue.storage)
        let mergedInteractions = mergeText(interactionNotes, overrideValue.interactionNotes)

        return (
            solubility: overrideValue.solubility ?? solubility,
            kuoMlPerG: overrideValue.kuoMlPerG ?? kuoMlPerG,
            storage: mergedStorage,
            interactionNotes: mergedInteractions,
            vrdG: overrideValue.vrdG ?? vrdG,
            vsdG: overrideValue.vsdG ?? vsdG,
            listA: overrideValue.listA ?? listA,
            isNarcotic: overrideValue.isNarcotic ?? isNarcotic
        )
    }

    nonisolated static func looksLikeAlkaloidSalt(
        innKey: String?,
        nameLatNom: String?,
        nameRu: String?
    ) -> Bool {
        let hay = normalizedCandidates(innKey: innKey, nameLatNom: nameLatNom, nameRu: nameRu).joined(separator: " ")
        guard !hay.isEmpty else { return false }

        let alkaloidMarkers = [
            "atropin", "morphin", "codein", "papaverin", "strychnin",
            "platyphyllin", "pilocarpin", "ephedrin", "theobromin",
            "дионин", "атропин", "морфин", "кодеин", "папаверин",
            "стрихнин", "платифиллин", "пилокарпин", "эфедрин"
        ]
        let saltMarkers = [
            "hydrochlorid", "hydrobromid", "sulfas", "sulfat",
            "nitras", "nitrat", "benzoas", "salicylas", "chlorid",
            "гидрохлорид", "гидробромид", "сульфат", "нитрат",
            "бензоат", "салицилат", "хлорид"
        ]

        return alkaloidMarkers.contains(where: hay.contains)
            && saltMarkers.contains(where: hay.contains)
    }

    nonisolated private static func normalizedCandidates(
        innKey: String?,
        nameLatNom: String?,
        nameRu: String?
    ) -> [String] {
        [innKey, nameLatNom, nameRu]
            .compactMap { value in
                let normalized = normalize(value)
                return normalized.isEmpty ? nil : normalized
            }
    }

    nonisolated private static func normalize(_ value: String?) -> String {
        guard let value else { return "" }

        let lowered = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)

        let filtered = lowered.replacingOccurrences(
            of: #"[^\p{L}\p{N}]+"#,
            with: " ",
            options: .regularExpression
        )

        let collapsed = filtered
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        return collapsed
    }

    nonisolated private static func mergeText(_ current: String?, _ overrideValue: String?) -> String? {
        let lhs = current?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rhs = overrideValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if lhs.isEmpty { return rhs.isEmpty ? nil : rhs }
        if rhs.isEmpty { return lhs }
        if lhs.localizedCaseInsensitiveContains(rhs) { return lhs }
        if rhs.localizedCaseInsensitiveContains(lhs) { return rhs }
        return lhs + " | " + rhs
    }
}

extension ExtempSubstance {
    nonisolated var propertyOverride: SubstancePropertyOverride? {
        SubstancePropertyCatalog.overrideFor(
            innKey: innKey,
            nameLatNom: nameLatNom,
            nameRu: nameRu
        )
    }
}

extension IngredientDraft {
    nonisolated var propertyOverride: SubstancePropertyOverride? {
        SubstancePropertyCatalog.overrideFor(
            innKey: refInnKey,
            nameLatNom: refNameLatNom,
            nameRu: displayName
        )
    }
}
