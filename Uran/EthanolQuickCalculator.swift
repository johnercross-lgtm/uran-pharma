import Foundation

enum EthanolCalculatorMode: String, CaseIterable, Identifiable, Sendable {
    case fertman
    case simple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fertman:
            return "Pro (Фертман)"
        case .simple:
            return "Формула"
        }
    }

    var subtitle: String {
        switch self {
        case .fertman:
            return "Учитывает контракцию через табличные данные при 20°C; вне диапазона переключается на формулу."
        case .simple:
            return "Быстрый теоретический расчет без учета контракции."
        }
    }
}

struct EthanolCalculatorResult: Sendable {
    let mode: EthanolCalculatorMode
    let sourceVolumeMl: Double
    let sourcePercent: Double
    let targetPercent: Double
    let waterToAddMl: Double
    let totalBeforeContractionMl: Double
    let expectedFinalVolumeMl: Double
    let contractionMl: Double
    let sourceInterpolationRange: ClosedRange<Int>?
    let targetInterpolationRange: ClosedRange<Int>?
    let usedFallbackFormula: Bool

    var usedTabularProMode: Bool {
        mode == .fertman && !usedFallbackFormula
    }
}

enum EthanolCalculatorError: Error, LocalizedError, Sendable {
    case invalidInput
    case invalidStrengthOrder(source: Double, target: Double)

    var errorDescription: String? {
        switch self {
        case .invalidInput:
            return "Введите корректные положительные значения объема и крепости."
        case .invalidStrengthOrder(let source, let target):
            return "Целевая крепость \(Self.format(target))% должна быть ниже или равна исходной \(Self.format(source))%."
        }
    }

    private static func format(_ value: Double) -> String {
        ExtempViewFormatter.formatAmount(value)
    }
}

enum EthanolQuickCalculator {
    static func calculate(
        sourceVolumeMl: Double,
        sourcePercent: Double,
        targetPercent: Double,
        mode: EthanolCalculatorMode
    ) throws -> EthanolCalculatorResult {
        guard sourceVolumeMl > 0, sourcePercent > 0, targetPercent > 0 else {
            throw EthanolCalculatorError.invalidInput
        }
        guard sourcePercent + 0.0001 >= targetPercent else {
            throw EthanolCalculatorError.invalidStrengthOrder(source: sourcePercent, target: targetPercent)
        }

        switch mode {
        case .simple:
            return simple(
                sourceVolumeMl: sourceVolumeMl,
                sourcePercent: sourcePercent,
                targetPercent: targetPercent
            )
        case .fertman:
            if let lookup = FertmanTable.lookup(sourcePercent: sourcePercent, targetPercent: targetPercent) {
                let water = lookup.waterMlPer1000SourceMl * sourceVolumeMl / 1000.0
                let totalBefore = sourceVolumeMl + water
                let expectedFinal = sourceVolumeMl * sourcePercent / targetPercent
                return EthanolCalculatorResult(
                    mode: .fertman,
                    sourceVolumeMl: sourceVolumeMl,
                    sourcePercent: sourcePercent,
                    targetPercent: targetPercent,
                    waterToAddMl: water,
                    totalBeforeContractionMl: totalBefore,
                    expectedFinalVolumeMl: expectedFinal,
                    contractionMl: max(0, totalBefore - expectedFinal),
                    sourceInterpolationRange: lookup.sourceInterpolationRange,
                    targetInterpolationRange: lookup.targetInterpolationRange,
                    usedFallbackFormula: false
                )
            }

            let simpleResult = simple(
                sourceVolumeMl: sourceVolumeMl,
                sourcePercent: sourcePercent,
                targetPercent: targetPercent
            )
            return EthanolCalculatorResult(
                mode: .fertman,
                sourceVolumeMl: simpleResult.sourceVolumeMl,
                sourcePercent: simpleResult.sourcePercent,
                targetPercent: simpleResult.targetPercent,
                waterToAddMl: simpleResult.waterToAddMl,
                totalBeforeContractionMl: simpleResult.totalBeforeContractionMl,
                expectedFinalVolumeMl: simpleResult.expectedFinalVolumeMl,
                contractionMl: 0,
                sourceInterpolationRange: nil,
                targetInterpolationRange: nil,
                usedFallbackFormula: true
            )
        }
    }

    private static func simple(
        sourceVolumeMl: Double,
        sourcePercent: Double,
        targetPercent: Double
    ) -> EthanolCalculatorResult {
        let finalVolume = sourceVolumeMl * sourcePercent / targetPercent
        let water = max(0, finalVolume - sourceVolumeMl)
        return EthanolCalculatorResult(
            mode: .simple,
            sourceVolumeMl: sourceVolumeMl,
            sourcePercent: sourcePercent,
            targetPercent: targetPercent,
            waterToAddMl: water,
            totalBeforeContractionMl: finalVolume,
            expectedFinalVolumeMl: finalVolume,
            contractionMl: 0,
            sourceInterpolationRange: nil,
            targetInterpolationRange: nil,
            usedFallbackFormula: false
        )
    }
}

private struct FertmanLookup: Sendable {
    let waterMlPer1000SourceMl: Double
    let sourceInterpolationRange: ClosedRange<Int>?
    let targetInterpolationRange: ClosedRange<Int>?
}

private enum FertmanTable {
    static let waterMlBySourceAndTarget: [Int: [Int: Double]] = [
        95: [90: 57, 85: 123, 80: 198, 75: 283, 70: 382, 65: 494, 60: 625, 55: 778, 50: 960, 45: 1177, 40: 1453, 35: 1805, 30: 2280],
        90: [85: 63, 80: 133, 75: 213, 70: 307, 65: 414, 60: 538, 55: 682, 50: 854, 45: 1058, 40: 1320, 35: 1650, 30: 2095],
        85: [80: 66, 75: 142, 70: 230, 65: 331, 60: 447, 55: 583, 50: 745, 45: 938, 40: 1184, 35: 1496, 30: 1908],
        80: [75: 71, 70: 153, 65: 249, 60: 361, 55: 490, 50: 642, 45: 824, 40: 1057, 35: 1350, 30: 1731],
        75: [70: 75, 65: 165, 60: 270, 55: 393, 50: 538, 45: 710, 40: 927, 35: 1205, 30: 1553],
        70: [65: 84, 60: 182, 55: 298, 50: 435, 45: 597, 40: 801, 35: 1060, 30: 1376],
        65: [60: 90, 55: 198, 50: 328, 45: 480, 40: 673, 35: 917, 30: 1201],
        60: [55: 99, 50: 218, 45: 360, 40: 542, 35: 773, 30: 1025],
        55: [50: 107, 45: 239, 40: 410, 35: 629, 30: 849],
        50: [45: 119, 40: 273, 35: 479, 30: 673],
        45: [40: 138, 35: 323, 30: 529],
        40: [35: 163, 30: 364]
    ]

    static func lookup(sourcePercent: Double, targetPercent: Double) -> FertmanLookup? {
        guard sourcePercent > targetPercent else { return nil }

        let sources = waterMlBySourceAndTarget.keys.sorted()
        guard let lowerSource = sources.last(where: { Double($0) <= sourcePercent }),
              let upperSource = sources.first(where: { Double($0) >= sourcePercent }) else {
            return nil
        }

        if lowerSource == upperSource {
            guard let rowLookup = interpolateTarget(in: lowerSource, targetPercent: targetPercent) else {
                return nil
            }
            return FertmanLookup(
                waterMlPer1000SourceMl: rowLookup.waterMl,
                sourceInterpolationRange: nil,
                targetInterpolationRange: rowLookup.targetInterpolationRange
            )
        }

        guard let lowerTargetLookup = interpolateTarget(in: lowerSource, targetPercent: targetPercent),
              let upperTargetLookup = interpolateTarget(in: upperSource, targetPercent: targetPercent) else {
            return nil
        }

        let factor = (sourcePercent - Double(lowerSource)) / Double(upperSource - lowerSource)
        let water = lowerTargetLookup.waterMl + (upperTargetLookup.waterMl - lowerTargetLookup.waterMl) * factor
        return FertmanLookup(
            waterMlPer1000SourceMl: water,
            sourceInterpolationRange: lowerSource...upperSource,
            targetInterpolationRange: mergedRange(
                lowerTargetLookup.targetInterpolationRange,
                upperTargetLookup.targetInterpolationRange
            )
        )
    }

    private static func interpolateTarget(in sourcePercent: Int, targetPercent: Double) -> (waterMl: Double, targetInterpolationRange: ClosedRange<Int>?)? {
        guard let row = waterMlBySourceAndTarget[sourcePercent] else { return nil }
        let targets = row.keys.sorted()

        if let exactTarget = targets.first(where: { abs(Double($0) - targetPercent) < 0.0001 }),
           let exactWater = row[exactTarget] {
            return (exactWater, nil)
        }

        guard let lowerTarget = targets.last(where: { Double($0) < targetPercent }),
              let upperTarget = targets.first(where: { Double($0) > targetPercent }),
              let lowerWater = row[lowerTarget],
              let upperWater = row[upperTarget] else {
            return nil
        }

        let factor = (targetPercent - Double(lowerTarget)) / Double(upperTarget - lowerTarget)
        let water = lowerWater + (upperWater - lowerWater) * factor
        return (water, lowerTarget...upperTarget)
    }

    private static func mergedRange(_ lhs: ClosedRange<Int>?, _ rhs: ClosedRange<Int>?) -> ClosedRange<Int>? {
        switch (lhs, rhs) {
        case let (.some(a), .some(b)):
            return min(a.lowerBound, b.lowerBound)...max(a.upperBound, b.upperBound)
        case let (.some(a), .none):
            return a
        case let (.none, .some(b)):
            return b
        case (.none, .none):
            return nil
        }
    }
}
