import Foundation

struct BuretteSystemBlock: RxProcessingBlock {
    static let blockId = "burette_system"
    let id = blockId

    func apply(context: inout RxPipelineContext) {
        guard context.draft.useBuretteSystem else { return }

        let result = BuretteSystem.evaluateBurette(draft: context.draft)
        if !result.issues.isEmpty {
            context.issues.append(contentsOf: result.issues)
        }

        let invalidItems = result.items.filter { $0.concentrateVolumeMl <= 0 || $0.soluteMassG <= 0 }
        if !invalidItems.isEmpty {
            context.addIssue(
                code: "burette.invalid_item",
                severity: .blocking,
                message: "Для бюреточного концентрату отримано нульовий або некоректний об’єм"
            )
        }
        let validItems = result.items.filter { $0.concentrateVolumeMl > 0 && $0.soluteMassG > 0 }

        if validItems.isEmpty {
            if result.issues.contains(where: { $0.severity == .blocking }) {
                return
            }
            context.addIssue(
                code: "burette.no_matches",
                severity: .warning,
                message: "Бюреточна система увімкнена, але для інгредієнтів рецепта не знайдено відповідних концентратів у каталозі."
            )
            return
        }

        let validTotal = validItems.reduce(0.0) { $0 + $1.concentrateVolumeMl }
        context.calculations["burette_items_count"] = String(validItems.count)
        context.calculations["burette_total_ml"] = BuretteSystem.format(validTotal)
        context.calculations["burette_block_rendered"] = "true"

        let calculationLines = validItems.map { item in
            let fraction = BuretteSystem.format(item.concentrate.concentrationFraction)
            return "\(item.concentrate.titleRu): V_conc = \(BuretteSystem.format(item.soluteMassG)) / \(fraction) = \(BuretteSystem.format(item.concentrateVolumeMl)) ml (\(item.concentrate.ratioTitle))"
        } + [
            "ΣV_концентратів = \(BuretteSystem.format(validTotal)) ml",
            "Вода для мікстури: V_H2O = V_total - ΣV_концентратів - ΣV_інших рідин",
            "Компоненти вводяться у вигляді концентрованих розчинів; КУО для них не застосовують."
        ]
        context.appendSection(title: "Бюреточні розрахунки", lines: calculationLines)

        let dosingLines = BuretteSystem.dosingRules.map { "\($0.title): \($0.detail)" }
        context.appendSection(title: "Контроль дозування бюретки", lines: dosingLines)

        let workflowLines = BuretteSystem.preparationLines + BuretteSystem.microxtureWorkflowLines
        context.appendSection(title: "Технологія виготовлення бюреточної мікстури", lines: workflowLines)

        context.appendSection(title: "Контроль якості", lines: BuretteSystem.finalMixtureQualityControlLines)
        context.appendSection(title: "Маркування та зберігання", lines: BuretteSystem.labelingLines)
    }
}
