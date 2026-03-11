import Foundation

struct ExtempIngredientDraft: Identifiable, Hashable {
    enum AmountScope: String, CaseIterable, Identifiable, Hashable {
        case auto
        case total
        case perDose

        var id: String { rawValue }
    }

    let id: UUID
    var substance: ExtempSubstance
    var amountValue: String
    var unit: ExtempUnit?
    var amountScope: AmountScope
    var isAd: Bool
    var isAna: Bool
    var isQs: Bool
    var presentationKind: IngredientPresentationKind
    var rpPrefix: IngredientRpPrefix
    var solPercentText: String
    var solVolumeMlText: String

    init(
        id: UUID = UUID(),
        substance: ExtempSubstance,
        amountValue: String = "",
        unit: ExtempUnit? = nil,
        amountScope: AmountScope = .auto,
        isAd: Bool = false,
        isAna: Bool = false,
        isQs: Bool = false,
        presentationKind: IngredientPresentationKind = .substance,
        rpPrefix: IngredientRpPrefix? = nil,
        useSolPrefix: Bool? = nil,
        solPercentText: String = "",
        solVolumeMlText: String = ""
    ) {
        self.id = id
        self.substance = substance
        self.amountValue = amountValue
        self.unit = unit
        self.amountScope = amountScope
        self.isAd = isAd
        self.isAna = isAna
        self.isQs = isQs
        let resolvedPresentationKind: IngredientPresentationKind = {
            if useSolPrefix == true { return .solution }
            return presentationKind
        }()
        self.presentationKind = resolvedPresentationKind
        self.rpPrefix = rpPrefix ?? (resolvedPresentationKind == .solution ? .sol : .none)
        self.solPercentText = solPercentText
        self.solVolumeMlText = solVolumeMlText
    }

    var useSolPrefix: Bool {
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
