import Foundation

// These shims are used only by standalone breaker scripts compiled via swiftc.
// They satisfy extension constraints in SubstancePropertyCatalog without pulling
// the full app model graph into the script build.
struct ExtempSubstance {
    let innKey: String
    let nameLatNom: String
    let nameRu: String
}

struct IngredientDraft {
    let refInnKey: String?
    let refNameLatNom: String?
    let displayName: String
}
