import Foundation

struct VMSColloidsBlock: RxProcessingBlock {
    static let blockId = "vms_colloids"
    let id = blockId

    func apply(context: inout RxPipelineContext) {
        var lines: [String] = ["Технологія (ВМС/колоїди):"]
        var emittedPepsinDetails = false
        let hasPepsin = context.draft.ingredients.contains(where: isPepsin)
        let hasLimitedHeat = context.draft.ingredients.contains(where: { inferredDissolutionType($0) == .hmcRestrictedHeat })
        let hasLimitedCool = context.draft.ingredients.contains(where: { inferredDissolutionType($0) == .hmcRestrictedCool })
        let hasProtectedColloids = context.draft.ingredients.contains(where: {
            let t = inferredDissolutionType($0)
            return t == .colloidProtargol || t == .colloidCollargol || t == .ichthyol
        })
        let hasWaterRemovingAgents = context.draft.ingredients.contains(where: isWaterRemovingAgent)
        let hasGlycerin = context.draft.ingredients.contains(where: isGlycerinIngredient)

        lines.append("• Розчиненню ВМС передує набухання: спочатку сольватація/гідратація, потім повільна дифузія макромолекул у розчинник")
        lines.append("• Через високу в’язкість розчини ВМС проціджують крізь крупнопористі матеріали (вата/марля)")

        if hasLimitedHeat {
            lines.append("• Обмежено набухаючі ВМС (крохмаль, желатин тощо): для повного розчинення потрібне нагрівання")
        }
        if hasLimitedCool {
            lines.append("• Для метилцелюлози: набухання у гарячій воді, розчинення після охолодження")
        }

        for ing in context.draft.ingredients {
            let t = inferredDissolutionType(ing)
            switch t {
            case .colloidProtargol:
                if hasGlycerin {
                    lines.append("• Protargolum: попередньо розтерти у ступці з 6–8 краплями гліцерину, потім розчинити у воді")
                    lines.append("  Після повного змочування довести водою до об'єму, перемішати обережно; за потреби процідити крізь вату")
                } else {
                    lines.append("• Protargolum: насипати на поверхню води без інтенсивного перемішування (уникати грудок)")
                    lines.append("  Залишити для набухання 15–20 хв, потім обережно перемішати; за потреби процідити крізь вату")
                }
            case .colloidCollargol:
                lines.append("• Collargolum: повільно набухає — попередньо розтерти з невеликою кількістю води (пептизація), потім розбавити")
            case .ichthyol:
                lines.append("• Ichthyolum: у фарфоровій чашці додавати розчинник порціями при ретельному перемішуванні; процідити крізь вату")
            case .hmcRestrictedHeat:
                lines.append("• \(ing.displayName): обмежити нагрів, контролювати набухання/гелеутворення")
            case .hmcRestrictedCool:
                lines.append("• \(ing.displayName): готувати у прохолодному режимі")
            case .hmcUnrestricted:
                if isPepsin(ing) {
                    if !emittedPepsinDetails {
                        emittedPepsinDetails = true
                        lines.append("• Pepsinum: спочатку підкислити воду Acidum hydrochloricum")
                        lines.append("  Pepsinum додати в останню чергу, перемішувати обережно")
                        lines.append("  ⚠ Не нагрівати (фермент інактивується при t > 40°C)")
                        lines.append("  Фільтрувати лише крізь пухкий тампон вати (не через папір)")
                    }
                } else {
                    lines.append("• \(ing.displayName): вводити при інтенсивному перемішуванні")
                }
            case .ordinary:
                break
            }
        }

        if context.facts.hasElectrolytes || hasWaterRemovingAgents {
            lines.append("⚠ Ризик висолювання/коагуляції ВМС та захищених колоїдів")
            lines.append("Електроліти, спирт, гліцерин, сиропи вводити у розведеному вигляді, малими порціями при постійному перемішуванні")
            context.addIssue(
                code: "vms.coagulation.risk",
                severity: .warning,
                message: "У складі є фактори коагуляції (електроліти/водовіднімаючі речовини)"
            )
        }

        lines.append("• При зберіганні можливі застудневання/синерезис; для відпуску доцільно маркувати «Перед вживанням збовтувати»")

        context.addIssue(code: "vms.special", severity: .warning, message: "ВМС/колоїди: застосовано спеціальну технологію")
        context.addStep(TechStep(kind: .mixing, title: "Ввести ВМС/колоїди в спеціальному режимі", isCritical: true))
        context.addStep(TechStep(kind: .filtration, title: "За потреби процідити через вату/марлю (крупнопористий фільтр)"))
        if hasPepsin {
            context.addStep(
                TechStep(
                    kind: .filtration,
                    title: "Процідити через пухкий ватний тампон",
                    notes: "Паперовий фільтр не використовувати (ризик адсорбції пепсину)",
                    isCritical: true
                )
            )
            context.appendSection(title: "Контроль якості", lines: [
                "Допускається слабка опалесценція для білкових розчинів (Pepsinum)"
            ])
            context.appendSection(title: "Упаковка/Маркування", lines: [
                "Флакон з оранжевого скла",
                "Зберігати при 2–8°C",
                "Термін придатності: 10 діб"
            ])
        }
        if hasProtectedColloids {
            context.appendSection(title: "Упаковка/Маркування", lines: [
                "Світлочутливі колоїдні розчини (Protargolum/Collargolum): флакон з оранжевого скла",
                "Маркування: «Перед вживанням збовтувати»"
            ])
        }
        context.appendSection(title: "Технологія", lines: lines)
    }

    private func inferredDissolutionType(_ ing: IngredientDraft) -> DissolutionType {
        if let t = ing.refDissolutionType { return t }
        let hay = ((ing.refNameLatNom ?? ing.displayName) + " " + (ing.refInnKey ?? ""))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if hay.contains("protarg") { return .colloidProtargol }
        if hay.contains("collarg") { return .colloidCollargol }
        if hay.contains("ichthy") || hay.contains("іхті") { return .ichthyol }
        if hay.contains("gelatin") || hay.contains("amylum") || hay.contains("starch") { return .hmcRestrictedHeat }
        if hay.contains("methylcell") { return .hmcRestrictedCool }
        if hay.contains("pepsin") { return .hmcUnrestricted }
        return .ordinary
    }

    private func isPepsin(_ ing: IngredientDraft) -> Bool {
        let hay = ((ing.refNameLatNom ?? ing.displayName) + " " + (ing.refInnKey ?? ""))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return hay.contains("pepsin")
    }

    private func isWaterRemovingAgent(_ ing: IngredientDraft) -> Bool {
        let hay = ((ing.refNameLatNom ?? ing.displayName) + " " + (ing.refInnKey ?? ""))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return hay.contains("spirit")
            || hay.contains("ethanol")
            || hay.contains("alcohol")
            || hay.contains("гліцерин")
            || hay.contains("glycerin")
            || hay.contains("glycerol")
            || hay.contains("sirup")
            || hay.contains("syrup")
            || hay.contains("сироп")
            || hay.contains("sacchar")
            || hay.contains("цукров")
    }

    private func isGlycerinIngredient(_ ing: IngredientDraft) -> Bool {
        let hay = ((ing.refNameLatNom ?? ing.displayName) + " " + (ing.refInnKey ?? ""))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return hay.contains("glycerin")
            || hay.contains("glycerol")
            || hay.contains("glycerinum")
            || hay.contains("гліцерин")
            || hay.contains("глицерин")
    }
}
