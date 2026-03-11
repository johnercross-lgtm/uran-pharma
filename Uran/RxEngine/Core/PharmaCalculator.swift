import Foundation

enum SolventCalculationMode: String, Codable {
    case qsToVolume = "qs_to_volume"
    case kouCalculation = "kou_calculation"
    case dilution = "dilution"
    case pharmacopoeial = "pharmacopoeial"
    case nonAqueous = "non_aqueous"
}

struct KuoCalculationPolicy {
    var thresholdPercent: Double
    var inclusiveThreshold: Bool
    var minDisplacementMlToApply: Double?
    var forceApply: Bool
    var forceDisable: Bool

    static let legacy = KuoCalculationPolicy(
        thresholdPercent: 3.0,
        inclusiveThreshold: true,
        minDisplacementMlToApply: nil,
        forceApply: false,
        forceDisable: false
    )

    static let adaptive = KuoCalculationPolicy(
        thresholdPercent: 3.0,
        inclusiveThreshold: false,
        minDisplacementMlToApply: 0.8,
        forceApply: false,
        forceDisable: false
    )

    static let forceApply = KuoCalculationPolicy(
        thresholdPercent: 3.0,
        inclusiveThreshold: false,
        minDisplacementMlToApply: nil,
        forceApply: true,
        forceDisable: false
    )

    static let forceDisable = KuoCalculationPolicy(
        thresholdPercent: 3.0,
        inclusiveThreshold: false,
        minDisplacementMlToApply: nil,
        forceApply: false,
        forceDisable: true
    )
}

struct AdCalculationResult {
    let targetVolume: Double
    let componentsVolume: Double
    let solidsWeight: Double
    let displacementVolume: Double
    let amountToMeasure: Double
    let rawAmountToMeasure: Double
    let isImpossible: Bool
    let needsKuo: Bool
    let missingKuoCount: Int
}

enum PharmaCalculator {
    static func calculateAdWater(
        targetVolume: Double,
        otherLiquids: [Double],
        solids: [(weight: Double, kuo: Double?)],
        kuoPolicy: KuoCalculationPolicy = .legacy
    ) -> AdCalculationResult {
        let normalizedTarget = max(0, targetVolume)
        let sumLiquids = otherLiquids.reduce(0.0) { $0 + max(0, $1) }

        let normalizedSolids = solids.map { (weight: max(0, $0.weight), kuo: $0.kuo) }
        let totalSolidsWeight = normalizedSolids.reduce(0.0) { $0 + $1.weight }

        let solidsPercentage = normalizedTarget > 0
            ? (totalSolidsWeight / normalizedTarget) * 100.0
            : 0.0
        let displacementEstimate = normalizedSolids.reduce(0.0) { partial, solid in
            partial + (solid.kuo ?? 0) * solid.weight
        }

        let thresholdPassed: Bool
        if kuoPolicy.inclusiveThreshold {
            thresholdPassed = solidsPercentage >= kuoPolicy.thresholdPercent
        } else {
            thresholdPassed = solidsPercentage > kuoPolicy.thresholdPercent
        }

        let needsKuo: Bool
        if kuoPolicy.forceDisable {
            needsKuo = false
        } else if kuoPolicy.forceApply {
            needsKuo = true
        } else if thresholdPassed {
            if let minDisplacement = kuoPolicy.minDisplacementMlToApply {
                needsKuo = displacementEstimate >= minDisplacement
            } else {
                needsKuo = true
            }
        } else {
            needsKuo = false
        }

        var displacement = 0.0
        var missingKuoCount = 0

        if needsKuo {
            for solid in normalizedSolids where solid.weight > 0 {
                guard let kuo = solid.kuo, kuo > 0 else {
                    missingKuoCount += 1
                    continue
                }
                displacement += solid.weight * kuo
            }
        }

        let rawToMeasure = normalizedTarget - sumLiquids - displacement

        return AdCalculationResult(
            targetVolume: normalizedTarget,
            componentsVolume: sumLiquids,
            solidsWeight: totalSolidsWeight,
            displacementVolume: displacement,
            amountToMeasure: max(0, rawToMeasure),
            rawAmountToMeasure: rawToMeasure,
            isImpossible: rawToMeasure <= 0,
            needsKuo: needsKuo,
            missingKuoCount: missingKuoCount
        )
    }
}
