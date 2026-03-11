import Foundation

struct RxOutputRenderConfig {
    var dosageForms: [ExtempDosageForm] = []
    var mfRules: [ExtempMfRule] = []
    var ingredientSubstanceById: [UUID: ExtempSubstance] = [:]
    var blankType: RxBlankType = .ordinary
    var patientDobText: String = ""
    var doctorFullName: String = ""
    var clinicName: String = ""
    var powderMassMode: PowderMassMode = .dispensa
    var showPpkSteps: Bool = true
    var showExtendedTech: Bool = false
    var belladonnaExtractVariant: BelladonnaExtractVariant?
}

struct RxOutputText {
    var rxText: String
    var ppkText: String
}

struct RxOutputPipeline {
    private let prescriptionBuilder = RxPrescriptionBuilder()
    private let ppkRenderer = PpkRenderer()

    func render(
        draft: ExtempRecipeDraft,
        derived: DerivedState,
        issues: [RxIssue],
        techPlan: TechPlan,
        config: RxOutputRenderConfig
    ) -> RxOutputText {
        let rxText = prescriptionBuilder.build(
            draft: draft,
            routeBranch: derived.routeBranch,
            config: config,
            issueDate: Date()
        )

        let filteredSections: [PpkSection] = config.showPpkSteps
            ? derived.ppkSections
            : derived.ppkSections.filter { !isCalculationSectionTitle($0.title) }

        let routeBranch = config.showExtendedTech ? derived.routeBranch : nil
        let activatedBlocks = config.showExtendedTech ? derived.activatedBlocks : []

        let ppkText: String
        if LivingDeathEasterEgg.isActive(draft: draft) {
            ppkText = LivingDeathEasterEgg.ppkText(draft: draft)
        } else {
            ppkText = ppkRenderer.renderPpk(
                draft: draft,
                plan: techPlan,
                issues: issues,
                sections: filteredSections,
                routeBranch: routeBranch,
                activatedBlocks: activatedBlocks,
                powderTechnology: derived.powderTechnology
            )
        }

        return RxOutputText(rxText: rxText, ppkText: ppkText)
    }

    private func isCalculationSectionTitle(_ title: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t.contains("розрах")
            || t.contains("расчет")
            || t.contains("calculation")
    }
}
