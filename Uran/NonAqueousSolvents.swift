import Foundation

enum NonAqueousSolventType: String, CaseIterable, Codable, Sendable {
    case ethanol
    case ether
    case chloroform
    case volatileOther
    case fattyOil
    case mineralOil
    case glycerin
    case vinylin
    case viscousOther

    var isVolatile: Bool {
        switch self {
        case .ethanol, .ether, .chloroform, .volatileOther:
            return true
        case .fattyOil, .mineralOil, .glycerin, .vinylin, .viscousOther:
            return false
        }
    }

    var isViscous: Bool {
        switch self {
        case .fattyOil, .mineralOil, .glycerin, .vinylin, .viscousOther:
            return true
        case .ethanol, .ether, .chloroform, .volatileOther:
            return false
        }
    }
}

enum NonAqueousHeatingAllowance: String, Codable, Sendable {
    case forbidden
    case conditional
    case waterBathOnly
}

enum NonAqueousCalculationMethod: String, Codable, Sendable {
    case mass
    case massVolume

    var title: String {
        switch self {
        case .mass:
            return "масовий"
        case .massVolume:
            return "масо-об'ємний"
        }
    }
}

struct NonAqueousSolventProfile: Sendable {
    let type: NonAqueousSolventType
    let title: String
    let density20C: Double?
    let isVolatile: Bool
    let isFlammable: Bool
    let heatingAllowed: NonAqueousHeatingAllowance
    let temperatureMaxC: Double?
    let defaultEthanolStrength: Int?
}

struct OfficinalAlcoholSolutionSpec: Sendable {
    let title: String
    let activeTitle: String
    let concentrationPercent: Double
    let ethanolStrength: Int
    let routeHint: String
}

struct ConcentrationControlProfile: Sendable {
    let title: String
    let concentrationPercent: Double?
    let dropsPerMlOverride: Double?
    let isConcentrationControlOnly: Bool
}

enum NonAqueousSolventCatalog {
    static let defaultEthanolSourceStrength = 96

    static func profile(
        for type: NonAqueousSolventType,
        ethanolStrength: Int? = nil
    ) -> NonAqueousSolventProfile {
        switch type {
        case .ethanol:
            let strength = normalizedEthanolStrength(ethanolStrength) ?? 90
            return NonAqueousSolventProfile(
                type: .ethanol,
                title: "Spiritus aethylici \(strength)%",
                density20C: ethanolDensity20C(for: strength),
                isVolatile: true,
                isFlammable: true,
                heatingAllowed: .forbidden,
                temperatureMaxC: nil,
                defaultEthanolStrength: 90
            )
        case .ether:
            return NonAqueousSolventProfile(
                type: .ether,
                title: "Aether",
                density20C: densityFromNormalizedTable(for: .ether) ?? 0.715,
                isVolatile: true,
                isFlammable: true,
                heatingAllowed: .forbidden,
                temperatureMaxC: nil,
                defaultEthanolStrength: nil
            )
        case .chloroform:
            return NonAqueousSolventProfile(
                type: .chloroform,
                title: "Chloroformium",
                density20C: densityFromNormalizedTable(for: .chloroform) ?? 1.480,
                isVolatile: true,
                isFlammable: false,
                heatingAllowed: .conditional,
                temperatureMaxC: 60,
                defaultEthanolStrength: nil
            )
        case .volatileOther:
            return NonAqueousSolventProfile(
                type: .volatileOther,
                title: "Volatile non-aqueous solvent",
                density20C: nil,
                isVolatile: true,
                isFlammable: true,
                heatingAllowed: .forbidden,
                temperatureMaxC: nil,
                defaultEthanolStrength: nil
            )
        case .fattyOil:
            return NonAqueousSolventProfile(
                type: .fattyOil,
                title: "Oleum pingue",
                density20C: 0.925,
                isVolatile: false,
                isFlammable: false,
                heatingAllowed: .waterBathOnly,
                temperatureMaxC: 50,
                defaultEthanolStrength: nil
            )
        case .mineralOil:
            return NonAqueousSolventProfile(
                type: .mineralOil,
                title: "Oleum Vaselini",
                density20C: densityFromNormalizedTable(for: .mineralOil) ?? 0.883,
                isVolatile: false,
                isFlammable: false,
                heatingAllowed: .waterBathOnly,
                temperatureMaxC: 50,
                defaultEthanolStrength: nil
            )
        case .glycerin:
            return NonAqueousSolventProfile(
                type: .glycerin,
                title: "Glycerinum",
                density20C: densityFromNormalizedTable(for: .glycerin) ?? 1.25,
                isVolatile: false,
                isFlammable: false,
                heatingAllowed: .waterBathOnly,
                temperatureMaxC: 50,
                defaultEthanolStrength: nil
            )
        case .vinylin:
            return NonAqueousSolventProfile(
                type: .vinylin,
                title: "Vinylinum",
                density20C: 0.912,
                isVolatile: false,
                isFlammable: false,
                heatingAllowed: .waterBathOnly,
                temperatureMaxC: 50,
                defaultEthanolStrength: nil
            )
        case .viscousOther:
            return NonAqueousSolventProfile(
                type: .viscousOther,
                title: "Viscous non-aqueous solvent",
                density20C: nil,
                isVolatile: false,
                isFlammable: false,
                heatingAllowed: .waterBathOnly,
                temperatureMaxC: 50,
                defaultEthanolStrength: nil
            )
        }
    }

    static func resolvedProfile(
        for ingredient: IngredientDraft?,
        type: NonAqueousSolventType,
        ethanolStrength: Int? = nil
    ) -> NonAqueousSolventProfile {
        let fallback = profile(for: type, ethanolStrength: ethanolStrength)
        guard let ingredient else { return fallback }

        let title = normalized((ingredient.refNameLatNom ?? "")).isEmpty
            ? fallback.title
            : (ingredient.refNameLatNom ?? fallback.title)

        return NonAqueousSolventProfile(
            type: type,
            title: title,
            density20C: ingredient.refDensity ?? fallback.density20C,
            isVolatile: ingredient.refIsVolatile ?? fallback.isVolatile,
            isFlammable: ingredient.refIsFlammable ?? fallback.isFlammable,
            heatingAllowed: ingredient.refHeatingAllowed ?? fallback.heatingAllowed,
            temperatureMaxC: ingredient.refHeatingTempMaxC ?? fallback.temperatureMaxC,
            defaultEthanolStrength: ingredient.refDefaultEthanolStrength ?? fallback.defaultEthanolStrength
        )
    }

    static func primarySolvent(in draft: ExtempRecipeDraft) -> (ingredient: IngredientDraft?, type: NonAqueousSolventType)? {
        let classified = draft.ingredients.compactMap { ingredient -> (IngredientDraft, NonAqueousSolventType)? in
            guard let type = classify(ingredient: ingredient) else { return nil }
            return (ingredient, type)
        }

        guard !classified.isEmpty else { return nil }

        let sorted = classified.sorted { lhs, rhs in
            let l = solventPriority(lhs.0)
            let r = solventPriority(rhs.0)
            if l != r { return l < r }
            if lhs.0.amountValue != rhs.0.amountValue { return lhs.0.amountValue > rhs.0.amountValue }
            return normalizedHay(lhs.0) < normalizedHay(rhs.0)
        }

        return (sorted[0].0, sorted[0].1)
    }

    static func classify(ingredient: IngredientDraft) -> NonAqueousSolventType? {
        let hay = normalizedHay(ingredient)
        let solventType = normalized((ingredient.refSolventType ?? ""))
        let storage = normalized((ingredient.refStorage ?? ""))
        let interaction = normalized((ingredient.refInteractionNotes ?? ""))
        let combined = [hay, solventType, storage, interaction].joined(separator: " ")

        if PurifiedWaterHeuristics.isPurifiedWater(ingredient) { return nil }
        if solventType.contains("water") || combined.contains("aqueous") || combined.contains("вод") { return nil }
        if let exact = NonAqueousSolventType.allCases.first(where: { normalized($0.rawValue) == solventType }) {
            return exact
        }

        if combined.contains("chloroform") || combined.contains("хлороформ") {
            return .chloroform
        }
        if combined.contains("aether") || combined.contains("ether") || combined.contains("ефір") || combined.contains("эфир") {
            return .ether
        }
        if combined.contains("spirit") || combined.contains("ethanol") || combined.contains("alcohol") || combined.contains("спирт") {
            return .ethanol
        }
        if combined.contains("glycerin") || combined.contains("glycerol") || combined.contains("glycerinum") || combined.contains("гліцерин") || combined.contains("глицерин") {
            return .glycerin
        }
        if combined.contains("vinylin") || combined.contains("vinylinum") || combined.contains("vinilin") || combined.contains("винилин") || combined.contains("вінілін") {
            return .vinylin
        }
        if combined.contains("vaseline oil")
            || combined.contains("vaselini")
            || combined.contains("paraffin oil")
            || combined.contains("mineral oil")
            || combined.contains("вазелінова олія")
            || combined.contains("вазелиновое масло")
        {
            return .mineralOil
        }
        if combined.contains("oleum")
            || combined.contains(" olei ")
            || combined.contains("oil")
            || combined.contains("олія")
            || combined.contains("масло")
        {
            return .fattyOil
        }
        if combined.contains("propylene glycol")
            || combined.contains("propylenglycol")
            || combined.contains("macrogol")
            || combined.contains("peg 400")
            || combined.contains("polyethylene glycol")
        {
            return .viscousOther
        }
        if combined.contains("acetone")
            || combined.contains("ацетон")
            || combined.contains("turpentine")
            || combined.contains("терпентин")
        {
            return .volatileOther
        }

        return nil
    }

    static func requestedEthanolStrength(from ingredient: IngredientDraft?) -> Int {
        guard let ingredient else { return 90 }

        if let officinal = officinalAlcoholSolution(for: ingredient) {
            return officinal.ethanolStrength
        }

        let explicitEthanolCandidates = [
            ingredient.refNameLatNom,
            ingredient.displayName
        ]

        for candidate in explicitEthanolCandidates {
            guard let candidate else { continue }
            let normalized = normalized(candidate)
            guard normalized.contains("spiritus aethylic")
                || normalized.contains("ethanol")
                || normalized.contains("спирт етил")
                || normalized.contains("спирта этил")
            else { continue }
            if let strength = parsePercent(from: candidate) {
                return normalizedEthanolStrength(strength) ?? 90
            }
        }

        let contextualCandidates = [
            ingredient.refInteractionNotes,
            ingredient.refStorage
        ]

        for candidate in contextualCandidates {
            guard let candidate, let strength = parsePercent(from: candidate) else { continue }
            return normalizedEthanolStrength(strength) ?? 90
        }

        if let defaultStrength = ingredient.refDefaultEthanolStrength,
           let normalizedStrength = normalizedEthanolStrength(defaultStrength) {
            return normalizedStrength
        }

        return 90
    }

    static func density(
        for type: NonAqueousSolventType,
        ethanolStrength: Int? = nil,
        fallback: Double? = nil
    ) -> Double? {
        if let fallback {
            return fallback
        }
        switch type {
        case .ethanol:
            if let normalized = normalizedEthanolStrength(ethanolStrength),
               let density = LiquidDensityCatalog.shared.ethanolDensity(strength: normalized) {
                return density
            }
        default:
            if let density = densityFromNormalizedTable(for: type) {
                return density
            }
        }
        return profile(for: type, ethanolStrength: ethanolStrength).density20C
    }

    static func standardDropsPerMl(
        for type: NonAqueousSolventType,
        ethanolStrength: Int? = nil
    ) -> Double? {
        switch type {
        case .ethanol:
            switch normalizedEthanolStrength(ethanolStrength) ?? 90 {
            case 70:
                return 28
            case 40:
                return 24
            case 90, 95, 96:
                return 30
            default:
                return 28
            }
        case .fattyOil, .mineralOil:
            return 40
        case .glycerin, .vinylin, .viscousOther:
            return 24
        case .ether, .chloroform, .volatileOther:
            return nil
        }
    }

    static func officinalAlcoholSolution(for ingredient: IngredientDraft?) -> OfficinalAlcoholSolutionSpec? {
        guard let ingredient else { return nil }
        let hay = normalizedHay(ingredient)

        if hay.contains("spiritus salicylicus")
            || hay.contains("spiritus salicylici")
            || hay.contains("salicyl alcohol")
            || ((hay.contains("салицил") || hay.contains("salicyl")) && hay.contains("спирт")) {
            return OfficinalAlcoholSolutionSpec(
                title: "Spiritus salicylicus 1%",
                activeTitle: "Acidum salicylicum",
                concentrationPercent: 1.0,
                ethanolStrength: 70,
                routeHint: "topical"
            )
        }

        if hay.contains("spiritus boricus")
            || hay.contains("spiritus borici")
            || hay.contains("boric alcohol")
            || ((hay.contains("борн") || hay.contains("boric")) && hay.contains("спирт")) {
            return OfficinalAlcoholSolutionSpec(
                title: "Spiritus boricus 3%",
                activeTitle: "Acidum boricum",
                concentrationPercent: 3.0,
                ethanolStrength: 70,
                routeHint: "otic"
            )
        }

        return nil
    }

    static func concentrationControlProfile(for ingredient: IngredientDraft?) -> ConcentrationControlProfile? {
        guard let ingredient else { return nil }
        let hay = normalizedHay(ingredient)
        let title = (ingredient.refNameLatNom ?? ingredient.displayName)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let officinal = officinalAlcoholSolution(for: ingredient) {
            return ConcentrationControlProfile(
                title: officinal.title,
                concentrationPercent: officinal.concentrationPercent,
                dropsPerMlOverride: officinal.ethanolStrength == 70 ? 60 : nil,
                isConcentrationControlOnly: true
            )
        }

        if hay.contains("spiritus camphor") || hay.contains("камфорн") {
            return ConcentrationControlProfile(
                title: title.isEmpty ? "Spiritus camphoratus" : title,
                concentrationPercent: parsePercentValue(from: title) ?? 10.0,
                dropsPerMlOverride: 60,
                isConcentrationControlOnly: true
            )
        }

        if hay.contains("solutio iodi spirit") || hay.contains("iodi spirit") || hay.contains("йод") && hay.contains("спирт") {
            return ConcentrationControlProfile(
                title: title.isEmpty ? "Solutio Iodi spirituosa" : title,
                concentrationPercent: parsePercentValue(from: title) ?? 5.0,
                dropsPerMlOverride: 60,
                isConcentrationControlOnly: true
            )
        }

        if hay.contains("viridis nitentis") || hay.contains("brilliant green") || hay.contains("бриллиант") {
            return ConcentrationControlProfile(
                title: title.isEmpty ? "Solutio Viridis nitentis" : title,
                concentrationPercent: parsePercentValue(from: title) ?? 1.0,
                dropsPerMlOverride: 60,
                isConcentrationControlOnly: true
            )
        }

        if hay.contains("fucorcin") || hay.contains("fukortsin") || hay.contains("фукорцин") || hay.contains("castellani") {
            return ConcentrationControlProfile(
                title: title.isEmpty ? "Fucorcinum" : title,
                concentrationPercent: nil,
                dropsPerMlOverride: nil,
                isConcentrationControlOnly: true
            )
        }

        if hay.contains("lugol") || hay.contains("люгол") {
            return ConcentrationControlProfile(
                title: title.isEmpty ? "Solutio Lugoli" : title,
                concentrationPercent: nil,
                dropsPerMlOverride: nil,
                isConcentrationControlOnly: true
            )
        }

        if hay.contains("hydrogen peroxide") || hay.contains("hydrogenii perox") || hay.contains("перекис") {
            return ConcentrationControlProfile(
                title: title.isEmpty ? "Hydrogenii peroxydum" : title,
                concentrationPercent: parsePercentValue(from: title) ?? 3.0,
                dropsPerMlOverride: nil,
                isConcentrationControlOnly: true
            )
        }

        if hay.contains("chlorhex") || hay.contains("хлоргексидин") {
            return ConcentrationControlProfile(
                title: title.isEmpty ? "Chlorhexidini bigluconas" : title,
                concentrationPercent: parsePercentValue(from: title) ?? 0.05,
                dropsPerMlOverride: nil,
                isConcentrationControlOnly: true
            )
        }

        if hay.contains("furacilin") || hay.contains("furacil") || hay.contains("фурацил") {
            return ConcentrationControlProfile(
                title: title.isEmpty ? "Solutio Furacilini" : title,
                concentrationPercent: parsePercentValue(from: title) ?? parseRatioPercent(from: title),
                dropsPerMlOverride: nil,
                isConcentrationControlOnly: true
            )
        }

        return nil
    }

    static func isNonAqueousSolution(_ draft: ExtempRecipeDraft) -> Bool {
        let hasLiquidLikeForm = draft.formMode == .solutions || draft.formMode == .drops
        return hasLiquidLikeForm && primarySolvent(in: draft) != nil
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
    }

    private static func normalizedHay(_ ingredient: IngredientDraft) -> String {
        normalized(
            [
                ingredient.refNameLatNom,
                ingredient.refNameLatGen,
                ingredient.refInnKey,
                ingredient.displayName,
                ingredient.refSolventType
            ]
            .compactMap { $0 }
            .joined(separator: " ")
        )
    }

    private static func solventPriority(_ ingredient: IngredientDraft) -> Int {
        if ingredient.role == .solvent { return 0 }
        if ingredient.refNormalizedType == "solvent" { return 1 }
        if ingredient.isAd || ingredient.isQS { return 2 }
        if ingredient.unit.rawValue == "ml" { return 3 }
        return 4
    }

    private static func parsePercent(from text: String) -> Int? {
        guard let value = parsePercentValue(from: text) else { return nil }
        return Int(value.rounded())
    }

    private static func parsePercentValue(from text: String) -> Double? {
        let source = text.replacingOccurrences(of: ",", with: ".")
        guard let range = source.range(of: "(\\d{1,2}(?:\\.\\d+)?)\\s*%", options: .regularExpression) else {
            return nil
        }
        let matched = String(source[range])
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(matched)
    }

    private static func parseRatioPercent(from text: String) -> Double? {
        let source = text.replacingOccurrences(of: ",", with: ".") as NSString
        let regexPattern = "1\\s*:\\s*(\\d+(?:\\.\\d+)?)"
        guard let regex = try? NSRegularExpression(pattern: regexPattern) else {
            return nil
        }
        let range = NSRange(location: 0, length: source.length)
        guard let match = regex.firstMatch(in: source as String, options: [], range: range),
              match.numberOfRanges > 1
        else { return nil }
        let denominatorRaw = source.substring(with: match.range(at: 1))
        guard let denominator = Double(denominatorRaw),
              denominator > 0
        else { return nil }
        return 100.0 / denominator
    }

    private static func normalizedEthanolStrength(_ strength: Int?) -> Int? {
        guard let strength else { return nil }
        switch strength {
        case ..<1:
            return nil
        case 66...74:
            return 70
        case 86...94:
            return 90
        case 95...99:
            return 96
        default:
            return strength
        }
    }

    private static func ethanolDensity20C(for strength: Int) -> Double? {
        if let normalizedDensity = LiquidDensityCatalog.shared.ethanolDensity(strength: strength) {
            return normalizedDensity
        }
        switch strength {
        case 70:
            return 0.882
        case 90:
            return 0.829
        case 95:
            return 0.811
        case 96:
            return 0.8074
        default:
            return nil
        }
    }

    private static func densityFromNormalizedTable(for type: NonAqueousSolventType) -> Double? {
        switch type {
        case .ether:
            return LiquidDensityCatalog.shared.density(named: "Эфир медицинский")
        case .chloroform:
            return LiquidDensityCatalog.shared.density(named: "Хлороформ")
        case .mineralOil:
            return LiquidDensityCatalog.shared.density(named: "Масло вазелиновое")
        case .glycerin:
            return LiquidDensityCatalog.shared.density(named: "Глицерин")
        case .vinylin, .volatileOther, .fattyOil, .viscousOther, .ethanol:
            return nil
        }
    }
}
