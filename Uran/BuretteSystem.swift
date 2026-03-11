import Foundation

// MARK: - Burette System (Concentrated solutions via burette)

enum BuretteSystem {
    enum MeniscusEdge: String, Hashable {
        case lower
        case upper

        var guidance: String {
            switch self {
            case .lower:
                return "Для безбарвних розчинів рівень відлічують по нижньому меніску."
            case .upper:
                return "Для інтенсивно забарвлених розчинів рівень відлічують по верхньому меніску."
            }
        }
    }

    // 1:x where x = ml per 1 g of solute (e.g. 20% solution => 1:5)
    struct Concentrate: Identifiable, Hashable {
        let id: String
        let titleRu: String
        let markers: [String] // normalized needles
        let mlPerG: Double // ratio part (x)
        let isColored: Bool

        init(titleRu: String, markers: [String], mlPerG: Double, isColored: Bool = false) {
            self.titleRu = titleRu
            self.markers = markers.map { $0.lowercased() }
            self.mlPerG = mlPerG
            self.isColored = isColored
            id = titleRu
        }

        var ratioTitle: String {
            if mlPerG == floor(mlPerG) {
                return "1:\(Int(mlPerG))"
            }
            return "1:\(mlPerG)"
        }

        var concentrationPercent: Double {
            100.0 / mlPerG
        }

        var concentrationFraction: Double {
            concentrationPercent / 100.0
        }

        var concentrationTitle: String {
            BuretteSystem.percentText(concentrationPercent)
        }

        var meniscusEdge: MeniscusEdge {
            isColored ? .upper : .lower
        }
    }

    struct ManufacturingRecipe: Identifiable, Hashable {
        let id: String
        let title: String
        let concentrationPercent: Double
        let batchVolumeMl: Double
        let kuoMlPerG: Double
        let isColored: Bool
        let notes: [String]
        let qualityControlNote: String

        init(
            title: String,
            concentrationPercent: Double,
            batchVolumeMl: Double = 500.0,
            kuoMlPerG: Double,
            isColored: Bool = false,
            notes: [String] = [],
            qualityControlNote: String = "Після виготовлення обов’язково перевірити концентрацію титруванням або рефрактометрично."
        ) {
            self.id = title
            self.title = title
            self.concentrationPercent = concentrationPercent
            self.batchVolumeMl = batchVolumeMl
            self.kuoMlPerG = kuoMlPerG
            self.isColored = isColored
            self.notes = notes
            self.qualityControlNote = qualityControlNote
        }

        var ratioMlPerG: Double {
            100.0 / concentrationPercent
        }

        var ratioTitle: String {
            if ratioMlPerG == floor(ratioMlPerG) {
                return "1:\(Int(ratioMlPerG))"
            }
            return "1:\(BuretteSystem.format(ratioMlPerG))"
        }

        var soluteMassG: Double {
            batchVolumeMl * concentrationPercent / 100.0
        }

        var waterVolumeMl: Double {
            batchVolumeMl - (soluteMassG * kuoMlPerG)
        }

        var meniscusEdge: MeniscusEdge {
            isColored ? .upper : .lower
        }
    }

    struct RuleHint: Identifiable, Hashable {
        let id: String
        let title: String
        let detail: String

        init(title: String, detail: String) {
            self.id = title
            self.title = title
            self.detail = detail
        }
    }

    // Operational catalog for automatic burette calculations in prescriptions.
    static let concentrates: [Concentrate] = [
        .init(
            titleRu: "Раствор кофеина-натрия бензоата 10%",
            markers: ["coffeini-natrii benzo", "caffeine-natrii benzo", "кофеин-натрия бензо"],
            mlPerG: 10
        ),
        .init(
            titleRu: "Раствор натрия бромида 20%",
            markers: ["natrii brom", "sodium brom", "натрия бромид", "натрію бромід"],
            mlPerG: 5
        ),
        .init(
            titleRu: "Раствор магния сульфата 20%",
            markers: ["magnesii sulf", "magnesium sulf", "магния сульфат", "магнію сульфат"],
            mlPerG: 5
        ),
        .init(
            titleRu: "Раствор калия иодида 20%",
            markers: ["kalii iod", "potassium iod", "калия йодид", "калия иодид", "калію йодид", "калію іодид"],
            mlPerG: 5,
            isColored: true
        ),
        .init(
            titleRu: "Раствор натрия гидрокарбоната 5%",
            markers: ["natrii hydrocarbon", "natrii bicarbon", "sodium bicarb", "sodium hydrogenocarbon", "натрия гидрокарбонат", "натрію гідрокарбонат"],
            mlPerG: 20
        ),
        .init(
            titleRu: "Раствор натрия салицилата 10%",
            markers: ["natrii salicyl", "sodium salicyl", "натрия салицилат", "натрію саліцилат"],
            mlPerG: 10
        ),
        .init(
            titleRu: "Раствор кальция хлорида 20%",
            markers: ["calcii chlor", "calcium chlor", "кальция хлорид", "кальцію хлорид"],
            mlPerG: 5
        ),
        .init(
            titleRu: "Раствор глюкозы 50%",
            markers: ["glucos", "glucose", "dextros", "глюкоз", "глюкоза"],
            mlPerG: 2
        ),
        .init(
            titleRu: "Раствор гексаметилентетрамина 20%",
            markers: ["hexamethylenetetramin", "urotropin", "уротроп", "urotropinum"],
            mlPerG: 5
        ),
        .init(
            titleRu: "Раствор калия бромида 20%",
            markers: ["kalii brom", "potassium brom", "калия бромид", "калію бромід"],
            mlPerG: 5
        ),
        .init(
            titleRu: "Раствор натрия бензоата 10%",
            markers: ["natrii benzo", "sodium benzo", "натрия бензоат", "натрію бензоат"],
            mlPerG: 10
        )
    ]

    static let manufacturingRecipes: [ManufacturingRecipe] = [
        .init(
            title: "Розчин натрію броміду 10%",
            concentrationPercent: 10,
            kuoMlPerG: 0.23,
            notes: ["Розчин 1:10.", "Використовують мірну колбу 500 мл або розраховану кількість води за КУО."]
        ),
        .init(
            title: "Розчин натрію броміду 20%",
            concentrationPercent: 20,
            kuoMlPerG: 0.23,
            notes: ["Розчин 1:5.", "Підходить як концентрат для бюреточної системи."]
        ),
        .init(
            title: "Розчин магнію сульфату 20%",
            concentrationPercent: 20,
            kuoMlPerG: 0.50,
            notes: ["Високий КУО, тому об’єм води рахують обов’язково.", "Після розчинення профільтрувати у бюреточну установку."],
            qualityControlNote: "Після виготовлення обов’язково перевірити концентрацію рефрактометрично або титруванням."
        ),
        .init(
            title: "Розчин натрію бензоату 10%",
            concentrationPercent: 10,
            kuoMlPerG: 0.60,
            notes: ["Розчин 1:10.", "Через значний КУО воду попередньо розраховують."]
        ),
        .init(
            title: "Розчин натрію гідрокарбонату 5%",
            concentrationPercent: 5,
            kuoMlPerG: 0.30,
            notes: ["Розчин 1:20.", "Для концентратів дотримуватися локального регламенту контролю якості."]
        )
    ]

    static let dosingRules: [RuleHint] = [
        .init(
            title: "Меніск",
            detail: "Для безбарвних розчинів (натрію бромід, магнію сульфат) відлік ведуть по нижньому меніску; для забарвлених (йод, калію перманганат) — по верхньому."
        ),
        .init(
            title: "Відмірювання",
            detail: "Заборонено працювати «від поділки до поділки». Рідину зливають тільки від нуля або встановленого рівня до повного закінчення зливу."
        ),
        .init(
            title: "Час зливу",
            detail: "Після припинення струменя витримують 2–3 секунди, щоб врахувати останню краплю."
        )
    ]

    static let microxtureWorkflowLines: [String] = [
        "1. Підібрати концентрати зі списку бюретки відповідно до інгредієнтів рецепта.",
        "2. Для кожної речовини розрахувати об’єм концентрату за формулою V_conc = m / C або еквівалентно V_conc = m × n для розчину 1:n.",
        "3. Воду очищену рахувати за формулою V_H2O = V_total - ΣV_концентратів - ΣV_інших рідин.",
        "4. При використанні концентратів КУО сухих речовин не застосовують, оскільки речовини вже введені в розчиненому стані."
    ]

    static let stockQualityControlLines: [String] = [
        "Після виготовлення концентрат підлягає повному хімічному контролю: ідентифікація, кількісний вміст, прозорість.",
        "Кількісний вміст контролюють титруванням або рефрактометрією.",
        "Допустиме відхилення: до 20% включно — не більше ±2%; понад 20% — не більше ±1%."
    ]

    static let finalMixtureQualityControlLines: [String] = [
        "Прозорість",
        "Відсутність механічних включень",
        "Відповідність об’єму",
        "За потреби — вибірковий хімічний контроль готової мікстури за локальними НД."
    ]

    static let labelingLines: [String] = [
        "Етикетка повинна містити: назву розчину, концентрацію, дату виготовлення.",
        "Додають номер серії (за журналом), результат аналізу або титр, підпис того, хто виготовив і перевірив.",
        "Перед застосуванням перевірити прозорість та відсутність осаду/пластівців."
    ]

    static let preparationLines: [String] = [
        "Перед роботою підготувати мірну колбу або балон та етикетки.",
        "Сливні крани бюреток протерти спирто-ефірною сумішшю 1:1.",
        "Зберігати за умовами, визначеними для конкретного розчину."
    ]

    static let magnesiumSulfateExampleLines: [String] = [
        "Magnesii sulfas = 100,0 g",
        "Aqua purificata = 450 ml (500 - (100 × 0,5))",
        "Загальний об’єм = 500 ml",
        "Ключові операції: розчинити, довести до об’єму, профільтрувати у бюреточну установку, перевірити концентрацію рефрактометрично."
    ]

    struct LineItem: Hashable {
        let concentrate: Concentrate
        let soluteMassG: Double
        let concentrateVolumeMl: Double
    }

    struct Result: Hashable {
        var items: [LineItem] = []
        var ppkLines: [String] = []
        var techSteps: [TechStep] = []
        var matchedIngredientIds: Set<UUID> = []
        var issues: [RxIssue] = []

        var totalConcentrateVolumeMl: Double {
            items.reduce(0) { $0 + $1.concentrateVolumeMl }
        }

        var isEmpty: Bool { items.isEmpty }
    }

    // MARK: Public API

    /// Main entry: computes burette block (PPK + TechPlan) from a recipe draft.
    static func evaluateBurette(draft: ExtempRecipeDraft) -> Result {
        guard draft.useBuretteSystem else { return Result() }

        let ingredients = draft.ingredients
        var result = Result()

        // 1) collect matches and total grams per concentrate
        var gramsByConcentrate: [Concentrate: Double] = [:]

        for ing in ingredients {
            if ing.isAd || ing.isQS { continue }
            let hay = normalizedHaystack(for: ing)
            guard let matched = concentrates.first(where: { matches(hay: hay, concentrate: $0) }) else {
                continue
            }

            guard let g = deriveSoluteMassG(for: ing, draft: draft), g > 0 else {
                result.issues.append(
                    RxIssue(
                        code: "burette.mass_derivation_failed",
                        severity: .blocking,
                        message: "Неможливо визначити масу речовини для бюреточного концентрату"
                    )
                )
                continue
            }

            let ml = g * matched.mlPerG
            guard ml > 0 else {
                result.issues.append(
                    RxIssue(
                        code: "burette.invalid_item",
                        severity: .blocking,
                        message: "Для бюреточного концентрату отримано нульовий або некоректний об’єм"
                    )
                )
                continue
            }

            gramsByConcentrate[matched, default: 0] += g
            result.matchedIngredientIds.insert(ing.id)
        }

        let items: [LineItem] = gramsByConcentrate
            .filter { $0.value > 0 }
            .sorted { $0.key.titleRu < $1.key.titleRu }
            .map { c, g in
                let ml = g * c.mlPerG
                return LineItem(concentrate: c, soluteMassG: g, concentrateVolumeMl: ml)
            }
            .filter { $0.soluteMassG > 0 && $0.concentrateVolumeMl > 0 }

        guard !items.isEmpty else { return result }
        result.items = items

        // 2) Build PPK lines
        var lines: [String] = []
        lines.append("Бюретка (концентровані розчини):")
        for it in items {
            lines.append("\(it.concentrate.titleRu) (\(it.concentrate.ratioTitle)): \(format(it.soluteMassG)) g → \(format(it.concentrateVolumeMl)) ml")
        }
        result.ppkLines = lines

        // 3) Build TechPlan steps
        // One step per concentrate (water/ad logic is handled by liquid blocks).
        var steps: [TechStep] = []
        for it in items {
            steps.append(
                TechStep(
                    kind: .mixing,
                    title: "Відміряти бюреткою: \(it.concentrate.titleRu) — \(format(it.concentrateVolumeMl)) ml",
                    notes: nil,
                    ingredientIds: [],
                    isCritical: false
                )
            )
        }
        result.techSteps = steps

        return result
    }

    // MARK: Matching

    private static func matches(hay: String, concentrate: Concentrate) -> Bool {
        for marker in concentrate.markers where hay.contains(marker) {
            return true
        }
        return false
    }

    private static func normalizedHaystack(for ingredient: IngredientDraft) -> String {
        [
            ingredient.displayName,
            ingredient.refNameLatNom ?? "",
            ingredient.refInnKey ?? ""
        ]
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "ё", with: "е")
    }

    private static func normalized(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
    }

    // MARK: Units / conversions

    /// Returns mass in grams if the ingredient unit is mass-like.
    /// If unit is not mass (ml, etc) -> nil (burette logic is solute mass driven).
    private static func massInGramsIfPossible(_ ing: IngredientDraft) -> Double? {
        let u = ing.unit.rawValue.lowercased()

        // common mass units
        if u == "g" || u == "гр" || u == "gram" || u == "grams" {
            return ing.amountValue
        }
        if u == "mg" || u == "мг" {
            return ing.amountValue / 1000.0
        }
        if u == "mcg" || u == "мкг" || u == "µg" {
            return ing.amountValue / 1_000_000.0
        }
        if u == "kg" || u == "кг" {
            return ing.amountValue * 1000.0
        }

        // if it is a volume unit -> not applicable here
        if u == "ml" || u == "мл" || u == "l" || u == "л" {
            return nil
        }

        // unknown unit -> safest: do not include
        return nil
    }

    private static func deriveSoluteMassG(for ingredient: IngredientDraft, draft: ExtempRecipeDraft) -> Double? {
        if ingredient.presentationKind == .solution,
           let solutionPercent = draft.solutionDisplayPercent(for: ingredient),
           let solutionVolume = draft.solutionVolumeMl(for: ingredient),
           solutionPercent > 0,
           solutionVolume > 0
        {
            return solutionVolume * solutionPercent / 100.0
        }

        if ingredient.unit.rawValue == "g", ingredient.amountValue > 0 {
            return ingredient.amountValue
        }

        return massInGramsIfPossible(ingredient)
    }

    // MARK: Formatting

    static func format(_ v: Double) -> String {
        // pharma-like formatting: trim trailing zeros, 3 decimals max
        let rounded = (v * 1000).rounded() / 1000
        if abs(rounded - rounded.rounded()) < 0.0001 {
            return String(Int(rounded))
        }
        var s = String(format: "%.3f", rounded)
        while s.contains(".") && (s.hasSuffix("0") || s.hasSuffix(".")) {
            s.removeLast()
            if s.hasSuffix(".") {
                s.removeLast()
                break
            }
        }
        return s.replacingOccurrences(of: ".", with: ",")
    }

    static func percentText(_ value: Double) -> String {
        "\(format(value))%"
    }
}
