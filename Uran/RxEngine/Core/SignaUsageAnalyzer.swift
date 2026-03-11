import Foundation

struct SignaUsageSemantics: Sendable {
    let normalizedSigna: String
    let hasDropsDose: Bool
    let hasSpoonDose: Bool
    let isEyeRoute: Bool
    let isNasalRoute: Bool
    let isRectalOrVaginalRoute: Bool
    let isRinseOrGargle: Bool
    let isExternalRoute: Bool
    let requiresDilutionBeforeUse: Bool

    nonisolated var dropMeasurementOnly: Bool {
        hasDropsDose && isRinseOrGargle && (requiresDilutionBeforeUse || normalizedSigna.contains("вод"))
    }

    nonisolated var isTrueDropsDosageForm: Bool {
        hasDropsDose && !dropMeasurementOnly
    }
}

enum SignaUsageAnalyzer {
    nonisolated static func analyze(signa: String) -> SignaUsageSemantics {
        let normalized = signa
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return SignaUsageSemantics(
            normalizedSigna: normalized,
            hasDropsDose: hasDropsMarker(in: normalized),
            hasSpoonDose: hasSpoonMarker(in: normalized),
            isEyeRoute: hasEyeRouteMarker(in: normalized),
            isNasalRoute: hasNasalRouteMarker(in: normalized),
            isRectalOrVaginalRoute: hasRectalOrVaginalMarker(in: normalized),
            isRinseOrGargle: hasRinseOrGargleMarker(in: normalized),
            isExternalRoute: hasExternalRouteMarker(in: normalized),
            requiresDilutionBeforeUse: requiresDilutionBeforeUse(in: normalized)
        )
    }

    nonisolated static func correctedFormMode(
        selectedFormMode: FormMode,
        draft: ExtempRecipeDraft
    ) -> FormMode {
        let semantics = analyze(signa: draft.signa)
        guard !draft.isOphthalmicDrops else { return selectedFormMode }

        if selectedFormMode == .drops && semantics.dropMeasurementOnly {
            return .solutions
        }

        return selectedFormMode
    }

    nonisolated static func effectiveFormMode(for draft: ExtempRecipeDraft) -> FormMode {
        let baseFormMode = draft.formMode == .auto
            ? AutoFormResolver.inferFormMode(draft: draft)
            : draft.formMode
        return correctedFormMode(selectedFormMode: baseFormMode, draft: draft)
    }

    nonisolated private static func hasDropsMarker(in signa: String) -> Bool {
        signa.contains("крап")
            || signa.contains("кап")
            || signa.contains("gtt")
            || signa.contains("drops")
    }

    nonisolated private static func hasSpoonMarker(in signa: String) -> Bool {
        signa.contains("ложк")
            || signa.contains("ч.л")
            || signa.contains("дес")
            || signa.contains("ст.л")
            || signa.contains("teaspoon")
            || signa.contains("tablespoon")
            || signa.contains("dessert spoon")
    }

    nonisolated private static func hasEyeRouteMarker(in signa: String) -> Bool {
        signa.contains("очн")
            || signa.contains("глаз")
            || signa.contains("in ocul")
            || signa.contains("oculo")
            || signa.contains("ophth")
            || signa.contains("eye")
    }

    nonisolated private static func hasNasalRouteMarker(in signa: String) -> Bool {
        signa.contains("нос")
            || signa.contains("назал")
            || signa.contains("nas")
    }

    nonisolated private static func hasRectalOrVaginalMarker(in signa: String) -> Bool {
        signa.contains("rect")
            || signa.contains("рект")
            || signa.contains("vagin")
            || signa.contains("вагин")
            || signa.contains("supp")
            || signa.contains("супп")
    }

    nonisolated private static func hasExternalRouteMarker(in signa: String) -> Bool {
        signa.contains("зовніш")
            || signa.contains("наруж")
            || signa.contains("extern")
            || signa.contains("ad usum extern")
            || signa.contains("на шкіру")
            || signa.contains("на кожу")
            || signa.contains("протират")
            || signa.contains("протиран")
            || signa.contains("протирать")
            || signa.contains("протирания")
            || signa.contains("втират")
            || signa.contains("змащ")
            || signa.contains("смаз")
    }

    nonisolated private static func hasRinseOrGargleMarker(in signa: String) -> Bool {
        signa.contains("полоск")
            || signa.contains("полоcк")
            || signa.contains("ополіск")
            || signa.contains("полость рта")
            || signa.contains("порожнини рота")
            || signa.contains("порожнини роту")
            || signa.contains("горла")
            || signa.contains("горло")
            || signa.contains("mouth")
            || signa.contains("mouth rinse")
            || signa.contains("gargle")
            || signa.contains("rinse")
    }

    nonisolated private static func requiresDilutionBeforeUse(in signa: String) -> Bool {
        signa.contains("развести")
            || signa.contains("развод")
            || signa.contains("розвести")
            || signa.contains("розвод")
            || signa.contains("dilute")
            || signa.contains("розбав")
            || signa.contains("разбав")
            || signa.contains("на 0,5стакана")
            || signa.contains("на 0,5 стакана")
            || signa.contains("на полстакана")
            || signa.contains("на півсклянки")
            || signa.contains("в 0,5 стакана")
            || signa.contains("в полстакана")
            || signa.contains("у півсклянки")
            || signa.contains("в склянці води")
            || signa.contains("у склянці води")
            || signa.contains("в стакане воды")
            || signa.contains("на стакан воды")
    }
}
