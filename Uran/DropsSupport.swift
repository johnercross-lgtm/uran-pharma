import Foundation

enum DropDeviceKind: String, Codable, Sendable {
    case standardDropper
    case nonStandardPipette
}

struct DropTableEntry: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let standardDropsPerMl: Double?
    let standardDropsPerGram: Double?
}

struct PipetteCalibration: Codable, Equatable, Sendable {
    let nonStandardPerOneStandard: Double
    let nonStandardDropsPerMl: Double?
    let nonStandardDropsPer01Ml: Double?
    let labelText: String
}

struct DoseCheckResult: Equatable, Sendable {
    let totalDropsInBottle: Double
    let numberOfDoses: Double
    let singleDoseSubstanceGrams: Double?
    let dailyDoseSubstanceGrams: Double?
    let messages: [String]
}

enum DropCalcError: Error, LocalizedError, Sendable {
    case invalidInput
    case missingReferenceData

    var errorDescription: String? {
        switch self {
        case .invalidInput: return "Некорректные входные данные."
        case .missingReferenceData: return "Не хватает данных (таблица капель/плотность/концентрация)."
        }
    }
}

final class DropsCalculator: Sendable {

    static let defaultStandardDropsPerMlWater = 20.0

    func ml(fromDrops drops: Double, dropsPerMl: Double) throws -> Double {
        guard drops >= 0, dropsPerMl > 0 else { throw DropCalcError.invalidInput }
        return drops / dropsPerMl
    }

    func drops(fromMl ml: Double, dropsPerMl: Double) throws -> Double {
        guard ml >= 0, dropsPerMl > 0 else { throw DropCalcError.invalidInput }
        return ml * dropsPerMl
    }

    func dropsPerMlForAqueousApprox() -> Double {
        Self.defaultStandardDropsPerMlWater
    }

    func calibratePipette(
        liquid: DropTableEntry,
        avgMassOf20DropsGram: Double
    ) throws -> PipetteCalibration {

        guard avgMassOf20DropsGram > 0 else { throw DropCalcError.invalidInput }
        guard let standardDropsPerGram = liquid.standardDropsPerGram else {
            throw DropCalcError.missingReferenceData
        }

        let nonStandardDropsPerGram = 20.0 / avgMassOf20DropsGram
        let ratio = nonStandardDropsPerGram / standardDropsPerGram

        let nonStandardPerMl: Double? = liquid.standardDropsPerMl.map { $0 * ratio }
        let nonStandardPer01Ml: Double? = nonStandardPerMl.map { $0 * 0.1 }

        var lines: [String] = []
        lines.append("1 станд. капля = \(format(ratio)) нестанд.")
        if let nsMl = nonStandardPerMl {
            lines.append("в 1 мл – \(format(nsMl)) капель")
        }
        if let ns01 = nonStandardPer01Ml {
            lines.append("в 0,1 мл – \(format(ns01)) капель")
        }

        return PipetteCalibration(
            nonStandardPerOneStandard: ratio,
            nonStandardDropsPerMl: nonStandardPerMl,
            nonStandardDropsPer01Ml: nonStandardPer01Ml,
            labelText: lines.joined(separator: "\n")
        )
    }

    func convertStandardDropsToNonStandard(
        standardDrops: Double,
        calibration: PipetteCalibration
    ) throws -> Double {
        guard standardDrops >= 0, calibration.nonStandardPerOneStandard > 0 else {
            throw DropCalcError.invalidInput
        }
        return standardDrops * calibration.nonStandardPerOneStandard
    }

    struct MixtureComponent: Sendable {
        let name: String
        let volumeMl: Double
        let standardDropsPerMl: Double
        let isStrong: Bool
        let vrddDrops: Double?
        let vsddDrops: Double?
    }

    func checkDoseForAqueousSolution(
        percentWv: Double,
        totalVolumeMl: Double,
        dropsPerDose: Double,
        timesPerDay: Double,
        dropsPerMl: Double = DropsCalculator.defaultStandardDropsPerMlWater,
        vrddGram: Double? = nil,
        vsddGram: Double? = nil
    ) throws -> DoseCheckResult {

        guard percentWv > 0, totalVolumeMl > 0, dropsPerDose > 0, timesPerDay > 0, dropsPerMl > 0 else {
            throw DropCalcError.invalidInput
        }

        let gramsTotal = (percentWv / 100.0) * totalVolumeMl
        let totalDrops = totalVolumeMl * dropsPerMl
        let doses = totalDrops / dropsPerDose
        let single = gramsTotal / doses
        let daily = single * timesPerDay

        var msgs: [String] = []
        msgs.append("Всего капель: \(format(totalDrops))")
        msgs.append("Число приемов: \(format(doses))")
        msgs.append("Разовая доза: \(format(single)) г")
        msgs.append("Суточная доза: \(format(daily)) г")

        if let vrddGram, single > vrddGram {
            msgs.append("⚠️ Разовая доза превышает ВРД (\(format(vrddGram)) г)")
        }
        if let vsddGram, daily > vsddGram {
            msgs.append("⚠️ Суточная доза превышает ВСД (\(format(vsddGram)) г)")
        }

        return .init(
            totalDropsInBottle: totalDrops,
            numberOfDoses: doses,
            singleDoseSubstanceGrams: single,
            dailyDoseSubstanceGrams: daily,
            messages: msgs
        )
    }

    func checkDoseForTinctureMixture(
        components: [MixtureComponent],
        dropsPerDose: Double,
        timesPerDay: Double
    ) throws -> DoseCheckResult {

        guard !components.isEmpty, dropsPerDose > 0, timesPerDay > 0 else { throw DropCalcError.invalidInput }

        let totalDrops = components.reduce(0.0) { acc, c in
            acc + (c.volumeMl * c.standardDropsPerMl)
        }

        let doses = totalDrops / dropsPerDose

        var msgs: [String] = []
        msgs.append("Всего капель смеси: \(format(totalDrops))")
        msgs.append("Число приемов: \(format(doses))")

        for c in components where c.isStrong {
            let dropsOfComponent = c.volumeMl * c.standardDropsPerMl
            let singleStrongDrops = dropsOfComponent / doses
            let dailyStrongDrops = singleStrongDrops * timesPerDay

            msgs.append("\(c.name): разовая \(format(singleStrongDrops)) кап., суточная \(format(dailyStrongDrops)) кап.")

            if let vr = c.vrddDrops, singleStrongDrops > vr {
                msgs.append("⚠️ \(c.name): разовая превышает ВРД (\(format(vr)) кап.)")
            }
            if let vs = c.vsddDrops, dailyStrongDrops > vs {
                msgs.append("⚠️ \(c.name): суточная превышает ВСД (\(format(vs)) кап.)")
            }
        }

        return .init(
            totalDropsInBottle: totalDrops,
            numberOfDoses: doses,
            singleDoseSubstanceGrams: nil,
            dailyDoseSubstanceGrams: nil,
            messages: msgs
        )
    }

    private func format(_ v: Double) -> String {
        if v >= 10 { return String(format: "%.0f", v) }
        if v >= 1 { return String(format: "%.1f", v) }
        return String(format: "%.3f", v)
    }
}

final class DropTableRepository: Sendable {
    static let shared = DropTableRepository()

    let entries: [DropTableEntry] = [
        .init(
            id: "tinctura_belladonnae",
            name: "Настойка красавки",
            standardDropsPerMl: 44,
            standardDropsPerGram: 46
        )
    ]

    func find(byId id: String) -> DropTableEntry? {
        entries.first { $0.id == id }
    }
}
