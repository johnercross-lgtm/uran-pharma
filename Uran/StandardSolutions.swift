import Foundation

struct PercentRange: Codable, Equatable, Sendable {
    let min: Double?
    let max: Double?
}

enum StandardSolutionPercentMode: String, Codable, Equatable, Sendable {
    case activeSubstance
    case stockSolution
}

enum StandardSolutionSpecialCase: String, Codable, Equatable, Sendable {
    case demyanovich2
    case lugolWaterTopical
    case lugolGlycerinTopical
}

enum SolutionKey: String, Codable, CaseIterable, Sendable {
    case hydrochloricAcid
    case hydrochloricAcidDiluted
    case aceticAcid
    case aceticAcidDiluted
    case ammoniaSolution
    case aluminumAcetateBasicSolution
    case hydrogenPeroxideConcentrated
    case hydrogenPeroxideDiluted
    case formaldehydeSolution
    case lugolWaterSolution
    case lugolGlycerinSolution
}

struct StandardSolution: Codable, Equatable, Identifiable, Sendable {
    let id: SolutionKey
    let chemicalName: String
    let gfPercentRange: PercentRange?
    let avgPercent: Double?
    let alias: String?
    let unitWhenAliased: Bool
    let chemicalPercentMode: StandardSolutionPercentMode
}

extension StandardSolution {
    var latinNameNom: String {
        switch id {
        case .hydrochloricAcid:
            return "Acidum hydrochloricum"
        case .hydrochloricAcidDiluted:
            return "Acidum hydrochloricum dilutum"
        case .aceticAcid:
            return "Acidum aceticum"
        case .aceticAcidDiluted:
            return "Acidum aceticum dilutum"
        case .ammoniaSolution:
            return "Solutio Ammonii caustici"
        case .aluminumAcetateBasicSolution:
            return "Solutio Aluminii subacetatis"
        case .hydrogenPeroxideConcentrated:
            return "Hydrogenii peroxydum concentratum"
        case .hydrogenPeroxideDiluted:
            return "Solutio Hydrogenii peroxydi diluta"
        case .formaldehydeSolution:
            return "Solutio Formaldehydi"
        case .lugolWaterSolution:
            return "Solutio Lugoli"
        case .lugolGlycerinSolution:
            return "Solutio Lugoli cum Glycerino"
        }
    }

    var latinNameGen: String {
        switch id {
        case .hydrochloricAcid:
            return "Acidi hydrochlorici"
        case .hydrochloricAcidDiluted:
            return "Acidi hydrochlorici diluti"
        case .aceticAcid:
            return "Acidi acetici"
        case .aceticAcidDiluted:
            return "Acidi acetici diluti"
        case .ammoniaSolution:
            return "Solutionis Ammonii caustici"
        case .aluminumAcetateBasicSolution:
            return "Solutionis Aluminii subacetatis"
        case .hydrogenPeroxideConcentrated:
            return "Hydrogenii peroxydi concentrati"
        case .hydrogenPeroxideDiluted:
            return "Solutionis Hydrogenii peroxydi dilutae"
        case .formaldehydeSolution:
            return "Solutionis Formaldehydi"
        case .lugolWaterSolution:
            return "Solutionis Lugoli"
        case .lugolGlycerinSolution:
            return "Solutionis Lugoli cum Glycerino"
        }
    }

    var aliasLatinNameNom: String? {
        switch id {
        case .hydrogenPeroxideConcentrated:
            return "Perhydrolum"
        case .aluminumAcetateBasicSolution:
            return "Liquor Burovi"
        case .formaldehydeSolution:
            return "Formalinum"
        default:
            return nil
        }
    }

    var aliasLatinNameGen: String? {
        switch id {
        case .hydrogenPeroxideConcentrated:
            return "Perhydroli"
        case .aluminumAcetateBasicSolution:
            return "Liquoris Burovi"
        case .formaldehydeSolution:
            return "Formalini"
        default:
            return nil
        }
    }
}

final class StandardSolutionsRepository: Sendable {
    static let shared = StandardSolutionsRepository()

    let solutions: [StandardSolution] = [
        .init(
            id: .hydrochloricAcid,
            chemicalName: "Кислота хлористоводородная",
            gfPercentRange: .init(min: 24.8, max: 25.2),
            avgPercent: 25.0,
            alias: nil,
            unitWhenAliased: false,
            chemicalPercentMode: .activeSubstance
        ),
        .init(
            id: .hydrochloricAcidDiluted,
            chemicalName: "Кислота хлористоводородная разведенная",
            gfPercentRange: .init(min: 8.2, max: 8.4),
            avgPercent: 8.3,
            alias: nil,
            unitWhenAliased: false,
            chemicalPercentMode: .stockSolution
        ),
        .init(
            id: .aceticAcid,
            chemicalName: "Кислота уксусная",
            gfPercentRange: .init(min: 98.0, max: nil),
            avgPercent: nil,
            alias: nil,
            unitWhenAliased: false,
            chemicalPercentMode: .activeSubstance
        ),
        .init(
            id: .aceticAcidDiluted,
            chemicalName: "Кислота уксусная разведенная",
            gfPercentRange: .init(min: 29.5, max: 30.5),
            avgPercent: 30.0,
            alias: nil,
            unitWhenAliased: false,
            chemicalPercentMode: .activeSubstance
        ),
        .init(
            id: .ammoniaSolution,
            chemicalName: "Раствор аммиака",
            gfPercentRange: .init(min: 9.5, max: 10.5),
            avgPercent: 10.0,
            alias: nil,
            unitWhenAliased: false,
            chemicalPercentMode: .activeSubstance
        ),
        .init(
            id: .aluminumAcetateBasicSolution,
            chemicalName: "Раствор алюминия ацетата основного",
            gfPercentRange: .init(min: 7.6, max: 9.2),
            avgPercent: 8.0,
            alias: "Жидкость Бурова",
            unitWhenAliased: true,
            chemicalPercentMode: .stockSolution
        ),
        .init(
            id: .hydrogenPeroxideConcentrated,
            chemicalName: "Раствор водорода перекиси концентрированный",
            gfPercentRange: .init(min: 27.5, max: 30.1),
            avgPercent: 30.0,
            alias: "Пергидроль",
            unitWhenAliased: true,
            chemicalPercentMode: .activeSubstance
        ),
        .init(
            id: .hydrogenPeroxideDiluted,
            chemicalName: "Раствор водорода перекиси разведенный",
            gfPercentRange: .init(min: 2.7, max: 3.3),
            avgPercent: 3.0,
            alias: nil,
            unitWhenAliased: false,
            chemicalPercentMode: .activeSubstance
        ),
        .init(
            id: .formaldehydeSolution,
            chemicalName: "Раствор формальдегида",
            gfPercentRange: .init(min: 36.5, max: 37.5),
            avgPercent: 37.0,
            alias: "Формалин",
            unitWhenAliased: true,
            chemicalPercentMode: .activeSubstance
        ),
        .init(
            id: .lugolWaterSolution,
            chemicalName: "Раствор Люголя (водный)",
            gfPercentRange: nil,
            avgPercent: nil,
            alias: nil,
            unitWhenAliased: false,
            chemicalPercentMode: .activeSubstance
        ),
        .init(
            id: .lugolGlycerinSolution,
            chemicalName: "Раствор Люголя с глицерином",
            gfPercentRange: nil,
            avgPercent: nil,
            alias: nil,
            unitWhenAliased: false,
            chemicalPercentMode: .activeSubstance
        )
    ]

    func get(_ key: SolutionKey) -> StandardSolution? {
        solutions.first { $0.id == key }
    }

    func matchIngredient(
        _ ing: IngredientDraft,
        parsedPercent: Double?
    ) -> (solution: StandardSolution, kind: DilutionInputNameKind)? {
        let a = (ing.refNameLatNom ?? ing.displayName).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let b = (ing.refInnKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hay = a + " " + b
        let hayNoSpaces = hay.replacingOccurrences(of: " ", with: "")

        let looksLikeHcl = hay.contains("acidum hydrochlor")
            || hay.contains("acidi hydrochlorici")
            || hay.contains("hydrochloric acid")
            || hay.contains("хлористовод")
        let saysConcentrated25 = hay.contains("25%")
            || hay.contains("24,8") || hay.contains("24.8")
            || hay.contains("25,2") || hay.contains("25.2")
            || hayNoSpaces.contains("24,8%") || hayNoSpaces.contains("24.8%")
        if looksLikeHcl, !saysConcentrated25, let s = get(.hydrochloricAcidDiluted) {
            return (s, .chemicalName)
        }

        if hay.contains("ammonii caust")
            || hay.contains("sol. ammon")
            || hay.contains("ammoniae")
            || hay.contains("ammon")
            || hay.contains("аммиак"),
           let s = get(.ammoniaSolution) {
            return (s, .chemicalName)
        }

        if hay.contains("hydrogenii perox") || hay.contains("водорода перекис") || hay.contains("hydrogen peroxide") {
            if let p = parsedPercent, p <= 3.0, let s = get(.hydrogenPeroxideDiluted) {
                return (s, .chemicalName)
            }
            if parsedPercent == nil, let s = get(.hydrogenPeroxideDiluted) {
                return (s, .chemicalName)
            }
            if let s = get(.hydrogenPeroxideConcentrated) {
                return (s, .chemicalName)
            }
        }
        if hay.contains("formalin") || hay.contains("формалин"), let s = get(.formaldehydeSolution) {
            return (s, .aliasName)
        }
        if hay.contains("perhydrol") || hay.contains("пергидрол"), let s = get(.hydrogenPeroxideConcentrated) {
            return (s, .aliasName)
        }
        if hay.contains("буров") || hay.contains("burrow") || hay.contains("burow"), let s = get(.aluminumAcetateBasicSolution) {
            return (s, .aliasName)
        }
        if hay.contains("acidum acetic") || hay.contains("уксусн") {
            if let p = parsedPercent, p >= 90, let s = get(.aceticAcid) {
                return (s, .chemicalName)
            }
            if let s = get(.aceticAcidDiluted) {
                return (s, .chemicalName)
            }
        }

        return solutions.first(where: { solution in
            let chemical = solution.chemicalName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !chemical.isEmpty && hay.contains(chemical)
        }).map { ($0, .chemicalName) }
    }
}

enum DilutionInputNameKind: Sendable {
    case chemicalName
    case aliasName
}

struct DilutionResult: Equatable, Sendable {
    let stockAmount: Double
    let waterAmount: Double
}

enum DilutionError: Error, LocalizedError, Sendable {
    case missingStockPercent
    case invalidInput

    var errorDescription: String? {
        switch self {
        case .missingStockPercent: return "Не задана концентрация стандартного раствора (avgPercent)."
        case .invalidInput: return "Некорректные входные данные."
        }
    }
}

final class StandardSolutionCalculator: Sendable {

    func dilute(
        stock: StandardSolution,
        finalVolume: Double,
        targetPercent: Double,
        inputNameKind: DilutionInputNameKind
    ) throws -> DilutionResult {

        guard finalVolume > 0, targetPercent > 0 else { throw DilutionError.invalidInput }

        let A: Double
        switch inputNameKind {
        case .chemicalName:
            if stock.chemicalPercentMode == .stockSolution {
                A = 100.0
                break
            }
            if let avg = stock.avgPercent {
                A = avg
            } else if let min = stock.gfPercentRange?.min, stock.gfPercentRange?.max == nil {
                // Fallback for ranges like "≥98": use the minimum as practical stock percent.
                A = min
            } else {
                throw DilutionError.missingStockPercent
            }
        case .aliasName:
            A = 100.0
        }

        let X = finalVolume * targetPercent / A
        let water = finalVolume - X

        return .init(stockAmount: X, waterAmount: water)
    }

    func defaultPercentIfMissing(for key: SolutionKey) -> Double? {
        switch key {
        case .hydrogenPeroxideDiluted: return 3.0
        case .hydrochloricAcidDiluted: return 8.3
        case .aceticAcidDiluted: return 30.0
        case .ammoniaSolution: return 10.0
        case .formaldehydeSolution: return 37.0
        default: return nil
        }
    }
}
