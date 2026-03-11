import Foundation

struct ExtempOutputLookupContext: Equatable {
    var dosageForms: [ExtempDosageForm]
    var mfRules: [ExtempMfRule]
    var ingredientSubstanceById: [UUID: ExtempSubstance]
}

struct ExtempOutputRenderState: Equatable {
    var blankType: RxBlankType
    var patientDobText: String
    var doctorFullName: String
    var clinicName: String
    var powderMassMode: PowderMassMode
    var showPpkSteps: Bool
    var showExtendedTech: Bool
    var belladonnaExtractVariant: BelladonnaExtractVariant
}

enum ExtempOutputCoordinator {
    static func makeConfig(
        lookup: ExtempOutputLookupContext,
        state: ExtempOutputRenderState
    ) -> RxOutputRenderConfig {
        RxOutputRenderConfig(
            dosageForms: lookup.dosageForms,
            mfRules: lookup.mfRules,
            ingredientSubstanceById: lookup.ingredientSubstanceById,
            blankType: state.blankType,
            patientDobText: state.patientDobText,
            doctorFullName: state.doctorFullName,
            clinicName: state.clinicName,
            powderMassMode: state.powderMassMode,
            showPpkSteps: state.showPpkSteps,
            showExtendedTech: state.showExtendedTech,
            belladonnaExtractVariant: state.belladonnaExtractVariant
        )
    }

    @MainActor
    static func sync(
        store: RxBuilderStore,
        lookup: ExtempOutputLookupContext,
        state: ExtempOutputRenderState
    ) {
        store.configureOutput(makeConfig(lookup: lookup, state: state))
    }
}
