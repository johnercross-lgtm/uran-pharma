import Foundation

enum IngredientPresentationKind: String, CaseIterable, Hashable, Codable {
    case substance
    case solution
    case standardSolution
}

enum IngredientRpPrefix: String, CaseIterable, Hashable, Codable {
    case none
    case sol
    case tincture
    case infusion
    case decoction
    case emulsion
    case suspension

    var latinToken: String? {
        switch self {
        case .none: return nil
        case .sol: return "Sol."
        case .tincture: return "T-rae"
        case .infusion: return "Inf."
        case .decoction: return "Decoct."
        case .emulsion: return "Emuls."
        case .suspension: return "Susp."
        }
    }
}

struct IngredientDraft: Identifiable, Hashable {

    var id = UUID()

    var substanceId: Int?
    var displayName: String

    var role: IngredientRole
    var amountValue: Double
    var unit: UnitCode
    var scope: AmountScope

    var isAna: Bool
    var isQS: Bool
    var isAd: Bool
    var presentationKind: IngredientPresentationKind
    var rpPrefix: IngredientRpPrefix

    // Snapshot of reference fields (from ExtempSubstance/extemp_reference_200)
    // Needed for engine blocks to avoid string-only heuristics.
    var refInnKey: String?
    var refType: String?
    var refNameLatNom: String?
    var refNameLatGen: String?
    var refVrdG: Double?
    var refVsdG: Double?
    var refPedsVrdG: Double?
    var refPedsRdG: Double?
    var refVrdChild0_1: Double?
    var refVrdChild1_6: Double?
    var refVrdChild7_14: Double?
    var refKuoMlPerG: Double?
    var refKvGPer100G: Double?
    var refGttsPerMl: Double?
    var refEFactor: Double?
    var refEFactorNaCl: Double?
    var refDensity: Double?
    var refSolubility: String?
    var refStorage: String?
    var refInteractionNotes: String?
    var refOintmentNote: String?
    var refDissolutionType: DissolutionType?
    var refNeedsTrituration: Bool
    var refListA: Bool
    var refListB: Bool
    var refIsNarcotic: Bool
    var refPharmActivity: String?
    var refPhysicalState: String?
    var refPrepMethod: String?
    var refHerbalRatio: String?
    var refWaterTempC: Double?
    var refHeatBathMin: Int?
    var refStandMin: Int?
    var refCoolMin: Int?
    var refStrain: Bool
    var refPressMarc: Bool
    var refBringToVolume: Bool
    var refExtractionSolvent: String?
    var refTinctureRatio: String?
    var refMacerationDays: Int?
    var refFilter: Bool
    var refExtractType: String?
    var refExtractSolvent: String?
    var refExtractRatio: String?
    var refSolventType: String?
    var refSterile: Bool
    var refIsVolatile: Bool?
    var refIsFlammable: Bool?
    var refHeatingAllowed: NonAqueousHeatingAllowance?
    var refHeatingTempMaxC: Double?
    var refDefaultEthanolStrength: Int?
    var refIncompatibleWithEthanol: Bool?

    init(
        id: UUID = UUID(),
        substanceId: Int? = nil,
        displayName: String = "",
        role: IngredientRole = .other,
        amountValue: Double = 0,
        unit: UnitCode = UnitCode(rawValue: "g"),
        scope: AmountScope = .auto,
        isAna: Bool = false,
        isQS: Bool = false,
        isAd: Bool = false,
        presentationKind: IngredientPresentationKind = .substance,
        rpPrefix: IngredientRpPrefix? = nil,
        isSol: Bool? = nil,
        refInnKey: String? = nil,
        refType: String? = nil,
        refNameLatNom: String? = nil,
        refNameLatGen: String? = nil,
        refVrdG: Double? = nil,
        refVsdG: Double? = nil,
        refPedsVrdG: Double? = nil,
        refPedsRdG: Double? = nil,
        refVrdChild0_1: Double? = nil,
        refVrdChild1_6: Double? = nil,
        refVrdChild7_14: Double? = nil,
        refKuoMlPerG: Double? = nil,
        refKvGPer100G: Double? = nil,
        refGttsPerMl: Double? = nil,
        refEFactor: Double? = nil,
        refEFactorNaCl: Double? = nil,
        refDensity: Double? = nil,
        refSolubility: String? = nil,
        refStorage: String? = nil,
        refInteractionNotes: String? = nil,
        refOintmentNote: String? = nil,
        refDissolutionType: DissolutionType? = nil,
        refNeedsTrituration: Bool = false,
        refListA: Bool = false,
        refListB: Bool = false,
        refIsNarcotic: Bool = false,
        refPharmActivity: String? = nil,
        refPhysicalState: String? = nil,
        refPrepMethod: String? = nil,
        refHerbalRatio: String? = nil,
        refWaterTempC: Double? = nil,
        refHeatBathMin: Int? = nil,
        refStandMin: Int? = nil,
        refCoolMin: Int? = nil,
        refStrain: Bool = false,
        refPressMarc: Bool = false,
        refBringToVolume: Bool = false,
        refExtractionSolvent: String? = nil,
        refTinctureRatio: String? = nil,
        refMacerationDays: Int? = nil,
        refFilter: Bool = false,
        refExtractType: String? = nil,
        refExtractSolvent: String? = nil,
        refExtractRatio: String? = nil,
        refSolventType: String? = nil,
        refSterile: Bool = false,
        refIsVolatile: Bool? = nil,
        refIsFlammable: Bool? = nil,
        refHeatingAllowed: NonAqueousHeatingAllowance? = nil,
        refHeatingTempMaxC: Double? = nil,
        refDefaultEthanolStrength: Int? = nil,
        refIncompatibleWithEthanol: Bool? = nil
    ) {
        self.id = id
        self.substanceId = substanceId
        self.displayName = displayName
        self.role = role
        self.amountValue = amountValue
        self.unit = unit
        self.scope = scope
        self.isAna = isAna
        self.isQS = isQS
        self.isAd = isAd
        let resolvedPresentationKind: IngredientPresentationKind = {
            if isSol == true { return .solution }
            return presentationKind
        }()
        self.presentationKind = resolvedPresentationKind
        self.rpPrefix = rpPrefix ?? (resolvedPresentationKind == .solution ? .sol : .none)
        self.refInnKey = refInnKey
        self.refType = refType
        self.refNameLatNom = refNameLatNom
        self.refNameLatGen = refNameLatGen
        self.refVrdG = refVrdG
        self.refVsdG = refVsdG
        self.refPedsVrdG = refPedsVrdG
        self.refPedsRdG = refPedsRdG
        self.refVrdChild0_1 = refVrdChild0_1
        self.refVrdChild1_6 = refVrdChild1_6
        self.refVrdChild7_14 = refVrdChild7_14
        self.refKuoMlPerG = refKuoMlPerG
        self.refKvGPer100G = refKvGPer100G
        self.refGttsPerMl = refGttsPerMl
        self.refEFactor = refEFactor
        self.refEFactorNaCl = refEFactorNaCl
        self.refDensity = refDensity
        self.refSolubility = refSolubility
        self.refStorage = refStorage
        self.refInteractionNotes = refInteractionNotes
        self.refOintmentNote = refOintmentNote
        self.refDissolutionType = refDissolutionType
        self.refNeedsTrituration = refNeedsTrituration
        self.refListA = refListA
        self.refListB = refListB
        self.refIsNarcotic = refIsNarcotic
        self.refPharmActivity = refPharmActivity
        self.refPhysicalState = refPhysicalState
        self.refPrepMethod = refPrepMethod
        self.refHerbalRatio = refHerbalRatio
        self.refWaterTempC = refWaterTempC
        self.refHeatBathMin = refHeatBathMin
        self.refStandMin = refStandMin
        self.refCoolMin = refCoolMin
        self.refStrain = refStrain
        self.refPressMarc = refPressMarc
        self.refBringToVolume = refBringToVolume
        self.refExtractionSolvent = refExtractionSolvent
        self.refTinctureRatio = refTinctureRatio
        self.refMacerationDays = refMacerationDays
        self.refFilter = refFilter
        self.refExtractType = refExtractType
        self.refExtractSolvent = refExtractSolvent
        self.refExtractRatio = refExtractRatio
        self.refSolventType = refSolventType
        self.refSterile = refSterile
        self.refIsVolatile = refIsVolatile
        self.refIsFlammable = refIsFlammable
        self.refHeatingAllowed = refHeatingAllowed
        self.refHeatingTempMaxC = refHeatingTempMaxC
        self.refDefaultEthanolStrength = refDefaultEthanolStrength
        self.refIncompatibleWithEthanol = refIncompatibleWithEthanol
    }

    var isSol: Bool {
        get { presentationKind == .solution }
        set {
            presentationKind = newValue ? .solution : .substance
            if newValue && rpPrefix == .none {
                rpPrefix = .sol
            }
            if !newValue && rpPrefix == .sol {
                rpPrefix = .none
            }
        }
    }
}

extension IngredientDraft {
    var refNormalizedType: String {
        (refType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var refNormalizedStorage: String {
        (refStorage ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var refNormalizedInteractionNotes: String {
        (refInteractionNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var refNormalizedPrepMethod: String {
        (refPrepMethod ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var normalizedReferenceHaystack: String {
        [
            refNameLatNom,
            refInnKey,
            displayName,
            refStorage,
            refInteractionNotes,
            refOintmentNote,
            refPrepMethod,
            refSolventType,
            refPharmActivity
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    private var isReferenceAuxiliaryLike: Bool {
        ["aux", "solv", "solvent", "base", "viscous liquid", "standardsolution", "liquidstandard"].contains(refNormalizedType)
    }

    private func containsNegativeListAMarker(_ text: String) -> Bool {
        text.contains("неядов")
            || text.contains("не ядов")
            || text.contains("non-poison")
            || text.contains("non poison")
    }

    private func containsPositiveListAMarker(_ text: String) -> Bool {
        guard !containsNegativeListAMarker(text) else { return false }
        return text.contains("ядовит")
            || text.contains("ядов")
            || text.contains("poison")
    }

    private func containsNegativeLightMarker(_ text: String) -> Bool {
        text.contains("не світлочут")
            || text.contains("не светочувств")
            || text.contains("світлозахист не потріб")
            || text.contains("защита от света не треб")
            || text.contains("not light sensitive")
            || text.contains("light protection not required")
            || text.contains("protect from light not required")
    }

    private func containsPositiveLightMarker(_ text: String) -> Bool {
        guard !containsNegativeLightMarker(text) else { return false }
        return text.contains("lightprotected")
            || text.contains("light sensitive")
            || text.contains("lightsensitive")
            || text.contains("protect from light")
            || text.contains("захищеному від світла")
            || text.contains("защищенном от света")
            || text.contains("світлочут")
            || text.contains("светочувств")
            || text.contains("darkglass")
            || text.contains("amberglass")
            || text.contains("темнескло")
            || text.contains("оранжев")
    }

    private var isStableBromideSaltWithoutPhotolability: Bool {
        let hay = normalizedReferenceHaystack
        let hasBromideMarker = hay.contains("natrii bromid")
            || hay.contains("kalii bromid")
            || hay.contains("sodium bromide")
            || hay.contains("potassium bromide")
            || hay.contains("натрия бромид")
            || hay.contains("натрію бромід")
            || hay.contains("калия бромид")
            || hay.contains("калію бромід")
        let hasHydrobromideMarker = hay.contains("hydrobromid")
            || hay.contains("гидробромид")
            || hay.contains("гідробромід")
        return hasBromideMarker && !hasHydrobromideMarker
    }

    private func containsNegativeListBMarker(_ text: String) -> Bool {
        text.contains("несильнод")
            || text.contains("не сильнод")
            || text.contains("несильнодейств")
            || text.contains("не сильнодейств")
            || text.contains("non-strong")
            || text.contains("non strong")
            || text.contains("not strong")
    }

    private func containsPositiveListBMarker(_ text: String) -> Bool {
        guard !containsNegativeListBMarker(text) else { return false }
        return text.contains("сильнод")
            || text.contains("сильнодейств")
            || text.contains("heroica")
            || text.contains("strong")
    }

    var hasReferenceEssentialOilVolatility: Bool {
        refNormalizedInteractionNotes.contains("essentialoilvolatility")
    }

    var hasReferenceToxicComponent: Bool {
        refNormalizedInteractionNotes.contains("toxiccomponent")
    }

    var hasReferenceAqueousNameMarker: Bool {
        let hay = normalizedReferenceHaystack
        return hay.contains("aqua ")
            || hay.contains("aquae ")
            || hay.contains(" water")
            || hay.contains("вода")
    }

    var hasReferenceAromaticWaterRatio: Bool {
        refNormalizedPrepMethod.contains("1:1000")
            || refNormalizedPrepMethod.contains("1/1000")
            || (isReferenceAromaticWater && hasReferenceEssentialOilVolatility)
    }

    var isReferenceAromaticWater: Bool {
        let hay = normalizedReferenceHaystack
        let markers = [
            "aqua menthae", "aquae menthae", "peppermint water",
            "aqua menthae piperitae", "aquae menthae piperitae",
            "aqua foeniculi", "aquae foeniculi", "fennel water", "dill water",
            "aqua anisi", "aquae anisi", "anise water",
            "aqua rosae", "aquae rosae", "rose water",
            "aqua coriandri", "aquae coriandri", "coriander water"
        ]

        if hasReferenceEssentialOilVolatility
            && (refNormalizedStorage.contains("coolplace")
                || hasReferenceAqueousNameMarker
                || ["aux", "solv", "solvent"].contains(refNormalizedType)) {
            return true
        }

        if refNormalizedPrepMethod.contains("prepared from"), hasReferenceAqueousNameMarker {
            return true
        }

        return markers.contains(where: { hay.contains($0) })
    }

    var isReferenceVolatileAqueousLiquid: Bool {
        let hay = normalizedReferenceHaystack
        let markers = [
            "aqua chloroformii", "aquae chloroformii", "chloroform water",
            "amygdalarum amararum", "bitter almond water", "aqua amygdalarum amararum"
        ]

        if hasReferenceToxicComponent
            && (hasReferenceAqueousNameMarker
                || refNormalizedStorage.contains("lightprotected")
                || refNormalizedStorage.contains("coolplace")) {
            return true
        }

        return markers.contains(where: { hay.contains($0) })
    }

    var isReferenceCoolPlaceSensitive: Bool {
        let storage = refNormalizedStorage
        return storage.contains("coolplace")
            || storage.contains("прохолод")
            || storage.contains("cool place")
            || storage.contains("8-15")
    }

    var isReferenceLightSensitive: Bool {
        if isStableBromideSaltWithoutPhotolability { return false }
        if isReferenceAromaticWater { return true }
        let storage = refNormalizedStorage
        return containsPositiveLightMarker(storage)
    }

    var isReferenceListA: Bool {
        if PurifiedWaterHeuristics.isPurifiedWater(self) { return false }
        if isBoricAntiseptic { return false }
        if isReferenceEthanolForAccounting { return false }
        if isSalicylicAlcoholAntiseptic { return false }
        if refListA { return true }
        if propertyOverride?.listA == true { return true }

        let ointmentNote = (refOintmentNote ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ointmentNote.contains("список а") || ointmentNote.contains("list a") {
            return true
        }

        let activity = (refPharmActivity ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !isReferenceAuxiliaryLike else { return false }
        return containsPositiveListAMarker(activity)
    }

    var requiresVolumeMeasurement: Bool {
        let unitRaw = unit.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if unitRaw == "ml" || unitRaw == "мл" || unitRaw == "l" || unitRaw == "л" {
            return true
        }
        if presentationKind == .solution || presentationKind == .standardSolution {
            return true
        }
        let liquidLikeTypes: Set<String> = [
            "solv",
            "solvent",
            "standardsolution",
            "liquidstandard",
            "liquid",
            "viscous liquid",
            "tincture",
            "extract",
            "syrup",
            "juice",
            "suspension",
            "emulsion",
            "alcoholic"
        ]
        return liquidLikeTypes.contains(refNormalizedType)
    }

    var isReferenceListB: Bool {
        if PurifiedWaterHeuristics.isPurifiedWater(self) { return false }
        if isReferenceListA { return false }
        if isSalicylicAlcoholAntiseptic { return false }
        if refListB { return true }

        let storage = (refStorage ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if storage.contains("список б")
            || storage.contains("list b")
            || storage.contains("heroica")
        {
            return true
        }

        let ointmentNote = (refOintmentNote ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if containsPositiveListBMarker(ointmentNote)
            || ointmentNote.contains("список б")
            || ointmentNote.contains("list b")
        {
            return true
        }

        let activity = (refPharmActivity ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !isReferenceAuxiliaryLike else { return false }
        return containsPositiveListBMarker(activity)
    }

    private var referenceMarkerSourceText: String {
        [
            refPrepMethod,
            refInteractionNotes,
            refStorage,
            refSolubility,
            refSolventType
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "; ")
    }

    private var isBoricAntiseptic: Bool {
        let hay = normalizedReferenceHaystack
        return hay.contains("acidum boric")
            || hay.contains("acidi borici")
            || hay.contains("boric acid")
            || hay.contains("spiritus boric")
            || hay.contains("spiritus borici")
            || hay.contains("борн")
    }

    private var isReferenceEthanolForAccounting: Bool {
        let hay = normalizedReferenceHaystack
        let hasEthanolMarker = hay.contains("spiritus aethylic")
            || hay.contains("spiritus vini")
            || hay.contains("ethanol")
            || hay.contains("ethanolum")
            || hay.contains("ethyl alcohol")
            || hay.contains("спирт этил")
            || hay.contains("спирт етил")
        guard hasEthanolMarker else { return false }

        let solventLikeTypes: Set<String> = [
            "solv",
            "solvent",
            "aux",
            "standardsolution",
            "liquidstandard",
            "alcoholic"
        ]
        return solventLikeTypes.contains(refNormalizedType) || requiresVolumeMeasurement
    }

    private var isSalicylicAlcoholAntiseptic: Bool {
        let hay = normalizedReferenceHaystack
        return hay.contains("spiritus salicylic")
            || hay.contains("salicyl alcohol")
            || hay.contains("салицилов спирт")
            || hay.contains("спирт салицил")
    }

    private func normalizeMarkerToken(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private var referenceMarkerPairs: [(key: String, value: String)] {
        let text = referenceMarkerSourceText
        guard !text.isEmpty else { return [] }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let regex = try? NSRegularExpression(pattern: #"([A-Za-z_][A-Za-z0-9_]*)\s*[:=]\s*([^;\n,]+)"#, options: []) else {
            return []
        }

        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard let keyRange = Range(match.range(at: 1), in: text),
                  let valueRange = Range(match.range(at: 2), in: text)
            else {
                return nil
            }

            let key = normalizeMarkerToken(String(text[keyRange]))
            let valueRaw = String(text[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !valueRaw.isEmpty else { return nil }
            return (key: key, value: valueRaw)
        }
    }

    func referenceMarkerValues(for keys: [String]) -> [String] {
        let normalizedKeys = Set(keys.map(normalizeMarkerToken).filter { !$0.isEmpty })
        guard !normalizedKeys.isEmpty else { return [] }

        return referenceMarkerPairs
            .filter { normalizedKeys.contains($0.key) }
            .map(\.value)
    }

    func referenceHasMarkerValue(keys: [String], expectedValues: [String]) -> Bool {
        let values = referenceMarkerValues(for: keys)
        guard !values.isEmpty else { return false }
        let expected = expectedValues.map(normalizeMarkerToken).filter { !$0.isEmpty }
        guard !expected.isEmpty else { return false }

        return values.contains { value in
            let normalizedValue = normalizeMarkerToken(value)
            return expected.contains { token in
                normalizedValue.contains(token)
            }
        }
    }

    func referenceContainsMarkerToken(_ expectedValues: [String]) -> Bool {
        let hay = normalizeMarkerToken(referenceMarkerSourceText)
        guard !hay.isEmpty else { return false }
        let expected = expectedValues.map(normalizeMarkerToken).filter { !$0.isEmpty }
        guard !expected.isEmpty else { return false }

        return expected.contains { hay.contains($0) }
    }
}
